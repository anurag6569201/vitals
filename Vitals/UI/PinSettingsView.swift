import AppKit
import SwiftUI

/// Settings › On Screen: pin live readings anywhere on your screen.
struct PinSettingsView: View {
    @ObservedObject var model: VitalsModel
    let isPro: Bool
    let upgrade: () -> Void

    private var pin: Binding<PinSettings> { $model.settings.pin }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.black.opacity(0.55), in: Circle())
            .padding(5)
    }

    var body: some View {
        Form {
            Section {
                PinStage(model: model, pin: pin, isPro: isPro)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Toggle(isOn: pin.enabled) {
                    Text("Pin Vitals to your screen").font(.headline)
                }
                if !isPro {
                    HStack(spacing: 6) {
                        Text("Free: one reading in the Edge Dock. Pro unlocks every reading, shape and theme.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Unlock", action: upgrade).controlSize(.small)
                    }
                }
                Text("Drag it anywhere — it snaps to edges and corners, and turns into a column on the left or right edge. Right-click it for quick options; double-click opens Vitals. Click a spot in the preview to move it there.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Start from a preset") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                    ForEach(PinPreset.allCases) { preset in
                        PinPresetButton(preset: preset, locked: preset.isPro && !isPro) {
                            if preset.isPro && !isPro { upgrade(); return }
                            var updated = pin.wrappedValue
                            preset.apply(to: &updated)
                            updated.enabled = true
                            pin.wrappedValue = updated
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Shape") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(PinShape.allCases) { shape in
                        PinShapeTile(model: model, pin: pin.wrappedValue, shape: shape,
                                     selected: pin.wrappedValue.shape == shape) {
                            if shape != .dock && !isPro { upgrade() } else { pin.wrappedValue.shape = shape }
                        }
                        .overlay(alignment: .topTrailing) { if shape != .dock && !isPro { lockBadge } }
                    }
                }
                .padding(.vertical, 2)
                Text(pin.wrappedValue.shape.subtitle).font(.caption).foregroundStyle(.secondary)
                if pin.wrappedValue.shape == .dock {
                    Toggle("Tuck into the edge until the pointer comes near", isOn: pin.autoHide)
                }
            }

            Section {
                ForEach(PinItem.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.rawValue.uppercased())
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                            ForEach(PinItem.allCases.filter { $0.group == group }) { item in
                                PinChip(item: item, selected: pin.wrappedValue.items.contains(item)) {
                                    if isPro { model.togglePinItem(item) } else { pin.wrappedValue.items = [item] }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if pin.wrappedValue.items.contains(.ping) {
                    Label("Ping times a connection to Apple's connectivity check (captive.apple.com) every few seconds. No data about you is sent.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(isPro ? "Show" : "Show (free: pick one)")
            }

            Section("Look") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(PinTheme.allCases) { theme in
                        PinThemeTile(theme: theme, colorHex: pin.wrappedValue.colorHex,
                                     selected: pin.wrappedValue.theme == theme) {
                            if theme != .auto && !isPro { upgrade() } else { pin.wrappedValue.theme = theme }
                        }
                        .overlay(alignment: .topTrailing) { if theme != .auto && !isPro { lockBadge } }
                    }
                }
                .padding(.vertical, 2)
                Text(pin.wrappedValue.theme.subtitle + ". Every theme keeps text at WCAG AA contrast or better, over light or dark windows.")
                    .font(.caption).foregroundStyle(.secondary)
                if pin.wrappedValue.theme == .custom {
                    PinSwatches(hex: pin.colorHex)
                }
                HStack {
                    Text("Background")
                    Slider(value: pin.opacity, in: 0.7...1)
                    Text(Format.percent(pin.wrappedValue.opacity))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
                Picker("Size", selection: pin.size) {
                    ForEach(PinSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Labels under each reading", isOn: pin.showLabels)
                Toggle("Gauge rings", isOn: pin.showGauges)
                Toggle("Color-code each reading", isOn: pin.colorfulIcons)
                Text(pin.wrappedValue.colorfulIcons
                     ? "Each reading gets its own color. Warnings still turn amber or red."
                     : "One calm accent for every gauge, so amber and red only ever mean “look at this”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Place") {
                Picker("Layout", selection: pin.layout) {
                    ForEach(PinLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Sits", selection: pin.level) {
                    ForEach(PinLevel.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Snap to edges and corners", isOn: pin.snapToEdges)
                Toggle("Show on every desktop and full-screen app", isOn: pin.allSpaces)
                Toggle("Lock in place — clicks pass straight through", isOn: pin.locked)
                if pin.wrappedValue.locked {
                    Text("While locked you can't drag or right-click the pin. Unlock it here or from the pin button in the Vitals menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        let enabled = pin.wrappedValue.enabled
                        var fresh = PinSettings()
                        fresh.enabled = enabled
                        pin.wrappedValue = fresh
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(Motion.spring, value: model.settings.pin)
    }
}

// MARK: - Stage (preview + position picker)

private struct PinStage: View {
    @ObservedObject var model: VitalsModel
    @Binding var pin: PinSettings
    var isPro = true
    @State private var hoverZone: Int?

    var body: some View {
        ZStack(alignment: alignment) {
            wallpaper
            // A hint of a menu bar.
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo").font(.system(size: 8, weight: .bold))
                    Capsule().fill(.white.opacity(0.5)).frame(width: 26, height: 4)
                    Capsule().fill(.white.opacity(0.35)).frame(width: 20, height: 4)
                    Spacer()
                    Image(systemName: "waveform.path.ecg").font(.system(size: 8, weight: .bold))
                    Capsule().fill(.white.opacity(0.5)).frame(width: 30, height: 4)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .frame(height: 16)
                .background(.black.opacity(0.18))
                Spacer()
            }
            PinnedVitalsView(model: model, pin: isPro ? pin : pin.freeTier(), interactive: false)
                .fixedSize()
                .scaleEffect(0.62, anchor: anchor)
                .padding(.top, 22)
                .padding([.horizontal, .bottom], 8)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .animation(.snappy, value: pin.position)
                .allowsHitTesting(false)
            zones
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.48), Color(red: 0.47, green: 0.25, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.35).opacity(0.75), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 320)
            RadialGradient(colors: [Color(red: 0.25, green: 0.85, blue: 0.85).opacity(0.45), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 260)
        }
    }

    /// 3×3 invisible buttons: click a spot to put the pin there.
    private var zones: some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3) { col in
                        let index = row * 3 + col
                        let preset = PinPosition.presets[index]
                        Rectangle()
                            .fill(.white.opacity(hoverZone == index ? 0.12 : 0.001))
                            .overlay {
                                if hoverZone == index {
                                    Text(preset.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.black.opacity(0.35), in: Capsule())
                                }
                            }
                            .contentShape(Rectangle())
                            .onHover { inside in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    if inside { hoverZone = index } else if hoverZone == index { hoverZone = nil }
                                }
                            }
                            .onTapGesture {
                                var p = pin.position
                                p.h = preset.h
                                p.v = preset.v
                                pin.position = p
                            }
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    private var hAxis: Int {
        switch pin.position.h {
        case .start: 0
        case .center: 1
        case .end: 2
        case .free: pin.position.fx < 0.33 ? 0 : (pin.position.fx > 0.66 ? 2 : 1)
        }
    }

    private var vAxis: Int {
        switch pin.position.v {
        case .start: 0
        case .center: 1
        case .end: 2
        case .free: pin.position.fy < 0.33 ? 0 : (pin.position.fy > 0.66 ? 2 : 1)
        }
    }

    private var alignment: Alignment {
        let h: [HorizontalAlignment] = [.leading, .center, .trailing]
        let v: [VerticalAlignment] = [.top, .center, .bottom]
        return Alignment(horizontal: h[hAxis], vertical: v[vAxis])
    }

    private var anchor: UnitPoint {
        UnitPoint(x: [0, 0.5, 1][hAxis], y: [0, 0.5, 1][vAxis])
    }
}

// MARK: - Pieces

private struct PinPresetButton: View {
    let preset: PinPreset
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(preset.title).font(.system(size: 12, weight: .semibold))
                        if locked { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
                    }
                    Text(preset.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hoverFill: false))
        .hoverLift(1.02)
    }
}

private struct PinChip: View {
    let item: PinItem
    let selected: Bool
    let action: () -> Void
    @State private var over = false

    var body: some View {
        let tint = Color(nsColor: NSColor(hex: item.tintHex) ?? .controlAccentColor)
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                    .frame(width: 22, height: 22)
                    .background(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)), in: Circle())
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? tint.opacity(0.12) : Color.primary.opacity(over ? 0.06 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.55) : Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hoverFill: false))
        .onHover { over = $0 }
        .animation(Motion.spring, value: selected)
    }
}

private struct PinShapeTile: View {
    @ObservedObject var model: VitalsModel
    let pin: PinSettings
    let shape: PinShape
    let selected: Bool
    let action: () -> Void

    var body: some View {
        var sample = pin
        sample.shape = shape
        sample.items = [.cpu, .memory, .battery]
        sample.size = .small
        sample.autoHide = false
        sample.layout = .row
        sample.position.h = .free
        sample.position.v = .end
        let wallpaper = LinearGradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.52), Color(red: 0.86, green: 0.48, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: shape == .dock ? .bottom : .center) {
                    wallpaper
                    PinnedVitalsView(model: model, pin: sample, interactive: false)
                        .fixedSize()
                        .scaleEffect(0.82, anchor: shape == .dock ? .bottom : .center)
                        .allowsHitTesting(false)
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(shape.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(PressableStyle(hoverFill: false))
        .hoverLift(1.03)
        .animation(Motion.spring, value: selected)
    }
}

private struct PinThemeTile: View {
    let theme: PinTheme
    let colorHex: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var system

    var body: some View {
        var sample = PinSettings()
        sample.theme = theme
        sample.colorHex = colorHex
        let palette = PinPalette.make(for: sample, system: system)
        return Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    // Half light, half dark page: shows the theme reads on both.
                    HStack(spacing: 0) {
                        Color(white: 0.96)
                        Color(white: 0.12)
                    }
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(palette.track, lineWidth: 2.4)
                            Circle().trim(from: 0, to: 0.62)
                                .stroke(palette.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 13, height: 13)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("62%").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.ink)
                            Text("CPU").font(.system(size: 7, weight: .bold)).foregroundStyle(palette.secondary)
                        }
                        Text("91%").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.warn)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(PinBackground(pin: sample, radius: 9))
                    .environment(\.pinPalette, palette)
                    .environment(\.colorScheme, palette.scheme)
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(theme.title).font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(PressableStyle(hoverFill: false))
        .hoverLift(1.04)
        .animation(Motion.spring, value: selected)
        .help(theme.subtitle)
    }
}

private struct PinSwatches: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 7) {
            Text("Color")
            Spacer()
            ForEach(MenuBarPalette.swatches, id: \.hex) { swatch in
                let selected = hex.uppercased() == swatch.hex.uppercased()
                Button { hex = swatch.hex } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: swatch.hex) ?? .gray).gradient)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: hex) ?? .systemIndigo) },
                set: { hex = NSColor($0).hexString }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
                .help("Any color")
        }
    }
}
