import Combine
import AppKit
import ServiceManagement
import UserNotifications

enum SystemActions {
    /// Politely asks every running instance of the app to quit. Returns false if macOS refused
    /// (for example inside the App Sandbox) — callers then fall back to Activity Monitor.
    @discardableResult
    static func quit(_ identity: AppIdentity, force: Bool = false) -> Bool {
        guard Edition.canQuitApps else { return false }
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

/// Delivers Vitals alerts as macOS notifications, with the issue's actions as notification buttons.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Action identifiers that aren't an `IssueAction`.
    static let quitAllAction = "vitals.quitAll"
    static let upgradeAction = "vitals.upgrade"

    /// (notification id, action identifier, userInfo). Default tap arrives as `UNNotificationDefaultActionIdentifier`.
    var onResponse: (@MainActor (String, String, [AnyHashable: Any]) -> Void)?

    private var categories: [String: UNNotificationCategory] = [:]
    private var center: UNUserNotificationCenter { .current() }

    func start() {
        center.delegate = self
    }

    static func requestPermission(completion: (@MainActor (Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion?(granted) } }
        }
    }

    /// Whether macOS will actually show Vitals notifications.
    static func checkCanDeliver(_ completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(ok) } }
        }
    }

    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Posts (or replaces) a notification. `actions` are (identifier, title) pairs shown as buttons.
    func post(id: String, title: String, body: String,
              actions: [(id: String, title: String)] = [], userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.userInfo = userInfo
        content.threadIdentifier = "vitals.alerts"
        if !actions.isEmpty {
            content.categoryIdentifier = register(actions)
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func register(_ actions: [(id: String, title: String)]) -> String {
        let key = "vitals." + actions.map(\.title).joined(separator: "|")
        if categories[key] == nil {
            let buttons = actions.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) }
            categories[key] = UNNotificationCategory(identifier: key, actions: buttons, intentIdentifiers: [], options: [])
            center.setNotificationCategories(Set(categories.values))
        }
        return key
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while the Vitals popover is open (the app is active then).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onResponse?(id, action, info) }
            completionHandler()
        }
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
