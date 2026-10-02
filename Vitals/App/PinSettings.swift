import AppKit
import Foundation

/// What the on-screen pin can show.
enum PinItem: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, swap, battery, power, batteryHealth, disk, diskIO,
         network, dataToday, wifi, ping, display, uptime, worldClock
    var id: String { rawValue }

    /// Groups for the Settings picker, so a long list stays easy to scan.
    enum Group: String, CaseIterable {
        case performance = "Performance", power = "Battery & power", storage = "Storage",
             network = "Network", display = "Display & time"
    }

    var group: Group {
        switch self {
        case .cpu, .gpu, .memory, .swap: .performance
        case .battery, .power, .batteryHealth: .power
        case .disk, .diskIO: .storage
        case .network, .dataToday, .wifi, .ping: .network
        case .display, .uptime, .worldClock: .display
        }
    }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .swap: "Swap used"
        case .battery: "Battery"
        case .power: "Power draw"
        case .batteryHealth: "Battery health"
        case .disk: "Disk free"
        case .diskIO: "Disk activity"
        case .network: "Network speed"
        case .dataToday: "Data today"
        case .wifi: "Wi‑Fi signal"
        case .ping: "Ping"
        case .display: "Refresh rate"
        case .uptime: "Uptime"
        case .worldClock: "World clock"
        }
    }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .swap: "Swap"
        case .battery: "Battery"
        case .power: "Power"
        case .batteryHealth: "Health"
        case .disk: "Free"
        case .diskIO: "Disk"
        case .network: "Network"
        case .dataToday: "Today"
        case .wifi: "Wi‑Fi"
        case .ping: "Ping"
        case .display: "Display"
        case .uptime: "Uptime"
        case .worldClock: "Clock"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .swap: "arrow.left.arrow.right.square"
        case .battery: "battery.75percent"
        case .power: "bolt"
        case .batteryHealth: "heart.text.square"
        case .disk: "internaldrive"
        case .diskIO: "externaldrive.badge.timemachine"
        case .network: "arrow.up.arrow.down"
        case .dataToday: "chart.bar.xaxis"
        case .wifi: "wifi"
        case .ping: "stopwatch"
        case .display: "display"
        case .uptime: "clock.arrow.circlepath"
        case .worldClock: "globe"
        }
    }

    /// Default accent when "color-code each reading" is on.
    var tintHex: String {
        switch self {
        case .cpu: "#0A84FF"
        case .gpu: "#FF375F"
        case .memory, .swap: "#BF5AF2"
        case .battery, .power, .batteryHealth: "#30D158"
        case .disk, .diskIO: "#00C7BE"
        case .network, .dataToday: "#5E5CE6"
        case .wifi, .ping: "#64D2FF"
        case .display: "#FF9F0A"
        case .uptime, .worldClock: "#8E8E93"
        }
    }

    /// The only reading that sends anything over the network (a connection-time check).
    var needsNetwork: Bool { self == .ping }
}

/// The pin's overall form. Researched patterns: floating cards (widgets), flush edge docks
/// (SlimHUD / edge-dock HUDs), Dynamic-Island-style pills, gaming OSD text, Stats-style meters.
enum PinShape: String, Codable, CaseIterable, Identifiable {
    case dock, pill, card, rings, bars, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: "Edge Dock"
        case .pill: "Pill"
        case .card: "Card"
        case .rings: "Rings"
        case .bars: "Meters"
        case .text: "Text Only"
        }
    }
    var subtitle: String {
        switch self {
        case .dock: "Flush to the screen edge, no gap. Can tuck away until you hover."
        case .pill: "One slim capsule, values only. The smallest box."
        case .card: "Readings with labels and gauges. The roomiest."
        case .rings: "Just gauge rings with the number inside."
        case .bars: "Tiny meter bars, like a dashboard."
        case .text: "No background at all — text with a soft shadow, like a game overlay."
        }
    }
    /// Gap between the pin and the screen edge.
    var margin: CGFloat {
        switch self {
        case .dock: 0
        case .text: 6
        default: 8
        }
    }
}

