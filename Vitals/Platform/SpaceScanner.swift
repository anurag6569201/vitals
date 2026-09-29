import AppKit
import Combine
import CoreServices
import CryptoKit
import Darwin
import Foundation

// MARK: - Model

nonisolated enum SpaceCategory: String, CaseIterable, Identifiable, Sendable {
    case bigFiles, downloads, installers, screenshots, duplicates, unusedApps, caches, developer, devices, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bigFiles: "Large files"
        case .downloads: "Old downloads"
        case .installers: "Installers & archives"
        case .screenshots: "Old screenshots"
        case .duplicates: "Duplicates"
        case .unusedApps: "Apps you don't use"
        case .caches: "App caches"
        case .developer: "Developer junk"
        case .devices: "iPhone & iPad"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .bigFiles: "doc.richtext"
        case .downloads: "arrow.down.circle"
        case .installers: "shippingbox"
        case .screenshots: "camera.viewfinder"
        case .duplicates: "square.on.square"
        case .unusedApps: "app.dashed"
        case .caches: "archivebox"
        case .developer: "hammer"
        case .devices: "iphone"
        case .trash: "trash"
        }
    }

    var explanation: String {
        switch self {
        case .bigFiles: "Your biggest files, with when you last opened them. Review before removing — these are your files."
        case .downloads: "Things in Downloads you haven't opened in over a month."
        case .installers: "Disk images and installers you've already used, and archives you've already unzipped."
        case .screenshots: "Screenshots and screen recordings older than a month."
        case .duplicates: "Identical copies of the same file. Vitals keeps the newest copy selected to stay."
        case .unusedApps: "Apps you haven't opened in 3 months or more."
        case .caches: "Temporary files apps rebuild on their own, including leftovers from apps you've deleted."
        case .developer: "Build caches and tools that rebuild or re-download themselves."
        case .devices: "iPhone and iPad software updates and backups."
        case .trash: "Files already in the Trash still take up space until you empty it."
        }
    }

    /// Safe categories are pre-selected; your own files never are.
    var preselect: Bool {
        switch self {
        case .caches, .developer, .installers: true
        default: false
        }
    }
}

nonisolated struct SpaceItem: Identifiable, Sendable, Hashable {
    let id: String
    let category: SpaceCategory
    let title: String
    let subtitle: String
    let path: String
    let bytes: UInt64
    let lastUsed: Date?
    /// Can be moved to the Trash from Vitals.
    let canTrash: Bool
    /// Trash the folder's contents, keep the folder.
    let contentsOnly: Bool
    /// Duplicates: items with the same group are copies of each other.
    let group: String?
    /// Duplicates: the copy Vitals suggests keeping.
    let keep: Bool
}

// MARK: - Folder access

/// App Store builds are sandboxed: they may only read folders the person chooses. Vitals asks once
/// for the home folder and remembers the choice with a security-scoped bookmark.
enum SpaceAccess {
    nonisolated static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    #if APPSTORE
    private static let bookmarkKey = "vitals.space.homeBookmark"
    private static var accessed: URL?

    static var isGranted: Bool { accessed != nil || restore() }

    @discardableResult
    static func restore() -> Bool {
        guard accessed == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return accessed != nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return false }
        accessed = url
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return true
    }

    /// Shows the standard folder picker, opened on the home folder.
    @discardableResult
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = realHome
        panel.prompt = "Allow"
        panel.message = "Choose your home folder (\(realHome.lastPathComponent)) so Vitals can look for files you can clear. Nothing leaves your Mac."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return restore()
    }
    #else
    static var isGranted: Bool { true }
    @discardableResult static func request() -> Bool { true }
    #endif
}

// MARK: - Scanner

