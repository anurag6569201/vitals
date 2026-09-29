import Combine
import AppKit
import ServiceManagement
import UserNotifications

enum SystemActions {
    /// Politely asks every running instance of the app to quit. Returns false if macOS refused
    /// (for example inside the App Sandbox) — callers then fall back to Activity Monitor.
    @discardableResult
    static func quit(_ identity: AppIdentity, force: Bool = false) -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            if let id = identity.bundleID, app.bundleIdentifier == id { return true }
            if let path = identity.bundlePath, app.bundleURL?.path == path { return true }
            return false
        }
        guard !running.isEmpty else { return false }
        var ok = true
        for app in running {
            ok = (force ? app.forceTerminate() : app.terminate()) && ok
        }
        return ok
    }

    static func openActivityMonitor() {
        open(bundleID: "com.apple.ActivityMonitor")
    }

    static func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMenuBarSettings() {
        for id in ["com.apple.MenuBar-Settings.extension", "com.apple.ControlCenter-Settings.extension"] {
            if let url = URL(string: "x-apple.systempreferences:\(id)"), NSWorkspace.shared.open(url) { return }
        }
    }

    static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func icon(for identity: AppIdentity?) -> NSImage? {
        guard let path = identity?.bundlePath else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Vitals launch-at-login change failed: %@", error.localizedDescription)
        }
    }
}

enum Notifier {
    static func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Tracks whether the person is away: screen locked, displays asleep, or the Mac asleep.
final class PresenceMonitor {
    private(set) var isLocked = false
    private(set) var displaysAsleep = false
    private(set) var systemAsleep = false

    var isAway: Bool { isLocked || displaysAsleep || systemAsleep }

    /// (wasAway, isAway)
    var onChange: ((Bool, Bool) -> Void)?
    var onSystemSleep: (() -> Void)?
    var onSystemWake: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        tokens.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.isLocked = true } }
        })
        tokens.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.isLocked = false } }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.displaysAsleep = true } }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.displaysAsleep = false } }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update { $0.systemAsleep = true }
                self?.onSystemSleep?()
            }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onSystemWake?()
                self?.update { $0.systemAsleep = false }
            }
        })
    }

    private func update(_ change: (PresenceMonitor) -> Void) {
        let before = isAway
        change(self)
        if before != isAway { onChange?(before, isAway) }
    }
}
