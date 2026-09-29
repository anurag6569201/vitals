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
        .frame(width: 560, height: 560)
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
                        if on { Notifier.requestPermission() }
                    }
                Toggle("Show a report after I've been away", isOn: $model.settings.awayReportsEnabled)
                Text("Vitals only notifies for real problems — never for routine readings.")
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
                ForEach(IssueKind.allCases) { kind in
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
                    feature("battery.25percent", "Fast-drain alerts with the app to blame")
                    feature("moon.zzz", "Catch apps that keep your Mac awake")
                    feature("moon.stars", "Full “While you were away” reports")
                    feature("externaldrive.badge.minus", "One-click clearing in Free Up Space")
                    feature("menubar.rectangle", "Menu-bar readings, including “only when high”, and extra icon styles")
                    feature("heart", "Support an independent developer — one payment, yours forever")
                }
                .padding(.vertical, 4)
            }

            if license.state != .pro {
                Section {
                    if license.usesAppStore {
                        HStack {
                            Button("Unlock Pro · \(license.priceText)") { Task { await license.purchase() } }
                                .buttonStyle(.borderedProminent)
                            Button("Restore Purchase") { Task { await license.restore() } }
                        }
                    } else {
                        Button("Buy Vitals Pro · \(license.priceText)") { NSWorkspace.shared.open(LicenseConfig.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                        HStack {
                            TextField("License key", text: $key)
                                .textFieldStyle(.roundedBorder)
                            Button("Activate") { Task { await license.activate(key: key) } }
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || license.isWorking)
                        }
                    }
                }
            } else if !license.usesAppStore {
                Section {
                    Button("Remove License From This Mac") { Task { await license.deactivate() } }
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
        case .free: "The free version keeps watching for runaway apps, heat, memory and disk."
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
                                Image(systemName: style.symbol)
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
                Text("The icon turns orange or red, with a dot, only when something needs you.")
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
                    ForEach(ReadingKind.allCases) { kind in
                        Toggle(isOn: readingBinding(kind)) {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                Text(kind.example).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                ForEach(PopoverSection.allCases) { section in
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
            if !control.isSupported {
                Text("Hiding other apps' icons from Vitals needs macOS 27. You can still switch icons off in macOS settings.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !control.isTrusted {
                Text("To see and tidy the icons in your menu bar, Vitals needs Accessibility permission. Vitals only reads menu-bar icons.")
                    .font(.callout)
                Button("Allow Accessibility…") { control.requestAccessibility() }
            } else {
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
                DisclosureGroup("Apple controls") {
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
                if let message = control.message, !control.apps.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Your menu bar icons")
                Text("BETA").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
                if !isPro { ProBadge() }
            }
        } footer: {
            Text("Hidden icons stay one click away in the Vitals popover. While icons are hidden, hover over the clock to reach Notification Center. Quitting Vitals shows everything again.")
        }
        .onAppear { control.startAfterMenuBarAppears() }
    }
}
