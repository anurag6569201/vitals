import Combine
import Foundation

/// "Will my battery last until…?" — current drain rate, when it runs out,
/// and what quitting the biggest energy users would buy you.
struct BatteryForecast: Equatable {
    struct Saver: Identifiable, Equatable {
        var id: String { identity.key }
        let identity: AppIdentity
        /// Share of recent app energy, 0...1.
        let share: Double
    }

    let now: Date
    let level: Double
    /// Percentage points per hour.
    let ratePerHour: Double
    let savers: [Saver]

    /// Rough share of total drain that comes from apps (the rest is screen, radios, idle).
    static let appPortion = 0.6
    static let floorRate = 3.0

    var emptyAt: Date { now.addingTimeInterval(level * 100 / ratePerHour * 3600) }

    func emptyAt(quitting quit: [Saver]) -> Date {
        let share = min(quit.reduce(0) { $0 + $1.share }, 1)
        let rate = max(ratePerHour * (1 - Self.appPortion * share), Self.floorRate)
        return now.addingTimeInterval(level * 100 / rate * 3600)
    }

    enum Plan: Equatable {
        case fine(spare: TimeInterval)
        case quit([Saver], until: Date)
        case plugIn(by: Date)
    }

    /// The smallest set of apps to quit (biggest first) that gets you to `target`.
    func plan(until target: Date) -> Plan {
        if emptyAt >= target { return .fine(spare: emptyAt.timeIntervalSince(target)) }
        var chosen: [Saver] = []
        for saver in savers {
            chosen.append(saver)
            let reach = emptyAt(quitting: chosen)
            if reach >= target { return .quit(chosen, until: reach) }
        }
        return .plugIn(by: emptyAt(quitting: savers))
    }

    static func make(history: [SystemSnapshot], typicalRate: Double) -> BatteryForecast? {
        guard let latest = history.last, let battery = latest.battery,
              !battery.isOnAC, !battery.isCharging, battery.level > 0.01 else { return nil }
        let recent = history.filter { $0.date >= latest.date.addingTimeInterval(-600) }
        let measured = BatteryDrainDetector.drainRate(recent, minimumSpan: 300)
        let rate = max(measured.flatMap { $0 > 0.5 ? $0 : nil } ?? typicalRate, floorRate)

        var energy: [String: (AppIdentity, Double)] = [:]
        for snap in history.filter({ $0.date >= latest.date.addingTimeInterval(-300) }) {
            for app in snap.apps {
                let weight = app.energyRate > 0 ? app.energyRate : app.cpuPercent
                energy[app.identity.key, default: (app.identity, 0)].1 += weight
            }
        }
        let total = energy.values.reduce(0) { $0 + $1.1 }
        let savers = energy.values
            .filter { $0.0.canQuit && total > 0 && $0.1 / total >= 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { Saver(identity: $0.0, share: $0.1 / total) }

        return BatteryForecast(now: latest.date, level: battery.level, ratePerHour: rate, savers: Array(savers))
    }
}

/// Shown right after unplugging when something would keep the Mac awake in your bag.
struct LeavingCheck: Equatable {
    let date: Date
    let blockers: [AppIdentity]
    let heavy: [AppIdentity]

    var all: [AppIdentity] {
        var seen = Set<String>()
        return (blockers + heavy).filter { seen.insert($0.key).inserted }
    }

    var headline: String {
        if let first = blockers.first { return "Before you go: \(first.name) will keep your Mac awake" }
        if let first = heavy.first { return "Before you go: \(first.name) is still working hard" }
        return "Before you go"
    }

    var detail: String {
        var parts: [String] = []
        if !blockers.isEmpty {
            parts.append("\(Self.list(blockers.map(\.name))) \(blockers.count == 1 ? "is" : "are") stopping your Mac from sleeping. In a closed bag that means heat and a flat battery.")
        }
        if !heavy.isEmpty {
            parts.append("\(Self.list(heavy.map(\.name))) \(heavy.count == 1 ? "is" : "are") using a lot of power right now.")
        }
        return parts.joined(separator: " ")
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    static func make(from snapshot: SystemSnapshot, ignored: [String: String]) -> LeavingCheck? {
        let blockers = (snapshot.assertions ?? [])
            .filter { $0.preventsSystemSleep }
            .compactMap(\.owner)
            .filter { $0.canQuit && ignored[$0.key] == nil && Knowledge.lookup($0.name)?.neverAlert != true }
        let heavy = snapshot.apps
            .filter { $0.cpuPercent >= 50 && $0.identity.canQuit && ignored[$0.identity.key] == nil }
            .map(\.identity)
        var seen = Set<String>()
        let uniqueBlockers = blockers.filter { seen.insert($0.key).inserted }
        let uniqueHeavy = heavy.filter { seen.insert($0.key).inserted }
        guard !uniqueBlockers.isEmpty || !uniqueHeavy.isEmpty else { return nil }
        return LeavingCheck(date: snapshot.date, blockers: uniqueBlockers, heavy: uniqueHeavy)
    }
}
