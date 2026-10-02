import Combine
import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Reads everything Vitals needs from macOS. All public APIs.
final class SystemSampler {
    private let processes = ProcessSampler()
    private var previousCPU: (active: UInt64, idle: UInt64)?
    private var previousInterfaces: (values: [String: (down: UInt64, up: UInt64)], date: Date)?
    private var cachedDisk: (free: UInt64?, total: UInt64?, date: Date)?
    private(set) var assertionsAvailable = true
    private(set) var batteryPowerAvailable = false

    var perAppAvailable: Bool { processes.isAvailable }

    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    func snapshot(isUserAway: Bool, now: Date = Date()) -> SystemSnapshot {
        let apps = processes.sample(now: now)
        let network = networkRates(now: now)
        let disk = diskSpace(now: now)
        let battery = batteryState()
        let assertions = powerAssertions()
        return SystemSnapshot(
            date: now,
            cpuTotal: cpuTotal() ?? 0,
            gpuUsage: gpuUsage(),
            memoryUsed: memoryUsed() ?? 0,
            memoryPressure: memoryPressure(),
            swapUsedBytes: swapUsed(),
            thermal: thermalLevel(),
            battery: battery,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            uptime: uptime(now: now),
            apps: apps,
            perAppAvailable: processes.isAvailable,
            assertions: assertions,
            downloadRate: network.down,
            uploadRate: network.up,
            isUserAway: isUserAway)
    }

    // MARK: CPU & memory

    private func cpuTotal() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let active = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
        let idle = UInt64(ticks.2)
        defer { previousCPU = (active, idle) }
        guard let previous = previousCPU else { return nil }
        let activeDelta = active >= previous.active ? active - previous.active : 0
        let idleDelta = idle >= previous.idle ? idle - previous.idle : 0
        let total = activeDelta + idleDelta
        return total > 0 ? Double(activeDelta) / Double(total) : nil
    }

    private func memoryUsed() -> Double? {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = Double(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used": app + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return min(max(used / total, 0), 1)
    }

    /// GPU utilization from the IOAccelerator's performance statistics (Apple silicon and most Intel/AMD GPUs).
    private func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber
                if let value { best = max(best ?? 0, min(value.doubleValue / 100, 1)) }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }

    private func memoryPressure() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    private func uptime(now: Date) -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return ProcessInfo.processInfo.systemUptime }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
        return now.timeIntervalSince(bootDate)
    }

    // MARK: Battery

    func batteryState() -> BatteryState? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String),
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let onAC = (description[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            var minutes = description[kIOPSTimeToEmptyKey as String] as? Int
            if let value = minutes, value <= 0 { minutes = nil }
            var toFull = description[kIOPSTimeToFullChargeKey as String] as? Int
            if let value = toFull, value <= 0 { toFull = nil }
            var state = BatteryState(level: min(max(Double(current) / Double(maximum), 0), 1),
                                     isCharging: charging, isOnAC: onAC, dischargeWatts: nil,
                                     minutesRemaining: onAC ? nil : minutes,
                                     minutesToFull: charging ? toFull : nil, cycleCount: nil, health: nil)
            addSmartBatteryDetails(to: &state)
            return state
        }
        return nil
    }

    private func addSmartBatteryDetails(to state: inout BatteryState) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
        }
        if let cycles = number("CycleCount") { state.cycleCount = cycles.intValue }
        // Some Macs only report capacities inside the "BatteryData" dictionary.
        let batteryData = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        func capacity(_ key: String) -> Double? {
            let value = number(key)?.doubleValue ?? (batteryData?[key] as? NSNumber)?.doubleValue
            return value.flatMap { $0 > 0 ? $0 : nil }
        }
        if state.cycleCount == nil, let cycles = batteryData?["CycleCount"] as? NSNumber { state.cycleCount = cycles.intValue }
        if let raw = capacity("AppleRawMaxCapacity") ?? capacity("NominalChargeCapacity") ?? capacity("FccComp1"),
           let design = capacity("DesignCapacity") {
            let ratio = raw / design
            if ratio > 0.2 && ratio < 1.5 { state.health = min(ratio, 1.0) }
        }
        if let amperage = number("InstantAmperage") ?? number("Amperage"), let voltage = number("Voltage") {
            let milliamps = Double(amperage.int64Value) // negative while discharging
            let watts = -milliamps * voltage.doubleValue / 1_000_000
            if !state.isOnAC && watts > 0.1 {
                state.dischargeWatts = watts
                batteryPowerAvailable = true
            }
        }
    }

    // MARK: Disk

    private func diskSpace(now: Date) -> (free: UInt64?, total: UInt64?) {
        if let cached = cachedDisk, now.timeIntervalSince(cached.date) < 60 { return (cached.free, cached.total) }
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        let total = values?.volumeTotalCapacity.map { UInt64(max(0, $0)) }
        cachedDisk = (free, total, now)
        return (free, total)
    }

    // MARK: Network

    private func networkRates(now: Date) -> (down: Double, up: Double) {
        // VPN tunnels are skipped: their traffic is already counted on Wi‑Fi or wired.
        let counters = InterfaceCounters.read().filter { !InterfaceCounters.isTunnel($0.key) }
        defer { previousInterfaces = (counters, now) }
        guard let previous = previousInterfaces else { return (0, 0) }
        let seconds = max(now.timeIntervalSince(previous.date), 0.1)
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, value) in counters {
            guard let old = previous.values[name] else { continue }
            down &+= InterfaceCounters.delta(value.down, since: old.down)
            up &+= InterfaceCounters.delta(value.up, since: old.up)
        }
        return (Double(down) / seconds, Double(up) / seconds)
    }

    // MARK: Power assertions

    private func powerAssertions() -> [PowerAssertion]? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() as NSDictionary? else {
            assertionsAvailable = false
            return nil
        }
        assertionsAvailable = true
        var result: [PowerAssertion] = []
        for (key, value) in dictionary {
            guard let pid = (key as? NSNumber)?.int32Value, pid != getpid(),
                  let list = value as? [[String: Any]] else { continue }
            for entry in list {
                let type = entry["AssertType"] as? String ?? ""
                let reason = entry["AssertName"] as? String ?? ""
                let processName = entry["Process Name"] as? String ?? ProcessSampler.name(for: pid)
                let owner = pid > 0 ? ProcessSampler.identity(for: pid, fallbackName: processName) : nil
                result.append(PowerAssertion(pid: pid, processName: processName, type: type,
                                             reason: reason, owner: owner))
            }
        }
        return result
    }
}
