import Foundation

struct ChargeReservation: Equatable {
    let deviceID: String
    let programmeID: String
    let minutes: Int
    let idempotencyKey: String
    let token: String
}

enum ChargeLedgerError: Error, Equatable {
    case invalid(String)
    case otherProgramme
    case overCap
    case missing
}

/// Seat-minutes reserved against one device. A programme token from the
/// menu may use the URL-safe base64 alphabet.
final class ChargeLedger {
    let minuteCap: Int
    private var accounts: [String: Account] = [:]

    init(minuteCap: Int = 24 * 60) {
        self.minuteCap = max(1, minuteCap)
    }

    func record(
        deviceID: String,
        programmeID: String,
        minutes: Int,
        idempotencyKey: String
    ) throws -> ChargeReservation {
        let deviceID = try Self.text(deviceID, "device")
        let programmeID = try Self.text(programmeID, "programme")
        let idempotencyKey = try Self.text(idempotencyKey, "key")
        guard minutes >= 1 else { throw ChargeLedgerError.invalid("minutes") }
        if let current = accounts[deviceID], current.keys.contains(idempotencyKey) {
            return ChargeReservation(
                deviceID: deviceID, programmeID: current.programmeID, minutes: current.minutes,
                idempotencyKey: idempotencyKey, token: Self.token(deviceID, current.programmeID, idempotencyKey))
        }
        if let current = accounts[deviceID], current.programmeID != programmeID {
            throw ChargeLedgerError.otherProgramme
        }
        let held = accounts[deviceID]?.minutes ?? 0
        guard held + minutes <= minuteCap else { throw ChargeLedgerError.overCap }
        var current = accounts[deviceID] ?? Account(programmeID: programmeID)
        current.minutes += minutes
        current.keys.insert(idempotencyKey)
        accounts[deviceID] = current
        return ChargeReservation(
            deviceID: deviceID, programmeID: programmeID, minutes: minutes,
            idempotencyKey: idempotencyKey, token: Self.token(deviceID, programmeID, idempotencyKey))
    }

    func minutes(for deviceID: String) -> Int { accounts[deviceID]?.minutes ?? 0 }

    func programme(for deviceID: String) -> String? { accounts[deviceID]?.programmeID }

    func programmeID(from header: String) throws -> String {
        let token = header.replacingOccurrences(of: "Programme ", with: "")
        guard header.hasPrefix("Programme "), !token.isEmpty else { throw ChargeLedgerError.invalid("header") }
        guard let id = Self.deviceID(from: token) else { throw ChargeLedgerError.invalid("token") }
        return id
    }

    func release(deviceID: String, idempotencyKey: String, minutes: Int) throws {
        guard var current = accounts[deviceID], current.keys.contains(idempotencyKey) else {
            throw ChargeLedgerError.missing
        }
        guard minutes >= 1, minutes <= current.minutes else { throw ChargeLedgerError.invalid("release") }
        current.minutes -= minutes
        current.keys.remove(idempotencyKey)
        accounts[deviceID] = current.minutes == 0 ? nil : current
    }

    /// Move minutes onto another device on the same programme. Repeating the
    /// same transfer must not drain the source a second time.
    func transfer(from deviceID: String, to destinationID: String, minutes: Int) throws -> ChargeReservation {
        guard let source = accounts[deviceID] else { throw ChargeLedgerError.missing }
        guard destinationID != deviceID else { throw ChargeLedgerError.invalid("same device") }
        guard minutes >= 1, minutes <= source.minutes else { throw ChargeLedgerError.invalid("transfer") }
        let key = "transfer:\(deviceID):\(destinationID):\(minutes)"
        let moved = try record(deviceID: destinationID, programmeID: source.programmeID, minutes: minutes, idempotencyKey: key)
        var updated = source
        updated.minutes -= minutes
        accounts[deviceID] = updated.minutes == 0 ? nil : updated
        return moved
    }

    private struct Account {
        var programmeID: String
        var minutes: Int = 0
        var keys: Set<String> = []
    }

    private static func text(_ value: String, _ name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChargeLedgerError.invalid(name) }
        return trimmed
    }

    private static func token(_ deviceID: String, _ programmeID: String, _ key: String) -> String {
        "\(deviceID)|\(programmeID)|\(key)".hashValue.description
    }

    static func deviceID(from token: String) -> String? {
        let standard = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        let padded = remainder == 0 ? standard : standard + String(repeating: "=", count: 4 - remainder)
        guard let data = Data(base64Encoded: padded), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        return text
    }
}
