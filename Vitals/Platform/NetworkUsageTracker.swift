import AppKit
import Combine
import Foundation

/// "Where your data went": how much this Mac downloaded and uploaded, hour by hour, split by
/// connection (Wi‑Fi, wired, VPN), and — in the direct edition — by app.
/// Everything is counted and kept on this Mac.
@MainActor
final class NetworkUsageTracker: ObservableObject {
    enum Span: String, CaseIterable, Identifiable {
        case today, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: "Today"
            case .week: "7 days"
            case .month: "30 days"
            }
        }
        var days: Int {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            }
        }
    }

    enum Connection: String, CaseIterable, Identifiable {
        case wifi, wired, vpn, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wifi: "Wi‑Fi"
            case .wired: "Wired"
            case .vpn: "VPN"
            case .other: "Other"
            }
        }
        var symbol: String {
            switch self {
            case .wifi: "wifi"
            case .wired: "cable.connector"
            case .vpn: "lock.shield"
            case .other: "network"
            }
        }
    }

    struct Bucket: Codable, Equatable {
        var down: Double = 0
        var up: Double = 0
        /// Connection raw value → bytes (down + up).
        var byConnection: [String: Double] = [:]
        var total: Double { down + up }
    }

    struct AppEntry: Identifiable, Hashable {
        let id: String      // process name
        let down: Double
        let up: Double
        var total: Double { down + up }
        var appURL: URL? {
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == id || $0.executableURL?.lastPathComponent == id }?.bundleURL
        }
    }

    struct Point: Identifiable, Hashable {
        let id: Date
        let down: Double
        let up: Double
    }

    /// "2026-10-02T14" → bucket.
    @Published private(set) var hours: [String: Bucket] = [:]
    /// "2026-10-02" → process name → [down, up]. Direct edition only.
    @Published private(set) var apps: [String: [String: [Double]]] = [:]
    /// Last ~2 minutes of live speed, for the sparkline.
    @Published private(set) var live: [Point] = []
    @Published private(set) var vpnActive = false
    /// Per app, since each app opened (direct edition). Also available immediately.
    @Published private(set) var appsSinceOpened: [AppEntry] = []

    /// The sandboxed App Store build can't see other apps' traffic.
    static var perAppAvailable: Bool { !Edition.isAppStore }

    private var previous: [String: (down: UInt64, up: UInt64)] = [:]
    private var previousApps: [String: (down: Double, up: Double)] = [:]
    private var lastAppSample = Date.distantPast // first tick samples right away
    private var appSampleRunning = false
    private var lastSave = Date.distantPast
    private var wifiNames: Set<String> = []

    private static let hoursKey = "vitals.network.hours.v1"
    private static let appsKey = "vitals.network.apps.v1"
    private static let keepDays = 31

    init() {
        load()
        wifiNames = Self.findWiFiInterfaces()
    }

    // MARK: Sampling

    /// Called on every Vitals tick.
    func sample(downRate: Double, upRate: Double, now: Date = Date()) {
        live.append(Point(id: now, down: downRate, up: upRate))
        if live.count > 60 { live.removeFirst(live.count - 60) }

        let counters = InterfaceCounters.read()
        var bucket = hours[Self.hourKey(now)] ?? Bucket()
        var changed = false
        var sawVPN = false
        for (name, value) in counters {
            let kind = connection(for: name)
            defer { previous[name] = value }
            guard let old = previous[name] else { continue }
            let down = Double(InterfaceCounters.delta(value.down, since: old.down))
            let up = Double(InterfaceCounters.delta(value.up, since: old.up))
            guard down + up > 0, down + up < 50_000_000_000 else { continue }
            // macOS keeps a few system tunnels (utun) open with a trickle of traffic. Only a
            // real VPN moves more than a few KB a second through them.
            if kind == .vpn {
                guard down + up > 40_000 else { continue }
                sawVPN = true
            }
            // VPN traffic also flows over the physical link, so it's shown as a share but
            // not added to the totals twice.
            if kind != .vpn {
                bucket.down += down
                bucket.up += up
            }
            bucket.byConnection[kind.rawValue, default: 0] += down + up
            changed = true
        }
        if vpnActive != sawVPN { vpnActive = sawVPN }
        if changed { hours[Self.hourKey(now)] = bucket }

        if Self.perAppAvailable, now.timeIntervalSince(lastAppSample) > 20, !appSampleRunning {
            lastAppSample = now
            sampleApps(day: Self.dayKey(now))
        }
        if now.timeIntervalSince(lastSave) > 120 { save() }
    }

    private func sampleApps(day: String) {
        appSampleRunning = true
        Task.detached(priority: .utility) {
            let totals = NetworkUsageTracker.readPerProcess()
            await MainActor.run { self.ingestApps(totals, day: day) }
        }
    }

    private func ingestApps(_ totals: [String: (name: String, down: Double, up: Double)], day: String) {
        appSampleRunning = false
        guard !totals.isEmpty else { return }
        var opened: [String: [Double]] = [:]
        for value in totals.values {
            var pair = opened[value.name] ?? [0, 0]
            pair[0] += value.down
            pair[1] += value.up
            opened[value.name] = pair
        }
        appsSinceOpened = opened.map { AppEntry(id: $0.key, down: $0.value[0], up: $0.value[1]) }
            .filter { $0.total >= 100_000 }
            .sorted { $0.total > $1.total }
        var today = apps[day] ?? [:]
        for (key, value) in totals {
            defer { previousApps[key] = (value.down, value.up) }
            guard let old = previousApps[key] else { continue }
            let down = max(0, value.down - old.down), up = max(0, value.up - old.up)
            guard down + up > 0 else { continue }
            var pair = today[value.name] ?? [0, 0]
            pair[0] += down
            pair[1] += up
            today[value.name] = pair
        }
        previousApps = previousApps.filter { totals[$0.key] != nil }
        apps[day] = today
    }

    private func connection(for interface: String) -> Connection {
        if interface.hasPrefix("utun") || interface.hasPrefix("ipsec") || interface.hasPrefix("ppp") { return .vpn }
        if wifiNames.contains(interface) { return .wifi }
        if interface.hasPrefix("en") { return .wired }
        return .other
    }

    // MARK: Reading

    private func hourKeys(_ span: Span, now: Date = Date()) -> [String] {
        dayKeys(span, now: now).flatMap { day in (0..<24).map { String(format: "%@T%02d", day, $0) } }
    }

    func dayKeys(_ span: Span, now: Date = Date()) -> [String] {
        (0..<span.days).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: now).map(Self.dayKey)
        }
    }

    func total(_ span: Span) -> Bucket {
        var result = Bucket()
        for key in hourKeys(span) {
            guard let b = hours[key] else { continue }
            result.down += b.down
            result.up += b.up
            for (k, v) in b.byConnection { result.byConnection[k, default: 0] += v }
        }
        return result
    }

    /// Today: 24 hourly points. 7 or 30 days: one point per day, oldest first.
    func series(_ span: Span, now: Date = Date()) -> [Point] {
        let calendar = Calendar.current
        if span == .today {
            let start = calendar.startOfDay(for: now)
            return (0..<24).map { hour in
                let date = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
                let b = hours[Self.hourKey(date)] ?? Bucket()
                return Point(id: date, down: b.down, up: b.up)
            }
        }
        return (0..<span.days).reversed().map { offset in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: now) ?? now)
            let day = Self.dayKey(date)
            var down = 0.0, up = 0.0
            for hour in 0..<24 {
                if let b = hours[String(format: "%@T%02d", day, hour)] { down += b.down; up += b.up }
            }
            return Point(id: date, down: down, up: up)
        }
    }

    func appEntries(_ span: Span) -> [AppEntry] {
        var totals: [String: [Double]] = [:]
        for day in dayKeys(span) {
            for (raw, pair) in apps[day] ?? [:] {
                let name = Self.prettify(raw)   // also folds names saved by older versions
                var t = totals[name] ?? [0, 0]
                t[0] += pair[0]
                t[1] += pair.count > 1 ? pair[1] : 0
                totals[name] = t
            }
        }
        return totals.map { AppEntry(id: $0.key, down: $0.value[0], up: $0.value[1]) }
            .filter { $0.total >= 100_000 }
            .sorted { $0.total > $1.total }
    }

    /// The hour (today) or day (longer spans) that used the most data.
    func busiest(_ span: Span) -> Point? {
        series(span).filter { $0.down + $0.up > 0 }.max { $0.down + $0.up < $1.down + $1.up }
    }

    func reset() {
        hours = [:]
        apps = [:]
        save()
    }

    // MARK: Platform

    /// Time since the Mac started, including sleep (matches the counters and the Uptime tile).
    nonisolated static func timeSinceBoot() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Date().timeIntervalSince1970 - (Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }

    private static func findWiFiInterfaces() -> Set<String> {
        // Wi‑Fi hardware ports, without needing CoreWLAN or location access.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallhardwareports"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return ["en0"] }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        var names: Set<String> = []
        var wifiPort = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("Hardware Port:") {
                wifiPort = line.contains("Wi-Fi") || line.contains("AirPort")
            } else if wifiPort, line.hasPrefix("Device:") {
                names.insert(line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces))
                wifiPort = false
            }
        }
        return names.isEmpty ? ["en0"] : names
    }

    /// Cumulative bytes per process from macOS's own `nettop` (direct edition only).
    nonisolated static func readPerProcess() -> [String: (name: String, down: Double, up: Double)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var result: [String: (name: String, down: Double, up: Double)] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let down = Double(fields[1]), let up = Double(fields[2]) else { continue }
            let key = String(fields[0])                       // "Safari.123"
            var name = key
            if let dot = key.lastIndex(of: "."), Int(key[key.index(after: dot)...]) != nil {
                name = String(key[..<dot])
            }
            result[key] = (prettify(name), down, up)
        }
        return result
    }

    /// Helper processes count toward the app people recognise.
    nonisolated static func prettify(_ name: String) -> String {
        let map: [(String, String)] = [
            ("com.apple.WebKi", "Safari"), ("Safari", "Safari"), ("Google Chrome", "Google Chrome"),
            ("Chrome Helper", "Google Chrome"), ("Brave Browser", "Brave Browser"), ("Microsoft Edge", "Microsoft Edge"),
            ("firefox", "Firefox"), ("Arc", "Arc"), ("Slack", "Slack"), ("Discord", "Discord"), ("zoom.us", "Zoom"),
            ("Spotify", "Spotify"), ("Dropbox", "Dropbox"), ("nsurlsessiond", "Background downloads"),
            ("softwareupdated", "Software Update"), ("cloudd", "iCloud"), ("bird", "iCloud Drive"),
            ("mDNSResponder", "Network services"), ("apsd", "Push notifications"), ("photolibraryd", "Photos"),
            ("Code Helper", "Visual Studio Code"), ("Electron", "Electron apps"), ("Teams", "Microsoft Teams"),
        ]
        for (prefix, pretty) in map where name.hasPrefix(prefix) { return pretty }
        // "Claude Helper (Renderer)", "Slack Helper (GPU)" → the app itself.
        for marker in [" Helper", " Web Content", " Networking", " Renderer"] {
            if let range = name.range(of: marker), range.lowerBound > name.startIndex {
                return String(name[..<range.lowerBound])
            }
        }
        return name
    }

    // MARK: Storage

    static func hourKey(_ date: Date) -> String {
        let p = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        return String(format: "%04d-%02d-%02dT%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0)
    }

    static func dayKey(_ date: Date) -> String {
        let p = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.hoursKey),
           let saved = try? JSONDecoder().decode([String: Bucket].self, from: data) { hours = saved }
        if let data = defaults.data(forKey: Self.appsKey),
           let saved = try? JSONDecoder().decode([String: [String: [Double]]].self, from: data) { apps = saved }
    }

    func save() {
        lastSave = Date()
        let cutoff = Self.dayKey(Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Date()) ?? Date())
        hours = hours.filter { String($0.key.prefix(10)) >= cutoff }
        apps = apps.filter { $0.key >= cutoff }
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(hours) { defaults.set(data, forKey: Self.hoursKey) }
        if let data = try? JSONEncoder().encode(apps) { defaults.set(data, forKey: Self.appsKey) }
    }
}
