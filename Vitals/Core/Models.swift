import Combine
import Foundation

// MARK: - Severity

enum Severity: Int, Codable, Comparable, CaseIterable {
    case calm = 0
    case notice = 1
    case warning = 2
    case critical = 3

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .calm: "All good"
        case .notice: "Heads up"
        case .warning: "Needs attention"
        case .critical: "Act now"
        }
    }
}

// MARK: - Issue kinds

enum IssueKind: String, Codable, CaseIterable, Identifiable {
    case runawayApp
    case heat
    case memoryPressure
    case batteryDrain
    case sleepBlocker
    case lowDisk
    case longUptime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runawayApp: "Runaway apps"
        case .heat: "Heat"
        case .memoryPressure: "Memory pressure"
        case .batteryDrain: "Fast battery drain"
        case .sleepBlocker: "Apps keeping your Mac awake"
        case .lowDisk: "Low disk space"
        case .longUptime: "Restart reminder"
        }
    }

    var explanation: String {
        switch self {
        case .runawayApp: "An app keeps a processor core busy for minutes at a time."
        case .heat: "macOS reports your Mac is running hot and may slow itself down."
        case .memoryPressure: "Your Mac ran out of free memory and is swapping to disk."
        case .batteryDrain: "Your battery is emptying much faster than it usually does."
        case .sleepBlocker: "An app stops your Mac from sleeping while you're away."
        case .lowDisk: "Free space is low enough to slow macOS down or block updates."
        case .longUptime: "Your Mac hasn't restarted in a long time."
        }
    }

    var symbol: String {
        switch self {
        case .runawayApp: "flame"
        case .heat: "thermometer.high"
        case .memoryPressure: "memorychip"
        case .batteryDrain: "battery.25percent"
        case .sleepBlocker: "moon.zzz"
        case .lowDisk: "internaldrive"
        case .longUptime: "arrow.clockwise"
        }
    }

    /// Kinds that need Vitals Pro. Free users still see that something was found.
    var requiresPro: Bool {
        switch self {
        case .batteryDrain, .sleepBlocker: true
        default: false
        }
    }
}

// MARK: - Apps & processes

struct AppIdentity: Hashable, Codable {
    /// Stable key: bundle identifier, else bundle path, else "proc:<name>".
    let key: String
    let name: String
    let bundlePath: String?
    let bundleID: String?
    /// True for macOS components (paths under /System, /usr, /sbin, /bin, /Library/Apple).
    let isSystem: Bool

    var canQuit: Bool { bundlePath != nil && !isSystem }
}

struct AppUsage: Hashable {
    let identity: AppIdentity
    /// 100 = one full core.
    var cpuPercent: Double
    /// Relative energy (nanojoules per second, "billed energy"); 0 when unavailable.
    var energyRate: Double
    var memoryBytes: UInt64
    var processCount: Int
}

struct PowerAssertion: Hashable, Codable {
    let pid: Int32
    let processName: String
    let type: String
    let reason: String
    let owner: AppIdentity?

    /// Whether this assertion stops the whole system from idle-sleeping.
    var preventsSystemSleep: Bool {
        ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"].contains(type)
    }
}

// MARK: - System state

enum ThermalLevel: Int, Codable, Comparable {
    case nominal = 0, fair = 1, serious = 2, critical = 3
    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .nominal: "Cool"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        }
    }
}

enum MemoryPressureLevel: Int, Codable, Comparable {
    case normal = 0, warning = 1, critical = 2
    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Tight"
        case .critical: "Critical"
        }
    }
}

struct BatteryState: Hashable {
    /// 0...1
    var level: Double
    var isCharging: Bool
    var isOnAC: Bool
    /// Positive while discharging, in watts. Nil if the battery doesn't report it.
    var dischargeWatts: Double?
    var minutesRemaining: Int?
    var cycleCount: Int?
    /// 0...1 of design capacity.
    var health: Double?
}

struct SystemSnapshot {
    var date: Date
    var cpuTotal: Double
    /// 0...1, nil if the GPU doesn't report it.
    var gpuUsage: Double?
    var memoryUsed: Double
    var memoryPressure: MemoryPressureLevel
    var swapUsedBytes: UInt64
    var thermal: ThermalLevel
    var battery: BatteryState?
    var diskFreeBytes: UInt64?
    var diskTotalBytes: UInt64?
    var uptime: TimeInterval
    /// Sorted by CPU, descending. Empty when per-app data is unavailable (App Sandbox).
    var apps: [AppUsage]
    var perAppAvailable: Bool
    /// Nil when unavailable.
    var assertions: [PowerAssertion]?
    var downloadRate: Double
    var uploadRate: Double
    var isUserAway: Bool

    var topByEnergy: [AppUsage] {
        apps.filter { $0.energyRate > 0 }.sorted { $0.energyRate > $1.energyRate }
    }

    var topByMemory: [AppUsage] {
        apps.sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

// MARK: - Issues & actions

enum IssueAction: String, Codable, Hashable {
    case quitApp
    case forceQuitApp
    case ignoreApp
    case snooze
    case openActivityMonitor
    case openStorageSettings
    case openBatterySettings
    case showAwayReport
    case findSpaceHogs

    var title: String {
        switch self {
        case .quitApp: "Quit"
        case .forceQuitApp: "Force Quit"
        case .ignoreApp: "Always ignore"
        case .snooze: "Snooze 1 hour"
        case .openActivityMonitor: "Activity Monitor"
        case .openStorageSettings: "Manage Storage"
        case .openBatterySettings: "Battery Settings"
        case .showAwayReport: "See report"
        case .findSpaceHogs: "Free up space"
        }
    }
}

struct Issue: Identifiable, Hashable {
    /// kind + subject; stable while the same problem persists.
    let id: String
    let kind: IssueKind
    var severity: Severity
    /// "Google Chrome is working hard"
    var headline: String
    /// Plain-English explanation and what to do.
    var detail: String
    /// Short text for the menu bar, e.g. "Chrome 180%".
    var shortLabel: String
    var subject: AppIdentity?
    var actions: [IssueAction]
    var since: Date

    var primaryAction: IssueAction? { actions.first }
}