/// One-click starting points, so nobody has to tune ten settings.
enum PinPreset: String, CaseIterable, Identifiable {
    case minimal, gamer, laptop, network, creator, dashboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .gamer: "Gamer"
        case .laptop: "On the go"
        case .network: "Network"
        case .creator: "Creator"
        case .dashboard: "Dashboard"
        }
    }
    var subtitle: String {
        switch self {
        case .minimal: "CPU in a slim edge dock"
        case .gamer: "Refresh rate, ping, CPU, GPU — overlay text"
        case .laptop: "Battery, power draw, time left"
        case .network: "Speed, data today, Wi‑Fi, ping"
        case .creator: "Memory, swap, disk activity, GPU"
        case .dashboard: "Everything important, as meters"
        }
    }
    var symbol: String {
        switch self {
        case .minimal: "minus.rectangle"
        case .gamer: "gamecontroller"
        case .laptop: "laptopcomputer"
        case .network: "network"
        case .creator: "paintbrush.pointed"
        case .dashboard: "gauge.with.dots.needle.67percent"
        }
    }
    var isPro: Bool { self != .minimal }

    func apply(to pin: inout PinSettings) {
        switch self {
        case .minimal:
            pin.items = [.cpu]; pin.shape = .dock; pin.theme = .auto; pin.autoHide = false
        case .gamer:
            pin.items = [.display, .ping, .cpu, .gpu]; pin.shape = .text; pin.layout = .column
            pin.position.h = .start; pin.position.v = .start
        case .laptop:
            pin.items = [.battery, .power, .batteryHealth]; pin.shape = .pill; pin.theme = .auto; pin.layout = .auto
        case .network:
            pin.items = [.network, .dataToday, .wifi, .ping]; pin.shape = .dock; pin.theme = .nord
        case .creator:
            pin.items = [.memory, .swap, .diskIO, .gpu]; pin.shape = .card; pin.theme = .graphite; pin.showGauges = true
        case .dashboard:
            pin.items = [.cpu, .gpu, .memory, .battery, .disk, .network]; pin.shape = .bars; pin.theme = .graphite
            pin.layout = .column
        }
    }
}

enum PinLayout: String, Codable, CaseIterable, Identifiable {
    case auto, row, column
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .row: "Row"
        case .column: "Column"
        }
    }
}

enum PinTheme: String, Codable, CaseIterable, Identifiable {
    case auto, graphite, frost, midnight, nord, dracula, mocha, solarized, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .graphite: "Graphite"
        case .frost: "Frost"
        case .midnight: "Midnight"
        case .nord: "Nord"
        case .dracula: "Dracula"
        case .mocha: "Mocha"
        case .solarized: "Solarized"
        case .custom: "Your Color"
        }
    }
    var subtitle: String {
        switch self {
        case .auto: "Graphite in dark mode, Frost in light mode"
        case .graphite: "Frosted dark gray — the calmest"
        case .frost: "Frosted light, for bright desktops"
        case .midnight: "Solid black, highest contrast"
        case .nord: "Cool arctic blue-gray"
        case .dracula: "Dark violet, from the coding theme"
        case .mocha: "Soft pastel dark (Catppuccin)"
        case .solarized: "Warm paper, easy on the eyes"
        case .custom: "Any color, kept readable automatically"
        }
    }

    /// Older versions stored glass / dark / light / color.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "glass": self = .auto
        case "dark": self = .graphite
        case "light": self = .frost
        case "color": self = .custom
        default: self = PinTheme(rawValue: raw) ?? .auto
        }
    }
}

enum PinSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.25
        }
    }
}

enum PinLevel: String, Codable, CaseIterable, Identifiable {
    case floating, desktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .floating: "Above other windows"
        case .desktop: "On the desktop, behind windows"
        }
    }
}

/// Where along one axis the pin sits. `free` uses the stored fraction.
enum PinAlign: String, Codable {
    case start, center, end, free
}

