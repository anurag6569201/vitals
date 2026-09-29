import AppKit
import ApplicationServices
import Combine
import Foundation

#if DEBUG
/// Development-only diagnostics. Writes to <repo>/.build/vitals-debug.log and runs experiments
/// when flag files exist in <repo>/.build/. Compiled out of Release builds.
enum DebugProbe {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var buildDir: URL { root.appendingPathComponent(".build") }

    nonisolated static func log(_ text: String) {
        let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(text)\n"
        NSLog("VitalsProbe %@", text)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/vitals-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }

    static func flag(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: buildDir.appendingPathComponent(name).path)
    }

    /// Our own menu-bar extras as macOS reports them through Accessibility (run off the main thread).
    nonisolated static func ownExtras() -> String {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 0.5)
        var bar: AnyObject?
        let r = AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar)
        guard r == .success, let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return "own extras: none (err \(r.rawValue))" }
        var children: AnyObject?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        let list = (children as? [AXUIElement]) ?? []
        let desc = list.map { child -> String in
            var pos: AnyObject?
            var size: AnyObject?
            var point = CGPoint.zero
            var extent = CGSize.zero
            if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &pos) == .success, let pos {
                AXValueGetValue(pos as! AXValue, .cgPoint, &point)
            }
            if AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size) == .success, let size {
                AXValueGetValue(size as! AXValue, .cgSize, &extent)
            }
            return "(\(Int(point.x)),\(Int(point.y)) \(Int(extent.width))x\(Int(extent.height)))"
        }
        return "own extras: \(list.count) \(desc.joined(separator: " "))"
    }

    /// What MenuBarAgent (the process that draws the macOS 27 menu bar) actually shows.
    nonisolated static func agentItems() -> String {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
            return "agent: not running"
        }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var out: [String] = []
        func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
            var v: AnyObject?
            return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
        }
        func walk(_ e: AXUIElement, depth: Int) {
            guard depth < 5, out.count < 80 else { return }
            let role = attr(e, kAXRoleAttribute) as? String ?? "?"
            let title = (attr(e, kAXTitleAttribute) as? String) ?? (attr(e, kAXDescriptionAttribute) as? String) ?? (attr(e, kAXIdentifierAttribute) as? String) ?? ""
            var point = CGPoint.zero
            if let pos = attr(e, kAXPositionAttribute), CFGetTypeID(pos) == AXValueGetTypeID() { AXValueGetValue(pos as! AXValue, .cgPoint, &point) }
            if depth > 0 { out.append("\(String(repeating: ".", count: depth))\(role)[\(title)]@\(Int(point.x))") }
            for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, depth: depth + 1) }
        }
        if let bar = attr(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            walk(bar as! AXUIElement, depth: 0)
        } else {
            walk(app, depth: 0)
        }
        return "agent: " + out.joined(separator: " ")
    }

    static func probe(_ label: String, statusItem: NSStatusItem) {
        let window = statusItem.button?.window
        let screen = NSScreen.main
        let areas = "screen=\(NSStringFromRect(screen?.frame ?? .zero)) right=\(NSStringFromRect(screen?.auxiliaryTopRightArea ?? .zero)) left=\(NSStringFromRect(screen?.auxiliaryTopLeftArea ?? .zero)) prefpos=\(UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position VitalsStatusItem") ?? "nil")"
        log("[\(label)] \(areas)")
        let local = "window visible=\(window?.isVisible ?? false) frame=\(NSStringFromRect(window?.frame ?? .zero)) occl=\(window?.occlusionState.rawValue ?? 0) len=\(statusItem.length)"
        DispatchQueue.global().async {
            let ax = ownExtras()
            log("[\(label)] \(local) | \(ax)")
            log("[\(label)] \(agentItems())")
        }
    }

    /// Interactive experiment driven by command files in <repo>/.build/ (hide-now, restore-now, freeze-on, freeze-off, probe-now).
    static var target: String?

    static func runHideExperiment(statusItem: NSStatusItem, freeze: @escaping (Bool) -> Void) {
        let control = MenuBarControl.shared
        log("bundlePath=\(Bundle.main.bundlePath) ppid=\(getppid())")
        log("=== command loop start; trusted=\(AXIsProcessTrusted()) supported=\(control.isSupported)")
        control.startAfterMenuBarAppears()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                func take(_ name: String) -> Bool {
                    let url = buildDir.appendingPathComponent(name)
                    guard FileManager.default.fileExists(atPath: url.path) else { return false }
                    try? FileManager.default.removeItem(at: url)
                    return true
                }
                if take("hide-now") {
                    target = control.apps.map(\.id).first { $0 != Bundle.main.bundleIdentifier }
                    log("hide \(target ?? "nil") apps=\(control.apps.map(\.id))")
                    if let target { control.setHidden(true, for: target) }
                }
                if take("restore-now"), let target {
                    control.setHidden(false, for: target)
                    log("restored \(target)")
                }
                if take("freeze-on") { freeze(true); log("frozen") }
                if take("freeze-off") { freeze(false); log("unfrozen") }
                if take("clear-all") { control.restoreAndClear(); log("cleared all") }
                if take("install-now") { log("moving to Applications"); control.moveToApplications() }
                if take("quit-now") { log("quit"); NSApp.terminate(nil) }
                if take("probe-now") { log("copies=\(NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").map(\.path)) default=\(NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")?.path ?? "nil")"); log("hidden=\(control.hiddenIDs) system=\(control.hiddenSystemIDs) message=\(control.message ?? "nil") problem=\(String(describing: control.installProblem))"); probe("probe restricted=\(control.isRestrictionActive)", statusItem: statusItem) }
            }
        }
    }
}
#endif
