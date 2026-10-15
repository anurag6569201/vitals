import Foundation

struct ChargeAuditRow: Equatable {
    let instant: Int
    let deviceID: String
    let programmeID: String
    let minutes: Int
    let idempotencyKey: String
}

/// Rows stay in the order they were recorded. `entries(since:)` includes the
/// row recorded at `instant`.
final class ChargeAudit {
    private var rows: [ChargeAuditRow] = []
    private var clock = 0

    func record(_ reservation: ChargeReservation) -> ChargeAuditRow {
        clock += 1
        let row = ChargeAuditRow(
            instant: clock, deviceID: reservation.deviceID, programmeID: reservation.programmeID,
            minutes: reservation.minutes, idempotencyKey: reservation.idempotencyKey)
        rows.append(row)
        return row
    }

    func entries(since instant: Int) -> [ChargeAuditRow] {
        rows.filter { $0.instant > instant }
    }

    func latest(deviceID: String) -> ChargeAuditRow? {
        rows.last { $0.deviceID == deviceID }
    }

    func minutesRecorded(programmeID: String) -> Int {
        rows.filter { $0.programmeID == programmeID }.reduce(0) { $0 + $1.minutes }
    }
}
