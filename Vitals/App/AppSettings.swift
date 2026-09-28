import Combine
import Foundation

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case iconOnly, smart, readings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .smart: "Icon + reason when something's wrong"
        case .readings: "Live readings"
        }
    }
}

enum ReadingKind: String, Codable, CaseIterable, Identifiable {
    case cpu, memory, battery, network, disk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .network: "Network"
        case .disk: "Disk free"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var detection = DetectionSettings()
    var menuBarStyle: MenuBarStyle = .smart
    var readings: [ReadingKind] = [.cpu, .memory]
    var notificationsEnabled = true
    var awayReportsEnabled = true
    var hasCompletedOnboarding = false

    init() {}

    // Tolerant decoding: new fields never wipe old preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        detection = (try? c.decodeIfPresent(DetectionSettings.self, forKey: .detection)) ?? d.detection
        menuBarStyle = (try? c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)) ?? d.menuBarStyle
        readings = (try? c.decodeIfPresent([ReadingKind].self, forKey: .readings)) ?? d.readings
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
        awayReportsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .awayReportsEnabled)) ?? d.awayReportsEnabled
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
    }

    private enum CodingKeys: String, CodingKey {
        case detection, menuBarStyle, readings, notificationsEnabled, awayReportsEnabled, hasCompletedOnboarding
    }

    private static let key = "vitals.settings.v2"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

enum AwayReportStore {
    private static let key = "vitals.awayReports.v1"

    static func load() -> [AwayReport] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let reports = try? JSONDecoder().decode([AwayReport].self, from: data) else { return [] }
        return reports
    }

    static func save(_ reports: [AwayReport]) {
        if let data = try? JSONEncoder().encode(Array(reports.prefix(20))) { UserDefaults.standard.set(data, forKey: key) }
    }
}
