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
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        render()
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        model.isPopoverOpen = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPopover() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { model.isPopoverOpen = false }
    }

    private func openSettings(_ tab: SettingsTab) {
        popover.performClose(nil)
        windows.showSettings(tab: tab)
    }

    // MARK: Rendering

    private func render() {
        guard let button = statusItem.button else { return }
        let severity = model.severity
        button.image = StatusIcon.image(severity: severity)
        button.toolTip = tooltip()

        var parts: [String] = []
        let style = model.settings.menuBarStyle
        if style != .iconOnly, severity >= .warning, let top = model.issues.first {
            parts.append(top.shortLabel)
        }
        if style == .readings, model.license.isPro, let snap = model.snapshot {
            parts.append(contentsOf: model.settings.readings.compactMap { reading(for: $0, snap) })
        }
        let text = parts.joined(separator: "  ")
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: severity >= .warning && !parts.isEmpty && style != .readings
                ? StatusIcon.color(for: severity) : NSColor.labelColor
        ])
    }

    private func reading(for kind: ReadingKind, _ snap: SystemSnapshot) -> String? {
        switch kind {
        case .cpu: "CPU \(Format.percent(snap.cpuTotal))"
        case .memory: "MEM \(Format.percent(snap.memoryUsed))"
        case .battery: snap.battery.map { "BAT \(Format.percent($0.level))" }
        case .network: "↓\(Format.rate(snap.downloadRate))"
        case .disk: snap.diskFreeBytes.map { "\(Format.diskBytes($0)) free" }
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

    /// A pulse line; a colored dot appears when there's something to see.
    static func image(severity: Severity) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Vitals")?
            .withSymbolConfiguration(config) else { return nil }
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
