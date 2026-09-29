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
        switch forecast.plan(until: target) {
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
            Label("Even quitting the big apps won't get you there. Plug in by \(by.formatted(date: .omitted, time: .shortened)).",
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
                    Button("Quit \(check.all.count == 1 ? Format.shortName(check.all[0].name) : "all \(check.all.count)")", action: quitAll)
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

/// Shortcuts to the bigger tools.
struct ToolsRow: View {
    let openReceipt: () -> Void
    let openSpace: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            tool("Battery receipt", symbol: "receipt", action: openReceipt)
            tool("Space hogs", symbol: "externaldrive.badge.minus", action: openSpace)
        }
    }

    private func tool(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
