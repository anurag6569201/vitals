import AppKit
import Foundation

/// What the on-screen pin can show.
enum PinItem: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, battery, disk, network, worldClock
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .disk: "Disk free"
        case .network: "Network"
        case .worldClock: "World clock"
        }
    }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .disk: "Free"
        case .network: "Network"
        case .worldClock: "Clock"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .battery: "battery.75percent"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .worldClock: "globe"
        }
    }

    /// Default accent for colorful icons.
    var tintHex: String {
        switch self {
        case .cpu: "#0A84FF"
        case .gpu: "#FF375F"
        case .memory: "#BF5AF2"
        case .battery: "#30D158"
        case .disk: "#00C7BE"
        case .network: "#5E5CE6"
        case .worldClock: "#64D2FF"
        }
    }
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
