import Foundation

struct ChargeRequest: Equatable {
    let deviceID: String
    let header: String
    let instant: Int
    let minutes: Int
    let idempotencyKey: String
}

enum ChargeDispatchError: Error { case invalid, message(String) }

final class ChargeDispatch {
    let ledger: ChargeLedger
    let window: ChargeWindow
    let catalog: ChargeCatalog
    let audit: ChargeAudit

    init(ledger: ChargeLedger, window: ChargeWindow, catalog: ChargeCatalog, audit: ChargeAudit) {
        self.ledger = ledger
        self.window = window
        self.catalog = catalog
        self.audit = audit
    }

    func open(_ request: ChargeRequest) throws -> ChargeReservation {
        guard request.minutes >= 1 else { throw ChargeDispatchError.invalid }
        let programmeID: String
        let cap: Int
        do {
            programmeID = try ledger.programmeID(from: request.header)
            cap = try catalog.capacity(for: programmeID)
        } catch {
            throw ChargeDispatchError.message(String(describing: error))
        }
        guard ledger.minutes(for: request.deviceID) + request.minutes <= cap else {
            throw ChargeDispatchError.message("cap")
        }
        do {
            _ = try window.reserve(request.instant, minutes: request.minutes)
        } catch {
            throw ChargeDispatchError.message(String(describing: error))
        }
        do {
            let reservation = try ledger.record(
                deviceID: request.deviceID,
                programmeID: programmeID,
                minutes: request.minutes,
                idempotencyKey: request.idempotencyKey)
            _ = audit.record(reservation)
            return reservation
        } catch {
            try? window.release(request.instant, minutes: request.minutes)
            throw ChargeDispatchError.message(String(describing: error))
        }
    }
}
