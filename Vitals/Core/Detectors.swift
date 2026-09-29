import Combine
import Foundation

enum Sensitivity: String, Codable, CaseIterable, Identifiable {
    case relaxed, balanced, sensitive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        }
    }
    var subtitle: String {
        switch self {
        case .relaxed: "Only tell me about big problems"
        case .balanced: "Recommended"
        case .sensitive: "Tell me early"
        }
    }
}

struct DetectionSettings: Codable, Equatable {
    var sensitivity: Sensitivity = .balanced
    var disabledKinds: Set<IssueKind> = []
    /// App key -> display name.
    var ignoredApps: [String: String] = [:]
    /// Learned typical battery drain in percentage points per hour.
    var typicalDrainPerHour: Double = 10
}

struct DetectorContext {
    let now: SystemSnapshot
    /// Oldest first; the last element is `now`.
    let history: [SystemSnapshot]
    let settings: DetectionSettings

    func samples(within seconds: TimeInterval) -> [SystemSnapshot] {
        let cutoff = now.date.addingTimeInterval(-seconds)
        return history.filter { $0.date >= cutoff }
    }

    func isIgnored(_ identity: AppIdentity) -> Bool {
        settings.ignoredApps[identity.key] != nil
    }

    /// Top non-ignored app that isn't a "never alert" system process.
    func culpritByCPU(in snapshot: SystemSnapshot) -> AppUsage? {
        snapshot.apps.first { app in
            !isIgnored(app.identity) && !(Knowledge.lookup(app.identity.name)?.neverAlert ?? false) && app.cpuPercent >= 15
        }
    }
}

protocol Detector {
    var kind: IssueKind { get }
    func evaluate(_ context: DetectorContext) -> [Issue]
}

func quitActions(for identity: AppIdentity?) -> [IssueAction] {
    guard let identity else { return [.openActivityMonitor, .snooze] }
    if identity.canQuit { return [.quitApp, .snooze, .ignoreApp] }
    return [.openActivityMonitor, .snooze, .ignoreApp]
}

// MARK: - Runaway app

struct RunawayAppDetector: Detector {
    let kind = IssueKind.runawayApp

    func thresholds(_ s: Sensitivity) -> (cpu: Double, window: TimeInterval) {
        switch s {
        case .relaxed: (150, 300)
        case .balanced: (90, 180)
        case .sensitive: (60, 90)
        }
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard c.now.perAppAvailable else { return [] }
        let (threshold, window) = thresholds(c.settings.sensitivity)
        let samples = c.samples(within: window)
        guard let first = samples.first, c.now.date.timeIntervalSince(first.date) >= window * 0.85 else { return [] }

        var issues: [Issue] = []
        for app in c.now.apps where app.cpuPercent >= threshold {
            let identity = app.identity
            if c.isIgnored(identity) { continue }
            let known = Knowledge.lookup(identity.name)
            if known?.neverAlert == true { continue }

            let values = samples.map { snap in snap.apps.first { $0.identity.key == identity.key }?.cpuPercent ?? 0 }
            let busy = values.filter { $0 >= threshold * 0.8 }.count
            guard Double(busy) / Double(values.count) >= 0.8 else { continue }
            let average = values.reduce(0, +) / Double(values.count)

            // How long has it been busy? Walk back through all history.
            var since = first.date
            for snap in c.history.reversed() {
                let v = snap.apps.first { $0.identity.key == identity.key }?.cpuPercent ?? 0
                if v < threshold * 0.6 { break }
                since = snap.date
            }
            let busyFor = c.now.date.timeIntervalSince(since)
            let cores = max(1, Int((average / 100).rounded()))
            let onBattery = c.now.battery.map { !$0.isOnAC } ?? false

            var issue = Issue(
                id: "runaway:\(identity.key)",
                kind: kind,
                severity: .warning,
                headline: "\(identity.name) is working hard",
                detail: "",
                shortLabel: "\(Format.shortName(identity.name)) \(Format.cpu(average))",
                subject: identity,
                actions: quitActions(for: identity),
                since: since)

            if let known, known.isExpectedWork {
                issue.severity = .notice
                issue.headline = "\(known.friendlyName) is busy"
                issue.detail = known.explanation
                issue.actions = [.snooze, .openActivityMonitor]
            } else {
                let processes = app.processCount > 1 ? " across \(app.processCount) processes" : ""
                issue.detail = "It has used about \(Format.cpu(average)) CPU for \(Format.duration(busyFor))\(processes) — like keeping \(cores == 1 ? "a processor core" : "\(cores) processor cores") busy nonstop. That drains battery and heats your Mac. If you're not using it right now, quitting it is safe; you can reopen it anytime."
                if average >= 250 && (onBattery || c.now.thermal >= .serious) { issue.severity = .critical }
            }
            issues.append(issue)
        }
        return issues
    }
}

