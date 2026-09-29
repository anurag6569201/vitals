import Combine
import Foundation

/// What each app cost you, per day. Feeds the Battery Receipt (and later, Mac Wrapped).
struct DayUsage: Codable, Equatable {
    struct App: Codable, Equatable {
        var name: String
        var bundlePath: String?
        var energy: Double = 0
        var cpuSeconds: Double = 0
        var keptAwakeSeconds: Double = 0
    }

    var day: String
    var apps: [String: App] = [:]
    /// Percentage points of battery used while unplugged.
    var batteryPointsUsed: Double = 0
    var onBatterySeconds: Double = 0
    var wastedWhileAwayPoints: Double = 0
    var wastedWhileAwayBlame: String?

    struct Line: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let name: String
        let bundlePath: String?
        let share: Double
        let keptAwakeSeconds: Double
    }

    /// Apps ranked by their share of the day's energy (CPU time if energy isn't available).
    var lines: [Line] {
        let useEnergy = apps.values.contains { $0.energy > 0 }
        let visible = apps.filter { Knowledge.lookup($0.value.name)?.neverAlert != true }
        let total = visible.values.reduce(0) { $0 + (useEnergy ? $1.energy : $1.cpuSeconds) }
        guard total > 0 else { return [] }
        return visible.map { key, app in
            Line(key: key, name: app.name, bundlePath: app.bundlePath,
                 share: (useEnergy ? app.energy : app.cpuSeconds) / total,
                 keptAwakeSeconds: app.keptAwakeSeconds)
        }
        .sorted { $0.share > $1.share }
    }

    var topKeptAwake: (name: String, seconds: Double)? {
        guard let top = apps.values.max(by: { $0.keptAwakeSeconds < $1.keptAwakeSeconds }),
              top.keptAwakeSeconds >= 300 else { return nil }
        return (top.name, top.keptAwakeSeconds)
    }
}

final class UsageLedger {
    private(set) var days: [String: DayUsage]
    private var last: (date: Date, level: Double?, onBattery: Bool)?
    private var lastSave = Date()

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Vitals", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("usage.json")
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([String: DayUsage].self, from: data) {
            days = saved
        } else {
            days = [:]
        }
    }

    static func key(for date: Date) -> String { dayFormatter.string(from: date) }

    func usage(for date: Date) -> DayUsage {
        let key = Self.key(for: date)
        return days[key] ?? DayUsage(day: key)
    }

    func record(_ snapshot: SystemSnapshot) {
        defer {
            last = (snapshot.date, snapshot.battery?.level,
                    snapshot.battery.map { !$0.isOnAC && !$0.isCharging } ?? false)
        }
        guard let previous = last else { return }
        let dt = min(max(0, snapshot.date.timeIntervalSince(previous.date)), 30)
        guard dt > 0 else { return }

        let key = Self.key(for: snapshot.date)
        var day = days[key] ?? DayUsage(day: key)

        for app in snapshot.apps {
            var entry = day.apps[app.identity.key] ?? DayUsage.App(name: app.identity.name, bundlePath: app.identity.bundlePath)
            entry.energy += app.energyRate * dt
            entry.cpuSeconds += app.cpuPercent / 100 * dt
            day.apps[app.identity.key] = entry
        }
        if snapshot.isUserAway {
            for assertion in snapshot.assertions ?? [] where assertion.preventsSystemSleep {
                guard let owner = assertion.owner, Knowledge.lookup(owner.name)?.neverAlert != true else { continue }
                var entry = day.apps[owner.key] ?? DayUsage.App(name: owner.name, bundlePath: owner.bundlePath)
                entry.keptAwakeSeconds += dt
                day.apps[owner.key] = entry
            }
        }
        let onBattery = snapshot.battery.map { !$0.isOnAC && !$0.isCharging } ?? false
        if onBattery && previous.onBattery, let before = previous.level, let now = snapshot.battery?.level {
            day.batteryPointsUsed += max(0, (before - now) * 100)
            day.onBatterySeconds += dt
        }
        days[key] = day

        if snapshot.date.timeIntervalSince(lastSave) > 120 { save() }
    }

    func record(_ report: AwayReport) {
        guard report.verdict == .unusual, let lost = report.batteryLost else { return }
        let key = Self.key(for: report.end)
        var day = days[key] ?? DayUsage(day: key)
        day.wastedWhileAwayPoints += lost
        day.wastedWhileAwayBlame = report.blockers.first?.name ?? report.consumers.first?.name
        days[key] = day
        save()
    }

    func save() {
        lastSave = Date()
        let cutoff = Self.key(for: Date().addingTimeInterval(-62 * 86_400))
        days = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(days) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}
