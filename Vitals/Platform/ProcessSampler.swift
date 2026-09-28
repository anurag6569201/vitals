import AppKit
import Darwin
import Foundation

/// Per-app CPU, energy and memory, aggregated from all of an app's processes
/// (Chrome's dozens of helpers become one "Google Chrome" line).
///
/// Uses libproc. Inside the App Sandbox these calls are denied, so `isAvailable`
/// becomes false and Vitals falls back to system-wide readings.
final class ProcessSampler {
    private struct ProcessKey: Hashable {
        let pid: pid_t
        let start: UInt64
    }

    private struct Previous {
        let cpuNanos: UInt64
        let energy: UInt64
    }

    private var previous: [ProcessKey: Previous] = [:]
    private var identities: [ProcessKey: AppIdentity] = [:]
    private var lastSample: Date?
    private let ownPID = getpid()
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    private(set) var isAvailable = true

    func sample(now: Date = Date()) -> [AppUsage] {
        let pids = Self.allPIDs()
        guard !pids.isEmpty else {
            isAvailable = false
            return []
        }

        let elapsed = lastSample.map { now.timeIntervalSince($0) } ?? 0
        lastSample = now

        var current: [ProcessKey: Previous] = [:]
        var byApp: [String: AppUsage] = [:]
        var readable = 0

        for pid in pids where pid > 0 && pid != ownPID {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            readable += 1

            let key = ProcessKey(pid: pid, start: info.ri_proc_start_abstime)
            let cpuTicks = info.ri_user_time &+ info.ri_system_time
            let cpuNanos = cpuTicks &* timebase.numer / timebase.denom
            let reading = Previous(cpuNanos: cpuNanos, energy: info.ri_billed_energy)
            current[key] = reading

            let identity: AppIdentity
            if let cached = identities[key] {
                identity = cached
            } else {
                identity = Self.identity(for: pid)
                identities[key] = identity
            }

            var cpuPercent = 0.0
            var energyRate = 0.0
            if let before = previous[key], elapsed > 0.2 {
                let cpuDelta = reading.cpuNanos >= before.cpuNanos ? reading.cpuNanos - before.cpuNanos : 0
                cpuPercent = Double(cpuDelta) / (elapsed * 1_000_000_000) * 100
                let energyDelta = reading.energy >= before.energy ? reading.energy - before.energy : 0
                energyRate = Double(energyDelta) / elapsed
            }

            var usage = byApp[identity.key] ?? AppUsage(identity: identity, cpuPercent: 0, energyRate: 0,
                                                       memoryBytes: 0, processCount: 0)
            usage.cpuPercent += cpuPercent
            usage.energyRate += energyRate
            usage.memoryBytes += info.ri_phys_footprint
            usage.processCount += 1
            byApp[identity.key] = usage
        }

        // If we can list PIDs but read almost none, we're sandboxed or restricted.
        isAvailable = readable > max(5, pids.count / 10)
        previous = current
        identities = identities.filter { current[$0.key] != nil }

        guard elapsed > 0 else { return [] }
        let all = Array(byApp.values)
        // Keep the snapshot small: the top apps by CPU, energy and memory.
        let top = Set(all.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(25).map(\.identity.key))
            .union(all.sorted { $0.energyRate > $1.energyRate }.prefix(10).map(\.identity.key))
            .union(all.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(10).map(\.identity.key))
        return all.filter { top.contains($0.identity.key) }.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    // MARK: - Helpers

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    static func name(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(cString: buffer) }
        return "Process \(pid)"
    }

    /// Maps a process to the outermost .app bundle that contains it.
    static func identity(for pid: pid_t, fallbackName: String? = nil) -> AppIdentity {
        // Works even inside the App Sandbox, for regular apps.
        if let running = NSRunningApplication(processIdentifier: pid), let url = running.bundleURL,
           running.activationPolicy != .prohibited, !url.path.contains(".app/") {
            let bundlePath = url.path
            let name = running.localizedName ?? url.deletingPathExtension().lastPathComponent
            return AppIdentity(key: running.bundleIdentifier ?? bundlePath, name: name, bundlePath: bundlePath,
                               bundleID: running.bundleIdentifier, isSystem: isSystemPath(bundlePath))
        }
        let executablePath = Self.path(for: pid)
        if let path = executablePath, let appRange = path.range(of: ".app/") {
            let bundlePath = String(path[..<appRange.lowerBound]) + ".app"
            let bundle = Bundle(path: bundlePath)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
            let bundleID = bundle?.bundleIdentifier
            return AppIdentity(key: bundleID ?? bundlePath, name: name, bundlePath: bundlePath,
                               bundleID: bundleID, isSystem: isSystemPath(bundlePath))
        }
        var processName = Self.name(for: pid)
        if processName.hasPrefix("Process "), let fallbackName { processName = fallbackName }
        let known = Knowledge.lookup(processName)
        return AppIdentity(key: "proc:\(processName)", name: known?.friendlyName ?? processName,
                           bundlePath: nil, bundleID: nil, isSystem: executablePath.map(isSystemPath) ?? true)
    }

    static func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/", "/Library/Developer/CommandLineTools/"]
            .contains { path.hasPrefix($0) }
    }
}