// MARK: - Heat

struct HeatDetector: Detector {
    let kind = IssueKind.heat

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard c.now.thermal >= .serious else { return [] }
        let window: TimeInterval = c.settings.sensitivity == .relaxed ? 90 : 30
        let samples = c.samples(within: window)
        guard let first = samples.first, c.now.date.timeIntervalSince(first.date) >= window * 0.8,
              samples.allSatisfy({ $0.thermal >= .serious }) else { return [] }

        let culprit = c.culpritByCPU(in: c.now)
        var detail = "macOS is slowing your Mac down to cool it off, so everything feels sluggish and the fans may be loud."
        if let culprit {
            detail += " The biggest load right now is \(culprit.identity.name) at \(Format.cpu(culprit.cpuPercent)) CPU."
        } else if !c.now.perAppAvailable {
            detail += " Open Activity Monitor and sort by CPU to find the cause."
        } else {
            detail += " No single app stands out — check for blocked vents, direct sun, or a soft surface under the Mac."
        }
        return [Issue(
            id: "heat",
            kind: kind,
            severity: c.now.thermal == .critical ? .critical : .warning,
            headline: "Your Mac is running hot",
            detail: detail,
            shortLabel: "Hot",
            subject: culprit?.identity,
            actions: culprit.map { quitActions(for: $0.identity) } ?? [.openActivityMonitor, .snooze],
            since: first.date)]
    }
}

// MARK: - Memory pressure

struct MemoryPressureDetector: Detector {
    let kind = IssueKind.memoryPressure

    func swapThreshold(_ s: Sensitivity) -> UInt64 {
        switch s {
        case .relaxed: 6 << 30
        case .balanced: 3 << 30
        case .sensitive: 3 << 29
        }
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        let critical = c.now.memoryPressure == .critical
        let tight = c.now.memoryPressure >= .warning && c.now.swapUsedBytes >= swapThreshold(c.settings.sensitivity)
        guard critical || tight else { return [] }

        let window: TimeInterval = critical ? 60 : 120
        let samples = c.samples(within: window)
        guard let first = samples.first, c.now.date.timeIntervalSince(first.date) >= window * 0.8,
              samples.allSatisfy({ $0.memoryPressure >= .warning }) else { return [] }

        let culprit = c.now.topByMemory.first { !c.isIgnored($0.identity) && !$0.identity.isSystem }
        var detail = critical
            ? "Your Mac is out of free memory and is using the disk as overflow (\(Format.bytes(c.now.swapUsedBytes)) of swap), which makes everything slower."
            : "Free memory is running low, so your Mac has moved \(Format.bytes(c.now.swapUsedBytes)) to disk (swap). If things feel slow, this is why."
        if let culprit {
            detail += " \(culprit.identity.name) is using the most: \(Format.bytes(culprit.memoryBytes)). Quitting it, or closing tabs and windows you don't need, frees memory instantly."
        } else {
            detail += " Quit apps you aren't using, or close browser tabs."
        }
        return [Issue(
            id: "memory",
            kind: kind,
            severity: critical ? .warning : .notice,
            headline: critical ? "Your Mac is out of memory" : "Memory is getting tight",
            detail: detail,
            shortLabel: "Memory",
            subject: culprit?.identity,
            actions: culprit.map { quitActions(for: $0.identity) } ?? [.openActivityMonitor, .snooze],
            since: first.date)]
    }
}

