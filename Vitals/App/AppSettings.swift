import Combine
import Foundation

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case iconOnly, smart, smartReadings, readings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .smart: "Icon + reason when something's wrong"
        case .smartReadings: "Readings only when they're high"
        case .readings: "Live readings, always"
        }
    }
    var isPro: Bool { self == .smartReadings || self == .readings }
    var showsReadings: Bool { self == .smartReadings || self == .readings }
}

enum IconStyle: String, Codable, CaseIterable, Identifiable {
    case pulse, heart, gauge, dot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pulse: "Pulse"
        case .heart: "Heart"
        case .gauge: "Gauge"
        case .dot: "Dot"
        }
    }
    var symbol: String {
        switch self {
        case .pulse: "waveform.path.ecg"
        case .heart: "heart.fill"
        case .gauge: "gauge.with.dots.needle.33percent"
        case .dot: "circle.fill"
        }
    }
    var isPro: Bool { self == .heart || self == .gauge }
}

enum PopoverSection: String, Codable, CaseIterable, Identifiable {
    case batteryPlanner, vitals, freeUpSpace, topApps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .batteryPlanner: "Battery forecast"
        case .vitals: "Live readings grid"
        case .freeUpSpace: "Free up space"
        case .topApps: "Apps using your Mac"
        }
    }
}

enum HotkeyChoice: String, Codable, CaseIterable, Identifiable {
    case none, optionCommandV, controlOptionV, controlOptionSpace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .optionCommandV: "⌥⌘V"
        case .controlOptionV: "⌃⌥V"
        case .controlOptionSpace: "⌃⌥Space"
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
    var iconStyle: IconStyle = .pulse
    var hiddenSections: Set<PopoverSection> = []
    var hotkey: HotkeyChoice = .none
    var keepAwakeAllowsDisplaySleep = false

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
        iconStyle = (try? c.decodeIfPresent(IconStyle.self, forKey: .iconStyle)) ?? d.iconStyle
        hiddenSections = (try? c.decodeIfPresent(Set<PopoverSection>.self, forKey: .hiddenSections)) ?? d.hiddenSections
        hotkey = (try? c.decodeIfPresent(HotkeyChoice.self, forKey: .hotkey)) ?? d.hotkey
        keepAwakeAllowsDisplaySleep = (try? c.decodeIfPresent(Bool.self, forKey: .keepAwakeAllowsDisplaySleep)) ?? d.keepAwakeAllowsDisplaySleep
    }

    private enum CodingKeys: String, CodingKey {
        case detection, menuBarStyle, readings, notificationsEnabled, awayReportsEnabled, hasCompletedOnboarding
        case iconStyle, hiddenSections, hotkey, keepAwakeAllowsDisplaySleep
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
