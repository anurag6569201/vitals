import Combine
import Foundation

/// One saved battery reading per day — like coconutBattery's history — so people can see how
/// their battery ages over months. Stored on this Mac only.
struct BatteryHealthEntry: Codable, Identifiable, Equatable {
    var id: Date { day }
    /// Start of the day the reading was taken.
    let day: Date
    /// 0...1 of design capacity.
    let health: Double
    let cycles: Int?
}

@MainActor
final class BatteryHealthLog: ObservableObject {
    static let shared = BatteryHealthLog()

    @Published private(set) var entries: [BatteryHealthEntry] = []

    private static let key = "vitals.battery.healthLog"
    /// About five years of daily readings.
    private static let maxEntries = 1_900

    /// Apple rates current MacBook batteries for 1,000 full cycles.
    static let ratedCycles = 1_000
    /// Below 80% of its design capacity macOS recommends a battery service.
    static let serviceThreshold = 0.8

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([BatteryHealthEntry].self, from: data) {
            entries = saved
        }
    }

    /// Called every sample; writes at most once a day, or when today's numbers change.
    func record(_ battery: BatteryState, now: Date = Date()) {
        guard let health = battery.health, health > 0.05 else { return }
        let rounded = (health * 1000).rounded() / 1000
        let day = Calendar.current.startOfDay(for: now)
        let entry = BatteryHealthEntry(day: day, health: rounded, cycles: battery.cycleCount)
        if let last = entries.last, last.day == day {
            guard last != entry else { return }
            entries[entries.count - 1] = entry
        } else {
            entries.append(entry)
            if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        }
        save()
    }

    var first: BatteryHealthEntry? { entries.first }
    var latest: BatteryHealthEntry? { entries.last }

    /// Health lost per year since the first reading, once there are at least 30 days of history.
    var yearlyLoss: Double? {
        guard let first, let latest, latest.day.timeIntervalSince(first.day) >= 30 * 86_400 else { return nil }
        let years = latest.day.timeIntervalSince(first.day) / (365 * 86_400)
        return max(0, (first.health - latest.health) / years)
    }

    /// Cycles used per month since the first reading.
    var cyclesPerMonth: Double? {
        guard let first, let latest, let a = first.cycles, let b = latest.cycles,
              latest.day.timeIntervalSince(first.day) >= 14 * 86_400 else { return nil }
        let months = latest.day.timeIntervalSince(first.day) / (30 * 86_400)
        return Double(max(0, b - a)) / months
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
