import AppKit
import Combine
import Foundation
import UserNotifications

/// The app's brain: samples the system, runs the health engine, tracks away periods,
/// and performs the actions people pick.
@MainActor
final class VitalsModel: ObservableObject {
    /// For Shortcuts / App Intents, which run inside the app.
    static weak var shared: VitalsModel?
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var issues: [Issue] = []
    @Published private(set) var lockedIssues: [Issue] = []
    @Published private(set) var severity: Severity = .calm
    @Published private(set) var awayReports: [AwayReport] = AwayReportStore.load()
    @Published var message: String?
    @Published private(set) var forecast: BatteryForecast?
    @Published private(set) var leavingCheck: LeavingCheck?
    /// False when macOS has notifications for Vitals turned off.
    @Published private(set) var canDeliverNotifications = true
    /// Bumped just before the popover opens, so its entrance animation replays.
    @Published private(set) var popoverEpoch = 0
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.hotkey != oldValue.hotkey { hotKey.register(settings.hotkey) }
            if settings.notificationsEnabled != oldValue.notificationsEnabled { refreshNotificationStatus() }
            if settings.pin.enabled != oldValue.pin.enabled { schedule() }
        }
    }

    let license: LicenseManager
    let updates = UpdateChecker()
    let space = SpaceModel()
    let network = NetworkUsageTracker()
    let extra = ExtraStats()
    let keepAwake = KeepAwake()
    let hotKey = HotKey()
    var openWindow: ((AppWindow) -> Void)?
    var openPopover: (() -> Void)?
    /// Ids of issues we've posted a notification for and that are still active.
    private var notifiedIDs: Set<String> = []
    private var wasOnAC: Bool?
    let sampler = SystemSampler()
    private let engine = HealthEngine()
    private let presence = PresenceMonitor()
    private let away = AwayTracker()
    private var timer: Timer?
    private var messageTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    var isPopoverOpen = false {
        didSet {
            guard isPopoverOpen != oldValue else { return }
            if isPopoverOpen {
                tick()
                updates.checkIfNeeded()
                refreshNotificationStatus()
            }
            schedule()
        }
    }

    init(license: LicenseManager) {
        self.license = license
        self.settings = AppSettings.load()
        license.$state
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            .store(in: &cancellables)
        VitalsModel.shared = self
    }

    var latestReport: AwayReport? {
        guard let report = awayReports.first, !report.seen,
              Date().timeIntervalSince(report.end) < 12 * 3600 else { return nil }
        return report
    }

    /// Alerts go to macOS notifications. They fall back to cards in the popover only when
    /// notifications are switched off, in Vitals or in System Settings.
    var alertsInPopover: Bool { !(settings.notificationsEnabled && canDeliverNotifications) }

    func start() {
        Notifier.shared.start()
        Notifier.shared.onResponse = { [weak self] id, action, info in
            self?.handleNotification(id: id, action: action, info: info)
        }
        if settings.notificationsEnabled && settings.hasCompletedOnboarding {
            Notifier.requestPermission { [weak self] _ in self?.refreshNotificationStatus() }
        }
        presence.onChange = { [weak self] wasAway, isAway in
            self?.presenceChanged(wasAway: wasAway, isAway: isAway)
        }
        presence.onSystemSleep = { [weak self] in self?.away.systemWillSleep(at: Date()) }
        presence.onSystemWake = { [weak self] in
            self?.away.systemDidWake(at: Date())
            self?.engine.resetHistory()
        }
        presence.start()
        hotKey.register(settings.hotkey)
        updates.checkIfNeeded()
        tick()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        // The on-screen pin shows live numbers, so it refreshes faster while you're at the Mac.
        let pinVisible = settings.pin.enabled
        let interval: TimeInterval = isPopoverOpen ? 2 : (presence.isAway ? 10 : (pinVisible ? 2.5 : 5))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func tick() {
        let snap = sampler.snapshot(isUserAway: presence.isAway)
        var detection = settings.detection
        let newlyVisible = engine.ingest(snap, settings: &detection, isPro: license.isPro)
        if detection != settings.detection { settings.detection = detection }
        if away.isTracking { away.ingest(snap) }
        updateBatteryPlanning(snap)
        space.backgroundRefreshIfDue(onAC: snap.battery?.isOnAC ?? true)

        network.sample(downRate: snap.downloadRate, upRate: snap.uploadRate, now: snap.date)
        sampleExtras(snap)
        checkHotspot()
        snapshot = snap
        publishIssues()
        notify(newlyVisible: newlyVisible)
    }

    private func publishIssues() {
        // Only publish real changes: fewer redraws, and no needless updates mid-render.
        if issues != engine.visibleIssues { issues = engine.visibleIssues }
        if lockedIssues != engine.lockedIssues { lockedIssues = engine.lockedIssues }
        if severity != engine.overallSeverity { severity = engine.overallSeverity }
    }

    // MARK: Battery planning & leaving check

    private func updateBatteryPlanning(_ snap: SystemSnapshot) {
        let newForecast = BatteryForecast.make(history: engine.history, typicalRate: settings.detection.typicalDrainPerHour)
        if newForecast != forecast { forecast = newForecast }

        let onAC = snap.battery?.isOnAC
        defer { wasOnAC = onAC }
        if onAC == true {
            if leavingCheck != nil { dismissLeavingCheck() }
            return
        }
        if let check = leavingCheck, snap.date.timeIntervalSince(check.date) > 20 * 60 {
            dismissLeavingCheck()
        }
        guard wasOnAC == true, onAC == false,
              let check = LeavingCheck.make(from: snap, ignored: settings.detection.ignoredApps) else { return }
        leavingCheck = check
        // Pro only: a notification that just advertises Pro would break App Review guideline 4.5.4.
        // Free users see the teaser card in the popover instead.
        guard settings.notificationsEnabled, license.isPro else { return }
        let quitTitle = Edition.canQuitApps
            ? "Quit \(check.all.count == 1 ? Format.shortName(check.all[0].name) : "all \(check.all.count)")"
            : "Show in Activity Monitor"
        Notifier.shared.post(id: "leaving", title: check.headline, body: check.detail,
                             actions: [(Notifier.quitAllAction, quitTitle)])
    }

    func popoverWillOpen() { popoverEpoch += 1 }

    /// 0 = nothing sent, 1 = warned at 80%, 2 = warned at the limit.
    private var hotspotAlertLevel = 0

    private func checkHotspot() {
        guard settings.hotspotGuard, network.onMeteredConnection else {
            hotspotAlertLevel = 0
            return
        }
        let limit = Double(settings.hotspotLimitMB) * 1_000_000
        let used = network.meteredBytes
        let level = used >= limit ? 2 : (used >= limit * 0.8 ? 1 : 0)
        guard level > hotspotAlertLevel else { return }
        hotspotAlertLevel = level
        guard settings.notificationsEnabled else { return }
        let usedText = Format.bytes(UInt64(used)), limitText = Format.bytes(UInt64(limit))
        Notifier.shared.post(
            id: "hotspot",
            title: level == 2 ? "Hotspot limit reached: \(usedText) used" : "\(usedText) of \(limitText) used on your hotspot",
            body: "Pause big downloads, cloud sync and updates to save mobile data. Change the limit in Vitals › Settings › Alerts.")
    }

    /// Extra readings are sampled only while something shows them; ping only when it's chosen
    /// (it's the one reading that sends anything).
    private func sampleExtras(_ snap: SystemSnapshot) {
        let pinItems = settings.pin.enabled ? Set(settings.pin.items) : []
        let barKinds = settings.menuBarStyle.showsReadings && license.isPro ? Set(settings.readings) : []
        let extrasShown = !pinItems.isDisjoint(with: [.wifi, .ping, .display, .diskIO])
            || !barKinds.isDisjoint(with: [.wifi, .ping, .display]) || isPopoverOpen
        extra.pingEnabled = pinItems.contains(.ping) || barKinds.contains(.ping)
        if extrasShown { extra.sample(now: snap.date) }
    }

    func startKeepAwake(_ duration: TimeInterval?) {
        keepAwake.start(for: duration, allowDisplaySleep: settings.keepAwakeAllowsDisplaySleep)
    }

    func dismissLeavingCheck() {
        leavingCheck = nil
        Notifier.shared.remove(ids: ["leaving"])
    }

    func quitAll(_ identities: [AppIdentity]) {
        guard Edition.canQuitApps else {
            SystemActions.openActivityMonitor()
            show("Quit \(LeavingCheck.list(identities.map(\.name))) in Activity Monitor.")
            return
        }
        var failed: [String] = []
        for identity in identities where !SystemActions.quit(identity) { failed.append(identity.name) }
        if failed.isEmpty {
            show("Asked \(LeavingCheck.list(identities.map(\.name))) to quit.")
        } else {
            show("macOS didn't let Vitals quit \(LeavingCheck.list(failed)). Quit it from its menu.")
        }
    }

    // MARK: Notifications

    private func notify(newlyVisible: [Issue]) {
        // Clear notifications for problems that have gone away.
        let activeIDs = Set(issues.map(\.id))
        let gone = notifiedIDs.subtracting(activeIDs)
        Notifier.shared.remove(ids: Array(gone))
        notifiedIDs.subtract(gone)

        guard settings.notificationsEnabled else { return }
        for issue in newlyVisible where !notifiedIDs.contains(issue.id) {
            let actions = issue.actions
                .filter { $0 != .showAwayReport && (Edition.canQuitApps || ($0 != .quitApp && $0 != .forceQuitApp)) }
                .prefix(4)
                .map { (id: $0.rawValue, title: issue.title(for: $0)) }
            Notifier.shared.post(id: issue.id, title: issue.headline, body: issue.detail,
                                 actions: Array(actions), userInfo: ["issue": issue.id])
            notifiedIDs.insert(issue.id)
        }
    }

    func refreshNotificationStatus() {
        Notifier.checkCanDeliver { [weak self] ok in
            guard let self, self.canDeliverNotifications != ok else { return }
            self.canDeliverNotifications = ok
        }
    }

    private func handleNotification(id: String, action: String, info: [AnyHashable: Any]) {
        switch action {
        case Notifier.upgradeAction:
            openWindow?(.settings(.pro))
        case Notifier.quitAllAction:
            if let check = leavingCheck { quitAll(check.all); dismissLeavingCheck() }
        case UNNotificationDefaultActionIdentifier:
            openPopover?()
        default:
            guard let issueAction = IssueAction(rawValue: action),
                  let issueID = info["issue"] as? String,
                  let issue = issues.first(where: { $0.id == issueID }) else {
                openPopover?()
                return
            }
            perform(issueAction, on: issue)
            if let message { Notifier.shared.post(id: "feedback", title: "Vitals", body: message) }
        }
    }

    // MARK: Away

    private func presenceChanged(wasAway: Bool, isAway: Bool) {
        let now = Date()
        if isAway && !wasAway {
            away.begin(at: now, battery: sampler.batteryState())
        } else if !isAway && wasAway {
            if let report = away.end(at: now, battery: sampler.batteryState()), settings.awayReportsEnabled {
                awayReports.insert(report, at: 0)
                AwayReportStore.save(awayReports)
                if report.verdict == .unusual && settings.notificationsEnabled {
                    let body = license.isPro ? report.explanation : "Open Vitals to see what happened."
                    Notifier.shared.post(id: "away-\(report.id)", title: report.headline, body: body)
                }
            }
        }
        schedule()
    }

    func markReportSeen(_ report: AwayReport) {
        guard let index = awayReports.firstIndex(where: { $0.id == report.id }) else { return }
        awayReports[index].seen = true
        AwayReportStore.save(awayReports)
    }

    // MARK: Actions

    func perform(_ action: IssueAction, on issue: Issue) {
        switch action {
        case .quitApp, .forceQuitApp:
            guard let subject = issue.subject else { return }
            if SystemActions.quit(subject, force: action == .forceQuitApp) {
                engine.dismiss(issue)
                show("Asked \(subject.name) to quit.")
            } else {
                SystemActions.openActivityMonitor()
                show("macOS didn't let Vitals quit \(subject.name). Quit it from its menu, or select it in Activity Monitor.")
            }
        case .ignoreApp:
            guard let subject = issue.subject else { return }
            settings.detection.ignoredApps[subject.key] = subject.name
            engine.dismiss(issue)
            show("Vitals will ignore \(subject.name). Undo this in Settings › Alerts.")
        case .snooze:
            engine.snooze(issue)
            show("Snoozed for \(Format.duration(HealthEngine.snoozeDuration(issue.kind))).")
        case .openActivityMonitor:
            SystemActions.openActivityMonitor()
        case .openStorageSettings:
            SystemActions.openStorageSettings()
        case .openBatterySettings:
            SystemActions.openBatterySettings()
        case .showAwayReport:
            break
        case .findSpaceHogs:
            openWindow?(.space)
        }
        publishIssues()
    }

    func hide(_ issue: Issue) {
        engine.hide(issue)
        publishIssues()
    }

    func quit(_ identity: AppIdentity) {
        guard Edition.canQuitApps else {
            SystemActions.openActivityMonitor()
            show("Quit \(identity.name) in Activity Monitor.")
            return
        }
        if SystemActions.quit(identity) {
            show("Asked \(identity.name) to quit.")
        } else {
            SystemActions.openActivityMonitor()
            show("macOS didn't let Vitals quit \(identity.name).")
        }
    }

    /// Adds or removes a reading from the on-screen pin, keeping the canonical order.
    func togglePinItem(_ item: PinItem) {
        var items = settings.pin.items
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        } else {
            items.append(item)
            items.sort { (PinItem.allCases.firstIndex(of: $0) ?? 0) < (PinItem.allCases.firstIndex(of: $1) ?? 0) }
        }
        settings.pin.items = items
    }

    func unignore(_ key: String) {
        settings.detection.ignoredApps[key] = nil
    }

    func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }
}
