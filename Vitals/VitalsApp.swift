//
//  VitalsApp.swift
//  Vitals
//
//  Created by Anurag Singh on 27/09/26.
//

import ApplicationServices
import AppKit
import SwiftUI

@MainActor
private final class VitalsRuntime {
    static let shared = VitalsRuntime()

    let monitor = VitalsMonitor()
    let settings = VitalsConfigurationStore()
    let menuControl = MenuBarControl.shared
}

@main
struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(VitalsAppDelegate.self) private var appDelegate
    @StateObject private var monitor = VitalsRuntime.shared.monitor
    @StateObject private var settings = VitalsRuntime.shared.settings
    @StateObject private var menuControl = VitalsRuntime.shared.menuControl

    var body: some Scene {
        WindowGroup("Vitals") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(menuControl)
        }
        .windowResizability(.contentSize)

        Window("Customize Vitals", id: "customize") {
            ContentView(configurationWindow: true)
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(menuControl)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class VitalsStatusController: NSObject {
    private let runtime: VitalsRuntime
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var updateTimer: Timer?
    private var lastVisibility: Bool?
    private var lastRestriction: Bool?

    init(runtime: VitalsRuntime) {
        self.runtime = runtime
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "VitalsMainStatus"
        statusItem.behavior = []
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Open Vitals: shortcuts and live stats"
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 408, height: 700)
        popover.contentViewController = NSHostingController(rootView:
            ContentView()
                .environmentObject(runtime.monitor)
                .environmentObject(runtime.settings)
                .environmentObject(runtime.menuControl))

        updateLabel()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateLabel() }
        }
        runtime.menuControl.startAfterMenuBarAppears()
    }

    func stop() {
        updateTimer?.invalidate()
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let visible = runtime.settings.menuMetrics(priority: runtime.monitor.priorityMetric)
        let apps = runtime.menuControl.hubApps
        let systemItems = ControlledSystemItem.allCases.filter {
            runtime.menuControl.hiddenSystemIDs.contains($0.id)
        }
        let totalShortcuts = apps.count + systemItems.count
        let previewLimit = visible.isEmpty ? 3 : (visible.count == 1 ? 2 : 1)
        let previewApps = runtime.settings.configuration.showHubPreview
            ? Array(apps.prefix(previewLimit)) : []
        let previewSystem = runtime.settings.configuration.showHubPreview
            ? Array(systemItems.prefix(max(0, previewLimit - previewApps.count))) : []
        let previewCount = previewApps.count + previewSystem.count

        let showPulse = runtime.settings.configuration.showIcon || (visible.isEmpty && previewCount == 0)
        let pulse = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Vitals")
        pulse?.isTemplate = true
        button.image = showPulse ? pulse : nil

        let title = NSMutableAttributedString(string: "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        func append(_ string: String) {
            title.append(NSAttributedString(string: string, attributes: attributes))
        }
        func appendIcon(_ image: NSImage?) {
            guard let image else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
            title.append(NSAttributedString(attachment: attachment))
        }

        if previewCount > 0 {
            append("  ")
            for app in previewApps {
                appendIcon(app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: app.name))
                append(" ")
            }
            for item in previewSystem {
                appendIcon(NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title))
                append(" ")
            }
            if totalShortcuts > previewCount { append("+\(totalShortcuts - previewCount)") }
        }
        if !visible.isEmpty {
            if previewCount > 0 { append("  |  ") }
            for (index, kind) in visible.enumerated() {
                if index > 0 { append("  |  ") }
                let label = runtime.settings.configuration.style == .compact ? kind.shortLabel : kind.title
                append("\(label) \(runtime.monitor.reading(for: kind))")
            }
        }
        button.attributedTitle = title
        let visibleNow = statusItem.isVisible
        let restrictedNow = runtime.menuControl.isRestrictionActive
        if lastVisibility != visibleNow || lastRestriction != restrictedNow {
            NSLog("Vitals status item visible=%@ restricted=%@ frame=%@",
                  visibleNow ? "yes" : "no", restrictedNow ? "yes" : "no",
                  NSStringFromRect(button.window?.frame ?? .zero))
            lastVisibility = visibleNow
            lastRestriction = restrictedNow
        }
    }
}

@MainActor
final class VitalsAppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: VitalsStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = VitalsStatusController(runtime: VitalsRuntime.shared)
        let trusted = AXIsProcessTrusted()
        UserDefaults.standard.set(trusted, forKey: "vitals.lastTrustProbe")
        UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "vitals.lastTrustProbePID")
        NSLog("Vitals Accessibility trusted at app launch: %@", trusted ? "yes" : "no")
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
        MenuBarControl.shared.stop()
    }
}
