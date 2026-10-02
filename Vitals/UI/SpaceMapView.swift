import AppKit
import Combine
import SwiftUI

// MARK: - Model

nonisolated struct MapNode: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bytes: UInt64
    let isFolder: Bool
    /// Other apps' private data: macOS asks before anyone reads it, so Vitals doesn't measure it.
    let isProtected: Bool
}

nonisolated enum MapSizer {
    /// Folders Vitals never walks into: reading them triggers macOS privacy prompts.
    private static var protectedPaths: Set<String> {
        let library = SpaceScanner.home.appendingPathComponent("Library")
        return Set(["Containers", "Group Containers", "Mail", "Messages", "Safari", "Cookies", "Suggestions",
                    "Application Support/MobileSync", "Application Support/AddressBook", "Application Support/CallHistoryDB",
                    "Calendars", "Metadata/CoreSpotlight", "Biome", "HomeKit", "IdentityServices", "PersonalizationPortrait"]
            .map { library.appendingPathComponent($0).path })
    }

    static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [])) ?? []
    }

    static func node(for url: URL) -> MapNode {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        let isLink = values?.isSymbolicLink == true
        let isDir = values?.isDirectory == true && !isLink
        let isPackage = values?.isPackage == true
        let blocked = protectedPaths.contains(url.path)
        let bytes: UInt64 = (isLink || blocked) ? 0 : size(of: url, isDirectory: isDir)
        return MapNode(url: url, name: url.lastPathComponent, bytes: bytes,
                       isFolder: isDir && !isPackage, isProtected: blocked)
    }

    static func size(of url: URL, isDirectory: Bool) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard isDirectory else {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return UInt64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        let blocked = protectedPaths
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            if blocked.contains(file.path) { enumerator.skipDescendants(); continue }
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Space Map: a CleanMyMac "Space Lens"-style picture of what fills your home folder, one level at a time.
@MainActor
final class SpaceMapModel: ObservableObject {
    @Published private(set) var trail: [URL] = [SpaceScanner.home]
    @Published private(set) var nodes: [MapNode] = []
    @Published private(set) var loading = false
    @Published private(set) var measured = 0
    @Published private(set) var toMeasure = 0
    /// Names of the folders being measured right now.
    @Published private(set) var measuring: Set<String> = []

    private var cache: [String: [MapNode]] = [:]
    private var task: Task<Void, Never>?

    var current: URL { trail.last ?? SpaceScanner.home }
    var total: UInt64 { nodes.reduce(0) { $0 + $1.bytes } }

    func loadIfNeeded() { if nodes.isEmpty && !loading { load() } }

    func open(_ node: MapNode) {
        guard node.isFolder, !node.isProtected else { reveal(node); return }
        trail.append(node.url)
        load()
    }

    func go(to index: Int) {
        guard index < trail.count - 1 else { return }
        trail = Array(trail.prefix(index + 1))
        load()
    }

    func back() { if trail.count > 1 { go(to: trail.count - 2) } }

    func refresh() {
        cache[current.path] = nil
        load()
    }

    func reveal(_ node: MapNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    private func load() {
        task?.cancel()
        let folder = current
        if let cached = cache[folder.path] {
            nodes = cached
            loading = false
            return
        }
        nodes = []
        loading = true
        measured = 0
        measuring = []
        task = Task {
            let urls = await Task.detached(priority: .userInitiated) { MapSizer.children(of: folder) }.value
            toMeasure = urls.count
            var found: [MapNode] = []
            // Measure a few at a time so one huge folder (usually Library) doesn't hold up the rest.
            await withTaskGroup(of: MapNode.self) { group in
                var queue = urls[...]
                var running: [String] = []
                for _ in 0..<4 {
                    guard let url = queue.popFirst() else { break }
                    running.append(url.lastPathComponent)
                    group.addTask(priority: .userInitiated) { MapSizer.node(for: url) }
                }
                measuring = Set(running)
                for await node in group {
                    if Task.isCancelled { group.cancelAll(); return }
                    running.removeAll { $0 == node.name }
                    found.append(node)
                    measured += 1
                    nodes = found.sorted { $0.bytes > $1.bytes }
                    if let url = queue.popFirst() {
                        running.append(url.lastPathComponent)
                        group.addTask(priority: .userInitiated) { MapSizer.node(for: url) }
                    }
                    measuring = Set(running)
                }
            }
            if Task.isCancelled { return }
            cache[folder.path] = nodes
            measuring = []
            loading = false
        }
    }
}

// MARK: - Treemap layout (squarified)

nonisolated enum Treemap {
    /// Lays out `values` (sorted largest first) as rectangles filling `rect`, keeping them close to square.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return rects }
        let scale = rect.width * rect.height / total
        let areas = values.map { $0 * scale }
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = min(remaining.width, remaining.height)
            guard side > 0 else { break }
            var end = start + 1
            var best = worst(areas[start..<end], side: side)
            while end < areas.count {
                let next = worst(areas[start...end], side: side)
                if next > best { break }
                best = next
                end += 1
            }
            let rowArea = areas[start..<end].reduce(0, +)
            if remaining.width >= remaining.height {
                let width = rowArea / remaining.height
                var y = remaining.minY
                for i in start..<end {
                    let height = areas[i] / width
                    rects[i] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                let height = rowArea / remaining.width
                var x = remaining.minX
                for i in start..<end {
                    let width = areas[i] / height
                    rects[i] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
            start = end
        }
        return rects
    }

    private static func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else { return .infinity }
        let s2 = side * side
        return max(s2 * largest / (sum * sum), (sum * sum) / (s2 * smallest))
    }
}

// MARK: - View

struct SpaceMapView: View {
    @ObservedObject var map: SpaceMapModel
    @State private var hovered: String?

    private static let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .green, .mint, .cyan, .brown]

    private var shown: [MapNode] { Array(map.nodes.filter { $0.bytes > 0 }.prefix(36)) }
    private var otherBytes: UInt64 {
        map.nodes.filter { $0.bytes > 0 }.dropFirst(36).reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            if map.nodes.isEmpty && map.loading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Measuring folders…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if map.total == 0 && !map.loading {
                Text("Nothing to show here.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    treemap.padding(12)
                    Divider()
                    list.frame(width: 250)
                }
            }
        }
        .onAppear { map.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Space Map", systemImage: "square.grid.3x3.square").font(.title3.bold())
                    Text("What fills your home folder. Click a folder to look inside; nothing is changed from here.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if map.loading {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: Double(map.measured), total: Double(max(map.toMeasure, 1)))
                            .frame(width: 80).controlSize(.small)
                        if let name = map.measuring.sorted().first {
                            Text("Measuring \(name)…").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 180, alignment: .trailing)
                }
                Button { map.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Measure again").disabled(map.loading)
            }
            HStack(spacing: 4) {
                Button { map.back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(map.trail.count < 2)
                ForEach(Array(map.trail.enumerated()), id: \.offset) { index, url in
                    if index > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                    Button(index == 0 ? "Home" : url.lastPathComponent) { map.go(to: index) }
                        .buttonStyle(.link)
                        .disabled(index == map.trail.count - 1)
                }
                Spacer()
                Text(Format.diskBytes(map.total)).font(.callout.monospacedDigit().weight(.semibold))
            }
            .font(.callout)
        }
    }

    private var treemap: some View {
        GeometryReader { geo in
            let nodes = shown
            let values = nodes.map { Double($0.bytes) } + (otherBytes > 0 ? [Double(otherBytes)] : [])
            let rects = Treemap.layout(values, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    tile(node, rect: rects[index], color: color(for: node, index: index))
                }
                if otherBytes > 0, let rect = rects.last {
                    otherTile(rect: rect)
                }
            }
            .animation(Motion.spring, value: map.nodes)
        }
        .frame(minWidth: 300, minHeight: 300)
    }

    private func color(for node: MapNode, index: Int) -> Color {
        node.isFolder ? Self.palette[index % Self.palette.count] : .gray
    }

    private func tile(_ node: MapNode, rect: CGRect, color: Color) -> some View {
        let isHovered = hovered == node.id
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(isHovered ? 0.85 : 0.65).gradient)
            if rect.width > 64 && rect.height > 34 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(Format.diskBytes(node.bytes)).font(.system(size: 10).monospacedDigit()).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(6)
            }
        }
        .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
        .offset(x: rect.minX + 1, y: rect.minY + 1)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? node.id : (hovered == node.id ? nil : hovered) }
        .onTapGesture { map.open(node) }
        .help("\(node.name) — \(Format.diskBytes(node.bytes))\(node.isFolder ? " · click to look inside" : "")")
        .contextMenu { Button("Show in Finder") { map.reveal(node) } }
    }

    private func otherTile(rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.25))
            if rect.width > 64 && rect.height > 34 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Everything else").font(.system(size: 11, weight: .semibold))
                    Text(Format.diskBytes(otherBytes)).font(.system(size: 10).monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(6)
            }
        }
        .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
        .offset(x: rect.minX + 1, y: rect.minY + 1)
    }

    private var list: some View {
        List {
            ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                Button { map.open(node) } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                            .resizable().frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            if node.isProtected {
                                Text("Other apps' private data · not measured").font(.caption2).foregroundStyle(.secondary)
                            } else if map.total > 0 {
                                GeometryReader { g in
                                    Capsule().fill(color(for: node, index: index).opacity(0.7))
                                        .frame(width: g.size.width * CGFloat(Double(node.bytes) / Double(map.total)))
                                }
                                .frame(height: 3)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(node.isProtected ? "—" : Format.diskBytes(node.bytes))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if node.isFolder && !node.isProtected {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Show in Finder") { map.reveal(node) } }
            }
        }
        .listStyle(.inset)
    }
}
