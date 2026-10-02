import Combine
import AppKit
import SwiftUI

@main
enum VitalsMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var license: LicenseManager!
    private var model: VitalsModel!
    private var windows: WindowManager!
    private var statusItem: StatusItemController!
    private var pinned: PinnedPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.clearLegacyMenuBarChoices()
        NSApp.mainMenu = Self.makeMainMenu()
        license = LicenseManager()
        model = VitalsModel(license: license)
        windows = WindowManager(model: model)
        statusItem = StatusItemController(model: model, windows: windows)
        model.openWindow = { [weak self] window in self?.windows.show(window) }
        model.openPopover = { [weak self] in self?.statusItem.showPopover() }
        pinned = PinnedPanelController(model: model,
                                       openPopover: { [weak self] in self?.statusItem.showPopover() },
                                       openSettings: { [weak self] in self?.windows.showSettings(tab: .pin) })
        model.start()
        let menuBar = MenuBarControl.shared
        if !menuBar.hiddenIDs.isEmpty || !menuBar.hiddenSystemIDs.isEmpty || !menuBar.hubOrder.isEmpty {
            menuBar.startAfterMenuBarAppears()
        }

        if !model.settings.hasCompletedOnboarding {
            windows.showOnboarding { [weak self] in
                self?.model.settings.hasCompletedOnboarding = true
                self?.statusItem.showPopover()
            }
        }
    }

    /// Opening Vitals again (Finder, Spotlight, Launchpad) opens the Menu Bar settings — the
    /// recovery path if the icon is ever hidden (behind the notch, by macOS, or by a hidden-icon choice).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings(tab: .menuBar)
        return true
    }

    /// The first prototype saved hidden-icon choices under the same keys. Don't silently re-apply
    /// them in this version — the person opts in again from Settings › Menu Bar.
    private static func clearLegacyMenuBarChoices() {
        let defaults = UserDefaults.standard
        // "Where your time went" was removed: drop its stored history.
        defaults.removeObject(forKey: "vitals.appTime.v1")
        defaults.removeObject(forKey: "vitals.appTime.names.v1")
        let marker = "vitals.menuBar.legacyCleared.v2"
        guard !defaults.bool(forKey: marker) else { return }
        for key in ["vitals.hiddenMenuApps.v1", "vitals.hiddenSystemItems.v1", "vitals.hubOrder.v1",
                    "vitals.profiles.v1", "vitals.activeProfile.v1"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: marker)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Always give every menu-bar icon back when Vitals quits.
        MenuBarControl.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Accessory apps have no visible menu, but text fields still need ⌘C / ⌘V / ⌘A.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Vitals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}

/// Owns the Settings and Welcome windows (plain AppKit windows hosting SwiftUI).
@MainActor
final class WindowManager {
    private let model: VitalsModel
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var spaceWindow: NSWindow?
    private var networkWindow: NSWindow?
    private let settingsRouter = SettingsRouter()

    init(model: VitalsModel) {
        self.model = model
    }

    func showSettings(tab: SettingsTab) {
        settingsRouter.tab = tab
        if settingsWindow == nil {
            let view = SettingsView(model: model, license: model.license, router: settingsRouter)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Vitals Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        present(settingsWindow)
    }

    func show(_ window: AppWindow) {
        switch window {
        case .settings(let tab): showSettings(tab: tab)
        case .space: showSpace()
        case .network: showNetwork()
        }
    }

    func showNetwork() {
        if networkWindow == nil {
            let view = NetworkWindowView(tracker: model.network, isPro: model.license.isPro,
                                         upgrade: { [weak self] in self?.showSettings(tab: .pro) })
            let window = makeWindow(NSHostingController(rootView: view), title: "Where Your Data Went")
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 760, height: 680))
            window.center()
            networkWindow = window
        }
        present(networkWindow)
    }

    func showSpace() {
        if spaceWindow == nil {
            let view = SpaceView(space: model.space, license: model.license, model: model,
                                 upgrade: { [weak self] in self?.showSettings(tab: .pro) })
            let window = makeWindow(NSHostingController(rootView: view), title: "Free Up Space")
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 900, height: 620))
            window.center()
            spaceWindow = window
        }
        present(spaceWindow)
    }

    private func makeWindow(_ controller: NSViewController, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func showOnboarding(completion: @escaping () -> Void) {
        let view = OnboardingView(model: model) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            completion()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Vitals"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        present(window)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

enum AppWindow {
    case settings(SettingsTab)
    case space
    case network
}

enum SettingsTab: String, Hashable {
    case general, menuBar, pin, popover, alerts, pro, about
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}
