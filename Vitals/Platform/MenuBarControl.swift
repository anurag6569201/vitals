import AppKit
import ApplicationServices
import Combine
import Foundation

// The macOS 27 restriction bridge is adapted from MenuBarHider by Saveliy Yudin (MIT).
// See THIRD_PARTY_NOTICES.md. Apple does not publish this API; resolve it at runtime.
@objc private protocol MenuBarAssessmentAssertion {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(with configuration: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

private final class MenuBarVisibilityBridge {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationInit = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")

    private let classes: (assertion: NSObject.Type, configuration: NSObject.Type)?
    private var active: MenuBarAssessmentAssertion?
    private var pending: MenuBarAssessmentAssertion?

    init() {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              assertion.instancesRespond(to: #selector(MenuBarAssessmentAssertion.activate(with:completionHandler:))),
              assertion.instancesRespond(to: #selector(MenuBarAssessmentAssertion.invalidate)),
              configuration.instancesRespond(to: Self.configurationInit)
        else {
            classes = nil
            return
        }
        classes = (assertion, configuration)
    }

    var isAvailable: Bool { classes != nil }

    func showOnly(bundleIDs: [String], hiddenSystemIDs: Set<Int>, completion: @escaping (Error?) -> Void) {
        guard let classes else {
            completion(NSError(domain: "Vitals", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "Menu-bar control is unavailable on this macOS build."]))
            return
        }
        let allocated = (classes.configuration as AnyObject)
            .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        // Preserve all known and future Apple system items. Only third-party bundle IDs are filtered.
        let systemItems = (0..<64).filter { !hiddenSystemIDs.contains($0) }
            .map { NSNumber(value: $0) } as NSArray
        guard let configuration = allocated?.perform(Self.configurationInit,
                                                     with: systemItems,
                                                     with: bundleIDs as NSArray)?.takeRetainedValue() else {
            completion(NSError(domain: "Vitals", code: 2,
                               userInfo: [NSLocalizedDescriptionKey: "Could not configure the menu bar."]))
            return
        }

        pending?.invalidate()
        let assertion = unsafeBitCast(classes.assertion.init(), to: MenuBarAssessmentAssertion.self)
        pending = assertion
        assertion.activate(with: configuration) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.pending === assertion else { return }
                self.pending = nil
                if let error {
                    assertion.invalidate()
                    completion(error)
                } else {
                    self.active?.invalidate()
                    self.active = assertion
                    completion(nil)
                }
            }
        }
    }

    func restoreAll() {
        pending?.invalidate()
        pending = nil
        active?.invalidate()
        active = nil
    }
}

struct ControlledMenuApp: Identifiable {
    let id: String // bundle identifier
    let name: String
    let items: [ControlledMenuItem]
    let x: CGFloat
    let icon: NSImage?

    var itemCount: Int { items.count }
}

struct ControlledMenuItem: Identifiable {
    let id: String
    let index: Int
    let title: String
    let x: CGFloat
}

private enum MenuItemActivator {
    static func appItem(pid: pid_t, index: Int) -> Bool {
        guard let bar = extrasMenuBar(pid: pid),
              let items = children(of: bar), items.indices.contains(index) else { return false }
        return performPress(on: items[index])
    }

    static func systemItem(pid: pid_t, item: ControlledSystemItem) -> Bool {
        guard let bar = extrasMenuBar(pid: pid), let groups = children(of: bar) else { return false }
        for group in groups {
            for child in children(of: group) ?? [] {
                var identifier: AnyObject?
                guard AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier) == .success,
                      let identifier = identifier as? String else { continue }
                if item.matches(identifier: identifier) { return performPress(on: child) }
            }
        }
        return false
    }