struct PinPosition: Codable, Equatable {
    /// Horizontal: start = left edge, end = right edge.
    var h: PinAlign = .end
    /// Vertical: start = top edge, end = bottom edge.
    var v: PinAlign = .center
    /// 0...1 across the free space, used when an axis is `free`. fy counts from the top.
    var fx: Double = 0.5
    var fy: Double = 0.5
    /// CGDirectDisplayID of the screen it lives on. nil = main screen.
    var screenID: UInt32?

    static let presets: [(name: String, h: PinAlign, v: PinAlign)] = [
        ("Top Left", .start, .start), ("Top Center", .center, .start), ("Top Right", .end, .start),
        ("Middle Left", .start, .center), ("Center", .center, .center), ("Middle Right", .end, .center),
        ("Bottom Left", .start, .end), ("Bottom Center", .center, .end), ("Bottom Right", .end, .end),
    ]

    /// Docked to the left or right edge, away from the corners: reads best as a column.
    var prefersColumn: Bool {
        (h == .start || h == .end) && (v == .center || v == .free)
    }
}

struct PinSettings: Codable, Equatable {
    var enabled = false
    var items: [PinItem] = [.cpu, .memory, .battery]
    var layout: PinLayout = .auto
    var theme: PinTheme = .auto
    var colorHex = "#5E5CE6"
    /// Background opacity, 0.7...1 — below that, numbers stop being readable over busy content.
    var opacity = 0.92
    var size: PinSize = .medium
    var showLabels = true
    var showGauges = true
    /// One color per reading. Off by default: a single calm accent keeps warnings meaningful.
    var colorfulIcons = false
    var position = PinPosition()
    var snapToEdges = true
    /// Clicks pass straight through; change it from the popover or Settings.
    var locked = false
    var allSpaces = true
    var level: PinLevel = .floating
    var shape: PinShape = .dock
    /// Edge Dock only: shrink to a slim tab on the edge until the pointer comes near.
    var autoHide = false

    /// What a free user gets: one reading in the Edge Dock with the Auto theme —
    /// enough to feel how good it is. Pro unlocks every reading, shape and theme.
    func freeTier() -> PinSettings {
        var p = self
        p.items = Array(items.prefix(1))
        if p.items.isEmpty { p.items = [.cpu] }
        p.shape = .dock
        p.theme = .auto
        p.colorfulIcons = false
        return p
    }

    var isColumn: Bool {
        switch layout {
        case .auto:
            // A dock on the left or right edge always runs down the edge, corners included.
            shape == .dock ? (dockEdge == .leading || dockEdge == .trailing) : position.prefersColumn
        case .row: false
        case .column: true
        }
    }

    enum Edge { case leading, trailing, top, bottom, none }

    /// Which screen edge an Edge Dock is attached to (sides win over top/bottom).
    var dockEdge: Edge {
        guard shape == .dock else { return .none }
        switch position.h {
        case .start: return .leading
        case .end: return .trailing
        default: break
        }
        switch position.v {
        case .start: return .top
        case .end: return .bottom
        default: return .none
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PinSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        enabled = value(.enabled, d.enabled)
        // Unknown items (from older versions) are dropped instead of resetting the whole list.
        items = (try? c.decodeIfPresent([String].self, forKey: .items))
            .map { $0.compactMap(PinItem.init(rawValue:)) } ?? d.items
        layout = value(.layout, d.layout)
        theme = value(.theme, d.theme)
        colorHex = value(.colorHex, d.colorHex)
        opacity = min(max(value(.opacity, d.opacity), 0.7), 1)
        size = value(.size, d.size)
        showLabels = value(.showLabels, d.showLabels)
        showGauges = value(.showGauges, d.showGauges)
        colorfulIcons = value(.colorfulIcons, d.colorfulIcons)
        position = value(.position, d.position)
        snapToEdges = value(.snapToEdges, d.snapToEdges)
        locked = value(.locked, d.locked)
        allSpaces = value(.allSpaces, d.allSpaces)
        level = value(.level, d.level)
        shape = value(.shape, d.shape)
        autoHide = value(.autoHide, d.autoHide)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, items, layout, theme, colorHex, opacity, size, showLabels, showGauges, colorfulIcons
        case position, snapToEdges, locked, allSpaces, level, shape, autoHide
    }
}
