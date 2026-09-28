import Combine
import Foundation

/// Plain-English notes about macOS processes people see and worry about.
/// Matching is by process name prefix, case-insensitive.
struct KnownProcess {
    let match: String
    let friendlyName: String
    let explanation: String
    /// If true, this is expected, temporary work — Vitals explains it instead of suggesting Quit.
    let isExpectedWork: Bool
    /// If true, Vitals never raises a runaway alert for it.
    let neverAlert: Bool
}

enum Knowledge {
    static let processes: [KnownProcess] = [
        .init(match: "kernel_task", friendlyName: "macOS (kernel_task)",
              explanation: "macOS uses kernel_task to slow things down when your Mac is hot. It's a symptom, not the cause — look for what's heating your Mac.",
              isExpectedWork: true, neverAlert: true),
        .init(match: "WindowServer", friendlyName: "WindowServer",
              explanation: "WindowServer draws everything on screen. High usage usually comes from many windows, external displays, or animated content.",
              isExpectedWork: true, neverAlert: true),
        .init(match: "mds", friendlyName: "Spotlight indexing",
              explanation: "Spotlight is indexing your files. This is normal after a macOS update or when you add lots of files, and it finishes on its own.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "mdworker", friendlyName: "Spotlight indexing",
              explanation: "Spotlight is indexing your files. This is normal after a macOS update or when you add lots of files, and it finishes on its own.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "backupd", friendlyName: "Time Machine",
              explanation: "Time Machine is backing up. It slows down briefly and finishes on its own.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "photoanalysisd", friendlyName: "Photos analysis",
              explanation: "Photos is analysing your library for people, places and search. It runs mostly when your Mac is plugged in and idle.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "mediaanalysisd", friendlyName: "Photos analysis",
              explanation: "Photos is analysing your library for search. It pauses on battery and finishes eventually.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "softwareupdated", friendlyName: "Software Update",
              explanation: "macOS is downloading or preparing an update.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "bird", friendlyName: "iCloud Drive sync",
              explanation: "iCloud Drive is syncing files. Large uploads or downloads can keep it busy for a while.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "cloudd", friendlyName: "iCloud sync",
              explanation: "iCloud is syncing data. Large uploads or downloads can keep it busy for a while.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "fileproviderd", friendlyName: "Cloud file sync",
              explanation: "A cloud storage service (iCloud, Dropbox, Google Drive…) is syncing files.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "XprotectService", friendlyName: "XProtect malware scan",
              explanation: "macOS is scanning apps for malware. It's brief and important.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "syspolicyd", friendlyName: "App security check",
              explanation: "macOS is checking an app's signature, usually right after you install or update something.",
              isExpectedWork: true, neverAlert: false),
        .init(match: "coreaudiod", friendlyName: "Core Audio",
              explanation: "The audio system. It keeps your Mac awake while something is playing sound.",
              isExpectedWork: true, neverAlert: true),
        .init(match: "powerd", friendlyName: "Power management",
              explanation: "macOS power management.", isExpectedWork: true, neverAlert: true),
        .init(match: "launchd", friendlyName: "launchd",
              explanation: "The process that starts everything else.", isExpectedWork: true, neverAlert: true),
    ]

    static func lookup(_ processName: String) -> KnownProcess? {
        let lower = processName.lowercased()
        return processes.first { lower.hasPrefix($0.match.lowercased()) || lower == $0.friendlyName.lowercased() }
    }
}
