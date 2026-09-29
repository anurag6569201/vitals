import AppKit
import Combine
import SwiftUI

struct SpaceView: View {
    @ObservedObject var space: SpaceModel
    @ObservedObject var license: LicenseManager
    let freeBytes: UInt64?
    let upgrade: () -> Void
    @State private var pending: SpaceHog?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Space Hogs").font(.title2.bold())
                    Text("Big folders that rebuild or re-download themselves. Nothing here is your personal files.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if space.isScanning { ProgressView().controlSize(.small) }
                Button { space.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Scan again")
                    .disabled(space.isScanning)
            }

            HStack(spacing: 12) {
                stat("Free now", freeBytes.map { Format.diskBytes($0) } ?? "—")
                stat("Safe to clear", Format.diskBytes(space.totalTrashable))
            }

            if let message = space.message {
                Label(message, systemImage: "trash").font(.callout).foregroundStyle(.secondary)
            }

            List {
                Section("Caches and developer tools") {
                    if space.known.isEmpty && !space.isScanning {
                        Text("Nothing big found. Nice and tidy.").foregroundStyle(.secondary)
                    }
                    ForEach(space.known) { row($0) }
                }
                Section {
                    if space.projectRoot == nil {
                        Button("Scan a projects folder…") { space.chooseProjectsFolder() }
                    } else if space.projects.isEmpty && !space.isScanning {
                        Text("No big build folders found.").foregroundStyle(.secondary)
                    }
                    ForEach(space.projects) { row($0) }
                } header: {
                    HStack {
                        Text("Old project build folders")
                        Spacer()
                        if let root = space.projectRoot {
                            Button(root.lastPathComponent) { space.chooseProjectsFolder() }
                                .buttonStyle(.link).font(.caption)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(20)
        .frame(width: 600, height: 600)
        .onAppear { space.scanIfNeeded() }
        .confirmationDialog("Move “\(pending?.title ?? "")” to the Trash?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Move to Trash (\(pending.map { Format.diskBytes($0.bytes) } ?? ""))", role: .destructive) {
                if let hog = pending { space.trash(hog) }
                pending = nil
            }
        } message: {
            Text(pending?.detail ?? "")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ hog: SpaceHog) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hog.title).font(.system(size: 13, weight: .medium))
                Text(hog.detail).font(.caption).foregroundStyle(.secondary)
                if let used = hog.lastUsed {
                    Text("Project last touched \(used.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(Format.diskBytes(hog.bytes))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Button { space.reveal(hog) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            if hog.canTrash {
                Button {
                    if license.isPro { pending = hog } else { upgrade() }
                } label: {
                    HStack(spacing: 3) {
                        if !license.isPro { Image(systemName: "lock.fill").font(.caption2) }
                        Text("Clear")
                    }
                }
                .controlSize(.small)
                .disabled(space.isScanning)
            } else {
                Text("Manual").font(.caption).foregroundStyle(.secondary).frame(width: 46)
            }
        }
        .padding(.vertical, 2)
    }
}