    private static func extrasMenuBar(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    private static func performPress(on item: AXUIElement) -> Bool {
        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
        // A status item can open a modal menu and fail to answer before the AX timeout.
        return result == .success || result == .cannotComplete
    }
}

enum ControlledSystemItem: Int, CaseIterable, Identifiable {
    case battery = 0, bluetooth = 1, displays = 3, keyboard = 4
    case sound = 5, wifi = 6, screenMirroring = 7

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .displays: "Displays"
        case .keyboard: "Keyboard"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .screenMirroring: "Screen Mirroring"
        }
    }
    var symbol: String {
        switch self {
        case .battery: "battery.100percent"
        case .bluetooth: "waveform"
        case .displays: "display"
        case .keyboard: "keyboard"
        case .sound: "speaker.wave.2"
        case .wifi: "wifi"
        case .screenMirroring: "rectangle.on.rectangle"
        }
    }

    func matches(identifier: String) -> Bool {
        let suffixes: [String]
        switch self {
        case .battery: suffixes = ["battery"]
        case .bluetooth: suffixes = ["bluetooth"]
        case .displays: suffixes = ["display", "displays"]
        case .keyboard: suffixes = ["keyboard"]
        case .sound: suffixes = ["volume", "sound"]
        case .wifi: suffixes = ["wifi"]
        case .screenMirroring: suffixes = ["airplay", "screenmirroring"]
        }
        return suffixes.contains { identifier.lowercased().hasSuffix($0) }
    }
}

@MainActor
final class MenuBarControl: ObservableObject {
    static let shared = MenuBarControl()

    @Published private(set) var apps: [ControlledMenuApp] = []
    @Published private(set) var hiddenIDs: Set<String>
    @Published private(set) var hiddenSystemIDs: Set<Int>
    @Published private(set) var hubOrder: [String]
    @Published private(set) var isRevealed = false
    @Published private(set) var isScanning = false
    @Published private(set) var isApplying = false
    @Published private(set) var isRestrictionActive = false
    @Published private(set) var openingItemID: String?
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var message: String?

    private let bridge = MenuBarVisibilityBridge()
    private let storageKey = "vitals.hiddenMenuApps.v1"
    private let systemStorageKey = "vitals.hiddenSystemItems.v1"
    private let hubStorageKey = "vitals.hubOrder.v1"
    private var scanGeneration = 0
    private var needsReconcileAfterApply = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var mouseMonitor: Any?
    private var clockElement: AXUIElement?
    private var clockFrameCache: (frame: CGRect, at: Date)?
    private var isClockHovered = false
    private var clockLeaveTimer: Timer?
    private var hasStarted = false