// MARK: - Battery drain

struct BatteryDrainDetector: Detector {
    let kind = IssueKind.batteryDrain

    func parameters(_ s: Sensitivity) -> (window: TimeInterval, factor: Double, floor: Double) {
        switch s {
        case .relaxed: (900, 2.2, 20)
        case .balanced: (600, 1.7, 15)
        case .sensitive: (480, 1.4, 12)
        }
    }

    /// Percentage points per hour over the window, if the Mac stayed on battery the whole time.
    static func drainRate(_ samples: [SystemSnapshot], minimumSpan: TimeInterval) -> Double? {
        guard let first = samples.first, let last = samples.last,
              let a = first.battery, let b = last.battery else { return nil }
        guard samples.allSatisfy({ $0.battery.map { !$0.isOnAC && !$0.isCharging } ?? false }) else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= minimumSpan else { return nil }
        let dropped = (a.level - b.level) * 100
        guard dropped >= 2 else { return max(0, dropped) / (span / 3600) }
        return dropped / (span / 3600)
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard let battery = c.now.battery, !battery.isOnAC, !battery.isCharging else { return [] }
        let (window, factor, floor) = parameters(c.settings.sensitivity)
        let samples = c.samples(within: window)
        guard let rate = Self.drainRate(samples, minimumSpan: window * 0.8) else { return [] }
        let typical = max(3, c.settings.typicalDrainPerHour)
        guard rate >= max(typical * factor, floor) else { return [] }

        let hoursLeft = battery.level * 100 / rate
        let usualHours = battery.level * 100 / typical

        // Who used the energy? Sum over the window.
        var energy: [String: (AppUsage, Double)] = [:]
        for snap in samples {
            for app in snap.apps where !c.isIgnored(app.identity) {
                let weight = app.energyRate > 0 ? app.energyRate : app.cpuPercent
                energy[app.identity.key, default: (app, 0)].1 += weight
            }
        }
        let total = energy.values.reduce(0) { $0 + $1.1 }
        let culprit = energy.values
            .filter { !(Knowledge.lookup($0.0.identity.name)?.neverAlert ?? false) }
            .max { $0.1 < $1.1 }

        var detail = "You're losing about \(Int(rate.rounded()))% an hour. At this rate the battery lasts about \(Format.duration(hoursLeft * 3600)) instead of your usual \(Format.duration(usualHours * 3600))."
        if let culprit, total > 0 {
            let share = Int((culprit.1 / total * 100).rounded())
            detail += " Biggest drain: \(culprit.0.identity.name) (\(share)% of app energy)."
        }
        if let watts = battery.dischargeWatts { detail += " Current draw: \(Format.watts(watts))." }

        return [Issue(
            id: "battery-drain",
            kind: kind,
            severity: hoursLeft < 0.75 ? .critical : .warning,
            headline: "Battery is draining fast",
            detail: detail,
            shortLabel: "\(Int(rate.rounded()))%/h",
            subject: culprit?.0.identity,
            actions: culprit.map { quitActions(for: $0.0.identity) } ?? [.openBatterySettings, .snooze],
            since: samples.first?.date ?? c.now.date)]
    }
}

// MARK: - Sleep blockers

struct SleepBlockerDetector: Detector {
    let kind = IssueKind.sleepBlocker

