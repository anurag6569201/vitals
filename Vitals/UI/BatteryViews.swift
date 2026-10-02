import AppKit
import Charts
import Combine
import SwiftUI

/// Popover row that opens the Battery window.
struct BatteryRow: View {
    let battery: BatteryState
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Label("Battery health", systemImage: "heart.text.square")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(summary)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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

    private var summary: String {
        var parts: [String] = []
        if let health = battery.health { parts.append(Format.percent(health)) }
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        return parts.joined(separator: " · ")
    }
}

/// Battery window: charge, health, cycles and how they've changed over time.
struct BatteryWindowView: View {
    @ObservedObject var model: VitalsModel
    @ObservedObject var log: BatteryHealthLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let battery = model.snapshot?.battery {
                    header(battery).vitalsAppear(0)
                    HStack(alignment: .top, spacing: 12) {
                        healthCard(battery)
                        cyclesCard(battery)
                    }
                    .vitalsAppear(1)
                    historyCard.vitalsAppear(2)
                    tipsCard.vitalsAppear(3)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "powerplug").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("This Mac doesn't have a battery.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private func header(_ battery: BatteryState) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle().trim(from: 0, to: battery.level)
                    .stroke(levelColor(battery).gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.spring, value: battery.level)
                VStack(spacing: 0) {
                    Text(Format.percent(battery.level)).font(.system(size: 20, weight: .bold).monospacedDigit())
                    if battery.isCharging { Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.green) }
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text("Battery").font(.system(size: 22, weight: .bold))
                Text(status(battery)).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if ProcessInfo.processInfo.isLowPowerModeEnabled {
                        Label("Low Power Mode on", systemImage: "leaf.fill").foregroundStyle(.green)
                    }
                    if let watts = battery.dischargeWatts {
                        Label("Using \(Format.watts(watts))", systemImage: "bolt")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func status(_ battery: BatteryState) -> String {
        if battery.isCharging {
            if let minutes = battery.minutesToFull { return "Charging · full in \(Format.duration(TimeInterval(minutes * 60)))" }
            return "Charging"
        }
        if battery.isOnAC { return "Plugged in, not charging" }
        if let minutes = battery.minutesRemaining { return "On battery · about \(Format.duration(TimeInterval(minutes * 60))) left" }
        return "On battery"
    }

    private func levelColor(_ battery: BatteryState) -> Color {
        if battery.isCharging || battery.level >= 0.5 { return .green }
        return battery.level >= 0.2 ? .orange : .red
    }

    // MARK: Cards

    private func healthCard(_ battery: BatteryState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Health", systemImage: "heart.text.square").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let health = battery.health {
                    Text(Format.percent(health)).font(.system(size: 26, weight: .bold).monospacedDigit())
                    ProgressView(value: health).tint(health >= BatteryHealthLog.serviceThreshold ? .green : .orange)
                    Text(health >= BatteryHealthLog.serviceThreshold
                         ? "Normal. It holds \(Format.percent(health)) of the charge it held when new."
                         : "Below 80% of its original capacity. Apple may recommend a battery service.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not reported").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cyclesCard(_ battery: BatteryState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Charge cycles", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let cycles = battery.cycleCount {
                    Text("\(cycles)").font(.system(size: 26, weight: .bold).monospacedDigit())
                    ProgressView(value: min(Double(cycles) / Double(BatteryHealthLog.ratedCycles), 1))
                        .tint(cycles < BatteryHealthLog.ratedCycles ? .accentColor : .orange)
                    Text(cyclesCaption(cycles))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not reported").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cyclesCaption(_ cycles: Int) -> String {
        var text = "Of about \(BatteryHealthLog.ratedCycles.formatted()) that Apple rates current MacBook batteries for."
        if let perMonth = log.cyclesPerMonth, perMonth > 0.5 {
            text += " You use about \(Int(perMonth.rounded())) a month."
        }
        return text
    }

    // MARK: History

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Health over time").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let first = log.first {
                        Text("Since \(first.day.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if log.entries.count >= 2 {
                    chart
                    if let loss = log.yearlyLoss {
                        Text(loss < 0.005 ? "Holding steady — no measurable loss so far."
                             : "Losing about \(String(format: "%.1f", loss * 100)) points a year at this rate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.secondary)
                        Text("Vitals saves one reading a day, on this Mac only. Check back in a few weeks to see how your battery is ageing.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private var chart: some View {
        let low = max(0, (log.entries.map(\.health).min() ?? 0.8) - 0.05)
        let lower = min(low, BatteryHealthLog.serviceThreshold - 0.02)
        return Chart {
            ForEach(log.entries) { entry in
                AreaMark(x: .value("Day", entry.day, unit: .day),
                         yStart: .value("Base", lower), yEnd: .value("Health", entry.health))
                    .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.25), Color.green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", entry.day, unit: .day), y: .value("Health", entry.health))
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Service", BatteryHealthLog.serviceThreshold))
                .foregroundStyle(Color.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("80% — service recommended").font(.system(size: 9)).foregroundStyle(.orange)
                }
        }
        .chartYScale(domain: lower...1.0)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Format.percent(v)) }
                }
            }
        }
        .frame(height: 180)
    }

    // MARK: Tips

    private var tipsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Make it last").font(.system(size: 14, weight: .semibold))
                tip("leaf", "Low Power Mode stretches a charge when you're away from a plug. Vitals' battery planner tells you when it would make the difference.")
                tip("bolt.batteryblock", "Optimized Battery Charging lets macOS learn your routine and hold the charge below full until you need it, which slows ageing.")
                tip("thermometer.medium", "Heat ages batteries fastest. Vitals warns you when your Mac runs hot.")
                HStack {
                    Spacer()
                    Button("Open Battery Settings") { SystemActions.openBatterySettings() }
                }
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