    private init() {
        hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        hiddenSystemIDs = Set(UserDefaults.standard.array(forKey: systemStorageKey) as? [Int] ?? [])
        var savedHub = UserDefaults.standard.stringArray(forKey: hubStorageKey) ?? []
        hubOrder = savedHub
        for id in hiddenIDs.sorted() where !savedHub.contains(id) {
            savedHub.append(id)
        }
        hubOrder = savedHub
        UserDefaults.standard.set(savedHub, forKey: hubStorageKey)
        NSLog("Vitals Accessibility trusted at launch: %@", isTrusted ? "yes" : "no")
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    guard self.hasStarted else { return }
                    self.refresh()
                }
            })
        }
    }

    func startAfterMenuBarAppears() {
        guard !hasStarted else { return }
        hasStarted = true
        // Do not start the assessment-mode restriction before AppKit has installed
        // Vitals' own status item, or the user can lose the menu-bar entry point.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            NSLog("Vitals status item initialized; scanning menu-bar icons")
            self.refresh()
            self.watchClock()
        }
    }

    var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && bridge.isAvailable
    }

    var hiddenCount: Int { apps.filter { hiddenIDs.contains($0.id) }.count + hiddenSystemIDs.count }

    private func saveIconChoices() {
        UserDefaults.standard.set(hiddenIDs.sorted(), forKey: storageKey)
        UserDefaults.standard.set(hiddenSystemIDs.sorted(), forKey: systemStorageKey)
        saveHubOrder()
    }

    var hubApps: [ControlledMenuApp] {
        let included = Set(hubOrder).union(hiddenIDs)
        let indices = Dictionary(uniqueKeysWithValues: hubOrder.enumerated().map { ($0.element, $0.offset) })
        return apps.filter { included.contains($0.id) }.sorted {
            let left = indices[$0.id] ?? Int.max
            let right = indices[$1.id] ?? Int.max
            return left == right ? $0.x < $1.x : left < right
        }
    }

    func isInHub(_ id: String) -> Bool { hubOrder.contains(id) || hiddenIDs.contains(id) }

    func setInHub(_ included: Bool, for id: String) {
        guard !hiddenIDs.contains(id) || included else { return }
        hubOrder.removeAll { $0 == id }
        if included { hubOrder.append(id) }
        saveHubOrder()
    }

    func moveInHub(_ id: String, by offset: Int) {
        let visible = hubApps.map(\.id)
        guard let visibleIndex = visible.firstIndex(of: id), visible.indices.contains(visibleIndex + offset),
              let first = hubOrder.firstIndex(of: id),
              let second = hubOrder.firstIndex(of: visible[visibleIndex + offset]) else { return }
        hubOrder.swapAt(first, second)
        saveHubOrder()
    }

    private func saveHubOrder() {
        UserDefaults.standard.set(hubOrder, forKey: hubStorageKey)
    }

    func openAppMenu(_ id: String, itemIndex: Int) {
        guard isTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
            message = "That app is no longer running. Refresh the list."
            return
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? "the app"
        let key = "\(id)#\(itemIndex)"
        openingItemID = key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let opened = MenuItemActivator.appItem(pid: pid, index: itemIndex)
            DispatchQueue.main.async {
                guard let self else { return }
                self.openingItemID = nil
                if opened {
                    self.message = nil
                } else {
                    self.reveal()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let retried = MenuItemActivator.appItem(pid: pid, index: itemIndex)
                            DispatchQueue.main.async {
                                self?.message = retried ? nil : "I revealed \(name). Click its icon in the menu bar."
                            }
                        }
                    }
                }
            }
        }
    }

    func openSystemMenu(_ item: ControlledSystemItem) {
        guard isTrusted,
              let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else {
            message = "The system menu bar is unavailable right now."
            return
        }
        let pid = agent.processIdentifier
        openingItemID = "system#\(item.id)"
        // Hidden system items disappear from MenuBarAgent's AX tree. Reveal, then press.
        let needsReveal = hiddenSystemIDs.contains(item.id) && !isRevealed
        if needsReveal { reveal() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsReveal ? 0.3 : 0)) { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let opened = MenuItemActivator.systemItem(pid: pid, item: item)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.openingItemID = nil
                    self.message = opened
                        ? "All icons are visible until you hide them again."
                        : "I revealed \(item.title). Click it in the menu bar."
                }
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    private func watchForAccessibility() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                if AXIsProcessTrusted() {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        let wasTrusted = isTrusted
        isTrusted = AXIsProcessTrusted()
        if isTrusted != wasTrusted {
            NSLog("Vitals Accessibility trust changed: %@", isTrusted ? "yes" : "no")
        }
        guard isTrusted else {
            watchForAccessibility()
            bridge.restoreAll()
            isApplying = false
            isRestrictionActive = false
            apps = []
            message = "Allow Accessibility to find the real icons in your menu bar."
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, String)? in
            guard app.processIdentifier != ownPID, app.activationPolicy != .prohibited,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  !id.hasPrefix("com.apple.") else { return nil }
            return (app.processIdentifier, id, app.localizedName ?? id)
        }
        // AX messaging may block on another app. Never scan on the UI thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = candidates.compactMap { candidate -> (String, String, [ControlledMenuItem], CGFloat)? in
                let (pid, id, name) = candidate
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.2)
                var barValue: AnyObject?
                guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &barValue) == .success,
                      let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return nil }
                let bar = unsafeDowncast(barValue, to: AXUIElement.self)
                var childrenValue: AnyObject?
                guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                      let children = childrenValue as? [AXUIElement], !children.isEmpty else { return nil }
                let items: [ControlledMenuItem] = children.enumerated().map { index, child in
                    var value: AnyObject?
                    var point = CGPoint.zero
                    if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &value) == .success,
                       let value, CFGetTypeID(value) == AXValueGetTypeID() {
                        _ = AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point)
                    }
                    var titleValue: AnyObject?
                    var descriptionValue: AnyObject?
                    _ = AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
                    _ = AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descriptionValue)
                    let title = [titleValue as? String, descriptionValue as? String]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty }) ?? (children.count == 1 ? name : "Item \(index + 1)")
                    return ControlledMenuItem(id: "\(id)#\(index)", index: index, title: title, x: point.x)
                }
                return (id, name, items, items.map(\.x).filter { $0 > 0 }.min() ?? .greatestFiniteMagnitude)
            }
            DispatchQueue.main.async {
                guard let self, generation == self.scanGeneration else { return }
                let currentApps = NSWorkspace.shared.runningApplications
                let icons = Dictionary(currentApps.compactMap { app -> (String, NSImage)? in
                    guard let id = app.bundleIdentifier, let icon = app.icon else { return nil }
                    return (id, icon)
                }, uniquingKeysWith: { first, _ in first })
                var merged = Dictionary(results.map { result in
                    (result.0, ControlledMenuApp(id: result.0, name: result.1,
                                                 items: result.2, x: result.3,
                                                 icon: icons[result.0]))
                }, uniquingKeysWith: { first, _ in first })
                let runningIDs = Set(currentApps.compactMap(\.bundleIdentifier))
                for previous in self.apps where self.hiddenIDs.contains(previous.id) && runningIDs.contains(previous.id) {
                    if merged[previous.id] == nil { merged[previous.id] = previous }
                }
                self.apps = merged.values.sorted { $0.x < $1.x }
                self.isScanning = false
                self.message = self.apps.isEmpty ? "No third-party menu-bar items found. Open one, then refresh." : nil
                if (!self.hiddenIDs.isEmpty || !self.hiddenSystemIDs.isEmpty) && !self.isRevealed {
                    if self.isApplying {
                        self.needsReconcileAfterApply = true
                    } else {
                        self.reconcile()
                    }
                }
            }
        }
    }

    func setHidden(_ hidden: Bool, for id: String) {
        guard isSupported, isTrusted, !isApplying else { return }
        let previous = hiddenIDs
        let previousHub = hubOrder
        if hidden { hiddenIDs.insert(id) } else { hiddenIDs.remove(id) }
        if hidden && !hubOrder.contains(id) { hubOrder.append(id); saveHubOrder() }
        UserDefaults.standard.set(hiddenIDs.sorted(), forKey: storageKey)
        isRevealed = false
        reconcile(rollbackApps: previous, rollbackHub: previousHub)
    }

    func setSystemHidden(_ hidden: Bool, for id: Int) {
        guard isSupported, isTrusted, !isApplying else { return }
        let previous = hiddenSystemIDs
        if hidden { hiddenSystemIDs.insert(id) } else { hiddenSystemIDs.remove(id) }
        UserDefaults.standard.set(hiddenSystemIDs.sorted(), forKey: systemStorageKey)
        isRevealed = false
        reconcile(rollbackSystem: previous)
    }

    func reveal() {
        isRevealed = true
        isClockHovered = false
        clockLeaveTimer?.invalidate()
        bridge.restoreAll()
        isApplying = false
        isRestrictionActive = false
        message = "All icons are visible until you hide them again."
    }

    func hideAgain() {
        isRevealed = false
        reconcile()
    }

    func restoreAndClear() {
        bridge.restoreAll()
        isApplying = false
        isRestrictionActive = false
        isClockHovered = false
        clockLeaveTimer?.invalidate()
        hiddenIDs.removeAll()
        hiddenSystemIDs.removeAll()
        hubOrder.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: systemStorageKey)
        UserDefaults.standard.removeObject(forKey: hubStorageKey)
        isRevealed = false
        message = "All menu-bar icons restored."
        refresh()
    }

    /// Set by the status item: is Vitals' own icon actually on screen?
    var isOwnItemVisible: (() -> Bool)?

    /// Safety net: if hiding other icons ever takes Vitals' own icon with it,
    /// give everything back immediately so the user never loses Vitals.
    private func verifyOwnIconStillVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.isRestrictionActive, let check = self.isOwnItemVisible, !check() else { return }
            NSLog("Vitals own status item disappeared after restriction; restoring all icons")
            self.bridge.restoreAll()
            self.isRestrictionActive = false
            self.isRevealed = true
            self.message = "macOS hid Vitals' own icon too, so Vitals showed everything again. Try hiding fewer icons, or quit an app you don't need."
        }
    }

    func stop() {
        bridge.restoreAll()
        isApplying = false
        isRestrictionActive = false
        permissionTimer?.invalidate()
        clockLeaveTimer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func watchClock() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateClockHover() }
        }
    }

    private func updateClockHover() {
        guard isSupported, isTrusted, !isRevealed,
              !hiddenIDs.isEmpty || !hiddenSystemIDs.isEmpty else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let inMenuBar = point.y > screen.frame.maxY - 40
        let overClock = inMenuBar && (clockFrame()?.contains(point) ?? false)
        guard overClock != isClockHovered else { return }
        isClockHovered = overClock
        clockLeaveTimer?.invalidate()
        if overClock {
            // Assessment mode prevents the clock from opening Notification Center. Lift it
            // while the pointer is on the clock, then reapply after the pointer leaves.
            bridge.restoreAll()
            isApplying = false
            isRestrictionActive = false
        } else {
            clockLeaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.reconcile() }
            }
        }
    }

    private func clockFrame() -> CGRect? {
        if let cached = clockFrameCache, Date().timeIntervalSince(cached.at) < 2 { return cached.frame }
        guard let clock = resolveClockElement() else { return nil }
        var originValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(clock, kAXPositionAttribute as CFString, &originValue) == .success,
              AXUIElementCopyAttributeValue(clock, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let originValue, let sizeValue,
              CFGetTypeID(originValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            clockElement = nil
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(originValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        else { return nil }
        let frame = CGRect(x: origin.x, y: primary.frame.height - origin.y - size.height,
                           width: size.width, height: size.height)
        clockFrameCache = (frame, Date())
        return frame
    }

    private func resolveClockElement() -> AXUIElement? {
        if let clockElement { return clockElement }
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var barValue: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &barValue) == .success,
              let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return nil }
        let bar = unsafeDowncast(barValue, to: AXUIElement.self)
        var groupsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &groupsValue) == .success,
              let groups = groupsValue as? [AXUIElement] else { return nil }
        for group in groups {
            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                var identifier: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier) == .success,
                   identifier as? String == "com.apple.menuextra.clock" {
                    clockElement = child
                    return child
                }
            }
        }
        return nil
    }

    private func reconcile(rollbackApps: Set<String>? = nil,
                           rollbackSystem: Set<Int>? = nil,
                           rollbackHub: [String]? = nil,
                           completion: ((Bool) -> Void)? = nil) {
        guard isSupported, isTrusted, !isRevealed, !isClockHovered,
              !hiddenIDs.isEmpty || !hiddenSystemIDs.isEmpty else {
            bridge.restoreAll()
            isApplying = false
            isRestrictionActive = false
            completion?(true)
            return
        }
        // Assessment mode is an allow-list. Include all currently running apps and Apple agents
        // so launching a new app does not make its menu item disappear by default.
        let allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .subtracting(hiddenIDs)
            .union(["com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.controlcenter",
                    "com.apple.notificationcenterui", "com.apple.UserNotificationCenter",
                    Bundle.main.bundleIdentifier ?? "anurag.Vitals"])
        isApplying = true
        bridge.showOnly(bundleIDs: allowed.sorted(), hiddenSystemIDs: hiddenSystemIDs) { [weak self] error in
            guard let self else { return }
            self.isApplying = false
            if let error {
                NSLog("Vitals icon restriction failed: %@", error.localizedDescription)
                self.bridge.restoreAll()
                self.isRestrictionActive = false
                if let rollbackApps {
                    self.hiddenIDs = rollbackApps
                    UserDefaults.standard.set(rollbackApps.sorted(), forKey: self.storageKey)
                }
                if let rollbackSystem {
                    self.hiddenSystemIDs = rollbackSystem
                    UserDefaults.standard.set(rollbackSystem.sorted(), forKey: self.systemStorageKey)
                }
                if let rollbackHub {
                    self.hubOrder = rollbackHub
                    self.saveHubOrder()
                }
                self.message = "Couldn't hide icons: \(error.localizedDescription)"
                completion?(false)
            } else {
                NSLog("Vitals icon restriction applied")
                self.isRestrictionActive = true
                self.message = nil
                completion?(true)
                self.verifyOwnIconStillVisible()
            }
            if self.needsReconcileAfterApply {
                self.needsReconcileAfterApply = false
                self.reconcile()
            }
        }
    }
}
