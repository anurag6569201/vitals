import AppKit
import Charts
import SwiftUI

private let downColor = Color(red: 0.25, green: 0.55, blue: 1.0)
private let upColor = Color(red: 0.75, green: 0.42, blue: 1.0)

// MARK: - Popover section

/// Popover section: where your data went, today or over the last week or month.
struct NetworkSection: View {
    @ObservedObject var tracker: NetworkUsageTracker
    var hotspotLimitMB: Int? = nil
    let isPro: Bool
    let upgrade: () -> Void
    let openDetails: () -> Void
    @State private var span: NetworkUsageTracker.Span = .today

    var body: some View {
        let total = tracker.total(span)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Where your data went").font(.system(size: 12, weight: .semibold))
                Spacer()
                NetworkSpanPicker(span: $span, isPro: isPro, upgrade: upgrade)
                    .frame(width: 150)
            }

            if tracker.onMeteredConnection, let limitMB = hotspotLimitMB {
                HotspotBanner(used: tracker.meteredBytes, limit: Double(limitMB) * 1_000_000)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                NetworkFigure(symbol: "arrow.down", color: downColor, value: total.down, caption: "down")
                NetworkFigure(symbol: "arrow.up", color: upColor, value: total.up, caption: "up")
                Spacer()
                if let last = tracker.live.last {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("↓ \(Format.rate(last.down))").font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        Text("↑ \(Format.rate(last.up))").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .help("Speed right now")
                }
            }

            NetworkBars(points: tracker.series(span), span: span)
                .frame(height: 44)
                .animation(Motion.spring, value: span)

            if NetworkUsageTracker.perAppAvailable {
                let apps = tracker.appEntries(span)
                if apps.isEmpty {
                    Text("Apps appear here as they use the network.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    let top = apps.first?.total ?? 1
                    ForEach(apps.prefix(3)) { app in NetworkAppRow(app: app, top: top, compact: true) }
                }
            } else {
                ConnectionChips(total: total)
            }

            Button(action: openDetails) {
                HStack(spacing: 4) {
                    Text("See the full breakdown")
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}

/// Shown while on an iPhone hotspot or other metered connection.
private struct HotspotBanner: View {
    let used: Double
    let limit: Double

    var body: some View {
        let fraction = limit > 0 ? used / limit : 0
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .teal)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "personalhotspot").foregroundStyle(tint)
                Text("On a hotspot").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("\(Format.bytes(UInt64(used))) of \(Format.bytes(UInt64(limit)))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(fraction >= 0.8 ? tint : .secondary)
                    .contentTransition(.numericText())
            }
            AnimatedBar(value: fraction, tint: tint, height: 4)
        }
        .padding(8)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(Motion.spring, value: used)
    }
}

private struct NetworkSpanPicker: View {
    @Binding var span: NetworkUsageTracker.Span
    let isPro: Bool
    let upgrade: () -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { span },
            set: { value in if value != .today && !isPro { upgrade() } else { span = value } })) {
            ForEach(NetworkUsageTracker.Span.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
    }
}

private struct NetworkFigure: View {
    let symbol: String
    let color: Color
    let value: Double
    let caption: String
    var large = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: large ? 13 : 10, weight: .heavy))
                .foregroundStyle(color)
            Text(Format.bytes(UInt64(max(0, value))))
                .font(.system(size: large ? 26 : 17, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(caption).font(.system(size: large ? 12 : 10)).foregroundStyle(.secondary)
        }
        .animation(.snappy, value: value)
    }
}

/// Compact stacked bars: hours of today, or days of the span.
private struct NetworkBars: View {
    let points: [NetworkUsageTracker.Point]
    let span: NetworkUsageTracker.Span

    var body: some View {
        let peak = max(points.map { $0.down + $0.up }.max() ?? 0, 1)
        let current = span == .today ? Calendar.current.component(.hour, from: Date()) : points.count - 1
        GeometryReader { geo in
            let gap: CGFloat = points.count > 24 ? 1.5 : 2.5
            let width = max(1, (geo.size.width - gap * CGFloat(points.count - 1)) / CGFloat(max(points.count, 1)))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let h = geo.size.height
                    let total = point.down + point.up
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if total > 0 {
                            RoundedRectangle(cornerRadius: 1.5).fill(upColor.opacity(index == current ? 1 : 0.75))
                                .frame(height: max(1, h * point.up / peak))
                            RoundedRectangle(cornerRadius: 1.5).fill(downColor.opacity(index == current ? 1 : 0.75))
                                .frame(height: max(1.5, h * point.down / peak))
                        } else {
                            RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(index > current ? 0.04 : 0.08))
                                .frame(height: 2)
                        }
                    }
                    .frame(width: width)
                    .help(tooltip(point))
                }
            }
            .animation(Motion.gauge, value: points)
        }
    }

    private func tooltip(_ point: NetworkUsageTracker.Point) -> String {
        let when = span == .today
            ? point.id.formatted(date: .omitted, time: .shortened)
            : point.id.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(when): ↓ \(Format.bytes(UInt64(point.down)))  ↑ \(Format.bytes(UInt64(point.up)))"
    }
}