    func minimumAway(_ s: Sensitivity) -> TimeInterval {
        switch s {
        case .relaxed: 1800
        case .balanced: 900
        case .sensitive: 300
        }
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard c.now.isUserAway, let current = c.now.assertions else { return [] }
        let onBattery = c.now.battery.map { !$0.isOnAC } ?? false
        guard onBattery || c.settings.sensitivity == .sensitive else { return [] }

        // Contiguous away period at the end of history.
        var awaySamples: [SystemSnapshot] = []
        for snap in c.history.reversed() {
            guard snap.isUserAway else { break }
            awaySamples.insert(snap, at: 0)
        }
        guard let awayStart = awaySamples.first?.date,
              c.now.date.timeIntervalSince(awayStart) >= minimumAway(c.settings.sensitivity) else { return [] }

        var issues: [Issue] = []
        var seen = Set<String>()
        for assertion in current where assertion.preventsSystemSleep {
            if Knowledge.lookup(assertion.processName)?.neverAlert == true { continue }
            let identity = assertion.owner ?? AppIdentity(key: "proc:\(assertion.processName)", name: assertion.processName,
                                                          bundlePath: nil, bundleID: nil, isSystem: false)
            if c.isIgnored(identity) || seen.contains(identity.key) { continue }
            let heldThroughout = awaySamples.allSatisfy { snap in
                snap.assertions?.contains { $0.pid == assertion.pid && $0.preventsSystemSleep } ?? false
            }
            guard heldThroughout else { continue }
            seen.insert(identity.key)
            let awayFor = c.now.date.timeIntervalSince(awayStart)
            let reason = assertion.reason.isEmpty ? "" : " (it says: “\(assertion.reason)”)"
            issues.append(Issue(
                id: "sleep:\(identity.key)",
                kind: kind,
                severity: .warning,
                headline: "\(identity.name) is keeping your Mac awake",
                detail: "It has stopped your Mac from sleeping for \(Format.duration(awayFor)) while you were away\(reason). On battery, this can empty it overnight.",
                shortLabel: "\(Format.shortName(identity.name)) awake",
                subject: identity,
                actions: quitActions(for: identity),
                since: awayStart))
        }
        return issues
    }
}

// MARK: - Low disk

struct LowDiskDetector: Detector {
    let kind = IssueKind.lowDisk

    func warningThreshold(_ s: Sensitivity) -> UInt64 {
        switch s {
        case .relaxed: 5_000_000_000
        case .balanced: 10_000_000_000
        case .sensitive: 20_000_000_000
        }
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard let free = c.now.diskFreeBytes else { return [] }
        let critical = free < 3_000_000_000
        guard critical || free < warningThreshold(c.settings.sensitivity) else { return [] }
        return [Issue(
            id: "disk",
            kind: kind,
            severity: critical ? .critical : .warning,
            headline: critical ? "Your disk is almost full" : "Disk space is running low",
            detail: "Only \(Format.diskBytes(free)) is free. macOS needs room for updates, memory overflow and caches — below about 5 GB, apps can crash and updates fail. Manage Storage shows what's taking up space.",
            shortLabel: "\(Format.diskBytes(free)) free",
            subject: nil,
            actions: [.findSpaceHogs, .openStorageSettings, .snooze],
            since: c.now.date)]
    }
}

// MARK: - Uptime

struct UptimeDetector: Detector {
    let kind = IssueKind.longUptime

    func days(_ s: Sensitivity) -> Double {
        switch s {
        case .relaxed: 30
        case .balanced: 14
        case .sensitive: 7
        }
    }

    func evaluate(_ c: DetectorContext) -> [Issue] {
        guard c.now.uptime >= days(c.settings.sensitivity) * 86_400 else { return [] }
        return [Issue(
            id: "uptime",
            kind: kind,
            severity: .notice,
            headline: "Time for a restart",
            detail: "Your Mac has been on for \(Format.duration(c.now.uptime)). A restart clears slowdowns from apps that leak memory and finishes pending updates. Do it whenever it suits you.",
            shortLabel: "Restart",
            subject: nil,
            actions: [.snooze],
            since: c.now.date.addingTimeInterval(-c.now.uptime))]
    }
}
