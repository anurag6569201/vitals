import AppKit
import SwiftUI

/// How a reading is doing. The only thing allowed to use warm colors on the pin.
enum PinAlert: Equatable {
    case warn, critical
}

/// One theme's colors. Rules (from data-viz practice and Apple's HIG):
/// - Numbers wear the ink color; labels the secondary ink. Never a decorative color.
/// - One calm accent draws every gauge, so a warm color *means* something.
/// - Warn / critical are reserved for readings that need attention.
/// - A frosted, mostly opaque surface keeps text legible over any wallpaper or white page.
/// Every palette below measures ≥ 4.5:1 (WCAG AA) for ink, secondary, accent, warn and critical,
/// even with no blur, at its default opacity over both pure white and pure black.
struct PinPalette {
    var surface: Color
    var ink: Color
    var secondary: Color
    var accent: Color
    var warn: Color
    var critical: Color
    var scheme: ColorScheme
    /// Blur behind the surface. Off for themes that are meant to be solid.
    var frosted = true

    var track: Color { ink.opacity(0.14) }
    var hairline: Color { scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08) }

    func color(for alert: PinAlert?) -> Color? {
        switch alert {
        case .warn: warn
        case .critical: critical
        case nil: nil
        }
    }

    /// The value's color: ink unless the reading needs attention.
    func value(_ alert: PinAlert?) -> Color { color(for: alert) ?? ink }

    private static func hex(_ value: String) -> Color { Color(nsColor: NSColor(hex: value) ?? .gray) }

    static let graphite = PinPalette(surface: hex("#1C1C1E"), ink: hex("#F5F5F7"), secondary: hex("#B4B4B9"),
                                     accent: hex("#64D2FF"), warn: hex("#FFB340"), critical: hex("#FF8A82"), scheme: .dark)
    static let frost = PinPalette(surface: hex("#F5F5F7"), ink: hex("#1D1D1F"), secondary: hex("#55555A"),
                                  accent: hex("#0060C0"), warn: hex("#9C4400"), critical: hex("#B3261E"), scheme: .light)
    static let midnight = PinPalette(surface: hex("#000000"), ink: hex("#FFFFFF"), secondary: hex("#A0A0A6"),
                                     accent: hex("#30D158"), warn: hex("#FFB340"), critical: hex("#FF7A70"), scheme: .dark, frosted: false)
    static let nord = PinPalette(surface: hex("#2E3440"), ink: hex("#ECEFF4"), secondary: hex("#B4BDCB"),
                                 accent: hex("#88C0D0"), warn: hex("#EBCB8B"), critical: hex("#F0A0A8"), scheme: .dark)
    static let dracula = PinPalette(surface: hex("#282A36"), ink: hex("#F8F8F2"), secondary: hex("#B9BEDA"),
                                    accent: hex("#BD93F9"), warn: hex("#FFB86C"), critical: hex("#FF8080"), scheme: .dark)
    static let mocha = PinPalette(surface: hex("#1E1E2E"), ink: hex("#CDD6F4"), secondary: hex("#A6ADC8"),
                                  accent: hex("#89B4FA"), warn: hex("#F9E2AF"), critical: hex("#F38BA8"), scheme: .dark)
    static let solarized = PinPalette(surface: hex("#FDF6E3"), ink: hex("#073642"), secondary: hex("#46585F"),
                                      accent: hex("#1A64A3"), warn: hex("#8A5500"), critical: hex("#B52B27"), scheme: .light, frosted: false)

    static func make(for pin: PinSettings, system: ColorScheme) -> PinPalette {
        switch pin.theme {
        case .auto: system == .dark ? graphite : frost
        case .graphite: graphite
        case .frost: frost
        case .midnight: midnight
        case .nord: nord
        case .dracula: dracula
        case .mocha: mocha
        case .solarized: solarized
        case .custom: custom(NSColor(hex: pin.colorHex) ?? .systemIndigo)
        }
    }

    /// A tinted theme from any color, with contrast enforced: the surface is a deep (or pale)
    /// version of the color, so white (or near-black) text always reads at ≥ 7:1.
    static func custom(_ color: NSColor) -> PinPalette {
        let base = color.usingColorSpace(.sRGB) ?? .systemIndigo
        let isLight = luminance(base) > 0.55
        if isLight {
            let surface = mix(base, .white, keep: 0.25)
            return PinPalette(surface: Color(nsColor: surface), ink: hex("#141416"), secondary: hex("#4A4A50"),
                              accent: Color(nsColor: mix(base, .black, keep: 0.45)), warn: hex("#9C4400"),
                              critical: hex("#B3261E"), scheme: .light)
        }
        // Darken until white text clears 7:1 (keeps the hue, loses the neon).
        var surface = base
        var keep: CGFloat = 0.7
        while contrast(.white, surface) < 7, keep > 0.1 {
            surface = mix(base, .black, keep: keep)
            keep -= 0.05
        }
        return PinPalette(surface: Color(nsColor: surface), ink: hex("#FFFFFF"), secondary: Color.white.opacity(0.72),
                          accent: Color(nsColor: mix(base, .white, keep: 0.45)), warn: hex("#FFC060"),
                          critical: hex("#FF9A92"), scheme: .dark)
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        guard let c = c.usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `keep` of `a`, the rest of `b`.
    static func mix(_ a: NSColor, _ b: NSColor, keep: CGFloat) -> NSColor {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return a }
        return NSColor(srgbRed: a.redComponent * keep + b.redComponent * (1 - keep),
                       green: a.greenComponent * keep + b.greenComponent * (1 - keep),
                       blue: a.blueComponent * keep + b.blueComponent * (1 - keep), alpha: 1)
    }
}

private struct PinPaletteKey: EnvironmentKey {
    static let defaultValue = PinPalette.graphite
}

extension EnvironmentValues {
    var pinPalette: PinPalette {
        get { self[PinPaletteKey.self] }
        set { self[PinPaletteKey.self] = newValue }
    }
}
