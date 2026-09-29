import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import IOKit.pwr_mgt

/// Keep the Mac awake for a while — replaces a separate "caffeine" menu-bar app.
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var until: Date?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?

    var isOn: Bool { until != nil }

    var statusText: String? {
        guard let until else { return nil }
        if until == .distantFuture { return "Keeping awake" }
        return "Awake · \(Format.duration(until.timeIntervalSinceNow)) left"
    }

    /// nil duration = until turned off.
    func start(for duration: TimeInterval?, allowDisplaySleep: Bool) {
        stop()
        let type = (allowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep) as CFString
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Vitals Keep Awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else { return }
        until = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let until = self.until else { return }
                if until <= Date() { self.stop() } else { self.objectWillChange.send() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        until = nil
    }
}

/// A global keyboard shortcut that opens the Vitals popover.
@MainActor
final class HotKey {
    static var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false

    func register(_ choice: HotkeyChoice) {
        unregister()
        let combo: (key: Int, modifiers: Int)?
        switch choice {
        case .none: combo = nil
        case .optionCommandV: combo = (kVK_ANSI_V, cmdKey | optionKey)
        case .controlOptionV: combo = (kVK_ANSI_V, controlKey | optionKey)
        case .controlOptionSpace: combo = (kVK_Space, controlKey | optionKey)
        }
        guard let combo else { return }
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.action?() } }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5654_4C53), id: 1)
        RegisterEventHotKey(UInt32(combo.key), UInt32(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
