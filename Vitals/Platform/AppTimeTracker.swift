import AppKit
import Combine
import CoreGraphics
import Foundation

/// "Where your time went": how long each app has been in front, today and this week.
/// Uses only what the App Sandbox allows (the frontmost app), stays on this Mac, and doesn't
/// count time while you're away from the keyboard or the screen is off.
@MainActor
final class AppTimeTracker: ObservableObject {
    enum Span: String, CaseIterable, Identifiable {
        case today, week
        var id: String { rawValue }
        var title: String { self == .today ? "Today" : "7 days" }
    }

    struct Entry: Identifiable, Hashable {
        let id: String      // bundle identifier
        let name: String
        let seconds: TimeInterval
        var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    }

    /// day ("2026-09-29") → bundle id → seconds
    @Published private(set) var days: [String: [String: Double]] = [:]
    private var names: [String: String] = [:]

    private var lastTick = Date()
    private var screenAsleep = false
    private var lastSave = Date.distantPast
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private static let storageKey = "vitals.appTime.v1"
    private static let namesKey = "vitals.appTime.names.v1"
    /// No keyboard or mouse for this long counts as away.
    private static let idleLimit: TimeInterval = 120
    private static let keepDays = 35
    private static let ignored: Set<String> = [
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.UserNotificationCenter",
    ]

    init() {
        load()
        let center = NSWorkspace.shared.notificationCenter
        let pause: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let resume: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in pause {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.tick(); self?.screenAsleep = true }
            })
        }
        for name in resume {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenAsleep = false; self?.lastTick = Date() }
            })
        }
        // Credit time when you switch apps, so short visits are counted to the right app.
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 5
    }

    // MARK: Counting

    private var frontmost: (id: String, name: String)?

    func tick() {
        let now = Date()
        let elapsed = min(now.timeIntervalSince(lastTick), 60)
        lastTick = now
        defer { frontmost = currentFrontmost() }
        guard elapsed > 0, !screenAsleep, let app = frontmost, !isIdle() else { return }
        let day = Self.dayKey(now)
        days[day, default: [:]][app.id, default: 0] += elapsed
        names[app.id] = app.name
        if now.timeIntervalSince(lastSave) > 60 { save() }
    }

    private func currentFrontmost() -> (id: String, name: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier, !Self.ignored.contains(id) else { return nil }
        return (id, app.localizedName ?? id)
    }

    private func isIdle() -> Bool {
        guard let anyInput = CGEventType(rawValue: ~0) else { return false }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > Self.idleLimit
    }

    // MARK: Reading

    func entries(_ span: Span) -> [Entry] {
        var totals: [String: Double] = [:]
        for key in dayKeys(span) {
            for (id, seconds) in days[key] ?? [:] { totals[id, default: 0] += seconds }
        }
        return totals.filter { $0.value >= 60 }
            .map { Entry(id: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    func total(_ span: Span) -> TimeInterval {
        dayKeys(span).reduce(0) { sum, key in sum + (days[key]?.values.reduce(0, +) ?? 0) }
    }

    private func dayKeys(_ span: Span) -> [String] {
        let count = span == .today ? 1 : 7
        return (0..<count).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map(Self.dayKey)
        }
    }

    func reset() {
        days = [:]
        names = [:]
        save()
    }

    // MARK: Storage

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            days = saved
        }
        names = defaults.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func save() {
        lastSave = Date()
        let keep = Set((0..<Self.keepDays).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date()).map(Self.dayKey)
        })
        days = days.filter { keep.contains($0.key) }
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
        UserDefaults.standard.set(names, forKey: Self.namesKey)
    }
}
