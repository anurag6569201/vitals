import AppKit
import Combine
import SwiftUI

// MARK: - The widget

/// Hover state for the floating panel, fed by an always-on tracking area (SwiftUI's own hover
/// tracking doesn't fire reliably in a non-activating panel).
@MainActor
final class PinHover: ObservableObject {
    @Published var inside = false
}

/// The on-screen pin, in one of six shapes. Used by the floating panel and, unchanged,
/// as the live preview in Settings.
struct PinnedVitalsView: View {
        @Environment(\.pinPalette) private var palette
    @ObservedObject var model: VitalsModel
    let pin: PinSettings
    var interactive = true
    var hover: PinHover? = nil
    var onClose: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    /// The panel's drag/right-click surface; sits above the content, below the hover buttons.
    var dragSurface: AnyView? = nil
    /// Settings preview: force the tucked-away look of an auto-hiding dock.
    var previewCollapsed = false

    var body: some View {
        if let hover {
            PinBody(model: model, pin: pin, interactive: interactive, hover: hover, onClose: onClose,
                 onSettings: onSettings, dragSurface: dragSurface, previewCollapsed: previewCollapsed)
        } else {
            PinBody(model: model, pin: pin, interactive: interactive, hover: PinHover(), onClose: onClose,
                 onSettings: onSettings, dragSurface: dragSurface, previewCollapsed: previewCollapsed)
        }
    }

    private struct PinBody: View {
        @Environment(\.colorScheme) private var system
        /// Resolved here too: this view *provides* the palette, so it can't read it from its own environment.
        private var palette: PinPalette { pin.shape == .text ? .midnight : .make(for: pin, system: system) }
        @ObservedObject var model: VitalsModel
        let pin: PinSettings
        let interactive: Bool
        @ObservedObject var hover: PinHover
        let onClose: (() -> Void)?
        let onSettings: (() -> Void)?
        let dragSurface: AnyView?
        let previewCollapsed: Bool

