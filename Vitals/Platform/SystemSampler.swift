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
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?
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
            var state = BatteryState(level: min(max(Double(current) / Double(maximum), 0), 1),
                                     isCharging: charging, isOnAC: onAC, dischargeWatts: nil,
                                     minutesRemaining: onAC ? nil : minutes, cycleCount: nil, health: nil)
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
        if let raw = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"),
           let design = number("DesignCapacity"), design.doubleValue > 0 {
            state.health = min(raw.doubleValue / design.doubleValue, 1.0)
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
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let address = cursor {
            let flags = address.pointee.ifa_flags
            if let socket = address.pointee.ifa_addr, socket.pointee.sa_family == UInt8(AF_LINK),
               flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0,
               let raw = address.pointee.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            cursor = address.pointee.ifa_next
        }
        defer { previousNetwork = (received, sent, now) }
        guard let previous = previousNetwork else { return (0, 0) }
        let seconds = max(now.timeIntervalSince(previous.date), 0.1)
        let down = received >= previous.received ? Double(received - previous.received) / seconds : 0
        let up = sent >= previous.sent ? Double(sent - previous.sent) / seconds : 0
        return (down, up)
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
            guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [[String: Any]] else { continue }
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
