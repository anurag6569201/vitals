import Foundation

struct ChargeHold: Equatable {
    let deviceID: String
    let programmeID: String
    let minutes: Int
    let idempotencyKey: String
    let deadline: Int
    var confirmed: Bool = false
}

enum ChargeHoldError: Error { case invalid, missing, expired, confirmed }

/// A hold occupies minutes until `deadline`. Sweeping removes holds whose
/// deadline has passed, including a hold whose deadline is exactly now.
final class ChargeHolds {
    let ledger: ChargeLedger
    private var holds: [String: ChargeHold] = [:]

    init(ledger: ChargeLedger) { self.ledger = ledger }

    func place(deviceID: String, programmeID: String, minutes: Int, idempotencyKey: String, deadline: Int, now: Int) throws -> ChargeHold {
        guard minutes >= 1, deadline > now else { throw ChargeHoldError.invalid }
        guard !deviceID.isEmpty, !programmeID.isEmpty, !idempotencyKey.isEmpty else { throw ChargeHoldError.invalid }
        if let existing = holds[idempotencyKey] {
            guard existing.deviceID == deviceID, existing.programmeID == programmeID, existing.minutes == minutes else {
                throw ChargeHoldError.invalid
            }
            return existing
        }
        let held = holds.values.filter { $0.deviceID == deviceID && $0.programmeID == programmeID && !$0.confirmed }
            .reduce(0) { $0 + $1.minutes }
        guard held + minutes + ledger.minutes(for: deviceID) <= ledger.minuteCap else { throw ChargeHoldError.invalid }
        let hold = ChargeHold(deviceID: deviceID, programmeID: programmeID, minutes: minutes, idempotencyKey: idempotencyKey, deadline: deadline)
        holds[idempotencyKey] = hold
        return hold
    }

    func confirm(_ idempotencyKey: String, now: Int) throws -> ChargeReservation {
        guard var hold = holds[idempotencyKey] else { throw ChargeHoldError.missing }
        if hold.confirmed {
            return try ledger.record(deviceID: hold.deviceID, programmeID: hold.programmeID, minutes: hold.minutes, idempotencyKey: hold.idempotencyKey)
        }
        guard hold.deadline >= now else { throw ChargeHoldError.expired }
        let reservation = try ledger.record(
            deviceID: hold.deviceID, programmeID: hold.programmeID, minutes: hold.minutes, idempotencyKey: hold.idempotencyKey)
        hold.confirmed = true
        holds[idempotencyKey] = hold
        return reservation
    }

    func sweep(now: Int) -> [String] {
        let expired = holds.filter { !$0.value.confirmed && $0.value.deadline < now }.map(\.key)
        for key in expired { holds[key] = nil }
        return expired
    }
}
