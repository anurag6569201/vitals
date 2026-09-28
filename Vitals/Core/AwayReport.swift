import Foundation

struct AwayReport: Codable, Identifiable, Equatable {
    struct Consumer: Codable, Equatable, Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let bundlePath: String?
        /// Share of all app energy while away, 0...1.
        let share: Double
        let cpuSeconds: Double
    }

    struct Blocker: Codable, Equatable, Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let reason: String
        let seconds: TimeInterval
    }

    enum Verdict: String, Codable {
        case normal, unusual, charging
    }

    var id = UUID()
    let start: Date
    let end: Date
    let startLevel: Double?
    let endLevel: Double?
    let asleepSeconds: TimeInterval
    let wasCharging: Bool
    let consumers: [Consumer]
    let blockers: [Blocker]
    var seen = false

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var awakeSeconds: TimeInterval { max(0, duration - asleepSeconds) }

    /// Percentage points lost. Nil if there is no battery or it charged.
    var batteryLost: Double? {
        guard !wasCharging, let startLevel, let endLevel else { return nil }
        return max(0, (startLevel - endLevel) * 100)
    }

    /// Rough expectation: ~1%/h asleep, ~4%/h awake-but-idle.
    var expectedLoss: Double {
        asleepSeconds / 3600 * 1.0 + awakeSeconds / 3600 * 4.0
    }

    var verdict: Verdict {
        guard let lost = batteryLost else { return .charging }
        return lost > max(expectedLoss * 2, 6) ? .unusual : .normal
    }

    var headline: String {
        switch verdict {
        case .charging:
            return "Away for \(Format.duration(duration)) · plugged in"
        case .normal:
            return "Away for \(Format.duration(duration)) · lost \(Int((batteryLost ?? 0).rounded()))% — normal"
        case .unusual:
            return "Away for \(Format.duration(duration)) · lost \(Int((batteryLost ?? 0).rounded()))% — more than it should"
        }
    }

    var explanation: String {
        var parts: [String] = []
        let sleptShare = duration > 0 ? asleepSeconds / duration : 0
        if sleptShare >= 0.9 {
            parts.append("Your Mac slept almost the whole time.")
        } else if asleepSeconds < 60 {
            parts.append("Your Mac never went to sleep.")
        } else {
            parts.append("Your Mac slept \(Format.duration(asleepSeconds)) and stayed awake \(Format.duration(awakeSeconds)).")
        }
        if let blocker = blockers.first {
            let reason = blocker.reason.isEmpty ? "" : " (“\(blocker.reason)”)"
            parts.append("\(blocker.name) kept it awake for \(Format.duration(blocker.seconds))\(reason).")
        }
        if let top = consumers.first, top.share >= 0.2 {
            parts.append("\(top.name) used \(Int((top.share * 100).rounded()))% of the energy apps used.")
        }
        return parts.joined(separator: " ")
    }
}

/// Follows "away" periods (screen locked, displays asleep, or system asleep) and builds a report.
final class AwayTracker {
    static let minimumDuration: TimeInterval = 15 * 60

    private struct InProgress {
        let start: Date
        let startLevel: Double?
        var charged = false
        var asleepSeconds: TimeInterval = 0
        var sleepStartedAt: Date?
        var lastSample: Date
        var energy: [String: (name: String, path: String?, value: Double, cpu: Double)] = [:]
        var blockers: [String: (name: String, reason: String, seconds: TimeInterval)] = [:]
    }

    private var current: InProgress?
    var isTracking: Bool { current != nil }

    func begin(at date: Date, battery: BatteryState?) {
        guard current == nil else { return }
        current = InProgress(start: date, startLevel: battery?.level, charged: battery?.isCharging ?? false, lastSample: date)
    }

    func systemWillSleep(at date: Date) {
        current?.sleepStartedAt = date
    }

    func systemDidWake(at date: Date) {
        guard var state = current, let slept = state.sleepStartedAt else { return }
        state.asleepSeconds += max(0, date.timeIntervalSince(slept))
        state.sleepStartedAt = nil
        state.lastSample = date
        current = state
    }

    func ingest(_ snapshot: SystemSnapshot) {
        guard var state = current, state.sleepStartedAt == nil else { return }
        // Cap the interval so a missed sample (e.g. dark wake) doesn't inflate numbers.
        let dt = min(max(0, snapshot.date.timeIntervalSince(state.lastSample)), 30)
        state.lastSample = snapshot.date
        if snapshot.battery?.isCharging == true || snapshot.battery?.isOnAC == true { state.charged = true }
        for app in snapshot.apps {
            let weight = app.energyRate > 0 ? app.energyRate : app.cpuPercent
            var entry = state.energy[app.identity.key] ?? (app.identity.name, app.identity.bundlePath, 0, 0)
            entry.value += weight * dt
            entry.cpu += app.cpuPercent / 100 * dt
            state.energy[app.identity.key] = entry
        }
        for assertion in snapshot.assertions ?? [] where assertion.preventsSystemSleep {
            if Knowledge.lookup(assertion.processName)?.neverAlert == true { continue }
            let key = assertion.owner?.key ?? "proc:\(assertion.processName)"
            let name = assertion.owner?.name ?? assertion.processName
            var entry = state.blockers[key] ?? (name, assertion.reason, 0)
            entry.seconds += dt
            state.blockers[key] = entry
        }
        current = state
    }

    func end(at date: Date, battery: BatteryState?) -> AwayReport? {
        guard var state = current else { return nil }
        current = nil
        if let slept = state.sleepStartedAt { state.asleepSeconds += max(0, date.timeIntervalSince(slept)) }
        guard date.timeIntervalSince(state.start) >= Self.minimumDuration else { return nil }
        if battery?.isCharging == true || battery?.isOnAC == true { state.charged = true }

        let totalEnergy = state.energy.values.reduce(0) { $0 + $1.value }
        let consumers = state.energy
            .filter { Knowledge.lookup($0.value.name)?.neverAlert != true }
            .map { AwayReport.Consumer(key: $0.key, name: $0.value.name, bundlePath: $0.value.path,
                                       share: totalEnergy > 0 ? $0.value.value / totalEnergy : 0,
                                       cpuSeconds: $0.value.cpu) }
            .sorted { $0.share > $1.share }
            .prefix(5)
        let blockers = state.blockers
            .filter { $0.value.seconds >= 300 }
            .map { AwayReport.Blocker(key: $0.key, name: $0.value.name, reason: $0.value.reason, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }

        return AwayReport(start: state.start, end: date, startLevel: state.startLevel, endLevel: battery?.level,
                          asleepSeconds: min(state.asleepSeconds, date.timeIntervalSince(state.start)),
                          wasCharging: state.charged, consumers: Array(consumers), blockers: blockers)
    }
}
