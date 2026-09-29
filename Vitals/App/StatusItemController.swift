import AppKit
import Combine
import SwiftUI

/// The one menu-bar item. Quiet by default; it only grows when something needs you.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: VitalsModel
    private let windows: WindowManager
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?

    init(model: VitalsModel, windows: WindowManager) {
        self.model = model
        self.windows = windows
        super.init()

        statusItem.autosaveName = "VitalsStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("Vitals")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let root = PopoverView(model: model, license: model.license,
                               openSettings: { [weak self] tab in self?.openSettings(tab) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        model.objectWillChange
            .merge(with: model.keepAwake.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        HotKey.action = { [weak self] in self?.toggle(nil) }
        render()
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
        // Refresh after the popover has laid out, never during a SwiftUI update pass.
        DispatchQueue.main.async { [weak self] in self?.model.isPopoverOpen = true }
    }

    @objc func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPopover() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.model.isPopoverOpen = false }
        }
    }

    private func openSettings(_ tab: SettingsTab) {
        popover.performClose(nil)
        windows.showSettings(tab: tab)
    }

    // MARK: Rendering

    private func render() {
        guard let button = statusItem.button else { return }
        let severity = model.severity
        button.image = StatusIcon.image(severity: severity, style: model.settings.iconStyle,
                                        awake: model.keepAwake.isOn)
        button.toolTip = tooltip()

        var parts: [String] = []
        let style = model.settings.menuBarStyle
        if style != .iconOnly, severity >= .warning, let top = model.issues.first {
            parts.append(top.shortLabel)
        }
        if style.showsReadings, model.license.isPro, let snap = model.snapshot {
            let onlyHigh = style == .smartReadings
            parts.append(contentsOf: model.settings.readings.compactMap { reading(for: $0, snap, onlyWhenHigh: onlyHigh) })
        }
        let text = parts.joined(separator: "  ")
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: severity >= .warning && !parts.isEmpty && !style.showsReadings
                ? StatusIcon.color(for: severity) : NSColor.labelColor
        ])
    }

    private func reading(for kind: ReadingKind, _ snap: SystemSnapshot, onlyWhenHigh: Bool) -> String? {
        if onlyWhenHigh && !Self.isHigh(kind, snap) { return nil }
        return switch kind {
        case .cpu: "CPU \(Format.percent(snap.cpuTotal))"
        case .gpu: snap.gpuUsage.map { "GPU \(Format.percent($0))" }
        case .memory: "MEM \(Format.percent(snap.memoryUsed))"
        case .download: "↓ \(Format.rate(snap.downloadRate))"
        case .upload: "↑ \(Format.rate(snap.uploadRate))"
        case .disk: snap.diskFreeBytes.map { "\(Format.diskBytes($0)) free" }
        case .topApp: snap.apps.first.map { "\(Format.shortName($0.identity.name)) \(Format.cpu($0.cpuPercent))" }
        case .worldClock: "\(WorldClock.label(for: model.settings.worldClockZone)) \(WorldClock.time(in: model.settings.worldClockZone))"
        }
    }

    /// When a reading is worth a glance in "only when high" mode.
    static func isHigh(_ kind: ReadingKind, _ snap: SystemSnapshot) -> Bool {
        switch kind {
        case .cpu: snap.cpuTotal >= 0.75
        case .gpu: (snap.gpuUsage ?? 0) >= 0.75
        case .memory: snap.memoryPressure >= .warning
        case .download: snap.downloadRate >= 5_000_000
        case .upload: snap.uploadRate >= 2_000_000
        case .disk: (snap.diskFreeBytes ?? .max) < 10_000_000_000
        case .topApp: (snap.apps.first?.cpuPercent ?? 0) >= 80
        case .worldClock: true
        }
    }

    private func tooltip() -> String {
        if model.issues.isEmpty { return "Vitals — your Mac is healthy" }
        return "Vitals — " + model.issues.prefix(3).map(\.headline).joined(separator: "\n")
    }
}

enum StatusIcon {
    static func color(for severity: Severity) -> NSColor {
        switch severity {
        case .calm: .systemGreen
        case .notice: .systemBlue
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    /// The chosen icon; a colored dot appears when there's something to see,
    /// and a small cup while Keep Awake is on.
    static func image(severity: Severity, style: IconStyle = .pulse, awake: Bool = false) -> NSImage? {
        let pointSize: CGFloat = style == .dot ? 8 : 13
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let base = NSImage(systemSymbolName: style.symbol, accessibilityDescription: "Vitals")?
            .withSymbolConfiguration(config) else { return nil }
        let symbol = awake ? withCup(base) : base
        guard severity > .calm else {
            symbol.isTemplate = true
            return symbol
        }
        let size = NSSize(width: symbol.size.width + 4, height: max(symbol.size.height, 16))
        let dotColor = color(for: severity)
        let tinted = symbol.tinted(severity >= .warning ? dotColor : NSColor.labelColor)
        let symbolSize = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            let symbolRect = NSRect(x: 0, y: (rect.height - symbolSize.height) / 2,
                                    width: symbolSize.width, height: symbolSize.height)
            tinted.draw(in: symbolRect)
            let dot = NSRect(x: rect.width - 7, y: rect.height - 7, width: 6.5, height: 6.5)
            dotColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Vitals: \(severity.title)"
        return image
    }
}

extension StatusIcon {
    static func withCup(_ base: NSImage) -> NSImage {
        let cupConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        guard let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Keeping awake")?
            .withSymbolConfiguration(cupConfig) else { return base }
        let size = NSSize(width: base.size.width + cup.size.width + 3, height: max(base.size.height, cup.size.height))
        let baseSize = base.size
        let cupSize = cup.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: (rect.height - baseSize.height) / 2, width: baseSize.width, height: baseSize.height))
            cup.draw(in: NSRect(x: baseSize.width + 3, y: (rect.height - cupSize.height) / 2, width: cupSize.width, height: cupSize.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension NSImage {
    nonisolated func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }
}
