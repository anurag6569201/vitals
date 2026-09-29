import AppKit
import Combine
import Foundation

/// A folder that takes a lot of space and is safe to rebuild or re-download.
nonisolated struct SpaceHog: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
    let path: String
    let bytes: UInt64
    /// Safe to move to the Trash (caches that rebuild themselves).
    let canTrash: Bool
    /// Trash the folder's contents but keep the folder itself.
    let contentsOnly: Bool
    let lastUsed: Date?
}

nonisolated enum SpaceScanner {
    private nonisolated struct Candidate: Sendable {
        let id: String
        let title: String
        let detail: String
        let path: String
        let canTrash: Bool
        let contentsOnly: Bool
    }

    private static let known: [Candidate] = [
        .init(id: "xcode-deriveddata", title: "Xcode build cache (DerivedData)",
              detail: "Rebuilt automatically the next time you build. Safe to clear.",
              path: "Library/Developer/Xcode/DerivedData", canTrash: true, contentsOnly: true),
        .init(id: "xcode-devicesupport", title: "iPhone debug symbols",
              detail: "Re-downloaded when you connect a device to Xcode. Safe to clear.",
              path: "Library/Developer/Xcode/iOS DeviceSupport", canTrash: true, contentsOnly: true),
        .init(id: "xcode-archives", title: "Old Xcode archives",
              detail: "Past app builds. Keep the ones you may need crash symbols for.",
              path: "Library/Developer/Xcode/Archives", canTrash: false, contentsOnly: false),
        .init(id: "sim-caches", title: "iOS Simulator caches",
              detail: "Rebuilt automatically. Safe to clear.",
              path: "Library/Developer/CoreSimulator/Caches", canTrash: true, contentsOnly: true),
        .init(id: "sim-devices", title: "iOS Simulator devices",
              detail: "Old simulators pile up. In Terminal: xcrun simctl delete unavailable",
              path: "Library/Developer/CoreSimulator/Devices", canTrash: false, contentsOnly: false),
        .init(id: "homebrew", title: "Homebrew downloads",
              detail: "Old package downloads. Safe to clear.",
              path: "Library/Caches/Homebrew", canTrash: true, contentsOnly: true),
        .init(id: "npm", title: "npm cache",
              detail: "Re-downloaded when needed. Safe to clear.",
              path: ".npm/_cacache", canTrash: true, contentsOnly: true),
        .init(id: "yarn", title: "Yarn cache",
              detail: "Re-downloaded when needed. Safe to clear.",
              path: "Library/Caches/Yarn", canTrash: true, contentsOnly: true),
        .init(id: "pnpm", title: "pnpm store",
              detail: "Shared package store. Clear with: pnpm store prune",
              path: "Library/pnpm/store", canTrash: false, contentsOnly: false),
        .init(id: "pip", title: "pip cache",
              detail: "Re-downloaded when needed. Safe to clear.",
              path: "Library/Caches/pip", canTrash: true, contentsOnly: true),
        .init(id: "gradle", title: "Gradle cache",
              detail: "Re-downloaded when needed. Safe to clear.",
              path: ".gradle/caches", canTrash: true, contentsOnly: true),
        .init(id: "cocoapods", title: "CocoaPods cache",
              detail: "Re-downloaded when needed. Safe to clear.",
              path: "Library/Caches/CocoaPods", canTrash: true, contentsOnly: true),
        .init(id: "huggingface", title: "Downloaded AI models (Hugging Face)",
              detail: "Big model files. Delete the ones you no longer use.",
              path: ".cache/huggingface", canTrash: false, contentsOnly: false),
        .init(id: "ollama", title: "Ollama models",
              detail: "Remove unused ones with: ollama rm <model>",
              path: ".ollama/models", canTrash: false, contentsOnly: false),
        .init(id: "docker", title: "Docker disk image",
              detail: "Shrink it from Docker Desktop › Troubleshoot › Clean / Purge data.",
              path: "Library/Containers/com.docker.docker/Data/vms", canTrash: false, contentsOnly: false),
        .init(id: "ios-backups", title: "iPhone & iPad backups",
              detail: "Manage them in Finder: select your device › Manage Backups.",
              path: "Library/Application Support/MobileSync/Backup", canTrash: false, contentsOnly: false),
    ]

    static let minimumBytes: UInt64 = 200_000_000

    static func scanKnown() -> [SpaceHog] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return known.compactMap { candidate in
            let url = home.appendingPathComponent(candidate.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = size(of: url)
            guard bytes >= minimumBytes else { return nil }
            return SpaceHog(id: candidate.id, title: candidate.title, detail: candidate.detail, path: url.path,
                            bytes: bytes, canTrash: candidate.canTrash, contentsOnly: candidate.contentsOnly,
                            lastUsed: nil)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Finds rebuildable project folders (node_modules, Pods, .build, venvs, Rust target) under a folder the person picked.
    static func scanProjects(in root: URL) -> [SpaceHog] {
        var results: [SpaceHog] = []
        let fm = FileManager.default
        let buildDirs: Set<String> = ["node_modules", "Pods", ".build", "venv", ".venv", "DerivedData", ".next", ".gradle"]

        func walk(_ url: URL, depth: Int) {
            guard depth <= 6, let children = try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let name = child.lastPathComponent
                let isRustTarget = name == "target" && fm.fileExists(atPath: url.appendingPathComponent("Cargo.toml").path)
                if buildDirs.contains(name) || isRustTarget {
                    let bytes = size(of: child)
                    if bytes >= 50_000_000 {
                        let project = url.lastPathComponent
                        let used = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        results.append(SpaceHog(
                            id: child.path, title: "\(project) › \(name)",
                            detail: rebuildHint(name, isRustTarget: isRustTarget),
                            path: child.path, bytes: bytes, canTrash: true, contentsOnly: false, lastUsed: used))
                    }
                    continue
                }
                if name.hasPrefix(".") || name == "Library" { continue }
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return results.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }

    private static func rebuildHint(_ name: String, isRustTarget: Bool) -> String {
        if isRustTarget { return "Rust build output. Rebuilt by cargo build." }
        switch name {
        case "node_modules": return "Reinstalled by npm install."
        case "Pods": return "Reinstalled by pod install."
        case ".build", "DerivedData": return "Swift build output. Rebuilt on the next build."
        case "venv", ".venv": return "Python environment. Recreate it from requirements."
        case ".next": return "Next.js build cache. Rebuilt on the next build."
        case ".gradle": return "Gradle project cache. Rebuilt on the next build."
        default: return "Rebuilt automatically."
        }
    }

    static func size(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Moves to the Trash (recoverable). Returns bytes freed.
    static func trash(_ hog: SpaceHog) -> UInt64 {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: hog.path)
        if hog.contentsOnly {
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for child in children { try? fm.trashItem(at: child, resultingItemURL: nil) }
        } else {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
        let remaining = fm.fileExists(atPath: url.path) ? size(of: url) : 0
        return hog.bytes > remaining ? hog.bytes - remaining : 0
    }
}

@MainActor
final class SpaceModel: ObservableObject {
    @Published private(set) var known: [SpaceHog] = []
    @Published private(set) var projects: [SpaceHog] = []
    @Published private(set) var isScanning = false
    @Published private(set) var projectRoot: URL?
    @Published var message: String?
    private(set) var hasScanned = false

    var totalTrashable: UInt64 {
        (known + projects).filter(\.canTrash).reduce(0) { $0 + $1.bytes }
    }

    func scanIfNeeded() {
        guard !hasScanned else { return }
        scan()
    }

    func scan() {
        hasScanned = true
        isScanning = true
        let root = projectRoot
        Task {
            let result = await Task.detached(priority: .utility) {
                (SpaceScanner.scanKnown(), root.map { SpaceScanner.scanProjects(in: $0) } ?? [])
            }.value
            known = result.0
            projects = result.1
            isScanning = false
        }
    }

    func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Pick the folder where you keep code projects (for example ~/Developer)."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectRoot = url
        scan()
    }

    func trash(_ hog: SpaceHog) {
        isScanning = true
        Task {
            let freed = await Task.detached(priority: .userInitiated) { SpaceScanner.trash(hog) }.value
            known.removeAll { $0.id == hog.id }
            projects.removeAll { $0.id == hog.id }
            message = "Moved to the Trash — \(Format.diskBytes(freed)) will be freed when you empty it."
            isScanning = false
        }
    }

    func reveal(_ hog: SpaceHog) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hog.path)])
    }
}
