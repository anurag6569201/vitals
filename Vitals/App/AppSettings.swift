import AppKit
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
    case pulse, heart, gauge, dot, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pulse: "Pulse"
        case .heart: "Heart"
        case .gauge: "Gauge"
        case .dot: "Dot"
        case .none: "None"
        }
    }
    /// Symbol drawn in the menu bar. "None" falls back to Pulse whenever an icon must show.
    var symbol: String {
        switch self {
        case .pulse, .none: "waveform.path.ecg"
        case .heart: "heart.fill"
        case .gauge: "gauge.with.dots.needle.33percent"
        case .dot: "circle.fill"
        }
    }
    /// Symbol for the picker in Settings.
    var pickerSymbol: String { self == .none ? "eye.slash" : symbol }
    var isPro: Bool { self == .heart || self == .gauge }
}

enum PopoverSection: String, Codable, CaseIterable, Identifiable {
    case menuBarItems, batteryPlanner, vitals, freeUpSpace, network, topApps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menuBarItems: "Menu bar shortcuts"
        case .batteryPlanner: "Battery forecast"
        case .vitals: "Live readings grid"
        case .freeUpSpace: "Free up space"
        case .network: "Where your data went"
        case .topApps: "Apps using your Mac"
        }
    }
    /// Sections this edition can show. The App Store build can't hide icons or see per-app usage.
    static var available: [PopoverSection] {
        Edition.isAppStore ? allCases.filter { $0 != .menuBarItems && $0 != .topApps } : allCases
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
    case cpu, gpu, memory, download, upload, disk, topApp, display, ping, wifi, worldClock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .download: "Download speed"
        case .upload: "Upload speed"
        case .disk: "Disk free"
        case .topApp: "Busiest app"
        case .display: "Refresh rate (Hz)"
        case .ping: "Ping"
        case .wifi: "Wi‑Fi signal"
        case .worldClock: "Second time zone"
        }
    }
    var example: String {
        switch self {
        case .cpu: "23%"
        case .gpu: "41%"
        case .memory: "64%"
        case .download: "2.4 MB/s"
        case .upload: "320 KB/s"
        case .disk: "84 GB"
        case .topApp: "45%"
        case .display: "120 Hz"
        case .ping: "24 ms"
        case .wifi: "−58 dBm"
        case .worldClock: "NYC 9:41"
        }
    }

    /// Readings this edition can show. The sandboxed App Store build can't see other apps' usage.
    static var available: [ReadingKind] {
        Edition.isAppStore ? allCases.filter { $0 != .topApp } : allCases
    }

    /// SF Symbol shown in the menu bar instead of a text label.
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .download: "arrow.down"
        case .upload: "arrow.up"
        case .disk: "internaldrive"
        case .topApp: "app.fill"
        case .display: "display"
        case .ping: "stopwatch"
        case .wifi: "wifi"
        case .worldClock: "globe"
        }
    }
}

enum WorldClock {
    static let zones: [(id: String, label: String)] = [
        ("America/Los_Angeles", "SF"), ("America/Denver", "DEN"), ("America/Chicago", "CHI"),
        ("America/New_York", "NYC"), ("America/Sao_Paulo", "SAO"), ("Europe/London", "LON"),
        ("Europe/Paris", "PAR"), ("Europe/Berlin", "BER"), ("Africa/Lagos", "LOS"), ("Europe/Moscow", "MOW"),
        ("Asia/Dubai", "DXB"), ("Asia/Kolkata", "IND"), ("Asia/Singapore", "SIN"), ("Asia/Shanghai", "SHA"),
        ("Asia/Tokyo", "TYO"), ("Australia/Sydney", "SYD"), ("Pacific/Auckland", "AKL"), ("UTC", "UTC"),
    ]

    static func label(for id: String) -> String {
        zones.first { $0.id == id }?.label
            ?? String(id.split(separator: "/").last ?? "").replacingOccurrences(of: "_", with: " ").prefix(8).uppercased()
    }

