import AppKit
import Combine
import SwiftUI

/// Owns the floating on-screen pin: a borderless, non-activating panel you can drag anywhere.
/// It snaps to screen edges and corners, remembers where you left it per screen, and
/// re-flows into a column when docked to the left or right edge.
@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    private let model: VitalsModel
    private let openPopover: () -> Void
    private let openSettings: () -> Void
    private var panel: PinPanel?
    private var host: NSHostingController<PinRoot>?
    private var cancellables: Set<AnyCancellable> = []
    private var contentSize = CGSize(width: 220, height: 50)
    private var positioning = false
    private var settleWork: DispatchWorkItem?
    private let hover = PinHover()
    private var collapseWork: DispatchWorkItem?

    static let snapDistance: CGFloat = 40

    init(model: VitalsModel, openPopover: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openPopover = openPopover
        self.openSettings = openSettings
        super.init()
        model.$settings.map(\.pin).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        model.license.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        // Readings change width as numbers change: re-measure after each model update.
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleMeasure() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.applyPosition(animated: false) }
            .store(in: &cancellables)
        // Entering or leaving a full-screen app shows or hides the menu bar.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.applyPosition(animated: true) }
            }
            .store(in: &cancellables)
    }

    /// Free users get one reading in the Edge Dock; Pro gets everything.
    private var pin: PinSettings { model.license.isPro ? model.settings.pin : model.settings.pin.freeTier() }

    private func update() {
        guard pin.enabled else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        host?.rootView = root
        measure()
        panel.ignoresMouseEvents = pin.locked
        updateLevel()
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        behavior.insert(pin.allSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        if pin.level == .desktop { behavior.insert(.stationary) }
        panel.collectionBehavior = behavior
        applyPosition(animated: panel.isVisible)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        }
    }

    private var root: PinRoot {
        PinRoot(model: model, pin: pin, hover: hover,
                onHover: { [weak self] inside in self?.hoverChanged(inside) },
                onClose: { [weak self] in self?.model.settings.pin.enabled = false },
                onSettings: { [weak self] in self?.openSettings() },
                onDoubleClick: { [weak self] in self?.openPopover() },
                menu: { [weak self] in self?.makeMenu() })
    }

    private func makePanel() -> PinPanel {
        let panel = PinPanel(contentRect: NSRect(origin: .zero, size: contentSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        let host = NSHostingController(rootView: root)
        // SwiftUI reports the pin's real rendered size here; the panel follows it.
        host.sizingOptions = [.preferredContentSize]
        host.publisher(for: \.preferredContentSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] size in self?.contentSizeChanged(size) }
            .store(in: &cancellables)
        host.view.frame = NSRect(origin: .zero, size: contentSize)
        host.view.autoresizingMask = [.width, .height]
        panel.contentView = host.view
        self.host = host
        self.panel = panel
        return panel
    }

    // MARK: Size & position

    private var measurePending = false

    private func scheduleMeasure() {
        guard panel?.isVisible == true, !measurePending else { return }
        measurePending = true
        DispatchQueue.main.async { [weak self] in
            self?.measurePending = false
            self?.measure()
        }
    }

    /// Asks SwiftUI for the pin's natural size and fits the panel to it.
    private func measure() {
        guard let host else { return }
        let fitted = host.sizeThatFits(in: CGSize(width: 4000, height: 4000))
        let preferred = host.preferredContentSize
        contentSizeChanged(CGSize(width: max(fitted.width, preferred.width),
                                  height: max(fitted.height, preferred.height)))
    }

    private func contentSizeChanged(_ size: CGSize) {
        let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard rounded.width > 1, rounded.height > 1, rounded != contentSize else { return }
        contentSize = rounded
        applyPosition(animated: panel?.isVisible ?? false)
    }

    private func screen(for position: PinPosition) -> NSScreen {
        if let id = position.screenID, let match = NSScreen.screens.first(where: { $0.displayID == id }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// The area the pin lives in. Floating shapes keep clear of the menu bar and Dock.
    /// An Edge Dock goes right to the physical edge: past a hidden Dock's sliver, and to the very
    /// top of the screen when the menu bar isn't showing (full-screen apps, auto-hide).
    private func usableRect(_ screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        guard pin.shape == .dock else { return vf }
        let full = screen.frame
        let minX = vf.minX - full.minX <= 6 ? full.minX : vf.minX
        let maxX = full.maxX - vf.maxX <= 6 ? full.maxX : vf.maxX
        let minY = vf.minY - full.minY <= 6 ? full.minY : vf.minY
        // The very top of the screen: an Edge Dock may sit over the menu bar (it floats above it),
        // so it can reach the true corners. The notch is handled in frame(for:).
        let maxY = full.maxY
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether the menu bar is on screen right now. Uses only window layers and bounds,
    /// which need no Screen Recording permission.
    static func menuBarVisible(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return true }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let cgTop = mainHeight - screen.frame.maxY
        for window in list where (window[kCGWindowLayer as String] as? Int) == menuLevel {
            guard let raw = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else { continue }
            let onThisScreen = bounds.midX > screen.frame.minX && bounds.midX < screen.frame.maxX
            if onThisScreen, abs(bounds.minY - cgTop) < 2, bounds.height >= 18, bounds.height <= 80,
               bounds.width > screen.frame.width * 0.5 {
                return true
            }
        }
        return false
    }

    func frame(for position: PinPosition, size: CGSize) -> NSRect {
        let vf = usableRect(screen(for: position))
        let m = pin.shape.margin
        let x: CGFloat = switch position.h {
        case .start: vf.minX + m
        case .center: vf.midX - size.width / 2
        case .end: vf.maxX - size.width - m
        case .free: vf.minX + m + CGFloat(position.fx) * max(0, vf.width - size.width - 2 * m)
        }
        let y: CGFloat = switch position.v {
        case .start: vf.maxY - size.height - m
        case .center: vf.midY - size.height / 2
        case .end: vf.minY + m
        case .free: vf.maxY - m - size.height - CGFloat(position.fy) * max(0, vf.height - size.height - 2 * m)
        }
        var rect = NSRect(x: round(x), y: round(y), width: size.width, height: size.height)
        // Never slide under the camera notch.
        let screen = screen(for: position)
        if pin.shape == .dock, screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notch = NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                               width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            if rect.intersects(notch) { rect.origin.y = min(rect.origin.y, notch.minY - rect.height) }
        }
        return rect
    }

    /// Floating pins sit above windows; an Edge Dock reaching into the menu bar sits above the
    /// menu bar too, or the menu bar would draw over it.
    private func updateLevel(for frame: NSRect? = nil) {
        guard let panel else { return }
        if pin.level == .desktop {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            return
        }
        let target = frame ?? panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? NSScreen.main
        let overMenuBar = pin.shape == .dock && screen.map { target.maxY > $0.visibleFrame.maxY + 1 } == true
        panel.level = overMenuBar ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1) : .floating
    }

    private func applyPosition(animated: Bool) {
        guard let panel else { return }
        let target = frame(for: pin.position, size: contentSize)
        updateLevel(for: target)
        guard target != panel.frame else { return }
        positioning = true
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.positioning = false
                    self?.panel?.invalidateShadow()
                }
            })
        } else {
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
            positioning = false
        }
    }

    /// Works out where a dragged pin belongs: snapped to an edge, a corner or the center line,
    /// or exactly where it was dropped.
    private func settle() {
        guard let panel else { return }
        if NSEvent.pressedMouseButtons != 0 {
            scheduleSettle()
            return
        }
        let f = panel.frame
        let center = CGPoint(x: f.midX, y: f.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = usableRect(screen)
        let m = pin.shape.margin, d = Self.snapDistance
        var p = PinPosition()
        p.screenID = screen.displayID
        let snap = pin.snapToEdges

        if snap && f.minX - vf.minX < d + m { p.h = .start }
        else if snap && vf.maxX - f.maxX < d + m { p.h = .end }
        else if snap && abs(f.midX - vf.midX) < d / 2 { p.h = .center }
        else {
            p.h = .free
            let span = max(1, vf.width - f.width - 2 * m)
            p.fx = Double(min(max((f.minX - vf.minX - m) / span, 0), 1))
        }
        if snap && vf.maxY - f.maxY < d + m { p.v = .start }
        else if snap && f.minY - vf.minY < d + m { p.v = .end }
        else if snap && abs(f.midY - vf.midY) < d / 2 { p.v = .center }
        else {
            p.v = .free
            let span = max(1, vf.height - f.height - 2 * m)
            p.fy = Double(min(max((vf.maxY - m - f.maxY) / span, 0), 1))
        }
        // An Edge Dock always lives on an edge: dropped mid-screen, it goes to the nearest one.
        if pin.shape == .dock, p.h != .start, p.h != .end, p.v != .start, p.v != .end {
            let distances: [(CGFloat, PinAlign, Bool)] = [
                (f.minX - vf.minX, .start, true), (vf.maxX - f.maxX, .end, true),
                (vf.maxY - f.maxY, .start, false), (f.minY - vf.minY, .end, false),
            ]
            if let nearest = distances.min(by: { $0.0 < $1.0 }) {
                if nearest.2 {
                    p.h = nearest.1
                    if p.v == .center { p.v = .free; p.fy = 0.5 }
                } else {
                    p.v = nearest.1
                    if p.h == .center { p.h = .free; p.fx = 0.5 }
                }
            }
        }
        if p != pin.position {
            model.settings.pin.position = p   // triggers update() → animated settle
        } else {
            applyPosition(animated: true)
        }
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settle() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    /// Expand at once; collapse (tuck back into the edge) after a short grace period.
    private func hoverChanged(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            if !hover.inside { hover.inside = true; refreshShadowAfterAnimation() }
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, NSEvent.pressedMouseButtons == 0 else { return }
                self.hover.inside = false
                self.refreshShadowAfterAnimation()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    /// The shadow follows what's drawn; recompute it once the drawer has finished moving.
    private func refreshShadowAfterAnimation() {
        for delay in [0.05, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.panel?.invalidateShadow() }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !positioning else { return }
        scheduleSettle()
    }

    // MARK: Right-click menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let place = NSMenu()
        for preset in PinPosition.presets {
            let current = pin.position.h == preset.h && pin.position.v == preset.v
            place.addItem(MenuAction.item(preset.name, checked: current) { [weak self] in
                guard let self else { return }
                var p = self.pin.position
                p.h = preset.h; p.v = preset.v
                self.model.settings.pin.position = p
            })
        }
        menu.addItem(MenuAction.submenu("Position", place))

        let presets = NSMenu()
        for preset in PinPreset.allCases {
            presets.addItem(MenuAction.item(preset.title + (preset.isPro && !model.license.isPro ? " (Pro)" : "")) { [weak self] in
                guard let self else { return }
                if preset.isPro && !self.model.license.isPro { self.openSettings(); return }
                var updated = self.model.settings.pin
                preset.apply(to: &updated)
                self.model.settings.pin = updated
            })
        }
        menu.addItem(MenuAction.submenu("Presets", presets))

        let shapes = NSMenu()
        for shape in PinShape.allCases {
            shapes.addItem(MenuAction.item(shape.title, checked: pin.shape == shape) { [weak self] in
                self?.model.settings.pin.shape = shape
            })
        }
        menu.addItem(MenuAction.submenu("Shape", shapes))
        if pin.shape == .dock {
            menu.addItem(MenuAction.item("Tuck Into Edge Until Hovered", checked: pin.autoHide) { [weak self] in
                self?.model.settings.pin.autoHide.toggle()
            })
        }

        let layout = NSMenu()
        for option in PinLayout.allCases {
            layout.addItem(MenuAction.item(option.title, checked: pin.layout == option) { [weak self] in
                self?.model.settings.pin.layout = option
            })
        }
        menu.addItem(MenuAction.submenu("Layout", layout))

        let style = NSMenu()
        for theme in PinTheme.allCases {
            style.addItem(MenuAction.item(theme.title, checked: pin.theme == theme) { [weak self] in
                self?.model.settings.pin.theme = theme
            })
        }
        menu.addItem(MenuAction.submenu("Style", style))

        let size = NSMenu()
        for option in PinSize.allCases {
            size.addItem(MenuAction.item(option.title, checked: pin.size == option) { [weak self] in
                self?.model.settings.pin.size = option
            })
        }
        menu.addItem(MenuAction.submenu("Size", size))

        let show = NSMenu()
        for item in PinItem.allCases {
            show.addItem(MenuAction.item(item.title, checked: pin.items.contains(item)) { [weak self] in
                self?.model.togglePinItem(item)
            })
        }
        menu.addItem(MenuAction.submenu("Show", show))

        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Labels", checked: pin.showLabels) { [weak self] in
            self?.model.settings.pin.showLabels.toggle()
        })
        menu.addItem(MenuAction.item("Gauges", checked: pin.showGauges) { [weak self] in
            self?.model.settings.pin.showGauges.toggle()
        })
        menu.addItem(MenuAction.item("Lock in Place (Clicks Pass Through)", checked: pin.locked) { [weak self] in
            self?.model.settings.pin.locked = true
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Open Vitals") { [weak self] in self?.openPopover() })
        menu.addItem(MenuAction.item("Customize…") { [weak self] in self?.openSettings() })
        menu.addItem(MenuAction.item("Unpin") { [weak self] in self?.model.settings.pin.enabled = false })
        return menu
    }
}

/// Never steals focus from the app you're using.
final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// macOS normally keeps windows out of the menu bar; the pin may go right to the screen edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// SwiftUI root inside the panel: reports its size and adds the drag surface.
struct PinRoot: View {
    @ObservedObject var model: VitalsModel
    let pin: PinSettings
    let hover: PinHover
    let onHover: (Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onDoubleClick: () -> Void
    let menu: () -> NSMenu?

    var body: some View {
        PinnedVitalsView(model: model, pin: pin, hover: hover, onClose: onClose, onSettings: onSettings,
                         dragSurface: AnyView(PinDragSurface(onDoubleClick: onDoubleClick, onHover: onHover, menu: menu)))
            .fixedSize()
    }
}

/// Drag anywhere on the pin to move it; double-click opens Vitals; right-click for options.
private struct PinDragSurface: NSViewRepresentable {
    let onDoubleClick: () -> Void
    let onHover: (Bool) -> Void
    let menu: () -> NSMenu?

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        view.onHover = onHover
        view.menuProvider = menu
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onHover = onHover
        view.menuProvider = menu
    }

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        var onHover: ((Bool) -> Void)?
        var menuProvider: (() -> NSMenu?)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // .activeAlways: works even though Vitals never becomes the active app.
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            window?.performDrag(with: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let menu = menuProvider?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

/// NSMenuItem with a closure.
final class MenuAction: NSObject {
    private let block: () -> Void
    private init(_ block: @escaping () -> Void) { self.block = block }
    @objc private func run() { block() }

    static func item(_ title: String, checked: Bool = false, _ block: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(block)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.state = checked ? .on : .off
        return item
    }

    static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
