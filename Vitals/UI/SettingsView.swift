import Combine
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: VitalsModel
    @ObservedObject var license: LicenseManager
    @ObservedObject var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings(model: model, isPro: license.isPro)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            MenuBarSettings(model: model, isPro: license.isPro, upgrade: { router.tab = .pro })
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)
            PinSettingsView(model: model, isPro: license.isPro, upgrade: { router.tab = .pro })
                .tabItem { Label("On Screen", systemImage: "pin") }
                .tag(SettingsTab.pin)
            PopoverSettings(model: model)
                .tabItem { Label("Popover", systemImage: "rectangle.stack") }
                .tag(SettingsTab.popover)
            AlertSettings(model: model, isPro: license.isPro)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag(SettingsTab.alerts)
            ProSettings(license: license)
                .tabItem { Label("Pro", systemImage: "star") }
                .tag(SettingsTab.pro)
            AboutSettings(model: model)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 620)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: VitalsModel
    let isPro: Bool
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Open Vitals when you log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        LaunchAtLogin.set(value)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if LaunchAtLogin.needsApproval {
                    Text("Approve Vitals in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle("Notify me when something needs attention", isOn: $model.settings.notificationsEnabled)
                    .onChange(of: model.settings.notificationsEnabled) { _, on in
                        if on { Notifier.requestPermission { _ in model.refreshNotificationStatus() } }
                    }
                if model.settings.notificationsEnabled && !model.canDeliverNotifications {
                    HStack {
                        Text("Notifications are off for Vitals in System Settings.")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open") { Notifier.openNotificationSettings() }.controlSize(.small)
                    }
                }
                Toggle("Show a report after I've been away", isOn: $model.settings.awayReportsEnabled)
                Text("Alerts arrive as macOS notifications, with Quit, Snooze and Ignore right on them. Vitals only notifies for real problems — never for routine readings. Turn this off to see alerts inside the Vitals popover instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}

// MARK: - Alerts

private struct AlertSettings: View {
    @ObservedObject var model: VitalsModel
    let isPro: Bool

    var body: some View {
        Form {
            Section {
                Picker("Sensitivity", selection: $model.settings.detection.sensitivity) {
                    ForEach(Sensitivity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(model.settings.detection.sensitivity.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Watch for") {
                ForEach(IssueKind.available) { kind in
                    Toggle(isOn: kindBinding(kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Label(kind.title, systemImage: kind.symbol)
                                if kind.requiresPro && !isPro { ProBadge() }
                            }
                            Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Hotspot data guard") {
                Toggle("Count data on hotspots and warn me near a limit", isOn: $model.settings.hotspotGuard)
                if model.settings.hotspotGuard {
                    Picker("Limit per hotspot session", selection: $model.settings.hotspotLimitMB) {
                        ForEach([500, 1000, 2048, 5120, 10240], id: \.self) { mb in
                            Text(mb >= 1000 ? "\(mb / 1024 == 0 ? 1 : mb / 1024) GB" : "\(mb) MB").tag(mb)
                        }
                    }
                    if model.network.onMeteredConnection {
                        Label("On a metered connection now · \(Format.bytes(UInt64(model.network.meteredBytes))) used",
                              systemImage: "personalhotspot")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("macOS marks iPhone Personal Hotspot, tethering and Low Data Mode networks as metered. Vitals counts from the moment you join one and warns at 80% and 100% of your limit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !Edition.isAppStore || !model.settings.detection.ignoredApps.isEmpty {
            Section("Ignored apps") {
                if model.settings.detection.ignoredApps.isEmpty {
                    Text("None. Choose “Always ignore” on an alert to add an app here.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.settings.detection.ignoredApps.sorted { $0.value < $1.value }, id: \.key) { entry in
                        HStack {
                            Text(entry.value)
                            Spacer()
                            Button("Remove") { model.unignore(entry.key) }
                        }
                    }
                }
            }
            }
        }
        .formStyle(.grouped)
    }

    private func kindBinding(_ kind: IssueKind) -> Binding<Bool> {
        Binding(
            get: { !model.settings.detection.disabledKinds.contains(kind) },
            set: { on in
                if on { model.settings.detection.disabledKinds.remove(kind) } else { model.settings.detection.disabledKinds.insert(kind) }
            })
    }
}

// MARK: - Pro

private struct ProSettings: View {
    @ObservedObject var license: LicenseManager
    @State private var key = ""
    @State private var copied = false

    static func masked(_ key: String) -> String {
        guard key.count > 8 else { return key }
        return String(key.prefix(11)) + String(repeating: "•", count: max(0, key.count - 15)) + String(key.suffix(4))
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vitals Pro").font(.title3.bold())
                        Text(statusText).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if Edition.isAppStore {
                        feature("battery.25percent", "Fast-drain alerts and “Will my battery last?”")
                        feature("arrow.up.arrow.down", "Where your data went — 7 and 30 days")
                    } else {
                        feature("battery.25percent", "Fast-drain alerts with the app to blame")
                        feature("moon.zzz", "Catch apps that keep your Mac awake")
                        feature("eye.slash", "Hide other apps' menu-bar icons")
                        feature("arrow.up.arrow.down", "Where your data went — 7 and 30 days, by app")
                    }
                    feature("moon.stars", "Full “While you were away” reports")
                    feature("externaldrive.badge.minus", "One-click clearing in Free Up Space")
                    feature("pin", "Pin live readings anywhere on your screen")
                    feature("menubar.rectangle", "Menu-bar readings, colors, “only when high”, and extra icon styles")
                    feature("heart", "One payment of \(license.priceText) — every feature, no subscription")
                }
                .padding(.vertical, 4)
            }

            if license.state != .pro {
                Section {
                    if license.usesAppStore {
                        if license.canStartTrial {
                            Button("Start \(LicenseConfig.trialDays)-Day Free Trial") { Task { await license.startTrial() } }
                                .disabled(license.isWorking)
                            Text("Free for \(LicenseConfig.trialDays) days, no payment details needed. When it ends, the Pro features above lock again and the free features keep working. To keep Pro, buy it once for \(license.priceText). You're never charged automatically.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Button("Unlock Pro · \(license.priceText)") { Task { await license.purchase() } }
                                .buttonStyle(.borderedProminent)
                            Button("Restore Purchase") { Task { await license.restore() } }
                        }
                    } else {
                        Button("Buy Vitals Pro · \(license.priceText)") { NSWorkspace.shared.open(LicenseConfig.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                        HStack {
                            TextField("License key", text: $key, prompt: Text("VITALS-XXXX-XXXX-XXXX-XXXX or your purchase key"))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("Activate") { Task { await license.activate(key: key) } }
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || license.isWorking)
                        }
                        Text("Bought Vitals Pro in the Mac App Store? Paste the key from Vitals › Settings › Pro there. Each key works on one Mac at a time.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !license.usesAppStore {
                Section("License") {
                    if let key = license.licenseKey {
                        LabeledContent("Key", value: Self.masked(key))
                            .font(.system(.body, design: .monospaced))
                    }
                    Button("Remove License From This Mac") { Task { await license.deactivate() } }
                        .disabled(license.isWorking)
                    Text("Moving to a new Mac? Remove it here first, then activate the same key there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if LicenseConfig.licenseServerConfigured {
                Section("Your license key") {
                    if let key = license.appStoreKey {
                        HStack {
                            Text(key)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key, forType: .string)
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        Text("Your purchase also includes this key for Vitals Pro on one Mac outside the Mac App Store. Keep it somewhere safe.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button("Show My License Key") { Task { await license.claimLicenseKey() } }
                            .disabled(license.isWorking)
                        Text("Your purchase includes one license key for using Vitals Pro on a Mac outside the Mac App Store.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let message = license.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch license.state {
        case .pro: "Unlocked. Thank you!"
        case .trial(let days): "Free trial — \(days) day\(days == 1 ? "" : "s") left. Everything is unlocked."
        case .free: license.canStartTrial
            ? "Try every Pro feature free for \(LicenseConfig.trialDays) days — no payment needed."
            : "The free version keeps watching your Mac's heat, memory, battery and disk."
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @ObservedObject var model: VitalsModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vitals").font(.title2.bold())
                    Text("The check-engine light for your Mac.").foregroundStyle(.secondary)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Text("Everything Vitals measures stays on this Mac. No accounts, no analytics, no tracking. The only network request is checking your license key.")
                    .font(.callout)
            }
            Section("What this Mac allows") {
                capability("Per-app CPU and energy", model.sampler.perAppAvailable)
                capability("Apps keeping the Mac awake", model.sampler.assertionsAvailable)
                capability("Battery power draw", model.sampler.batteryPowerAvailable || model.snapshot?.battery == nil)
                LabeledContent("Build", value: SystemSampler.isSandboxed ? "App Store (sandboxed)" : "Direct")
            }
        }
        .formStyle(.grouped)
    }

    private func capability(_ title: String, _ available: Bool) -> some View {
        LabeledContent(title) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

// MARK: - Menu bar

private struct MenuBarSettings: View {
    @ObservedObject var model: VitalsModel
    let isPro: Bool
    let upgrade: () -> Void
    @ObservedObject private var control = MenuBarControl.shared

    var body: some View {
        Form {
            Section("Icon") {
                HStack(spacing: 10) {
                    ForEach(IconStyle.allCases) { style in
                        Button {
                            if style.isPro && !isPro { upgrade() } else { model.settings.iconStyle = style }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: style.pickerSymbol)
                                    .font(.system(size: style == .dot ? 10 : 18, weight: .semibold))
                                    .frame(width: 44, height: 32)
                                    .background(model.settings.iconStyle == style ? Color.accentColor.opacity(0.18) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(model.settings.iconStyle == style ? Color.accentColor : Color.secondary.opacity(0.3)))
                                HStack(spacing: 3) {
                                    Text(style.title).font(.caption)
                                    if style.isPro && !isPro { Image(systemName: "lock.fill").font(.system(size: 8)) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(model.settings.iconStyle == .none
                     ? "No icon while your readings are showing. The Pulse icon comes back if no readings are on, and whenever something needs you."
                     : "The icon turns orange or red, with a dot, only when something needs you.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Show next to the icon") {
                Picker("Show", selection: styleBinding) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title + (style.isPro && !isPro ? " (Pro)" : "")).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if model.settings.menuBarStyle.showsReadings {
                    ForEach(ReadingKind.available) { kind in
                        Toggle(isOn: readingBinding(kind)) {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                HStack(spacing: 3) {
                                    Image(systemName: kind.symbol).imageScale(.small)
                                    Text(kind.example).font(.caption.monospacedDigit())
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if model.settings.readings.contains(.worldClock) {
                        Picker("Time zone", selection: $model.settings.worldClockZone) {
                            ForEach(WorldClock.zones, id: \.id) { zone in
                                Text("\(zone.label) — \(zone.id.replacingOccurrences(of: "_", with: " "))").tag(zone.id)
                            }
                        }
                    }
                    if model.settings.menuBarStyle == .smartReadings {
                        Text("CPU above 75%, memory pressure, battery under 20%, fast network or under 10 GB free. Otherwise your menu bar stays clean.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ColorChoice(title: "Icon", hex: colorBinding(\.iconColorHex))
                if model.settings.menuBarStyle.showsReadings {
                    ColorChoice(title: "Reading text", hex: colorBinding(\.readingTextColorHex))
                    ColorChoice(title: "Reading icons", hex: colorBinding(\.readingIconColorHex))
                    Toggle("Turn a reading orange when it's high", isOn: Binding(
                        get: { model.settings.colorReadingsWhenHigh },
                        set: { value in if isPro { model.settings.colorReadingsWhenHigh = value } else { upgrade() } }))
                    if !model.settings.readings.isEmpty {
                        DisclosureGroup("Color each reading") {
                            ForEach(model.settings.readings) { kind in
                                ColorChoice(title: kind.title, symbol: kind.symbol, hex: readingColorBinding(kind))
                            }
                        }
                    }
                }
                HStack {
                    Text("Auto follows your menu bar, light or dark. Alerts always show in orange or red.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset colors") {
                        model.settings.iconColorHex = nil
                        model.settings.readingTextColorHex = nil
                        model.settings.readingIconColorHex = nil
                        model.settings.readingColors = [:]
                        model.settings.colorReadingsWhenHigh = true
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Colors")
                    if !isPro { ProBadge() }
                }
            }

            Section("Keyboard shortcut") {
                Picker("Open Vitals with", selection: $model.settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.title).tag($0) }
                }
            }

            MenuBarItemsSection(control: control, isPro: isPro, upgrade: upgrade)

            Section("Tidy tips") {
                Label("Hold ⌘ and drag icons in the menu bar to reorder them.", systemImage: "arrow.left.and.right")
                    .font(.callout)
                Label("Vitals can replace separate stats, keep-awake and cleaner apps — quit those for a calmer menu bar.", systemImage: "square.stack.3d.down.right")
                    .font(.callout)
                Button("Open macOS Menu Bar Settings…") { SystemActions.openMenuBarSettings() }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppSettings, String?>) -> Binding<String?> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in if isPro { model.settings[keyPath: keyPath] = value } else { upgrade() } })
    }

    private func readingColorBinding(_ kind: ReadingKind) -> Binding<String?> {
        Binding(
            get: { model.settings.readingColors[kind.rawValue] },
            set: { value in
                guard isPro else { upgrade(); return }
                model.settings.readingColors[kind.rawValue] = value
            })
    }

    private var styleBinding: Binding<MenuBarStyle> {
        Binding(
            get: { model.settings.menuBarStyle },
            set: { style in
                if style.isPro && !isPro { upgrade() } else { model.settings.menuBarStyle = style }
            })
    }

    private func readingBinding(_ kind: ReadingKind) -> Binding<Bool> {
        Binding(
            get: { model.settings.readings.contains(kind) },
            set: { on in
                var list = model.settings.readings.filter { $0 != kind }
                if on { list.append(kind) }
                model.settings.readings = ReadingKind.allCases.filter { list.contains($0) }
            })
    }
}

// MARK: - Popover

private struct PopoverSettings: View {
    @ObservedObject var model: VitalsModel

    var body: some View {
        Form {
            Section {
                ForEach(PopoverSection.available) { section in
                    Toggle(section.title, isOn: Binding(
                        get: { !model.settings.hiddenSections.contains(section) },
                        set: { on in
                            if on { model.settings.hiddenSections.remove(section) }
                            else { model.settings.hiddenSections.insert(section) }
                        }))
                }
            } header: {
                Text("Show in the popover")
            } footer: {
                Text("Alerts always show. Hide everything else for the calmest possible Vitals.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Other apps' menu bar icons

private struct MenuBarItemsSection: View {
    @ObservedObject var control: MenuBarControl
    let isPro: Bool
    let upgrade: () -> Void

    var body: some View {
        Section {
            if !Edition.canHideMenuBarIcons {
                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS can switch off most menu-bar icons for you:")
                        .font(.callout)
                    Label("Open Menu Bar settings with the button below.", systemImage: "1.circle")
                    Label("Under “Allow in the Menu Bar”, turn off the apps you don't need to see.", systemImage: "2.circle")
                    Label("Hold ⌘ and drag icons in the menu bar to reorder them.", systemImage: "3.circle")
                    Button("Open Menu Bar Settings…") { SystemActions.openMenuBarSettings() }
                        .padding(.top, 2)
                }
            } else if !control.isSupported {
                Text("Hiding other apps' icons from Vitals needs macOS 27. You can still switch icons off in macOS settings.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !control.isTrusted {
                Text("To see and tidy the icons in your menu bar, Vitals needs Accessibility permission. Vitals only reads menu-bar icons.")
                    .font(.callout)
                Button("Allow Accessibility…") { control.requestAccessibility() }
            } else {
                if let problem = control.installProblem {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(problem.explanation, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        HStack {
                            if problem == .notInApplications {
                                Button("Move Vitals to Applications") { control.moveToApplications() }
                            }
                            Button("Show in Finder") { control.showInstallProblemInFinder() }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if control.apps.isEmpty {
                    Text(control.isScanning ? "Looking at your menu bar…" : (control.message ?? "No third-party icons found."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(control.apps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
                            .resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            if control.hiddenIDs.contains(app.id) {
                                Text("Hidden · one click away in the Vitals popover").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            control.setInHub(!control.isInHub(app.id), for: app.id)
                        } label: {
                            Image(systemName: control.isInHub(app.id) ? "star.fill" : "star")
                                .foregroundStyle(control.isInHub(app.id) ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Keep a shortcut to this icon in the Vitals popover")
                        .disabled(control.hiddenIDs.contains(app.id))
                        Toggle("Show", isOn: Binding(
                            get: { !control.hiddenIDs.contains(app.id) },
                            set: { show in
                                if !show && !isPro { upgrade() } else { control.setHidden(!show, for: app.id) }
                            }))
                            .toggleStyle(.switch).labelsHidden()
                            .disabled(control.isApplying)
                    }
                }
                Text("Apple icons").font(.headline).padding(.top, 6)
                Group {
                    ForEach(ControlledSystemItem.allCases) { item in
                        Toggle(isOn: Binding(
                            get: { !control.hiddenSystemIDs.contains(item.id) },
                            set: { show in
                                if !show && !isPro { upgrade() } else { control.setSystemHidden(!show, for: item.id) }
                            })) {
                            Label(item.title, systemImage: item.symbol)
                        }
                        .toggleStyle(.switch)
                        .disabled(control.isApplying)
                    }
                }
                HStack {
                    Button(control.isRevealed ? "Hide again" : "Show everything for now") {
                        if control.isRevealed { control.hideAgain() } else { control.reveal() }
                    }
                    Button("Refresh") { control.refresh() }
                    Spacer()
                    Button("Reset all") { control.restoreAndClear() }
                }
                if let message = control.message, !control.apps.isEmpty, message != control.installProblem?.explanation {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text(Edition.canHideMenuBarIcons ? "Your menu bar icons" : "Tidy your menu bar")
                if Edition.canHideMenuBarIcons {
                    Text("BETA").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
                    if !isPro { ProBadge() }
                }
            }
        } footer: {
            if Edition.canHideMenuBarIcons {
                Text("Hidden icons stay one click away in the Vitals popover. While icons are hidden, hover over the clock to reach Notification Center. Quitting Vitals shows everything again.")
            }
        }
        .onAppear { control.startAfterMenuBarAppears() }
    }
}

// MARK: - Color picker row

/// Automatic + a row of swatches + a custom color well.
private struct ColorChoice: View {
    let title: String
    var symbol: String? = nil
    @Binding var hex: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(.secondary).frame(width: 16)
            }
            Text(title)
            Spacer(minLength: 12)
            swatch(nil, name: "Automatic")
            ForEach(MenuBarPalette.swatches, id: \.hex) { swatch($0.hex, name: $0.name) }
            ColorPicker("", selection: custom, supportsOpacity: false)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 26)
                .help("Pick any color")
        }
    }

    private func swatch(_ value: String?, name: String) -> some View {
        let selected = (hex ?? "").uppercased() == (value ?? "").uppercased()
        return Button { hex = value } label: {
            Group {
                if let value, let color = NSColor(hex: value) {
                    Circle().fill(Color(nsColor: color))
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Text("A").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray))
                }
            }
            .frame(width: 15, height: 15)
            .overlay(Circle().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35),
                                     lineWidth: selected ? 2 : 0.5).padding(-2.5))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private var custom: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: hex) ?? .labelColor) },
            set: { hex = NSColor($0).hexString })
    }
}
