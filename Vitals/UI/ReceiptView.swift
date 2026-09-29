import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum ReceiptStyle: String, CaseIterable, Identifiable {
    case thermal, midnight, retro

    var id: String { rawValue }
    var title: String {
        switch self {
        case .thermal: "Thermal"
        case .midnight: "Midnight"
        case .retro: "Diner"
        }
    }
    var isPro: Bool { self != .thermal }
    var paper: Color {
        switch self {
        case .thermal: Color(red: 0.98, green: 0.975, blue: 0.96)
        case .midnight: Color(red: 0.09, green: 0.10, blue: 0.12)
        case .retro: Color(red: 0.99, green: 0.93, blue: 0.78)
        }
    }
    var ink: Color {
        switch self {
        case .thermal: Color(red: 0.13, green: 0.13, blue: 0.14)
        case .midnight: Color(red: 0.86, green: 0.95, blue: 0.88)
        case .retro: Color(red: 0.55, green: 0.12, blue: 0.10)
        }
    }
}

struct ReceiptData {
    struct Row: Identifiable {
        let id: String
        let name: String
        let share: Double
        let points: Double?
        let time: TimeInterval?
    }

    let date: Date
    let rows: [Row]
    let batteryPoints: Double
    let onBatterySeconds: Double
    let wastedPoints: Double
    let wastedBlame: String?
    let keptAwake: (name: String, seconds: Double)?

    var isEmpty: Bool { rows.isEmpty }
    var wasOnBattery: Bool { onBatterySeconds >= 600 && batteryPoints >= 1 }
    var topName: String { rows.first?.name ?? "YOUR MAC" }

    init(day: DayUsage, date: Date) {
        self.date = date
        let lines = day.lines
        let onBattery = day.onBatterySeconds >= 600 && day.batteryPointsUsed >= 1
        let top = Array(lines.prefix(6))
        let rest = lines.dropFirst(6).reduce(0) { $0 + $1.share }
        var rows = top.map { line in
            Row(id: line.key, name: line.name, share: line.share,
                points: onBattery ? line.share * day.batteryPointsUsed : nil,
                time: onBattery ? line.share * day.onBatterySeconds : nil)
        }
        if rest >= 0.01 {
            rows.append(Row(id: "other", name: "Everything else", share: rest,
                            points: onBattery ? rest * day.batteryPointsUsed : nil,
                            time: onBattery ? rest * day.onBatterySeconds : nil))
        }
        self.rows = rows
        batteryPoints = day.batteryPointsUsed
        onBatterySeconds = day.onBatterySeconds
        wastedPoints = day.wastedWhileAwayPoints
        wastedBlame = day.wastedWhileAwayBlame
        keptAwake = day.topKeptAwake
    }

    var sendoff: String {
        let lines = ["NO REFUNDS ON BATTERY CYCLES", "COME AGAIN (PLUG IN SOON)", "YOUR FANS THANK YOU",
                     "KEEP THIS FOR YOUR RECORDS", "ALL SALES FINAL", "TIPS NOT ACCEPTED, ONLY CHARGERS"]
        let seed = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return lines[seed % lines.count]
    }
}

// MARK: - The card (also what gets rendered to PNG)

struct ReceiptCard: View {
    let data: ReceiptData
    let style: ReceiptStyle

    private var mono: Font { .system(size: 12, weight: .regular, design: .monospaced) }
    private var monoBold: Font { .system(size: 12, weight: .bold, design: .monospaced) }

    var body: some View {
        VStack(spacing: 0) {
            ZigZag(edge: .top).fill(style.paper).frame(height: 8)
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 2) {
                    Text("VITALS").font(.system(size: 22, weight: .black, design: .monospaced))
                    Text("BATTERY RECEIPT").font(monoBold)
                    Text(data.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()).uppercased())
                        .font(mono)
                }
                .frame(maxWidth: .infinity)

                dashes
                HStack {
                    Text("ITEM").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SHARE").frame(width: 52, alignment: .trailing)
                    Text(data.wasOnBattery ? "BATT" : "").frame(width: 44, alignment: .trailing)
                    Text(data.wasOnBattery ? "TIME" : "").frame(width: 56, alignment: .trailing)
                }
                .font(monoBold)