private struct ConnectionChips: View {
    let total: NetworkUsageTracker.Bucket

    var body: some View {
        let parts = NetworkUsageTracker.Connection.allCases.compactMap { kind -> (NetworkUsageTracker.Connection, Double)? in
            let value = total.byConnection[kind.rawValue] ?? 0
            return value > 0 ? (kind, value) : nil
        }
        if parts.isEmpty {
            Text("Vitals counts what this Mac sends and receives while it's running.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(parts, id: \.0) { kind, value in
                    Label("\(kind.title) \(Format.bytes(UInt64(value)))", systemImage: kind.symbol)
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
    }
}

private struct NetworkAppRow: View {
    let app: NetworkUsageTracker.AppEntry
    let top: Double
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
            Text(app.id).font(.system(size: compact ? 12 : 13)).lineLimit(1)
                .frame(width: compact ? 110 : 170, alignment: .leading)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    Capsule().fill(downColor).frame(width: max(2, geo.size.width * app.down / top))
                    Capsule().fill(upColor).frame(width: max(app.up > 0 ? 2 : 0, geo.size.width * app.up / top))
                }
                .frame(height: compact ? 5 : 7)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)
            Text(Format.bytes(UInt64(app.total)))
                .font(.system(size: compact ? 11 : 12, weight: .medium).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
        .help("↓ \(Format.bytes(UInt64(app.down)))  ↑ \(Format.bytes(UInt64(app.up)))")
    }

    @ViewBuilder private var icon: some View {
        if let url = app.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "gearshape.2.fill").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window

/// The full picture: live speed, a chart, totals, and what used the data.
struct NetworkWindowView: View {
    @ObservedObject var tracker: NetworkUsageTracker
    let isPro: Bool
    let upgrade: () -> Void
    @State private var span: NetworkUsageTracker.Span = .today
    @State private var showAllApps = false

    var body: some View {
        let total = tracker.total(span)
        let series = tracker.series(span)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(total).vitalsAppear(0)
                chart(series).vitalsAppear(1)
                    .animation(Motion.spring, value: span)
                stats(total, series).vitalsAppear(2)
                if NetworkUsageTracker.perAppAvailable && !tracker.appsSinceOpened.isEmpty {
                    OpenAppsPanel(tracker: tracker)
                }
                HStack(alignment: .top, spacing: 16) {
                    connections(total).frame(maxWidth: .infinity, alignment: .topLeading)
                    apps.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .vitalsAppear(4)
                privacy
            }
            .padding(22)
        }
        .frame(minWidth: 680, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ total: NetworkUsageTracker.Bucket) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where your data went").font(.system(size: 22, weight: .bold))
                HStack(spacing: 22) {
                    NetworkFigure(symbol: "arrow.down", color: downColor, value: total.down, caption: "downloaded", large: true)
                    NetworkFigure(symbol: "arrow.up", color: upColor, value: total.up, caption: "uploaded", large: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                NetworkSpanPicker(span: $span, isPro: isPro, upgrade: upgrade).frame(width: 220).controlSize(.regular)
                LiveCard(tracker: tracker)
            }
        }
    }

