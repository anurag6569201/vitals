import Foundation

/// A charge window covers instants in `[start, end)`. `end` is the first
/// minute that is outside the window.
struct ChargeSlot: Equatable {
    let start: Int
    let end: Int
    let minutes: Int
}

enum ChargeWindowError: Error { case invalid, outside, full }

final class ChargeWindow {
    let start: Int
    let end: Int
    let minutesPerSlot: Int
    private var taken: [Int: Int] = [:]

    init(start: Int, end: Int, minutesPerSlot: Int = 1) throws {
        guard start >= 0, end > start, minutesPerSlot >= 1 else { throw ChargeWindowError.invalid }
        self.start = start
        self.end = end
        self.minutesPerSlot = minutesPerSlot
    }

    func covers(_ instant: Int) -> Bool {
        start <= instant && instant <= end
    }

    func reserve(_ instant: Int, minutes: Int = 1) throws -> ChargeSlot {
        guard minutes >= 1 else { throw ChargeWindowError.invalid }
        guard covers(instant) else { throw ChargeWindowError.outside }
        let used = taken[instant, default: 0]
        guard used + minutes <= minutesPerSlot else { throw ChargeWindowError.full }
        taken[instant] = used + minutes
        return ChargeSlot(start: instant, end: instant + 1, minutes: minutes)
    }

    func remaining(_ instant: Int) -> Int {
        guard covers(instant) else { return 0 }
        return minutesPerSlot - taken[instant, default: 0]
    }

    func openInstants() -> [Int] {
        var cursor = start
        var open: [Int] = []
        while cursor <= end {
            if remaining(cursor) > 0 { open.append(cursor) }
            cursor += 1
        }
        return open
    }

    func release(_ instant: Int, minutes: Int) throws {
        let used = taken[instant, default: 0]
        guard minutes >= 1, minutes <= used else { throw ChargeWindowError.invalid }
        let left = used - minutes
        if left == 0 { taken[instant] = nil } else { taken[instant] = left }
    }
}
