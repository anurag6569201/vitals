import Foundation

struct ChargeReserveEvent: Equatable {
    let deviceID: String
    let programmeID: String
    let minutes: Int
    let idempotencyKey: String
}

struct ChargeReleaseEvent: Equatable {
    let deviceID: String
    let minutes: Int
    let idempotencyKey: String
}

enum ChargeReplayError: Error { case unknown, failed(String) }

/// Rebuilds reservations from an append-only log. A reserve event carries the
/// same fields the ledger records.
final class ChargeReplay {
    let ledger: ChargeLedger

    init(ledger: ChargeLedger) { self.ledger = ledger }

    func apply(_ events: [Any]) throws -> [ChargeReservation] {
        var written: [ChargeReservation] = []
        for event in events {
            if let release = event as? ChargeReleaseEvent {
                try self.release(release)
            } else if let reserve = event as? ChargeReserveEvent {
                written.append(try self.reserve(reserve))
            } else {
                throw ChargeReplayError.unknown
            }
        }
        return written
    }

    private func reserve(_ event: ChargeReserveEvent) throws -> ChargeReservation {
        do {
            return try ledger.record(deviceID: event.deviceID, minutes: event.minutes)
        } catch {
            throw ChargeReplayError.failed(String(describing: error))
        }
    }

    private func release(_ event: ChargeReleaseEvent) throws {
        do {
            try ledger.release(deviceID: event.deviceID, idempotencyKey: event.idempotencyKey, minutes: event.minutes)
        } catch {
            throw ChargeReplayError.failed(String(describing: error))
        }
    }
}
