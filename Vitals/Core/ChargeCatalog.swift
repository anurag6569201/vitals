import Foundation

struct ChargeProgramme: Equatable {
    let programmeID: String
    let title: String
    let minuteCap: Int
    var active: Bool = true
}

enum ChargeCatalogError: Error { case invalid, exists, closed }

/// Programme ids are exact. A shorter id is not a prefix of another programme.
final class ChargeCatalog {
    private var programmes: [String: ChargeProgramme] = [:]

    func add(_ programme: ChargeProgramme) throws {
        guard !programme.programmeID.isEmpty, programme.minuteCap >= 1, !programme.title.isEmpty else {
            throw ChargeCatalogError.invalid
        }
        guard programmes[programme.programmeID] == nil else { throw ChargeCatalogError.exists }
        programmes[programme.programmeID] = programme
    }

    func get(_ programmeID: String) throws -> ChargeProgramme {
        guard let found = programmes[programmeID], found.active else { throw ChargeCatalogError.closed }
        return found
    }

    func capacity(for programmeID: String) throws -> Int {
        let matches = programmes.compactMap { key, programme -> Int? in
            guard key.hasPrefix(programmeID), programme.active else { return nil }
            return programme.minuteCap
        }
        guard let cap = matches.max() else { throw ChargeCatalogError.closed }
        return cap
    }

    func retire(_ programmeID: String) throws {
        guard var programme = programmes[programmeID] else { throw ChargeCatalogError.invalid }
        programme.active = false
        programmes[programmeID] = programme
    }

    func openIDs() -> [String] {
        programmes.filter { $0.value.active }.map(\.key).sorted()
    }
}
