import AppIntents
import Foundation

/// Shortcuts & Spotlight: "Toggle the Vitals pin", "How's my Mac in Vitals", etc.
/// They run inside the menu-bar app, so Vitals needs to be running (it usually is).

enum VitalsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    var localizedStringResource: LocalizedStringResource { "Open Vitals first, then try again." }
}

@MainActor
private func vitals() throws -> VitalsModel {
    guard let model = VitalsModel.shared else { throw VitalsIntentError.notRunning }
    return model
}

struct TogglePinIntent: AppIntent {
    static var title: LocalizedStringResource = "Show or Hide the Vitals Pin"
    static var description = IntentDescription("Pins live readings to the edge of your screen, or unpins them.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try vitals()
        model.settings.pin.enabled.toggle()
        return .result(dialog: model.settings.pin.enabled ? "Pinned to your screen." : "Unpinned.")
    }
}

struct KeepAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep My Mac Awake"
    static var description = IntentDescription("Stops your Mac from sleeping for a while.")

    @Parameter(title: "Minutes", default: 60, inclusiveRange: (5, 1440))
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try vitals()
        model.startKeepAwake(TimeInterval(minutes * 60))
        return .result(dialog: "Keeping your Mac awake for \(Format.duration(TimeInterval(minutes * 60))).")
    }
}

struct DataTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "How Much Data Did I Use Today"
    static var description = IntentDescription("Downloaded and uploaded today, counted by Vitals on this Mac.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try vitals()
        let today = model.network.total(.today)
        let text = "\(Format.bytes(UInt64(today.total))) today — \(Format.bytes(UInt64(today.down))) down, \(Format.bytes(UInt64(today.up))) up."
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct MacStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "How Is My Mac Doing"
    static var description = IntentDescription("A one-line health check: alerts, CPU, memory and battery.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try vitals()
        var parts: [String] = []
        parts.append(model.issues.isEmpty ? "Your Mac is healthy." : model.issues.prefix(2).map(\.headline).joined(separator: ". ") + ".")
        if let snap = model.snapshot {
            parts.append("CPU \(Format.percent(snap.cpuTotal)), memory \(Format.percent(snap.memoryUsed))")
            if let battery = snap.battery { parts.append("battery \(Format.percent(battery.level))") }
        }
        let text = parts.joined(separator: " ")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct VitalsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MacStatusIntent(),
                    phrases: ["How's my Mac in \(.applicationName)", "Check my Mac with \(.applicationName)"],
                    shortTitle: "Mac Status", systemImageName: "waveform.path.ecg")
        AppShortcut(intent: TogglePinIntent(),
                    phrases: ["Toggle the \(.applicationName) pin", "Pin \(.applicationName) to my screen"],
                    shortTitle: "Toggle Pin", systemImageName: "pin")
        AppShortcut(intent: DataTodayIntent(),
                    phrases: ["How much data did I use in \(.applicationName)"],
                    shortTitle: "Data Today", systemImageName: "chart.bar.xaxis")
        AppShortcut(intent: KeepAwakeIntent(),
                    phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Awake", systemImageName: "cup.and.saucer")
    }
}
