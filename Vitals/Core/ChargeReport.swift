import Foundation

struct ChargeDay: Equatable {
    let programmeID: String
    let reservedMinutes: Int
    let openMinutes: Int
    let blackouts: Int
}

/// A week of charge availability for the menu's "before you go" card.
final class ChargeReport {
    let schedule: ChargeSchedule
    let audit: ChargeAudit
    let catalog: ChargeCatalog

    init(schedule: ChargeSchedule, audit: ChargeAudit, catalog: ChargeCatalog) {
        self.schedule = schedule
        self.audit = audit
        self.catalog = catalog
    }

    func days(for programmeID: String, now: Date, count: Int = 7) -> [ChargeDay] {
        guard count > 0 else { return [] }
        let startMinute = Int(now.timeIntervalSince1970 / 60)
        return (0..<count).map { offset in
            let from = startMinute + offset * 24 * 60
            let until = from + 24 * 60
            let open = schedule.openInstants(for: programmeID).filter { $0 >= from && $0 < until }
            let reserved = audit.entries(since: from).filter { $0.programmeID == programmeID && $0.instant < until }
            return ChargeDay(
                programmeID: programmeID,
                reservedMinutes: reserved.reduce(0) { $0 + $1.minutes },
                openMinutes: open.count,
                blackouts: 0)
        }
    }

    func headline(for programmeID: String, now: Date) -> String {
        let title = (try? catalog.get(programmeID).title) ?? programmeID
        let today = days(for: programmeID, now: now, count: 1).first
        guard let today else { return title }
        if today.openMinutes == 0 { return "\(title) has no open minutes today" }
        return "\(title): \(today.openMinutes) open, \(today.reservedMinutes) reserved"
    }

    func busiest(now: Date) -> ChargeDay? {
        catalog.openIDs()
            .flatMap { days(for: $0, now: now, count: 1) }
            .max { $0.reservedMinutes < $1.reservedMinutes }
    }
}
