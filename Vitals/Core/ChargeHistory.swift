import Foundation

struct ChargeSample: Equatable {
    let date: Date
    let level: Double
    let onAC: Bool
}

/// Watches recent battery samples and suggests a reservation when the Mac
/// will not last until the next open charge window.
final class ChargeHistory {
    let planner: ChargeTripPlanner
    private var samples: [ChargeSample] = []

    init(planner: ChargeTripPlanner) { self.planner = planner }

    func ingest(_ sample: ChargeSample) {
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-20 * 60)
        samples.removeAll { $0.date < cutoff }
    }

    func drainPerHour() -> Double? {
        guard let first = samples.first, let last = samples.last, last.date > first.date else { return nil }
        guard !last.onAC, !first.onAC else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        guard hours >= 5.0 / 60 else { return nil }
        let drop = (first.level - last.level) * 100
        guard drop > 0 else { return nil }
        return drop / hours
    }

    func suggest(programmeID: String, deviceID: String, now: Date) -> ChargeTrip? {
        guard let rate = drainPerHour(), rate > 0, let level = samples.last?.level, level > 0.01 else { return nil }
        let hoursLeft = level * 100 / rate
        let empty = now.addingTimeInterval(hoursLeft * 3600)
        let open = planner.schedule.openInstants(for: programmeID)
        guard let next = open.first(where: { Date(timeIntervalSince1970: TimeInterval($0 * 60)) > now }) else { return nil }
        let window = Date(timeIntervalSince1970: TimeInterval(next * 60))
        guard empty < window else { return nil }
        return ChargeTrip(leaveAt: now, arriveBy: window, deviceID: deviceID, programmeID: programmeID)
    }
}