        private var s: CGFloat { pin.size.scale }
        private var items: [PinItem] { pin.items.filter(isAvailable) }
        private var collapsed: Bool {
            pin.shape == .dock && pin.autoHide && pin.dockEdge != .none && (previewCollapsed || (interactive && !hover.inside))
        }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // The window always keeps the expanded size. Tucking away is a drawer: the content
            // slides into the screen edge it's attached to and the slim tab fades up in its place,
            // so the motion always starts and ends at that edge — the window itself never moves.
            ZStack(alignment: tabAlignment) {
                shaped
                    .overlay { if !collapsed { dragSurface } }
                    .overlay(alignment: .topTrailing) {
                        if interactive && hover.inside && !pin.locked && pin.shape == .card { hoverControls }
                    }
                    .visualEffect { [collapsed, edge = pin.dockEdge, reduceMotion] content, proxy in
                        content.offset(Self.drawerOffset(collapsed: collapsed && !reduceMotion, edge: edge, size: proxy.size))
                    }
                    .opacity(collapsed ? 0 : 1)
                    .allowsHitTesting(!collapsed)

                if pin.shape == .dock && pin.autoHide && pin.dockEdge != .none {
                    DockTab(pin: pin, severity: model.severity)
                        // A slightly wider, nearly invisible pad makes the slim tab easy to find.
                        .padding(tabPadding, 6)
                        .background(Color.black.opacity(0.01))
                        .overlay { if collapsed { dragSurface } }
                        .opacity(collapsed ? 1 : 0)
                        .scaleEffect(collapsed ? 1 : 0.6, anchor: tabAnchor)
                        .allowsHitTesting(collapsed)
                }
            }
            .modifier(PaletteProvider(pin: pin))
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86), value: collapsed)
            .animation(Motion.spring, value: pin.items)
            .animation(Motion.spring, value: pin.isColumn)
            .animation(Motion.spring, value: pin.shape)
        }

        /// Where the content hides: fully past the screen edge it's docked to.
        nonisolated static func drawerOffset(collapsed: Bool, edge: PinSettings.Edge, size: CGSize) -> CGSize {
            guard collapsed else { return .zero }
            switch edge {
            case .leading: return CGSize(width: -size.width, height: 0)
            case .trailing: return CGSize(width: size.width, height: 0)
            case .top: return CGSize(width: 0, height: -size.height)
            case .bottom: return CGSize(width: 0, height: size.height)
            case .none: return .zero
            }
        }

        private var tabAlignment: Alignment {
            switch pin.dockEdge {
            case .leading: .leading
            case .trailing: .trailing
            case .top: .top
            case .bottom: .bottom
            case .none: .center
            }
        }

        private var tabAnchor: UnitPoint {
            switch pin.dockEdge {
            case .leading: .leading
            case .trailing: .trailing
            case .top: .top
            case .bottom: .bottom
            case .none: .center
            }
        }

        /// Pad only on the side facing into the screen.
        private var tabPadding: Edge.Set {
            switch pin.dockEdge {
            case .leading: .trailing
            case .trailing: .leading
            case .top: .bottom
            default: .top
            }
        }

        @ViewBuilder private var shaped: some View {
            switch pin.shape {
            case .card:
                stack(spacingRow: 12, spacingColumn: 10, dividers: true) { PinCell(item: $0, reading: reading($0), pin: pin) }
                    .padding(.horizontal, (pin.isColumn ? 12 : 13) * s)
                    .padding(.vertical, (pin.isColumn ? 12 : 9) * s)
                    .background(PinBackground(pin: pin, shape: AnyShape(RoundedRectangle(cornerRadius: (pin.isColumn ? 18 : 16) * s, style: .continuous))))
            case .dock:
                stack(spacingRow: 10, spacingColumn: 9, dividers: false) { PinCompactCell(item: $0, reading: reading($0), pin: pin, vertical: pin.isColumn) }
                    .padding(.horizontal, (pin.isColumn ? 7 : 10) * s)
                    .padding(.vertical, (pin.isColumn ? 10 : 6) * s)
                    .background(PinBackground(pin: pin, shape: AnyShape(DockShape(edge: pin.dockEdge, radius: 13 * s))))
            case .pill:
                stack(spacingRow: 10, spacingColumn: 7, dividers: false) { PinCompactCell(item: $0, reading: reading($0), pin: pin, vertical: false) }
                    .padding(.horizontal, 11 * s)
                    .padding(.vertical, 5.5 * s)
                    .background(PinBackground(pin: pin, shape: AnyShape(RoundedRectangle(cornerRadius: (pin.isColumn ? 14 : 30) * s, style: .continuous))))
            case .rings:
                stack(spacingRow: 7, spacingColumn: 7, dividers: false) { PinRingCell(item: $0, reading: reading($0), pin: pin) }
                    .padding(7 * s)
                    .background(PinBackground(pin: pin, shape: AnyShape(RoundedRectangle(cornerRadius: (pin.isColumn ? 24 : 26) * s, style: .continuous))))
            case .bars:
                stack(spacingRow: 12, spacingColumn: 7, dividers: false) { PinBarCell(item: $0, reading: reading($0), pin: pin) }
                    .padding(.horizontal, 10 * s)
                    .padding(.vertical, 8 * s)
                    .background(PinBackground(pin: pin, shape: AnyShape(RoundedRectangle(cornerRadius: 11 * s, style: .continuous))))
            case .text:
                stack(spacingRow: 12, spacingColumn: 2, dividers: false) { PinTextCell(item: $0, reading: reading($0), pin: pin) }
                    .padding(.horizontal, 6 * s)
                    .padding(.vertical, 4 * s)
                    // Almost invisible, so the pin can still be dragged (fully clear pixels pass clicks through).
                    .background(Color.black.opacity(0.012), in: RoundedRectangle(cornerRadius: 6))
            }
        }

        @ViewBuilder
        private func stack<Cell: View>(spacingRow: CGFloat, spacingColumn: CGFloat, dividers: Bool,
                                       @ViewBuilder cell: @escaping (PinItem) -> Cell) -> some View {
            if items.isEmpty {
                Label("Pick readings", systemImage: "pin")
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .padding(8)
                    .background(PinBackground(pin: pin, shape: AnyShape(Capsule())))
            } else if pin.isColumn {
                VStack(alignment: pin.shape == .dock || pin.shape == .rings ? .center : .leading, spacing: spacingColumn * s) {
                    ForEach(items) { cell($0) }
                }
            } else {
                HStack(spacing: spacingRow * s) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        if dividers && index > 0 {
                            Capsule().fill(palette.track).frame(width: 1, height: 22 * s)
                        }
                        cell(item)
                    }
                }
            }
        }

        private func reading(_ item: PinItem) -> PinReading { PinReading.make(item, model: model) }

        private func isAvailable(_ item: PinItem) -> Bool {
            switch item {
            case .battery: model.snapshot?.battery != nil
            case .gpu: model.snapshot?.gpuUsage != nil || model.snapshot == nil
            default: true
            }
        }

        private var hoverControls: some View {
            HStack(spacing: 4) {
                if let onSettings {
                    PinHoverButton(symbol: "slider.horizontal.3", help: "Customize", action: onSettings)
                }
                if let onClose {
                    PinHoverButton(symbol: "xmark", help: "Unpin", action: onClose)
                }
            }
            .padding(5)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

/// Rounded only on the side facing into the screen, square where it meets the edge.
struct DockShape: Shape {
    let edge: PinSettings.Edge
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = RectangleCornerRadii(
            topLeading: edge == .leading || edge == .top ? 0 : radius,
            bottomLeading: edge == .leading || edge == .bottom ? 0 : radius,
            bottomTrailing: edge == .trailing || edge == .bottom ? 0 : radius,
            topTrailing: edge == .trailing || edge == .top ? 0 : radius)
        return UnevenRoundedRectangle(cornerRadii: r, style: .continuous).path(in: rect)
    }
}

