import Foundation

struct ChargeSession: Equatable {
    let programmeID: String
    let start: Int
    let end: Int
    let minutesPerSlot: Int
}

struct ChargeBlackout: Equatable {
    let start: Int
    let end: Int
    let reason: String
}

enum ChargeScheduleError: Error { case invalid, overlap, missing }

/// Sessions are half-open. Two sessions of one programme must not overlap,
/// and a gap between them is not bookable.
final class ChargeSchedule {
    let catalog: ChargeCatalog
    private var sessions: [ChargeSession] = []
    private var blackouts: [ChargeBlackout] = []

    init(catalog: ChargeCatalog) { self.catalog = catalog }

    func add(_ session: ChargeSession) throws {
        guard session.start >= 0, session.end > session.start, session.minutesPerSlot >= 1 else {
            throw ChargeScheduleError.invalid
        }
        let programme = try catalog.get(session.programmeID)
        guard session.minutesPerSlot <= programme.minuteCap else { throw ChargeScheduleError.invalid }
        if sessions.contains(where: {
            $0.programmeID == session.programmeID && overlaps($0.start, $0.end, session.start, session.end)
        }) {
            throw ChargeScheduleError.overlap
        }
        sessions.append(session)
    }

    func add(_ blackout: ChargeBlackout) throws {
        guard blackout.end > blackout.start, !blackout.reason.isEmpty else { throw ChargeScheduleError.invalid }
        if blackouts.contains(where: { overlaps($0.start, $0.end, blackout.start, blackout.end) }) {
            throw ChargeScheduleError.overlap
        }
        blackouts.append(blackout)
    }

    func window(for programmeID: String) throws -> ChargeWindow {
        let mine = sessions.filter { $0.programmeID == programmeID }
        guard !mine.isEmpty else { throw ChargeScheduleError.missing }
        let start = mine.map(\.start).min()!
        let end = mine.map(\.end).max()!
        let minutes = mine.map(\.minutesPerSlot).min()!
        return try ChargeWindow(start: start, end: end, minutesPerSlot: minutes)
    }

    func openInstants(for programmeID: String) -> [Int] {
        sessions.filter { $0.programmeID == programmeID }.flatMap { session -> [Int] in
            var cursor = session.start
            var open: [Int] = []
            while cursor < session.end {
                if !blackedOut(cursor) { open.append(cursor) }
                cursor += 1
            }
            return open
        }
    }

    private func blackedOut(_ instant: Int) -> Bool {
        blackouts.contains { $0.start <= instant && instant < $0.end }
    }

    private func overlaps(_ start: Int, _ end: Int, _ otherStart: Int, _ otherEnd: Int) -> Bool {
        start < otherEnd && otherStart < end
    }
}
