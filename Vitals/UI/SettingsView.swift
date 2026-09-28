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
        .frame(width: 520, height: 500)
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

            Section("Menu bar") {
                Picker("Show", selection: $model.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        HStack {
                            Text(style.title)
                            if style == .readings && !isPro { Text("(Pro)") }
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                if model.settings.menuBarStyle == .readings {
                    if isPro {
                        ForEach(ReadingKind.allCases) { kind in
                            Toggle(kind.title, isOn: readingBinding(kind))
                        }
                    } else {
                        Text("Live readings in the menu bar are part of Vitals Pro.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                    feature("menubar.rectangle", "Live readings in the menu bar")
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