/// An auto-hiding dock tucked into the edge: a slim glowing tab in the health color.
private struct DockTab: View {
    let pin: PinSettings
    let severity: Severity

    var body: some View {
        let vertical = pin.dockEdge == .leading || pin.dockEdge == .trailing
        let s = pin.size.scale
        ZStack {
            DockShape(edge: pin.dockEdge, radius: 5 * s)
                .fill(.ultraThinMaterial)
            DockShape(edge: pin.dockEdge, radius: 5 * s)
                .fill(severity.color.opacity(severity == .calm ? 0.55 : 0.95).gradient)
                .padding(vertical ? .vertical : .horizontal, 4 * s)
                .padding(edgeInset, 1.5)
        }
        .frame(width: vertical ? 6 * s : 54 * s, height: vertical ? 54 * s : 6 * s)
        .shadow(color: severity.color.opacity(severity >= .warning ? 0.6 : 0), radius: 4)
        .help("Vitals — hover to show")
    }

    private var edgeInset: Edge.Set {
        switch pin.dockEdge {
        case .leading: .trailing
        case .trailing: .leading
        case .top: .bottom
        default: .top
        }
    }
}

/// Resolves the theme (Auto follows the system) and hands its palette and appearance down.
private struct PaletteProvider: ViewModifier {
    let pin: PinSettings
    @Environment(\.colorScheme) private var system
    func body(content: Content) -> some View {
        let palette = pin.shape == .text ? PinPalette.midnight : PinPalette.make(for: pin, system: system)
        content
            .environment(\.pinPalette, palette)
            .environment(\.colorScheme, palette.scheme)
    }
}

private struct PinHoverButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 17, height: 17)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(over ? 0.35 : 0.15), lineWidth: 0.5))
                .foregroundStyle(.primary.opacity(over ? 1 : 0.75))
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .help(help)
    }
}

// MARK: - One reading

struct PinReading {
    var value: String
    var detail: String?
    /// 0...1 for a gauge ring, nil for readings without one.
    var fraction: Double?
    /// Needs attention: the only time the pin uses warm colors.
    var alert: PinAlert?
    var symbol: String
    var pulse = false

    @MainActor
    static func make(_ item: PinItem, model: VitalsModel) -> PinReading {
        guard let snap = model.snapshot else { return PinReading(value: "—", symbol: item.symbol) }
        func level(_ f: Double, warn: Double = 0.75, bad: Double = 0.9) -> PinAlert? {
            f >= bad ? .critical : (f >= warn ? .warn : nil)
        }
        switch item {
        case .cpu:
            return PinReading(value: Format.percent(snap.cpuTotal), fraction: snap.cpuTotal,
                              alert: level(snap.cpuTotal), symbol: item.symbol)
        case .gpu:
            let g = snap.gpuUsage ?? 0
            return PinReading(value: snap.gpuUsage.map { Format.percent($0) } ?? "—", fraction: g,
                              alert: level(g), symbol: item.symbol)
        case .memory:
            let alert: PinAlert? = snap.memoryPressure >= .critical ? .critical : (snap.memoryPressure >= .warning ? .warn : nil)
            return PinReading(value: Format.percent(snap.memoryUsed), fraction: snap.memoryUsed,
                              alert: alert, symbol: item.symbol)
        case .battery:
            guard let b = snap.battery else { return PinReading(value: "AC", symbol: "powerplug") }
            let low = !b.isOnAC && b.level < 0.2
            let symbol = b.isCharging ? "bolt.fill" : (b.isOnAC ? "powerplug.fill" : "battery.75percent")
            var detail: String?
            if !b.isOnAC, let m = b.minutesRemaining { detail = Format.duration(TimeInterval(m * 60)) }
            return PinReading(value: Format.percent(b.level), detail: detail, fraction: b.level,
                              alert: low ? (b.level < 0.1 ? .critical : .warn) : nil, symbol: symbol)
        case .disk:
            var fraction: Double?
            if let free = snap.diskFreeBytes, let total = snap.diskTotalBytes, total > 0 {
                fraction = 1 - Double(free) / Double(total)
            }
            let low = (snap.diskFreeBytes ?? .max) < 10_000_000_000
            return PinReading(value: snap.diskFreeBytes.map { Format.diskBytes($0) } ?? "—",
                              fraction: fraction, alert: low ? .warn : nil, symbol: item.symbol)
        case .network:
            return PinReading(value: "↓ " + Format.rate(snap.downloadRate),
                              detail: "↑ " + Format.rate(snap.uploadRate), symbol: item.symbol)
        case .worldClock:
            let zone = model.settings.worldClockZone
            return PinReading(value: WorldClock.time(in: zone), detail: WorldClock.label(for: zone), symbol: item.symbol)
        }
    }
}