nonisolated enum SpaceScanner {
    /// The real home folder. (In a sandboxed build FileManager's home is the app's container.)
    static let home = SpaceAccess.realHome
    static let month: TimeInterval = 30 * 86_400

    static func scan(_ category: SpaceCategory, projectRoot: URL?) -> [SpaceItem] {
        switch category {
        case .bigFiles: bigFiles()
        case .downloads: oldDownloads()
        case .installers: installers()
        case .screenshots: screenshots()
        case .duplicates: duplicates()
        case .unusedApps: unusedApps()
        case .caches: caches()
        case .developer: developer() + (projectRoot.map { projectBuildFolders(in: $0) } ?? [])
        case .devices: devices()
        case .trash: trash()
        }
    }

    // MARK: Large files (Spotlight)

    static func bigFiles() -> [SpaceItem] {
        spotlight("kMDItemFSSize >= 500000000")
            .filter { !isInsideBundle($0) && !$0.path.contains("/Library/") }
            .compactMap { url in
                let bytes = fileSize(url)
                guard bytes >= 500_000_000 else { return nil }
                return SpaceItem(id: url.path, category: .bigFiles, title: url.lastPathComponent,
                                 subtitle: prettyFolder(url), path: url.path, bytes: bytes,
                                 lastUsed: lastUsed(url), canTrash: true, contentsOnly: false, group: nil, keep: false)
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(60).map { $0 }
    }

    // MARK: Downloads, installers, screenshots

    static func oldDownloads() -> [SpaceItem] {
        let downloads = home.appendingPathComponent("Downloads")
        let cutoff = Date().addingTimeInterval(-month)
        return topLevel(downloads).compactMap { url in
            guard !isInstaller(url) else { return nil }
            let used = lastUsed(url) ?? dateAdded(url) ?? modified(url)
            guard let used, used < cutoff else { return nil }
            let bytes = size(of: url)
            guard bytes >= 5_000_000 else { return nil }
            return SpaceItem(id: url.path, category: .downloads, title: url.lastPathComponent,
                             subtitle: "Downloads", path: url.path, bytes: bytes, lastUsed: used,
                             canTrash: true, contentsOnly: false, group: nil, keep: false)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    static func installers() -> [SpaceItem] {
        let folders = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        var results: [SpaceItem] = []
        for folder in folders {
            let items = topLevel(folder)
            let names = Set(items.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
            for url in items {
                let ext = url.pathExtension.lowercased()
                var reason: String?
                if ["dmg", "pkg", "mpkg", "xip", "iso"].contains(ext) {
                    reason = appInstalled(named: url.deletingPathExtension().lastPathComponent)
                        ? "Installer for an app you already have" : "Disk image or installer"
                } else if ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) {
                    let base = url.deletingPathExtension().lastPathComponent.lowercased()
                    let unzipped = items.contains { $0 != url && $0.deletingPathExtension().lastPathComponent.lowercased() == base }
                    if unzipped || names.contains(base + ".app") { reason = "Already unzipped next to it" }
                }
                guard let reason else { continue }
                let bytes = size(of: url)
                guard bytes >= 1_000_000 else { continue }
                results.append(SpaceItem(id: url.path, category: .installers, title: url.lastPathComponent,
                                         subtitle: "\(folder.lastPathComponent) · \(reason)", path: url.path, bytes: bytes,
                                         lastUsed: dateAdded(url) ?? modified(url), canTrash: true, contentsOnly: false,
                                         group: nil, keep: false))
            }
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    static func screenshots() -> [SpaceItem] {
        var folders = [home.appendingPathComponent("Desktop"), home.appendingPathComponent("Pictures/Screenshots")]
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            folders.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        }
        let cutoff = Date().addingTimeInterval(-month)
        var seen = Set<String>()
        var results: [SpaceItem] = []
        for folder in folders {
            for url in topLevel(folder) where seen.insert(url.path).inserted {
                let name = url.lastPathComponent
                guard ["Screenshot", "Screen Shot", "Screen Recording", "CleanShot"].contains(where: { name.hasPrefix($0) }),
                      let date = modified(url), date < cutoff else { continue }
                let bytes = fileSize(url)
                results.append(SpaceItem(id: url.path, category: .screenshots, title: name,
                                         subtitle: folder.lastPathComponent, path: url.path, bytes: bytes,
                                         lastUsed: date, canTrash: true, contentsOnly: false, group: nil, keep: false))
            }
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    // MARK: Duplicates

    static func duplicates() -> [SpaceItem] {
        let candidates = spotlight("kMDItemFSSize >= 20000000")
            .filter { !isInsideBundle($0) && !$0.path.contains("/Library/") && !$0.lastPathComponent.hasPrefix(".") }
            .prefix(4000)
        var bySize: [UInt64: [URL]] = [:]
        for url in candidates {
            let bytes = fileSize(url)
            if bytes > 0 { bySize[bytes, default: []].append(url) }
        }
        var results: [SpaceItem] = []
        for (bytes, urls) in bySize where urls.count > 1 {
            // Cheap fingerprint first, then a full hash to be certain.
            var byQuick: [String: [URL]] = [:]
            for url in urls { if let quick = quickHash(url, size: bytes) { byQuick[quick, default: []].append(url) } }
            for (_, group) in byQuick where group.count > 1 {
                var byFull: [String: [URL]] = [:]
                for url in group { if let full = fullHash(url) { byFull[full, default: []].append(url) } }
                for (hash, copies) in byFull where copies.count > 1 {
                    let newest = copies.max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
                    for url in copies {
                        results.append(SpaceItem(id: url.path, category: .duplicates, title: url.lastPathComponent,
                                                 subtitle: prettyFolder(url), path: url.path, bytes: bytes,
                                                 lastUsed: modified(url), canTrash: true, contentsOnly: false,
                                                 group: hash, keep: url == newest))
                    }
                }
            }
        }
        return results.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : ($0.group ?? "") < ($1.group ?? "") }
    }

    private static func quickHash(_ url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 256 * 1024
        for offset in [UInt64(0), size / 2, size > UInt64(chunk) ? size - UInt64(chunk) : 0] {
            try? handle.seek(toOffset: offset)
            if let data = try? handle.read(upToCount: chunk) { hasher.update(data: data) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Apps

    static func unusedApps() -> [SpaceItem] {
        let cutoff = Date().addingTimeInterval(-3 * month)
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var results: [SpaceItem] = []
        for folder in folders {
            var apps: [URL] = []
            for url in topLevel(folder) {
                if url.pathExtension == "app" { apps.append(url) }
                else if isDirectory(url) { apps.append(contentsOf: topLevel(url).filter { $0.pathExtension == "app" }) }
            }
            for app in apps {
                let bundle = Bundle(url: app)
                let id = bundle?.bundleIdentifier ?? ""
                if id.hasPrefix("com.apple.") || id == Bundle.main.bundleIdentifier { continue }
                let used = lastUsed(app)
                if let used, used > cutoff { continue }
                if used == nil, let added = dateAdded(app) ?? modified(app), added > cutoff { continue }
                let bytes = size(of: app)
                guard bytes >= 50_000_000 else { continue }
                let name = app.deletingPathExtension().lastPathComponent
                let subtitle = used.map { "Last opened \($0.formatted(.relative(presentation: .named)))" } ?? "Never opened on this Mac"
                results.append(SpaceItem(id: app.path, category: .unusedApps, title: name, subtitle: subtitle,
                                         path: app.path, bytes: bytes, lastUsed: used, canTrash: true,
                                         contentsOnly: false, group: nil, keep: false))
            }
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    // MARK: Caches

    static func caches() -> [SpaceItem] {
        let root = home.appendingPathComponent("Library/Caches")
        var results: [SpaceItem] = []
        for url in topLevel(root) where isDirectory(url) {
            let id = url.lastPathComponent
            if id.hasPrefix("com.apple.") || id == Bundle.main.bundleIdentifier || id == "Homebrew" || id == "CocoaPods"
                || id == "Yarn" || id == "pip" { continue }
            let bytes = size(of: url)
            guard bytes >= 100_000_000 else { continue }
            let looksLikeBundleID = id.split(separator: ".").count >= 3
            let appURL = looksLikeBundleID ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) : nil
            let name = appURL.map { $0.deletingPathExtension().lastPathComponent } ?? id
            let leftover = looksLikeBundleID && appURL == nil
            results.append(SpaceItem(id: url.path, category: .caches, title: name,
                                     subtitle: leftover ? "Left behind by an app you deleted" : "Rebuilt automatically · quit the app first",
                                     path: url.path, bytes: bytes, lastUsed: nil, canTrash: true,
                                     contentsOnly: !leftover, group: nil, keep: false))
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    // MARK: Developer

    private static let developerFolders: [(String, String, String, Bool, Bool)] = [
        ("Library/Developer/Xcode/DerivedData", "Xcode build cache", "Rebuilt on your next build.", true, true),
        ("Library/Developer/Xcode/iOS DeviceSupport", "iPhone debug symbols", "Re-downloaded when you connect a device.", true, true),
        ("Library/Developer/Xcode/Archives", "Old Xcode archives", "Keep any you need crash symbols for.", false, false),
        ("Library/Developer/CoreSimulator/Caches", "Simulator caches", "Rebuilt automatically.", true, true),
        ("Library/Developer/CoreSimulator/Devices", "Simulator devices", "In Terminal: xcrun simctl delete unavailable", false, false),
        ("Library/Caches/Homebrew", "Homebrew downloads", "Old package downloads.", true, true),
        (".npm/_cacache", "npm cache", "Re-downloaded when needed.", true, true),
        ("Library/Caches/Yarn", "Yarn cache", "Re-downloaded when needed.", true, true),
        ("Library/pnpm/store", "pnpm store", "Clear with: pnpm store prune", false, false),
        ("Library/Caches/pip", "pip cache", "Re-downloaded when needed.", true, true),
        (".gradle/caches", "Gradle cache", "Re-downloaded when needed.", true, true),
        ("Library/Caches/CocoaPods", "CocoaPods cache", "Re-downloaded when needed.", true, true),
        (".cache/huggingface", "Hugging Face models", "Delete the models you no longer use.", false, false),
        (".ollama/models", "Ollama models", "Remove with: ollama rm <model>", false, false),
        ("Library/Containers/com.docker.docker/Data/vms", "Docker disk image", "Shrink it in Docker Desktop › Troubleshoot.", false, false),
    ]

    static func developer() -> [SpaceItem] {
        developerFolders.compactMap { path, title, detail, canTrash, contentsOnly in
            let url = home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = size(of: url)
            guard bytes >= 100_000_000 else { return nil }
            return SpaceItem(id: url.path, category: .developer, title: title, subtitle: detail, path: url.path,
                             bytes: bytes, lastUsed: nil, canTrash: canTrash, contentsOnly: contentsOnly,
                             group: nil, keep: false)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    static func projectBuildFolders(in root: URL) -> [SpaceItem] {
        var results: [SpaceItem] = []
        let fm = FileManager.default
        let buildDirs: Set<String> = ["node_modules", "Pods", ".build", "venv", ".venv", "DerivedData", ".next", ".gradle"]
        func walk(_ url: URL, depth: Int) {
            guard depth <= 6 else { return }
            for child in topLevel(url, includeHidden: true) where isDirectory(child) {
                let name = child.lastPathComponent
                let isRust = name == "target" && fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path)
                if buildDirs.contains(name) || isRust {
                    let bytes = size(of: child)
                    if bytes >= 50_000_000 {
                        results.append(SpaceItem(id: child.path, category: .developer, title: "\(url.lastPathComponent) › \(name)",
                                                 subtitle: "Project build folder · rebuilt when you build or install again",
                                                 path: child.path, bytes: bytes, lastUsed: modified(url), canTrash: true,
                                                 contentsOnly: false, group: nil, keep: false))
                    }
                    continue
                }
                if name.hasPrefix(".") || name == "Library" { continue }
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return results
    }

    // MARK: Devices & Trash

    static func devices() -> [SpaceItem] {
        var results: [SpaceItem] = []
        for folder in ["Library/iTunes/iPhone Software Updates", "Library/iTunes/iPad Software Updates"] {
            for url in topLevel(home.appendingPathComponent(folder)) where url.pathExtension == "ipsw" {
                results.append(SpaceItem(id: url.path, category: .devices, title: url.lastPathComponent,
                                         subtitle: "Old iOS software update · downloaded again if needed", path: url.path,
                                         bytes: fileSize(url), lastUsed: modified(url), canTrash: true,
                                         contentsOnly: false, group: nil, keep: false))
            }
        }
        let backups = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        for url in topLevel(backups) where isDirectory(url) {
            let bytes = size(of: url)
            guard bytes > 0 else { continue }
            results.append(SpaceItem(id: url.path, category: .devices, title: "Device backup", subtitle:
                                     "Manage in Finder › your device › Manage Backups", path: url.path, bytes: bytes,
                                     lastUsed: modified(url), canTrash: false, contentsOnly: false, group: nil, keep: false))
        }
        return results.sorted { $0.bytes > $1.bytes }
    }

    static func trash() -> [SpaceItem] {
        let url = home.appendingPathComponent(".Trash")
        let bytes = size(of: url)
        guard bytes >= 10_000_000 else { return [] }
        return [SpaceItem(id: url.path, category: .trash, title: "Items in the Trash",
                          subtitle: "Empty the Trash in Finder to get this space back", path: url.path, bytes: bytes,
                          lastUsed: nil, canTrash: false, contentsOnly: false, group: nil, keep: false)]
    }

    // MARK: Actions

    /// Moves to the Trash (always recoverable). Returns bytes moved, or nil if macOS refused.
    static func moveToTrash(_ item: SpaceItem) -> UInt64? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: item.path)
        do {
            if item.contentsOnly {
                for child in (try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) {
                    try? fm.trashItem(at: child, resultingItemURL: nil)
                }
            } else {
                try fm.trashItem(at: url, resultingItemURL: nil)
            }
            return item.bytes
        } catch {
            return nil
        }
    }

    // MARK: Helpers

    private static func spotlight(_ query: String) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", home.path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let found = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
        return found.isEmpty ? walkUserFolders() : found
    }

    /// Fallback when Spotlight is off or returns nothing: walk the usual user folders.
    private static func walkUserFolders() -> [URL] {
        var results: [URL] = []
        for name in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"] {
            guard let enumerator = FileManager.default.enumerator(
                at: home.appendingPathComponent(name), includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true, (values?.fileSize ?? 0) >= 20_000_000 { results.append(url) }
            }
        }
        return results
    }

    static func topLevel(_ folder: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: options)) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private static func isInsideBundle(_ url: URL) -> Bool {
        let path = url.path
        return path.contains(".app/") || path.contains(".photoslibrary/") || path.contains(".musiclibrary/")
            || path.contains(".tvlibrary/") || path.contains(".fcpbundle/") || path.contains(".logicx/")
    }

    private static func isInstaller(_ url: URL) -> Bool {
        ["dmg", "pkg", "mpkg", "xip", "iso"].contains(url.pathExtension.lowercased())
    }

    private static func appInstalled(named name: String) -> Bool {
        let base = name.components(separatedBy: CharacterSet(charactersIn: "-_ 0123456789.")).first(where: { $0.count > 2 }) ?? name
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        return apps.contains { $0.lowercased().hasPrefix(base.lowercased()) }
    }

    private static func prettyFolder(_ url: URL) -> String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~")
    }

    private static func metadataDate(_ url: URL, _ key: CFString) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, key) as? Date
    }

    static func lastUsed(_ url: URL) -> Date? { metadataDate(url, kMDItemLastUsedDate) }
    private static func dateAdded(_ url: URL) -> Date? { metadataDate(url, kMDItemDateAdded) }
    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return size(of: url) }
        return UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    static func size(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
        let values = try? url.resourceValues(forKeys: Set(keys))
        if values?.isDirectory != true { return UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - View model

@MainActor
final class SpaceModel: ObservableObject {
    @Published private(set) var items: [SpaceCategory: [SpaceItem]] = [:]
    @Published private(set) var scanning: Set<SpaceCategory> = []
    @Published var selection: Set<String> = []
    @Published var message: String?
    @Published private(set) var projectRoot: URL?
    @Published private(set) var lastScan: Date?

    var isScanning: Bool { !scanning.isEmpty }

    private let launchDate = Date()
    private var lastBackgroundScan: Date?
    private static let openedKey = "vitals.space.opened"

    /// Folders like Downloads and Desktop trigger a macOS permission prompt, so they're only
    /// scanned in the background after the person has opened Free Up Space themselves.
    var hasOpenedTool: Bool { UserDefaults.standard.bool(forKey: Self.openedKey) }

    func markOpened() {
        UserDefaults.standard.set(true, forKey: Self.openedKey)
    }

    /// Once a day, while plugged in, quietly refresh the cheap categories so the popover
    /// can say how much space is waiting to be freed.
    func backgroundRefreshIfDue(onAC: Bool) {
        guard onAC, !isScanning, Date().timeIntervalSince(launchDate) > 300 else { return }
        if let last = [lastScan, lastBackgroundScan].compactMap({ $0 }).max(),
           Date().timeIntervalSince(last) < 86_400 { return }
        lastBackgroundScan = Date()
        let categories: [SpaceCategory] = hasOpenedTool
            ? [.bigFiles, .downloads, .installers, .screenshots, .caches, .developer, .devices, .trash]
            : [.caches, .developer, .devices]
        for category in categories { scan(category) }
    }

    func total(_ category: SpaceCategory) -> UInt64 {
        (items[category] ?? []).reduce(0) { $0 + $1.bytes }
    }

    var reviewableTotal: UInt64 {
        SpaceCategory.allCases.filter { $0 != .trash }.reduce(0) { $0 + total($1) }
    }

    var selectedItems: [SpaceItem] {
        items.values.flatMap { $0 }.filter { selection.contains($0.id) && $0.canTrash }
    }

    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    func scanIfNeeded() {
        if let lastScan, Date().timeIntervalSince(lastScan) < 600 { return }
        scanAll()
    }

    var hasAccess: Bool { SpaceAccess.isGranted }

    func requestAccess() {
        if SpaceAccess.request() {
            objectWillChange.send()
            scanAll()
        }
    }

    func scanAll() {
        guard hasAccess else { return }
        lastScan = Date()
        for category in SpaceCategory.allCases { scan(category) }
    }

    func scan(_ category: SpaceCategory) {
        guard hasAccess, !scanning.contains(category) else { return }
        scanning.insert(category)
        let root = projectRoot
        Task {
            let found = await Task.detached(priority: .utility) { SpaceScanner.scan(category, projectRoot: root) }.value
            items[category] = found
            for item in found where item.canTrash {
                if category == .duplicates { if !item.keep { selection.insert(item.id) } }
                else if category.preselect { selection.insert(item.id) }
            }
            scanning.remove(category)
        }
    }

    func toggle(_ item: SpaceItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func select(all category: SpaceCategory, _ on: Bool) {
        for item in items[category] ?? [] where item.canTrash {
            if on { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        panel.message = "Pick the folder where you keep code projects."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectRoot = url
        scan(.developer)
    }

    func trashSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        scanning.insert(.trash)
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                targets.map { ($0.id, SpaceScanner.moveToTrash($0)) }
            }.value
            var freed: UInt64 = 0
            var failed = 0
            for (id, bytes) in results {
                if let bytes {
                    freed += bytes
                    selection.remove(id)
                    for category in SpaceCategory.allCases { items[category]?.removeAll { $0.id == id } }
                } else {
                    failed += 1
                }
            }
            scanning.remove(.trash)
            var text = "Moved \(Format.diskBytes(freed)) to the Trash. Empty the Trash to get the space back."
            if failed > 0 { text += " \(failed) item\(failed == 1 ? "" : "s") need your password — drag them to the Trash in Finder." }
            message = text
            scan(.trash)
        }
    }

    func reveal(_ item: SpaceItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func openTrash() {
        NSWorkspace.shared.open(SpaceScanner.home.appendingPathComponent(".Trash"))
    }
}
