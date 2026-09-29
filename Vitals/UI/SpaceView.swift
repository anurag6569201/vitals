import AppKit
import Combine
import SwiftUI

struct SpaceView: View {
    @ObservedObject var space: SpaceModel
    @ObservedObject var license: LicenseManager
    @ObservedObject var model: VitalsModel
    let upgrade: () -> Void
    @State private var category: SpaceCategory? = .bigFiles
    @State private var confirming = false

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Section {
                    ForEach(SpaceCategory.allCases) { item in
                        HStack {
                            Label(item.title, systemImage: item.symbol)
                            Spacer()
                            if space.scanning.contains(item) {
                                ProgressView().controlSize(.mini)
                            } else if space.total(item) > 0 {
                                Text(Format.diskBytes(space.total(item)))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .tag(item)
                    }
                } header: {
                    DiskSummary(snapshot: model.snapshot, found: space.reviewableTotal)
                        .padding(.bottom, 6)
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            if let category {
                CategoryDetail(category: category, space: space, isPro: license.isPro)
            } else {
                Text("Pick a category").foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItem {
                Button { space.scanAll() } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                    .disabled(space.isScanning)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear { space.scanIfNeeded() }
        .confirmationDialog("Move \(space.selectedItems.count) item\(space.selectedItems.count == 1 ? "" : "s") to the Trash?",
                            isPresented: $confirming) {
            Button("Move to Trash (\(Format.diskBytes(space.selectedBytes)))", role: .destructive) { space.trashSelected() }
        } message: {
            Text("You can put anything back from the Trash until you empty it.")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let message = space.message {
                Label(message, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(space.selectedItems.isEmpty ? "Select items to clear. Nothing is deleted without asking."
                     : "\(space.selectedItems.count) selected · \(Format.diskBytes(space.selectedBytes))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if space.total(.trash) > 0 {
                Button("Open Trash") { space.openTrash() }
            }
            Button {
                if license.isPro { confirming = true } else { upgrade() }
            } label: {
                HStack(spacing: 4) {
                    if !license.isPro { Image(systemName: "lock.fill") }
                    Text("Move to Trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(space.selectedItems.isEmpty || space.scanning.contains(.trash))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct DiskSummary: View {
    let snapshot: SystemSnapshot?
    let found: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let free = snapshot?.diskFreeBytes, let total = snapshot?.diskTotalBytes, total > 0 {
                Text("\(Format.diskBytes(free)) free of \(Format.diskBytes(total))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                ProgressView(value: 1 - Double(free) / Double(total)).tint(free < 20_000_000_000 ? .orange : .accentColor)
            }
            if found > 0 {
                Text("Vitals found \(Format.diskBytes(found)) to review")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }
}

private struct CategoryDetail: View {
    let category: SpaceCategory
    @ObservedObject var space: SpaceModel
    let isPro: Bool

    private var items: [SpaceItem] { space.items[category] ?? [] }
    private var trashable: [SpaceItem] { items.filter(\.canTrash) }
    private var allSelected: Bool { !trashable.isEmpty && trashable.allSatisfy { space.selection.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(category.title, systemImage: category.symbol).font(.title3.bold())
                    Text(category.explanation).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !trashable.isEmpty {
                    Toggle("Select all", isOn: Binding(get: { allSelected }, set: { space.select(all: category, $0) }))
                        .toggleStyle(.checkbox)
                }
            }
            .padding(16)

            if category == .developer {
                HStack {
                    Button(space.projectRoot == nil ? "Also scan a projects folder…" : "Projects: \(space.projectRoot!.lastPathComponent)") {
                        space.chooseProjectsFolder()
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            Divider()

            if space.scanning.contains(category) && items.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(category == .duplicates ? "Comparing files… this can take a minute." : "Looking…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Nothing here. Nice and tidy.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    SpaceRow(item: item, selected: space.selection.contains(item.id),
                             toggle: { space.toggle(item) }, reveal: { space.reveal(item) })
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct SpaceRow: View {
    let item: SpaceItem
    let selected: Bool
    let toggle: () -> Void
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if item.canTrash {
                Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                    .toggleStyle(.checkbox).labelsHidden()
            } else {
                Image(systemName: "hand.raised").foregroundStyle(.secondary).frame(width: 16)
                    .help("Vitals won't remove this for you — see the note.")
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if item.group != nil && item.keep {
                        Text("KEEP").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.subtitle).lineLimit(1).truncationMode(.middle)
                    if let used = item.lastUsed, item.category != .unusedApps {
                        Text("· \(used.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.diskBytes(item.bytes))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            Button(action: reveal) { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if item.canTrash { toggle() } }
    }
}