private struct PinCell: View {
    let item: PinItem
    let reading: PinReading
    let pin: PinSettings
    private var s: CGFloat { pin.size.scale }

    @Environment(\.pinPalette) private var palette
    private var tint: Color { pinTint(item, reading, pin, palette) }

    var body: some View {
        HStack(spacing: 8 * s) {
            badge
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    Text(reading.value)
                        .font(.system(size: 13.5 * s, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(palette.value(reading.alert))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    if let detail = reading.detail, !pin.showLabels || item == .network {
                        Text(detail)
                            .font(.system(size: 10 * s, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                if pin.showLabels {
                    Text(labelText)
                        .font(.system(size: 8.5 * s, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
        .animation(.snappy, value: reading.value)
        .help(item.title)
    }

    private var labelText: String {
        if item != .network, let detail = reading.detail { return "\(item.label) · \(detail)" }
        return item.label
    }

    @ViewBuilder private var badge: some View {
        let d = 26 * s
        ZStack {
            if pin.showGauges, let f = reading.fraction {
                Circle().stroke(palette.track, lineWidth: 2.6 * s)
                Circle()
                    .trim(from: 0, to: max(0.02, min(f, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: f)
            } else {
                Circle().fill(tint.opacity(0.16))
            }
            if reading.pulse { PulseRing(color: tint, size: d) }
            Image(systemName: reading.symbol)
                .font(.system(size: 10.5 * s, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: d, height: d)
    }
}

private struct PulseRing: View {
        @Environment(\.pinPalette) private var palette
    let color: Color
    let size: CGFloat
    @State private var on = false
    var body: some View {
        Circle()
            .stroke(color.opacity(on ? 0 : 0.7), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(on ? 1.7 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

// MARK: - Compact styles

/// Gauge and icon color: warn/critical when the reading needs attention; otherwise the theme's
/// single accent (or the reading's own color if "color-code each reading" is on).
private func pinTint(_ item: PinItem, _ reading: PinReading, _ pin: PinSettings, _ palette: PinPalette) -> Color {
    if let alert = palette.color(for: reading.alert) { return alert }
    return pin.colorfulIcons ? Color(nsColor: NSColor(hex: item.tintHex) ?? .controlAccentColor) : palette.accent
}

private func shortValue(_ item: PinItem, _ reading: PinReading) -> String {
    switch item {
    case .network: reading.value.replacingOccurrences(of: "↓ ", with: "")
    default: reading.value
    }
}

/// Edge Dock and Pill: a small icon and the value. Stacks icon-over-value in a column.
private struct PinCompactCell: View {
    @Environment(\.pinPalette) private var palette
    let item: PinItem
    let reading: PinReading
    let pin: PinSettings
    let vertical: Bool
    private var s: CGFloat { pin.size.scale }

    var body: some View {
        let tint = pinTint(item, reading, pin, palette)
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2 * s)) : AnyLayout(HStackLayout(spacing: 4 * s))
        layout {
            Image(systemName: reading.symbol)
                .font(.system(size: 9.5 * s, weight: .bold))
                .foregroundStyle(tint)
                .frame(height: 13 * s)
                Text(shortValue(item, reading))
                    .font(.system(size: (vertical ? 10.5 : 12) * s, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.value(reading.alert))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
        }
        .animation(.snappy, value: reading.value)
        .help("\(item.title): \(reading.value)\(reading.detail.map { " · \($0)" } ?? "")")
    }
}

/// Rings: a gauge with the number inside. Readings without a level get a soft disc.
private struct PinRingCell: View {
    @Environment(\.pinPalette) private var palette
    let item: PinItem
    let reading: PinReading
    let pin: PinSettings
    private var s: CGFloat { pin.size.scale }

    var body: some View {
        let tint = pinTint(item, reading, pin, palette)
        let d = 34 * s
        ZStack {
            if let f = reading.fraction {
                Circle().stroke(palette.track, lineWidth: 3 * s)
                Circle()
                    .trim(from: 0, to: max(0.02, min(f, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: f)
            } else {
                Circle().fill(tint.opacity(0.15))
            }
            if reading.pulse { PulseRing(color: tint, size: d) }
                VStack(spacing: -1) {
                    Text(ringText)
                        .font(.system(size: 10 * s, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Image(systemName: reading.symbol)
                        .font(.system(size: 6.5 * s, weight: .bold))
                        .foregroundStyle(tint)
                }
                .padding(.horizontal, 4 * s)
        }
        .frame(width: d, height: d)
        .animation(.snappy, value: reading.value)
        .help("\(item.title): \(reading.value)")
    }

    private var ringText: String {
        let v = shortValue(item, reading)
        return v.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: " ", with: "")
    }
}

/// Meters: label, value and a thin bar, dashboard style.
private struct PinBarCell: View {
    @Environment(\.pinPalette) private var palette
    let item: PinItem
    let reading: PinReading
    let pin: PinSettings
    private var s: CGFloat { pin.size.scale }

    var body: some View {
        let tint = pinTint(item, reading, pin, palette)
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack(spacing: 4 * s) {
                Image(systemName: reading.symbol)
                    .font(.system(size: 8 * s, weight: .bold))
                    .foregroundStyle(tint)
                Text(item.label.uppercased())
                    .font(.system(size: 7.5 * s, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 6 * s)
                Text(shortValue(item, reading))
                    .font(.system(size: 10.5 * s, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.value(reading.alert))
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(tint)
                        .frame(width: max(2, geo.size.width * min(max(reading.fraction ?? 0, 0), 1)))
                        .animation(.smooth(duration: 0.6), value: reading.fraction)
                }
            }
            .frame(height: 3 * s)
            .opacity(reading.fraction == nil ? 0 : 1)
        }
        .frame(width: 96 * s)
        .animation(.snappy, value: reading.value)
        .help(item.title)
    }
}

/// Text Only: game-overlay style, no box. A soft shadow keeps it readable on any wallpaper.
private struct PinTextCell: View {
    @Environment(\.pinPalette) private var palette
    let item: PinItem
    let reading: PinReading
    let pin: PinSettings
    private var s: CGFloat { pin.size.scale }

    var body: some View {
        let tint = pinTint(item, reading, pin, palette)
        HStack(spacing: 5 * s) {
            Text(item.label.uppercased())
                .font(.system(size: 9 * s, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint)
            Text(shortValue(item, reading))
                .font(.system(size: 12 * s, weight: .bold, design: .monospaced).monospacedDigit())
                .foregroundStyle(palette.value(reading.alert))
                .contentTransition(.numericText())
        }
        .shadow(color: .black.opacity(0.85), radius: 1.5, x: 0, y: 1)
        .shadow(color: .black.opacity(0.4), radius: 4)
        .animation(.snappy, value: reading.value)
        .fixedSize()
    }
}

// MARK: - Background


struct PinBackground: View {
    let pin: PinSettings
    let shape: AnyShape
    @Environment(\.pinPalette) private var palette

    init(pin: PinSettings, shape: AnyShape) {
        self.pin = pin
        self.shape = shape
    }

    init(pin: PinSettings, radius: CGFloat) {
        self.init(pin: pin, shape: AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }

    var body: some View {
        ZStack {
            if palette.frosted {
                VisualEffectBlur(material: palette.scheme == .dark ? .hudWindow : .popover)
            }
            shape.fill(palette.surface.opacity(pin.opacity))
            // A faint top sheen gives depth without adding color.
            shape.fill(LinearGradient(colors: [.white.opacity(palette.scheme == .dark ? 0.05 : 0.25), .clear],
                                      startPoint: .top, endPoint: .center))
        }
        .clipShape(shape)
        .overlay(shape.stroke(palette.hairline, lineWidth: 1))
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThroughEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }

    /// Purely decorative: never takes the mouse.
    final class PassThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
