import AppKit
import Combine
import SwiftUI

/// Popover section: which apps you spent time in, today or over the last 7 days.
struct TimeSpentSection: View {
    @ObservedObject var tracker: AppTimeTracker
    let isPro: Bool
    let upgrade: () -> Void
    @State private var span: AppTimeTracker.Span = .today
    @State private var expanded = false

    var body: some View {
        let entries = tracker.entries(span)
        let top = entries.first?.seconds ?? 1
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Where your time went").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: Binding(
                    get: { span },
                    set: { value in if value == .week && !isPro { upgrade() } else { span = value } })) {
                    ForEach(AppTimeTracker.Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 110)
            }
            if entries.isEmpty {
                Text("Vitals counts the time each app is in front while you're at your Mac. Check back in a little while.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Format.duration(tracker.total(span))) in apps\(span == .week ? " this week" : " today")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(entries.prefix(expanded ? 10 : 4))) { entry in
                    HStack(spacing: 8) {
                        icon(for: entry).frame(width: 16, height: 16)
                        Text(entry.name).font(.system(size: 12)).lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.accentColor.opacity(0.75))
                                .frame(width: max(3, geo.size.width * entry.seconds / top), height: 5)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                        Text(Format.duration(entry.seconds))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                if entries.count > 4 {
                    Button(expanded ? "Show less" : "Show all") { withAnimation(.snappy) { expanded.toggle() } }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for entry: AppTimeTracker.Entry) -> some View {
        if let url = entry.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "app").foregroundStyle(.secondary)
        }
    }
}
