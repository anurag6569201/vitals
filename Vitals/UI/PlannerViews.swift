import AppKit
import Combine
import SwiftUI

/// "Will my battery last?" — when it runs out, and what to quit to make it to a time you pick.
struct BatteryPlannerCard: View {
    let forecast: BatteryForecast
    let isPro: Bool
    let quit: ([AppIdentity]) -> Void
    let upgrade: () -> Void
    @State private var planning = false
    @State private var target = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "battery.75percent").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Battery lasts until \(forecast.emptyAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 13, weight: .semibold))
                        Text("About \(Format.duration(forecast.emptyAt.timeIntervalSince(forecast.now))) at \(Int(forecast.ratePerHour.rounded()))% an hour")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(planning ? "Done" : "Need longer?") {
                        if isPro { withAnimation(.snappy) { planning.toggle() } } else { upgrade() }
                    }
                    .controlSize(.small)
                }
                if planning {
                    HStack {
                        Text("I need it until").font(.callout)
                        DatePicker("", selection: $target, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                    planView
                }
            }
        }
    }

    @ViewBuilder
    private var planView: some View {
        let plan = forecast.plan(until: target)
        let fine: Bool = { if case .fine = plan { return true }; return false }()
        planMessage(plan)
        if !fine { lowPowerHint(plan) }
    }

    /// TurtleBar-style nudge: would Low Power Mode get you there? Vitals can't switch it on for you
    /// (that needs an administrator), so it opens Battery settings.
    @ViewBuilder
    private func lowPowerHint(_ plan: BatteryForecast.Plan) -> some View {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            Label("Low Power Mode is already on.", systemImage: "leaf.fill")
                .font(.caption).foregroundStyle(.secondary)
        } else if case .quit = plan {
            // Quitting already works; offer Low Power Mode as the alternative if it would do on its own.
            let reach = forecast.emptyAtWithLowPower()
            if reach >= target {
                lowPowerRow("Or keep your apps open and turn on Low Power Mode instead (about \(reach.formatted(date: .omitted, time: .shortened))).")
            }
        } else {
            let reach = forecast.emptyAtWithLowPower(quitting: forecast.savers)
            lowPowerRow(reach >= target
                        ? "\(forecast.savers.isEmpty ? "Low Power Mode" : "Quitting them and turning on Low Power Mode") should get you there (about \(reach.formatted(date: .omitted, time: .shortened)))."
                        : "Low Power Mode would stretch it to about \(reach.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private func lowPowerRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "leaf").foregroundStyle(.green)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Battery Settings") { SystemActions.openBatterySettings() }
                .buttonStyle(.link).font(.caption)
        }
    }

    @ViewBuilder
    private func planMessage(_ plan: BatteryForecast.Plan) -> some View {
        switch plan {
        case .fine(let spare):
            Label("You'll make it, with about \(Format.duration(spare)) to spare.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case .quit(let savers, let until):
            VStack(alignment: .leading, spacing: 6) {
                Label("Not at this rate. Quit \(LeavingCheck.list(savers.map(\.identity.name))) and it should last until \(until.formatted(date: .omitted, time: .shortened)).",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Quit \(savers.count == 1 ? Format.shortName(savers[0].identity.name) : "them")") {
                    quit(savers.map(\.identity))
                }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            }
        case .plugIn(let by):
            Label(forecast.savers.isEmpty
                  ? "Not at this rate. Plug in by \(by.formatted(date: .omitted, time: .shortened))."
                  : "Even quitting the big apps won't get you there. Plug in by \(by.formatted(date: .omitted, time: .shortened)).",
                  systemImage: "powerplug.fill")
                .foregroundStyle(.red).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Right after unplugging: things that would keep the Mac awake and warm in a bag.
struct LeavingCheckCard: View {
    let check: LeavingCheck
    let isPro: Bool
    let quitAll: () -> Void
    let dismiss: () -> Void
    let upgrade: () -> Void

    var body: some View {
        Card(accent: .orange) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Label(isPro ? check.headline : "Before you go: Vitals spotted something", systemImage: "backpack")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if isPro {
                    Text(check.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(Edition.canQuitApps
                           ? "Quit \(check.all.count == 1 ? Format.shortName(check.all[0].name) : "all \(check.all.count)")"
                           : "Show in Activity Monitor", action: quitAll)
                        .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                } else {
                    HStack {
                        Text("An app would keep your Mac awake in your bag.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) { ProBadge(); Button("See", action: upgrade).controlSize(.small) }
                    }
                }
            }
        }
    }
}

/// Shortcut to Free Up Space.
struct ToolsRow: View {
    @ObservedObject var space: SpaceModel
    let openSpace: () -> Void

    var body: some View {
        Button(action: openSpace) {
            HStack {
                Label("Free up space", systemImage: "externaldrive.badge.minus")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if space.reviewableTotal > 0 {
                    Text("\(Format.diskBytes(space.reviewableTotal)) found")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .hoverLift(1.01)
    }
}

/// One-click access to menu-bar icons you've hidden (or starred) from the Menu Bar settings.
struct MenuBarShortcuts: View {
    @ObservedObject var control: MenuBarControl

    private var systemItems: [ControlledSystemItem] {
        ControlledSystemItem.allCases.filter { control.hiddenSystemIDs.contains($0.id) }
    }

    var body: some View {
        if Edition.canHideMenuBarIcons, !control.hubApps.isEmpty || !systemItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Menu bar").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if control.isRevealed {
                        Button("Hide again") { control.hideAgain() }.buttonStyle(.borderless).font(.caption)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(control.hubApps) { app in
                        ForEach(app.items) { item in
                            tile(title: app.itemCount > 1 ? item.title : app.name,
                                 image: Image(nsImage: app.icon ?? NSImage()),
                                 busy: control.openingItemID == item.id) {
                                control.openAppMenu(app.id, itemIndex: item.index)
                            }
                        }
                    }
                    ForEach(systemItems) { item in
                        tile(title: item.title, image: Image(systemName: item.symbol),
                             busy: control.openingItemID == "system#\(item.id)") {
                            control.openSystemMenu(item)
                        }
                    }
                }
            }
        }
    }

    private func tile(title: String, image: Image, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    image.resizable().scaledToFit().frame(width: 20, height: 20)
                    if busy { ProgressView().controlSize(.mini) }
                }
                .frame(width: 34, height: 30)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                Text(title).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
