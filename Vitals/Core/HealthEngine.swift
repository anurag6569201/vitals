import Combine
import Foundation

/// Turns a stream of snapshots into a small, stable list of issues.
/// Pure logic: no AppKit, no timers — easy to test.
final class HealthEngine {
    static let historyLength: TimeInterval = 20 * 60
    /// An issue stays visible this long after its condition stops, to avoid flapping.
    static let clearGrace: TimeInterval = 20

    let detectors: [Detector] = [
        RunawayAppDetector(), HeatDetector(), MemoryPressureDetector(), BatteryDrainDetector(),
        SleepBlockerDetector(), LowDiskDetector(), UptimeDetector()
    ]

    private(set) var history: [SystemSnapshot] = []
    private var active: [String: Issue] = [:]
    private var lastSeen: [String: Date] = [:]
    private var snoozedUntil: [String: Date] = [:]
    private var lastDrainLearning: Date?

    /// Issues the user can see, most severe first.
    private(set) var visibleIssues: [Issue] = []
    /// Issues that need Pro; free users see only that they exist.
    private(set) var lockedIssues: [Issue] = []

    var overallSeverity: Severity { visibleIssues.map(\.severity).max() ?? .calm }

    /// Returns ids of issues that became visible in this pass (for notifications).
    @discardableResult
    func ingest(_ snapshot: SystemSnapshot, settings: inout DetectionSettings, isPro: Bool) -> [Issue] {
        history.append(snapshot)
        let cutoff = snapshot.date.addingTimeInterval(-Self.historyLength)
        if let firstKeep = history.firstIndex(where: { $0.date >= cutoff }), firstKeep > 0 {
            history.removeFirst(firstKeep)
        }

        let context = DetectorContext(now: snapshot, history: history, settings: settings)
        var found: [String: Issue] = [:]
        for detector in detectors where !settings.disabledKinds.contains(detector.kind) {
            for issue in detector.evaluate(context) { found[issue.id] = issue }
        }

        let previouslyVisible = Set(visibleIssues.map(\.id))
        for (id, issue) in found {
            var updated = issue
            if let existing = active[id] { updated.since = min(existing.since, issue.since) }
            active[id] = updated
            lastSeen[id] = snapshot.date
        }
        for (id, seen) in lastSeen where found[id] == nil && snapshot.date.timeIntervalSince(seen) > Self.clearGrace {
            active[id] = nil
            lastSeen[id] = nil
        }
        snoozedUntil = snoozedUntil.filter { $0.value > snapshot.date }

        let shown = active.values
            .filter { snoozedUntil[$0.id] == nil }
            .filter { issue in
                guard let subject = issue.subject else { return true }
                return settings.ignoredApps[subject.key] == nil
            }
            .sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.since < $1.since }
        visibleIssues = shown.filter { isPro || !$0.kind.requiresPro }
        lockedIssues = shown.filter { !isPro && $0.kind.requiresPro }

        learnTypicalDrain(settings: &settings)
        return visibleIssues.filter { !previouslyVisible.contains($0.id) }
    }

    func snooze(_ issue: Issue, now: Date = Date()) {
        snoozedUntil[issue.id] = now.addingTimeInterval(Self.snoozeDuration(issue.kind))
        visibleIssues.removeAll { $0.id == issue.id }
        lockedIssues.removeAll { $0.id == issue.id }
    }

    /// After sleep, old samples would distort rates and durations.
    func resetHistory() {
        history.removeAll()
        lastDrainLearning = nil
    }

    func dismiss(_ issue: Issue) {
        active[issue.id] = nil
        lastSeen[issue.id] = nil
        visibleIssues.removeAll { $0.id == issue.id }
    }

    static func snoozeDuration(_ kind: IssueKind) -> TimeInterval {
        switch kind {
        case .runawayApp, .memoryPressure: 3600
        case .heat: 1800
        case .batteryDrain: 7200
        case .sleepBlocker: 8 * 3600
        case .lowDisk: 86_400
        case .longUptime: 3 * 86_400
        }
    }

    /// Slowly learns what "normal" drain looks like on this Mac, from calm periods on battery.
    private func learnTypicalDrain(settings: inout DetectionSettings) {
        guard let now = history.last?.date else { return }
        if let last = lastDrainLearning, now.timeIntervalSince(last) < 600 { return }
        let cutoff = now.addingTimeInterval(-600)
        let window = history.filter { $0.date >= cutoff }
        guard let rate = BatteryDrainDetector.drainRate(window, minimumSpan: 540) else { return }
        lastDrainLearning = now
        guard !active.values.contains(where: { $0.kind == .batteryDrain }), rate > 0.5 else { return }
        let learned = settings.typicalDrainPerHour * 0.85 + rate * 0.15
        settings.typicalDrainPerHour = min(max(learned, 3), 40)
    }
}