    private func chart(_ series: [NetworkUsageTracker.Point]) -> some View {
        Chart {
            ForEach(series) { point in
                BarMark(x: .value("When", point.id, unit: span == .today ? .hour : .day),
                        y: .value("Downloaded", point.down))
                    .foregroundStyle(by: .value("Direction", "Downloaded"))
                    .cornerRadius(2)
                BarMark(x: .value("When", point.id, unit: span == .today ? .hour : .day),
                        y: .value("Uploaded", point.up))
                    .foregroundStyle(by: .value("Direction", "Uploaded"))
                    .cornerRadius(2)
            }
        }
        .chartForegroundStyleScale(["Downloaded": downColor, "Uploaded": upColor])
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let bytes = value.as(Double.self) { Text(Format.bytes(UInt64(max(0, bytes)))) }
                }
            }
        }
        .chartXAxis {
            if span == .today {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: span == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 200)
        .padding(14)
        .background(panel)
    }

    private func stats(_ total: NetworkUsageTracker.Bucket, _ series: [NetworkUsageTracker.Point]) -> some View {
        let active = series.filter { $0.down + $0.up > 0 }
        let busiest = tracker.busiest(span)
        let average = active.isEmpty ? 0 : total.total / Double(active.count)
        return HStack(spacing: 12) {
            StatTile(title: "Total", value: Format.bytes(UInt64(total.total)), symbol: "arrow.up.arrow.down", tint: downColor)
            StatTile(title: span == .today ? "Busiest hour" : "Busiest day",
                     value: busiest.map { span == .today
                        ? $0.id.formatted(date: .omitted, time: .shortened)
                        : $0.id.formatted(.dateTime.weekday(.abbreviated).day()) } ?? "—",
                     detail: busiest.map { Format.bytes(UInt64($0.down + $0.up)) },
                     symbol: "flame", tint: .orange)
            StatTile(title: span == .today ? "Per active hour" : "Per active day",
                     value: Format.bytes(UInt64(average)), symbol: "chart.bar", tint: .teal)
            StatTile(title: "Upload share",
                     value: total.total > 0 ? Format.percent(total.up / total.total) : "—",
                     symbol: "icloud.and.arrow.up", tint: upColor)
        }
    }

    private func connections(_ total: NetworkUsageTracker.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By connection").font(.headline)
            let sum = max(NetworkUsageTracker.Connection.allCases
                .filter { $0 != .vpn }.reduce(0) { $0 + (total.byConnection[$1.rawValue] ?? 0) }, 1)
            ForEach(NetworkUsageTracker.Connection.allCases) { kind in
                let value = total.byConnection[kind.rawValue] ?? 0
                if value > 0 || kind == .wifi {
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                        Text(kind.title).frame(width: 60, alignment: .leading)
                        ProgressView(value: min(value / sum, 1)).tint(kind == .vpn ? .green : downColor)
                        Text(Format.bytes(UInt64(value))).font(.callout.monospacedDigit()).frame(width: 72, alignment: .trailing)
                    }
                }
            }
            if tracker.vpnActive || (total.byConnection[NetworkUsageTracker.Connection.vpn.rawValue] ?? 0) > 0 {
                Text("VPN traffic also travels over Wi‑Fi or wired, so it isn't counted twice in the totals.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel)
    }

    @ViewBuilder private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By app").font(.headline)
            if NetworkUsageTracker.perAppAvailable {
                let entries = tracker.appEntries(span)
                if entries.isEmpty {
                    Text("Apps appear here as they use the network.").font(.callout).foregroundStyle(.secondary)
                } else {
                    let top = entries.first?.total ?? 1
                    ForEach(entries.prefix(showAllApps ? 40 : 8)) { NetworkAppRow(app: $0, top: top) }
                    if entries.count > 8 {
                        Button(showAllApps ? "Show less" : "Show all \(entries.count)") {
                            withAnimation(.snappy) { showAllApps.toggle() }
                        }
                        .buttonStyle(.link)
                    }
                }
            } else {
                Label("macOS keeps each app's network use private from App Store apps, so this edition shows totals by connection instead.",
                      systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel)
    }

    private var privacy: some View {
        Label("Counted on this Mac while Vitals is running, and never sent anywhere. Websites aren't listed: no Mac app can see them without installing a VPN-style network filter, and Vitals won't do that.",
              systemImage: "hand.raised")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Window panel (direct edition): apps that are still open, counted since each one started —
/// so this includes time before Vitals was running.
private struct OpenAppsPanel: View {
    @ObservedObject var tracker: NetworkUsageTracker

    var body: some View {
        let apps = tracker.appsSinceOpened
        let top = apps.first?.total ?? 1
        VStack(alignment: .leading, spacing: 10) {
            Label("Open apps, since each one started", systemImage: "clock.arrow.circlepath").font(.headline)
            ForEach(apps.prefix(8)) { NetworkAppRow(app: $0, top: top) }
            Text("Counted by macOS for each running app, including time before Vitals started. Apps you've quit are no longer listed here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07))))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.18)))
        .hoverLift(1.025)
        .animation(Motion.spring, value: value)
    }
}

/// Live speed with a two-minute sparkline.
private struct LiveCard: View {
    @ObservedObject var tracker: NetworkUsageTracker

    var body: some View {
        HStack(spacing: 10) {
            Chart {
                ForEach(tracker.live) { point in
                    AreaMark(x: .value("t", point.id), y: .value("down", point.down))
                        .foregroundStyle(downColor.opacity(0.35).gradient)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", point.id), y: .value("down", point.down))
                        .foregroundStyle(downColor)
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 110, height: 34)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Live").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text("↓ \(Format.rate(tracker.live.last?.down ?? 0))").font(.system(size: 12, weight: .semibold).monospacedDigit())
                Text("↑ \(Format.rate(tracker.live.last?.up ?? 0))").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
    }
}
