import AppKit
import ServiceManagement
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var monitor: VitalsMonitor
    @EnvironmentObject private var settings: VitalsConfigurationStore
    @EnvironmentObject private var menuControl: MenuBarControl
    @State private var iconSearch = ""
    @State private var profileName = ""
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    let configurationWindow: Bool

    init(configurationWindow: Bool = false) {
        self.configurationWindow = configurationWindow
    }

    private var accent: Color { settings.configuration.theme.color }
    private var panelMetrics: [MetricKind] { settings.configuration.panelMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                if configurationWindow { customization } else { dashboard }
            }
            .frame(maxHeight: configurationWindow ? .infinity : 590)
            footer
        }
        .frame(width: configurationWindow ? 480 : 408,
               height: configurationWindow ? 650 : nil)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if configurationWindow { launchesAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 38, height: 38)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(configurationWindow ? "Customize Vitals" : "Vitals")
                    .font(.system(size: 17, weight: .bold))
                Text(configurationWindow ? "Control your menu bar" : "Shortcuts and live readings")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if configurationWindow {
                    dismissWindow(id: "customize")
                } else {
                    openWindow(id: "customize")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Image(systemName: configurationWindow ? "checkmark" : "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help(configurationWindow ? "Done customizing" : "Customize Vitals")
            .accessibilityLabel(configurationWindow ? "Done customizing" : "Customize Vitals")
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 16)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            hubShelf
            let networkItems = panelMetrics.filter { $0 == .download || $0 == .upload }
            if panelMetrics.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(accent)
                    Text("No readings selected")
                        .font(.subheadline.weight(.semibold))
                    Text("Add live stats from Customize Vitals.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            if !networkItems.isEmpty {
                networkPanel(networkItems)
            }
            let cards = panelMetrics.filter { $0 != .download && $0 != .upload &&
                ($0 != .battery || monitor.batteryText != "N/A") }
            if !cards.isEmpty {
                HStack(spacing: 8) {
                    ForEach(cards) { kind in
                        metricCard(kind)
                    }
                }
            }
            if monitor.priorityMetric != nil {
                HStack(spacing: 9) {
                    Image(systemName: monitor.insightSymbol).foregroundStyle(.orange)
                    Text(monitor.insight).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func networkPanel(_ items: [MetricKind]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Network activity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Circle().fill(accent).frame(width: 6, height: 6)
                Text("Live").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(items) { kind in
                    HStack(spacing: 9) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 28, height: 28)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(monitor.reading(for: kind))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if items.contains(.download) {
                NetworkSparkline(values: monitor.downloadHistory, color: accent)
                    .frame(height: 23)
                    .accessibilityLabel("Recent download activity")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 15))
    }

    private func metricCard(_ kind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: kind.symbol)
                    .foregroundStyle(accent).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(monitor.reading(for: kind))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(kind.title).font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(accent)
                        .frame(width: geometry.size.width * min(max(monitor.fraction(for: kind), 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 13))
    }

    private var customization: some View {
        VStack(alignment: .leading, spacing: 13) {
            profilesEditor
            menuItems
            sectionCard {
                sectionTitle("QUICK LAYOUTS")
                HStack(spacing: 7) {
                    ForEach(LayoutPreset.allCases) { preset in
                        Button(preset.title) { settings.apply(preset) }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                    }
                }
            }

            sectionCard {
                HStack {
                    sectionTitle("YOUR ITEMS")
                    Spacer()
                    Text("ORDER · PLACEMENT")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                ForEach(settings.configuration.metrics) { item in
                    metricRow(item)
                }
                if let message = settings.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            sectionCard {
                sectionTitle("MENU BAR APPEARANCE")
                HStack {
                    Text("Reading style").font(.caption)
                    Spacer()
                    Picker("Reading style", selection: Binding(
                        get: { settings.configuration.style },
                        set: { settings.setStyle($0) }
                    )) {
                        ForEach(MenuDisplayStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 145)
                }
                Toggle("Show Vitals icon", isOn: Binding(
                    get: { settings.configuration.showIcon },
                    set: { settings.setShowIcon($0) }
                ))
                Toggle("Preview hub icons in menu bar", isOn: Binding(
                    get: { settings.configuration.showHubPreview },
                    set: { settings.setShowHubPreview($0) }
                ))
                Text("Shows a few shortcuts beside your chosen readings. Click Vitals to open their menus.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Surface important readings", isOn: Binding(
                    get: { settings.configuration.smartPriority },
                    set: { settings.setSmartPriority($0) }
                ))
                Text("Low battery or sustained high CPU can temporarily take a menu-bar slot. Hidden items stay hidden.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("PREVIEW  \(previewText)")
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            sectionCard {
                sectionTitle("ACCENT COLOR")
                HStack(spacing: 8) {
                    ForEach(AccentTheme.allCases) { option in
                        Button {
                            settings.setTheme(option)
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(option.color).frame(width: 12, height: 12)
                                Text(option.title).font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(settings.configuration.theme == option
                                ? option.color.opacity(0.2) : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            sectionCard {
                sectionTitle("QUICK ACTIONS")
                ForEach(QuickAction.allCases) { action in
                    Toggle(action.title, isOn: Binding(
                        get: { settings.configuration.quickActions.contains(action) },
                        set: { settings.setQuickAction(action, enabled: $0) }
                    ))
                }
            }

            sectionCard {
                sectionTitle("STARTUP")
                Toggle("Launch Vitals at login", isOn: Binding(
                    get: { launchesAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginMessage {
                    Text(loginMessage).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var profilesEditor: some View {
        sectionCard {
            HStack {
                sectionTitle("SAVED MENU-BAR LAYOUTS")
                Spacer()
                if menuControl.hasUnsavedProfileChanges(configuration: settings.configuration) {
                    Text("Unsaved changes")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Text("Save your icons, hub order, readings and appearance together. Switch layouts from the Vitals popup.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !menuControl.profiles.isEmpty {
                ForEach(menuControl.profiles) { profile in
                    HStack {
                        Image(systemName: menuControl.activeProfileID == profile.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(menuControl.activeProfileID == profile.id ? accent : .secondary)
                        Text(profile.name).font(.caption.weight(.medium))
                        Spacer()
                        Button("Use") { menuControl.applyProfile(profile.id, settings: settings) }
                            .disabled(menuControl.isApplying || !menuControl.isSupported || !menuControl.isTrusted)
                    }
                }
            }
            HStack {
                TextField("New layout name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveProfile() }
                Button("Save new") { saveProfile() }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || menuControl.isApplying)
            }
            if let active = menuControl.activeProfile {
                HStack {
                    Button("Update \(active.name)") {
                        menuControl.updateActiveProfile(configuration: settings.configuration)
                    }
                    .disabled(!menuControl.hasUnsavedProfileChanges(configuration: settings.configuration) || menuControl.isApplying)
                    Spacer()
                    Button("Delete profile") { menuControl.deleteActiveProfile() }
                        .buttonStyle(.link)
                        .disabled(menuControl.isApplying)
                }
            }
        }
    }

    private func saveProfile() {
        menuControl.saveNewProfile(named: profileName, configuration: settings.configuration)
        profileName = ""
    }

    private var menuItems: some View {
        sectionCard {
            HStack {
                sectionTitle("YOUR MENU-BAR ICONS")
                Spacer()
                Text("\(menuControl.hiddenCount) tucked away")
                    .font(.caption2).foregroundStyle(.secondary)
                if menuControl.isScanning { ProgressView().controlSize(.small) }
                Button { menuControl.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Rescan menu-bar items")
                .accessibilityLabel("Rescan menu-bar items")
            }

            if !menuControl.isSupported {
                Label("Icon control needs macOS 27 and is unavailable on this build.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if !menuControl.isTrusted {
                Text("Allow this copy of Vitals in System Settings → Privacy & Security → Device Control and Data Access so it can control menu-bar icons.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Enable Accessibility") { menuControl.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Check again") { menuControl.refresh() }
                        .buttonStyle(.bordered)
                }
                Text("Access must be granted to this exact Vitals app. If you approved an older copy, add this one instead, then reopen it.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Running: \(Bundle.main.bundleURL.path)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Find an app", text: $iconSearch)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Text("HUB").frame(width: 28)
                    Text("HIDE").frame(width: 50)
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                if menuControl.apps.isEmpty && !menuControl.isScanning {
                    Text(menuControl.message ?? "No third-party icons found yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(menuControl.apps.filter {
                    iconSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(iconSearch)
                }) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 19, height: 19)
                        } else {
                            Image(systemName: "app").frame(width: 19, height: 19)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.caption.weight(.semibold))
                            if app.itemCount > 1 {
                                Text("\(app.itemCount) icons from this app")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            menuControl.setInHub(!menuControl.isInHub(app.id), for: app.id)
                        } label: {
                            Image(systemName: menuControl.isInHub(app.id) ? "star.fill" : "star")
                                .foregroundStyle(menuControl.isInHub(app.id) ? accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(menuControl.hiddenIDs.contains(app.id))
                        .help(menuControl.hiddenIDs.contains(app.id)
                              ? "Hidden apps always appear in Vitals"
                              : "Keep \(app.name) in the Vitals hub")
                        if menuControl.isInHub(app.id) {
                            let index = menuControl.hubApps.firstIndex(where: { $0.id == app.id }) ?? 0
                            VStack(spacing: 1) {
                                Button { menuControl.moveInHub(app.id, by: -1) } label: {
                                    Image(systemName: "chevron.up").frame(width: 18, height: 12)
                                }
                                .disabled(index == 0)
                                Button { menuControl.moveInHub(app.id, by: 1) } label: {
                                    Image(systemName: "chevron.down").frame(width: 18, height: 12)
                                }
                                .disabled(index == menuControl.hubApps.count - 1)
                            }
                            .buttonStyle(.plain)
                            .help("Change the order in Vitals")
                        }
                        Toggle("Hide \(app.name)", isOn: Binding(
                            get: { menuControl.hiddenIDs.contains(app.id) },
                            set: { menuControl.setHidden($0, for: app.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(menuControl.isApplying)
                    }
                    .padding(.vertical, 3)
                }
                Text("Star an app to keep it in Vitals. Hidden apps appear there automatically. Use the arrows to order your hub.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                sectionTitle("APPLE SYSTEM CONTROLS")
                ForEach(ControlledSystemItem.allCases) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(accent)
                            .frame(width: 19, height: 19)
                        Text(item.title).font(.caption.weight(.medium))
                        Spacer()
                        Toggle("Hide \(item.title)", isOn: Binding(
                            get: { menuControl.hiddenSystemIDs.contains(item.id) },
                            set: { menuControl.setSystemHidden($0, for: item.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(menuControl.isApplying)
                    }
                    .padding(.vertical, 2)
                }
                if !menuControl.hiddenIDs.isEmpty || !menuControl.hiddenSystemIDs.isEmpty {
                    HStack {
                        Circle().fill(menuControl.isRestrictionActive ? .green : .orange)
                            .frame(width: 7, height: 7)
                        Text(menuControl.isRevealed ? "Revealed" :
                             menuControl.isRestrictionActive ? "Applied" :
                             menuControl.isApplying ? "Applying" : "Not applied")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button(menuControl.isRevealed ? "Hide selected icons" : "Reveal all icons") {
                            if menuControl.isRevealed { menuControl.hideAgain() }
                            else { menuControl.reveal() }
                        }
                        .buttonStyle(.bordered)
                        Button("Reset icons") { menuControl.restoreAndClear() }
                            .buttonStyle(.link)
                    }
                    Text("Vitals briefly reveals icons when you hover over the clock so Notification Center can open. Reveal all if it doesn't.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message = menuControl.message, !menuControl.apps.isEmpty {
                    Text(message).font(.caption2).foregroundStyle(.orange)
                }
                Text("App toggles affect every icon from that app. Clock and Control Center stay protected. To change the Mac's physical icon order, hold ⌘ and drag icons in the menu bar.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hubShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps & controls")
                        .font(.subheadline.weight(.semibold))
                    Text("Your shortcuts, one click away")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openWindow(id: "customize")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Manage menu-bar icons")
            }
            if !menuControl.profiles.isEmpty {
                Menu {
                    ForEach(menuControl.profiles) { profile in
                        Button {
                            menuControl.applyProfile(profile.id, settings: settings)
                        } label: {
                            if menuControl.activeProfileID == profile.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(accent)
                        Text(menuControl.activeProfile?.name ?? "Choose a layout")
                            .font(.caption.weight(.medium)).lineLimit(1)
                        if menuControl.hasUnsavedProfileChanges(configuration: settings.configuration) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                }
                .disabled(menuControl.isApplying || !menuControl.isSupported || !menuControl.isTrusted)
            }
            if !menuControl.isSupported {
                Text("Icon control needs macOS 27. Your live readings still work.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !menuControl.isTrusted {
                Text("Allow this Vitals copy in Device Control and Data Access to use app shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Enable Accessibility") { menuControl.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Check again") { menuControl.refresh() }
                        .buttonStyle(.bordered)
                }
            } else {
                let hubApps = menuControl.hubApps
                let systemItems = ControlledSystemItem.allCases.filter {
                    menuControl.hiddenSystemIDs.contains($0.id)
                }
                if hubApps.isEmpty && systemItems.isEmpty {
                    Text("Star an app or tuck away an icon to add a shortcut here.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    if !hubApps.isEmpty {
                        sectionTitle("APPS")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                            ForEach(hubApps) { app in
                                ForEach(app.items) { item in
                                    Button {
                                        menuControl.openAppMenu(app.id, itemIndex: item.index)
                                    } label: {
                                        HubShortcutTile(title: app.itemCount == 1 ? app.name : item.title,
                                                        icon: app.icon, symbol: "app",
                                                        isHidden: menuControl.hiddenIDs.contains(app.id),
                                                        accent: accent)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(menuControl.openingItemID != nil)
                                    .help("Open \(app.name) menu")
                                    .accessibilityLabel("Open \(app.name) menu")
                                }
                            }
                        }
                    }
                    if !systemItems.isEmpty {
                        sectionTitle("SYSTEM CONTROLS")
                        HStack(spacing: 7) {
                            ForEach(systemItems) { item in
                                Button {
                                    menuControl.openSystemMenu(item)
                                } label: {
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(accent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                                .disabled(menuControl.openingItemID != nil)
                                .help("Open \(item.title)")
                                .accessibilityLabel("Open \(item.title)")
                            }
                        }
                    }
                }
                if menuControl.hiddenCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.caption2).foregroundStyle(accent)
                        Text("\(menuControl.hiddenCount) tucked away")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button(menuControl.isRevealed ? "Hide again" : "Reveal all") {
                            if menuControl.isRevealed { menuControl.hideAgain() }
                            else { menuControl.reveal() }
                        }
                        .font(.caption2.weight(.medium))
                        .buttonStyle(.link)
                    }
                }
                if let message = menuControl.message {
                    Text(message).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 15))
    }

    private var previewText: String {
        let visible = settings.menuMetrics(priority: monitor.priorityMetric)
        if visible.isEmpty { return "Vitals icon only" }
        return visible.map { kind in
            settings.configuration.style == .compact
                ? monitor.value(for: kind)
                : "\(kind.title) \(monitor.reading(for: kind))"
        }.joined(separator: "  ·  ")
    }

    private func metricRow(_ item: MetricPreference) -> some View {
        let index = settings.configuration.metrics.firstIndex(where: { $0.kind == item.kind }) ?? 0
        return HStack(spacing: 9) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title).font(.caption.weight(.semibold))
                Text(monitor.reading(for: item.kind))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            Picker(item.kind.title, selection: Binding(
                get: { settings.placement(for: item.kind) },
                set: { settings.setPlacement($0, for: item.kind) }
            )) {
                ForEach(MetricPlacement.allCases) { placement in
                    Text(placement.title).tag(placement)
                }
            }
            .labelsHidden()
            .frame(width: 112)
            VStack(spacing: 1) {
                Button { settings.move(item.kind, by: -1) } label: {
                    Image(systemName: "chevron.up").frame(width: 18, height: 14)
                }
                .disabled(index == 0)
                .help("Move \(item.kind.title) up")
                Button { settings.move(item.kind, by: 1) } label: {
                    Image(systemName: "chevron.down").frame(width: 18, height: 14)
                }
                .disabled(index == settings.configuration.metrics.count - 1)
                .help("Move \(item.kind.title) down")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 15))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1).foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            if configurationWindow {
                Label("Changes save automatically", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.configuration.quickActions) { action in
                    Button { open(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if configurationWindow {
                Button("Done") { dismissWindow(id: "customize") }
                    .buttonStyle(.link)
            } else {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(.quaternary.opacity(0.3))
    }

    private func open(_ action: QuickAction) {
        let path: String
        switch action {
        case .activityMonitor: path = "/System/Applications/Utilities/Activity Monitor.app"
        case .systemSettings: path = "/System/Applications/System Settings.app"
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Vitals in System Settings → General → Login Items."
                : nil
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = error.localizedDescription
        }
    }
}

private struct HubShortcutTile: View {
    let title: String
    let icon: NSImage?
    let symbol: String
    let isHidden: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 42, height: 42)
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable().interpolation(.high)
                            .frame(width: 25, height: 25)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 42, height: 42)
                if isHidden {
                    Circle().fill(accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }
            }
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.055)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct NetworkSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maximum = max(values.max() ?? 0, 1)
            var line = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * Double(index) / Double(values.count - 1)
                let y = size.height * (1 - min(value / maximum, 1))
                let point = CGPoint(x: x, y: y)
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