                ForEach(data.rows) { row in
                    HStack {
                        Text(row.name.uppercased()).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.percent(row.share)).frame(width: 52, alignment: .trailing)
                        Text(row.points.map { "\(Int($0.rounded()))%" } ?? "").frame(width: 44, alignment: .trailing)
                        Text(row.time.map { Format.duration($0) } ?? "").frame(width: 56, alignment: .trailing)
                    }
                    .font(mono)
                }

                dashes
                if data.wasOnBattery {
                    total("BATTERY USED", "\(Int(data.batteryPoints.rounded()))%")
                    total("TIME ON BATTERY", Format.duration(data.onBatterySeconds))
                } else {
                    total("BATTERY USED", "PLUGGED IN")
                }
                if data.wastedPoints >= 1 {
                    total("LOST WHILE AWAY", "\(Int(data.wastedPoints.rounded()))%" + (data.wastedBlame.map { " ← \($0.uppercased())" } ?? ""))
                }
                if let kept = data.keptAwake {
                    total("KEPT YOU UP", "\(kept.name.uppercased()) \(Format.duration(kept.seconds))")
                }
                dashes

                VStack(spacing: 3) {
                    Text("THANK YOU FOR CHOOSING").font(mono)
                    Text(data.topName.uppercased()).font(.system(size: 16, weight: .black, design: .monospaced))
                        .multilineTextAlignment(.center)
                    Text(data.sendoff).font(mono).padding(.top, 4)
                    Barcode(seed: data.topName + data.date.formatted(.iso8601.year().month().day()))
                        .fill(style.ink)
                        .frame(height: 34)
                        .padding(.top, 6)
                    Text("getvitals.app").font(mono)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(style.paper)
            ZigZag(edge: .bottom).fill(style.paper).frame(height: 8)
        }
        .foregroundStyle(style.ink)
        .frame(width: 340)
    }

    private var dashes: some View {
        Text(String(repeating: "- ", count: 24))
            .font(mono).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).clipped()
    }

    private func total(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).lineLimit(1)
        }
        .font(monoBold)
    }
}

private struct ZigZag: Shape {
    enum Edge { case top, bottom }
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tooth: CGFloat = 8
        let count = Int(rect.width / tooth)
        if edge == .top {
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            for i in 0...count {
                let x = CGFloat(i) * tooth
                path.addLine(to: CGPoint(x: x, y: i.isMultiple(of: 2) ? rect.maxY : rect.minY))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: 0, y: rect.minY))
            for i in 0...count {
                let x = CGFloat(i) * tooth
                path.addLine(to: CGPoint(x: x, y: i.isMultiple(of: 2) ? rect.minY : rect.maxY))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

private struct Barcode: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var value: UInt64 = 1469598103934665603
        for byte in seed.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        var x: CGFloat = rect.width * 0.15
        let end = rect.width * 0.85
        while x < end {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let width = CGFloat(1 + (value >> 33) % 3)
            let gap = CGFloat(1 + (value >> 40) % 3)
            path.addRect(CGRect(x: x, y: 0, width: width, height: rect.height))
            x += width + gap
        }
        return path
    }
}

// MARK: - Window

struct ReceiptWindowView: View {
    @ObservedObject var model: VitalsModel
    @ObservedObject var license: LicenseManager
    let upgrade: () -> Void
    @State private var dayOffset = 0
    @State private var style: ReceiptStyle = .thermal
    @State private var copied = false

    private var date: Date { Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date() }
    private var data: ReceiptData { ReceiptData(day: model.ledger.usage(for: date), date: date) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Picker("", selection: $dayOffset) {
                    Text("Today").tag(0)
                    Text("Yesterday").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
                ForEach(ReceiptStyle.allCases) { option in
                    Button {
                        if option.isPro && !license.isPro { upgrade() } else { style = option }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(option.paper).overlay(Circle().stroke(option.ink, lineWidth: 2))
                                .frame(width: 14, height: 14)
                            Text(option.title)
                            if option.isPro && !license.isPro { Image(systemName: "lock.fill").font(.caption2) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(style == option ? .accentColor : nil)
                }
            }

            ScrollView {
                if data.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "receipt").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Vitals is still adding up today's usage.")
                        Text("Leave it running for a while and check back.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ReceiptCard(data: data, style: style)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text(data.wasOnBattery ? "Based on today's time on battery." : "You were plugged in, so this shows each app's share of energy.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy Image") { copy() }
                    .disabled(data.isEmpty)
                Button("Save…") { save() }
                    .disabled(data.isEmpty)
                if let image = render() {
                    ShareLink(item: Image(nsImage: image),
                              preview: SharePreview("My Mac's battery receipt", image: Image(nsImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(data.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 720)
    }

    private func render() -> NSImage? {
        guard !data.isEmpty else { return nil }
        let renderer = ImageRenderer(content:
            ReceiptCard(data: data, style: style)
                .padding(24)
                .background(Color(red: 0.93, green: 0.92, blue: 0.90)))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func copy() {
        guard let image = render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func save() {
        guard let image = render(), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Vitals Receipt \(date.formatted(.iso8601.year().month().day())).png"
        panel.allowedContentTypes = [.png]
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
    }
}