    static func time(in id: String, at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: id)
        formatter.dateFormat = "H:mm"
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
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
    var worldClockZone = "America/New_York"
    /// Menu-bar colors as hex ("#RRGGBB"). nil = follow the menu bar (light/dark automatically).
    var iconColorHex: String?
    var readingTextColorHex: String?
    var readingIconColorHex: String?
    /// Per-reading icon colors, keyed by ReadingKind raw value. Overrides readingIconColorHex.
    var readingColors: [String: String] = [:]
    /// Turn a reading orange when it's high (e.g. CPU over 75%).
    var colorReadingsWhenHigh = true
    /// The floating on-screen pin.
    var pin = PinSettings()
    /// Count data on hotspots / metered connections and warn near the limit.
    var hotspotGuard = true
    var hotspotLimitMB = 2048

    init() {}

    // Tolerant decoding: new fields never wipe old preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        detection = (try? c.decodeIfPresent(DetectionSettings.self, forKey: .detection)) ?? d.detection
        menuBarStyle = (try? c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)) ?? d.menuBarStyle
        // Unknown kinds (removed in newer versions) are dropped instead of resetting the list.
        readings = (try? c.decodeIfPresent([String].self, forKey: .readings))
            .map { $0.compactMap(ReadingKind.init(rawValue:)) } ?? d.readings
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
        awayReportsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .awayReportsEnabled)) ?? d.awayReportsEnabled
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
        iconStyle = (try? c.decodeIfPresent(IconStyle.self, forKey: .iconStyle)) ?? d.iconStyle
        hiddenSections = (try? c.decodeIfPresent([String].self, forKey: .hiddenSections))
            .map { Set($0.compactMap(PopoverSection.init(rawValue:))) } ?? d.hiddenSections
        hotkey = (try? c.decodeIfPresent(HotkeyChoice.self, forKey: .hotkey)) ?? d.hotkey
        keepAwakeAllowsDisplaySleep = (try? c.decodeIfPresent(Bool.self, forKey: .keepAwakeAllowsDisplaySleep)) ?? d.keepAwakeAllowsDisplaySleep
        worldClockZone = (try? c.decodeIfPresent(String.self, forKey: .worldClockZone)) ?? d.worldClockZone
        iconColorHex = (try? c.decodeIfPresent(String.self, forKey: .iconColorHex)) ?? nil
        readingTextColorHex = (try? c.decodeIfPresent(String.self, forKey: .readingTextColorHex)) ?? nil
        readingIconColorHex = (try? c.decodeIfPresent(String.self, forKey: .readingIconColorHex)) ?? nil
        readingColors = (try? c.decodeIfPresent([String: String].self, forKey: .readingColors)) ?? d.readingColors
        colorReadingsWhenHigh = (try? c.decodeIfPresent(Bool.self, forKey: .colorReadingsWhenHigh)) ?? d.colorReadingsWhenHigh
        pin = (try? c.decodeIfPresent(PinSettings.self, forKey: .pin)) ?? d.pin
        hotspotGuard = (try? c.decodeIfPresent(Bool.self, forKey: .hotspotGuard)) ?? d.hotspotGuard
        hotspotLimitMB = (try? c.decodeIfPresent(Int.self, forKey: .hotspotLimitMB)) ?? d.hotspotLimitMB
    }

    private enum CodingKeys: String, CodingKey {
        case detection, menuBarStyle, readings, notificationsEnabled, awayReportsEnabled, hasCompletedOnboarding
        case iconStyle, hiddenSections, hotkey, keepAwakeAllowsDisplaySleep, worldClockZone
        case iconColorHex, readingTextColorHex, readingIconColorHex, readingColors, colorReadingsWhenHigh, pin, hotspotGuard, hotspotLimitMB
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

// MARK: - Edition

/// Which build this is. The App Store build is sandboxed: no quitting other apps and no
/// menu-bar icon hiding (see RELEASE.md › Two editions).
enum Edition {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
    static var canQuitApps: Bool { !isAppStore }
    static var canHideMenuBarIcons: Bool { !isAppStore }
}

// MARK: - Colors

extension NSColor {
    /// "#RRGGBB" → color (sRGB). Returns nil for anything else.
    convenience init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

/// Ready-made swatches for the menu bar.
enum MenuBarPalette {
    static let swatches: [(name: String, hex: String)] = [
        ("Green", "#34C759"), ("Mint", "#00C7BE"), ("Blue", "#0A84FF"), ("Indigo", "#5E5CE6"),
        ("Purple", "#BF5AF2"), ("Pink", "#FF375F"), ("Red", "#FF453A"), ("Orange", "#FF9F0A"),
        ("Yellow", "#FFD60A"), ("Gray", "#8E8E93"),
    ]
}
