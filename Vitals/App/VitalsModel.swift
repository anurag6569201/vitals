import AppKit
import Combine
import Foundation

/// The app's brain: samples the system, runs the health engine, tracks away periods,
/// and performs the actions people pick.
@MainActor
final class VitalsModel: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var issues: [Issue] = []
    @Published private(set) var lockedIssues: [Issue] = []
    @Published private(set) var severity: Severity = .calm
    @Published private(set) var awayReports: [AwayReport] = AwayReportStore.load()
    @Published var message: String?
    @Published private(set) var forecast: BatteryForecast?
    @Published private(set) var leavingCheck: LeavingCheck?
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save() } }
    }

    let license: LicenseManager
    let updates = UpdateChecker()
    let ledger = UsageLedger()
    let space = SpaceModel()
    var openWindow: ((AppWindow) -> Void)?
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
    }

    var latestReport: AwayReport? {
        guard let report = awayReports.first, !report.seen,
              Date().timeIntervalSince(report.end) < 12 * 3600 else { return nil }
        return report
    }

    func start() {
        presence.onChange = { [weak self] wasAway, isAway in
            self?.presenceChanged(wasAway: wasAway, isAway: isAway)
        }
        presence.onSystemSleep = { [weak self] in self?.away.systemWillSleep(at: Date()) }
        presence.onSystemWake = { [weak self] in
            self?.away.systemDidWake(at: Date())
            self?.engine.resetHistory()
        }
        presence.start()
        updates.checkIfNeeded()
        tick()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = isPopoverOpen ? 2 : (presence.isAway ? 10 : 5)
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
        ledger.record(snap)
        updateBatteryPlanning(snap)

        snapshot = snap
        publishIssues()
        notify(about: newlyVisible)
    }

    private func publishIssues() {
        issues = engine.visibleIssues
        lockedIssues = engine.lockedIssues
        severity = engine.overallSeverity
    }

    // MARK: Battery planning & leaving check

    private func updateBatteryPlanning(_ snap: SystemSnapshot) {
        forecast = BatteryForecast.make(history: engine.history, typicalRate: settings.detection.typicalDrainPerHour)

        let onAC = snap.battery?.isOnAC
        defer { wasOnAC = onAC }
        if onAC == true {
            leavingCheck = nil
            return
        }
        if let check = leavingCheck, snap.date.timeIntervalSince(check.date) > 20 * 60 {
            leavingCheck = nil
        }
        guard wasOnAC == true, onAC == false,
              let check = LeavingCheck.make(from: snap, ignored: settings.detection.ignoredApps) else { return }
        leavingCheck = check
        if settings.notificationsEnabled && license.isPro {
            Notifier.post(id: "leaving", title: check.headline, body: check.detail)
        }
    }

    func dismissLeavingCheck() {
        leavingCheck = nil
    }

    func quitAll(_ identities: [AppIdentity]) {
        var failed: [String] = []
        for identity in identities where !SystemActions.quit(identity) { failed.append(identity.name) }
        if failed.isEmpty {
            show("Asked \(LeavingCheck.list(identities.map(\.name))) to quit.")
        } else {
            show("macOS didn't let Vitals quit \(LeavingCheck.list(failed)). Quit it from its menu.")
        }
    }

    // MARK: Notifications

    private func notify(about newIssues: [Issue]) {
        guard settings.notificationsEnabled, !isPopoverOpen else { return }
        for issue in newIssues where issue.severity >= .warning {
            Notifier.post(id: issue.id, title: issue.headline, body: issue.detail)
        }
    }

    // MARK: Away

    private func presenceChanged(wasAway: Bool, isAway: Bool) {
        let now = Date()
        if isAway && !wasAway {
            away.begin(at: now, battery: sampler.batteryState())
        } else if !isAway && wasAway {
            if let report = away.end(at: now, battery: sampler.batteryState()), settings.awayReportsEnabled {
                ledger.record(report)
                awayReports.insert(report, at: 0)
                AwayReportStore.save(awayReports)
                if report.verdict == .unusual && settings.notificationsEnabled {
                    let body = license.isPro ? report.explanation : "Open Vitals to see what happened."
                    Notifier.post(id: "away-\(report.id)", title: report.headline, body: body)
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
        if SystemActions.quit(identity) {
            show("Asked \(identity.name) to quit.")
        } else {
            SystemActions.openActivityMonitor()
            show("macOS didn't let Vitals quit \(identity.name).")
        }
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
