import Combine
import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: VitalsModel
    @ObservedObject var license: LicenseManager
    let openSettings: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(model: model, keepAwake: model.keepAwake)

            if let message = model.message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if let check = model.leavingCheck {
                LeavingCheckCard(check: check, isPro: license.isPro,
                                 quitAll: { model.quitAll(check.all); model.dismissLeavingCheck() },
                                 dismiss: { withAnimation { model.dismissLeavingCheck() } },
                                 upgrade: { openSettings(.pro) })
            }

            ForEach(model.issues) { issue in
                IssueCard(issue: issue, close: {
                    withAnimation(.snappy) { model.hide(issue) }
                }) { action in
                    withAnimation(.snappy) { model.perform(action, on: issue) }
                }
            }

            if !model.lockedIssues.isEmpty {
                LockedIssuesCard(issues: model.lockedIssues) { openSettings(.pro) }
            }

            if let report = model.latestReport {
                AwayReportCard(report: report, isPro: license.isPro,
                               dismiss: { withAnimation { model.markReportSeen(report) } },
                               upgrade: { openSettings(.pro) })
            }

            if let forecast = model.forecast, show(.batteryPlanner) {
                BatteryPlannerCard(forecast: forecast, isPro: license.isPro,
                                   quit: { model.quitAll($0) }, upgrade: { openSettings(.pro) })
            }

            if let snapshot = model.snapshot {
                if show(.vitals) { VitalsGrid(snapshot: snapshot) }
                if show(.freeUpSpace) {
                    ToolsRow(space: model.space, openSpace: { model.openWindow?(.space) })
                }
                if show(.topApps) { TopAppsSection(snapshot: snapshot, quit: { model.quit($0) }) }
            }

            if let release = model.updates.available {
                Button {
                    model.updates.openDownload()
                } label: {
                    Label("Vitals \(release.version) is available — download", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            FooterView(license: license, openSettings: openSettings)
        }
        .padding(14)
        .frame(width: 368)
        .animation(.snappy, value: model.issues)
    }

    private func show(_ section: PopoverSection) -> Bool {
        !model.settings.hiddenSections.contains(section)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @ObservedObject var model: VitalsModel
    @ObservedObject var keepAwake: KeepAwake

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(model.severity.color.gradient).frame(width: 40, height: 40)
                Image(systemName: model.severity == .calm ? "checkmark" : "waveform.path.ecg")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if keepAwake.isOn {
                    Button("Stop keeping awake") { keepAwake.stop() }
                    Divider()
                }
                Button("Keep awake for 30 minutes") { model.startKeepAwake(1800) }
                Button("Keep awake for 1 hour") { model.startKeepAwake(3600) }
                Button("Keep awake for 3 hours") { model.startKeepAwake(3 * 3600) }
                Button("Keep awake until I turn it off") { model.startKeepAwake(nil) }
                Divider()
                Toggle("Let the display sleep", isOn: $model.settings.keepAwakeAllowsDisplaySleep)
            } label: {
                Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(keepAwake.isOn ? Color.orange : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(keepAwake.statusText ?? "Keep your Mac awake")
        }
    }

    private var title: String {
        let count = model.issues.filter { $0.severity >= .warning }.count
        switch model.severity {
        case .calm: return "Your Mac is healthy"
        case .notice: return model.issues.count == 1 ? "One small heads-up" : "\(model.issues.count) small heads-ups"
        case .warning, .critical: return count == 1 ? "One thing needs your attention" : "\(count) things need your attention"
        }
    }

    private var subtitle: String {
        guard let snap = model.snapshot else { return "Checking…" }
        var parts = [keepAwake.statusText ?? "Watching quietly"]
        if snap.thermal >= .fair { parts.append(snap.thermal.title) }
        if let battery = snap.battery {
            if battery.isOnAC {
                parts.append(battery.isCharging ? "Charging" : "Plugged in")
            } else if let minutes = battery.minutesRemaining {
                parts.append("\(Format.duration(TimeInterval(minutes * 60))) left")
            }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Issue card

struct IssueCard: View {
    let issue: Issue
    let close: () -> Void
    let perform: (IssueAction) -> Void
    @State private var hovering = false

    var body: some View {
        Card(accent: issue.severity.color) {
            HStack(alignment: .top, spacing: 10) {
                AppIconView(identity: issue.subject, fallbackSymbol: issue.kind.symbol, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(issue.headline).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 4)
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(Color.secondary.opacity(hovering ? 0.18 : 0), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering = $0 }
                        .help("Hide until this happens again")
                    }
                    Text(issue.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(Array(issue.actions.prefix(2).enumerated()), id: \.offset) { index, action in
                            let label = title(for: action)
                            if index == 0 {
                                Button(label) { perform(action) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(issue.severity.color)
                            } else {
                                Button(label) { perform(action) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        if issue.actions.count > 2 {
                            Menu {
                                ForEach(Array(issue.actions.dropFirst(2)), id: \.self) { action in
                                    Button(title(for: action)) { perform(action) }
                                }
                                if issue.subject?.canQuit == true {
                                    Button("Force Quit") { perform(.forceQuitApp) }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func title(for action: IssueAction) -> String {
        switch action {
        case .quitApp: "Quit \(Format.shortName(issue.subject?.name ?? "App"))"
        case .ignoreApp: "Always ignore \(Format.shortName(issue.subject?.name ?? "this app"))"
        default: action.title
        }
    }
}

// MARK: - Locked (Pro) issues

private struct LockedIssuesCard: View {
    let issues: [Issue]
    let upgrade: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(issues.count == 1 ? "Vitals found 1 battery issue" : "Vitals found \(issues.count) battery issues")
                            .font(.system(size: 12.5, weight: .semibold))
                        ProBadge()
                    }
                    Text(Set(issues.map(\.kind.title)).sorted().joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Unlock", action: upgrade).controlSize(.small)
            }
        }
    }
}

// MARK: - Away report

struct AwayReportCard: View {
    let report: AwayReport
    let isPro: Bool
    let dismiss: () -> Void
    let upgrade: () -> Void

    var body: some View {
        Card(accent: report.verdict == .unusual ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("While you were away", systemImage: "moon.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Text(report.headline).font(.system(size: 13, weight: .semibold))
                if isPro {
                    Text(report.explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(report.consumers.prefix(3)) { consumer in
                        HStack(spacing: 8) {
                            AppIconView(identity: consumer.bundlePath.map {
                                AppIdentity(key: consumer.key, name: consumer.name, bundlePath: $0, bundleID: nil, isSystem: false)
                            }, fallbackSymbol: "gearshape", size: 16)
                            Text(consumer.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            ProgressView(value: consumer.share).frame(width: 70)
                            Text(Format.percent(consumer.share))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                } else {
                    HStack {
                        Text("See what drained it and what kept your Mac awake.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Unlock", action: upgrade).controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Vitals grid

private struct VitalsGrid: View {
    let snapshot: SystemSnapshot

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            Tile(symbol: "cpu", title: "CPU", value: Format.percent(snapshot.cpuTotal),
                 caption: snapshot.thermal >= .fair ? snapshot.thermal.title : "Load",
                 fraction: snapshot.cpuTotal)
            Tile(symbol: "memorychip", title: "Memory", value: Format.percent(snapshot.memoryUsed),
                 caption: "Pressure: \(snapshot.memoryPressure.title)", fraction: snapshot.memoryUsed,
                 warn: snapshot.memoryPressure >= .warning)
            if let battery = snapshot.battery {
                Tile(symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                     title: "Battery", value: Format.percent(battery.level),
                     caption: batteryCaption(battery), fraction: battery.level, warn: battery.level < 0.2 && !battery.isOnAC)
            } else {
                Tile(symbol: "powerplug", title: "Power", value: "AC", caption: "No battery")
            }
            Tile(symbol: "internaldrive", title: "Disk", value: snapshot.diskFreeBytes.map { Format.diskBytes($0) } ?? "—",
                 caption: "free", fraction: diskUsedFraction)
            Tile(symbol: "arrow.down.circle", title: "Network", value: Format.rate(snapshot.downloadRate),
                 caption: "↑ \(Format.rate(snapshot.uploadRate))")
            Tile(symbol: "clock.arrow.circlepath", title: "Uptime", value: Format.duration(snapshot.uptime),
                 caption: "since restart")
        }
    }

    private var diskUsedFraction: Double? {
        guard let free = snapshot.diskFreeBytes, let total = snapshot.diskTotalBytes, total > 0 else { return nil }
        return 1 - Double(free) / Double(total)
    }

    private func batteryCaption(_ battery: BatteryState) -> String {
        if battery.isOnAC { return battery.isCharging ? "Charging" : "Plugged in" }
        if let watts = battery.dischargeWatts { return "Using \(Format.watts(watts))" }
        if let minutes = battery.minutesRemaining { return "\(Format.duration(TimeInterval(minutes * 60))) left" }
        return "On battery"
    }
}

private struct Tile: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String
    var fraction: Double? = nil
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(warn ? .orange : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(warn ? .orange : .accentColor)
                    .controlSize(.mini)
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Top apps

private struct TopAppsSection: View {
    let snapshot: SystemSnapshot
    let quit: (AppIdentity) -> Void
    @State private var expanded = false
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Using your Mac right now").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if snapshot.perAppAvailable {
                    ForEach(Array(snapshot.apps.prefix(6)), id: \.identity.key) { app in
                        HStack(spacing: 8) {
                            AppIconView(identity: app.identity, fallbackSymbol: "gearshape", size: 18)
                            Text(app.identity.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            if hovered == app.identity.key && app.identity.canQuit {
                                Button("Quit") { quit(app.identity) }
                                    .controlSize(.mini)
                            }
                            Text(Format.bytes(app.memoryBytes))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(Format.cpu(app.cpuPercent))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                        }
                        .onHover { inside in hovered = inside ? app.identity.key : (hovered == app.identity.key ? nil : hovered) }
                    }
                } else {
                    Text("Per-app details aren't available in this build. Activity Monitor shows them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    @ObservedObject var license: LicenseManager
    let openSettings: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { openSettings(.general) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
            Button { SystemActions.openActivityMonitor() } label: { Image(systemName: "chart.bar.xaxis") }
                .buttonStyle(.borderless)
                .help("Open Activity Monitor")
            Spacer()
            switch license.state {
            case .pro:
                ProBadge()
            case .trial(let days):
                Button("Pro trial · \(days) day\(days == 1 ? "" : "s") left") { openSettings(.pro) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            case .free:
                Button("Upgrade to Pro") { openSettings(.pro) }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
            }
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
                .help("Quit Vitals")
        }
        .foregroundStyle(.secondary)
    }
}
