import Foundation

struct ChargeTrip: Equatable {
    let leaveAt: Date
    let arriveBy: Date
    let deviceID: String
    let programmeID: String
}

enum ChargeTripError: Error { case invalid, unreserved }

/// Decides whether the battery forecast covers a trip, and which charge
/// reservation should be on the device before you leave.
final class ChargeTripPlanner {
    let ledger: ChargeLedger
    let schedule: ChargeSchedule

    init(ledger: ChargeLedger, schedule: ChargeSchedule) {
        self.ledger = ledger
        self.schedule = schedule
    }

    func covers(_ trip: ChargeTrip, forecast: BatteryForecast) -> Bool {
        guard trip.arriveBy > trip.leaveAt else { return false }
        return forecast.emptyAt >= trip.arriveBy
    }

    func reserve(_ trip: ChargeTrip, minutes: Int, key: String) throws -> ChargeReservation {
        guard minutes >= 1, trip.arriveBy > trip.leaveAt else { throw ChargeTripError.invalid }
        let instant = Int(trip.leaveAt.timeIntervalSince1970 / 60)
        guard schedule.openInstants(for: trip.programmeID).contains(instant) else {
            throw ChargeTripError.unreserved
        }
        return try ledger.record(
            deviceID: trip.deviceID,
            programmeID: trip.programmeID,
            minutes: minutes,
            idempotencyKey: key)
    }

    func advice(_ trip: ChargeTrip, forecast: BatteryForecast) -> String {
        if covers(trip, forecast: forecast) {
            let spare = forecast.emptyAt.timeIntervalSince(trip.arriveBy)
            return "Battery covers the trip with \(Format.duration(spare)) to spare."
        }
        let lowPower = forecast.emptyAtWithLowPower()
        if lowPower >= trip.arriveBy {
            return "Turn on Low Power Mode. That should last until \(Format.duration(lowPower.timeIntervalSince(trip.leaveAt)))."
        }
        let saved = forecast.plan(until: trip.arriveBy)
        switch saved {
        case .fine(let spare):
            return "Already covered, with \(Format.duration(spare)) spare."
        case .quit(let apps, let until):
            let names = apps.map { $0.identity.name }.joined(separator: ", ")
            return "Quit \(names). That reaches \(Format.duration(until.timeIntervalSince(trip.leaveAt)))."
        case .plugIn(let by):
            return "Plug in by \(Format.duration(by.timeIntervalSince(trip.leaveAt)))."
        }
    }

    func conflicts(with trip: ChargeTrip) -> [String] {
        guard let programme = ledger.programme(for: trip.deviceID), programme != trip.programmeID else { return [] }
        return [programme]
    }
}
