import Combine
import Darwin
import Foundation
import IOKit.ps

@MainActor
final class VitalsMonitor: ObservableObject {
    @Published private(set) var downloadText = "—"
    @Published private(set) var uploadText = "—"
    @Published private(set) var cpuText = "—"
    @Published private(set) var memoryText = "—"
    @Published private(set) var batteryText = "—"
    @Published private(set) var cpuFraction = 0.0
    @Published private(set) var memoryFraction = 0.0
    @Published private(set) var batteryFraction = 0.0
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var insight = "Collecting live readings…"
    @Published private(set) var insightSymbol = "waveform.path.ecg"
    @Published private(set) var priorityMetric: MetricKind?

    private var timer: Timer?
    private var previousNetwork: NetworkCounters?
    private var previousCPU: CPUTicks?
    private var previousTime: Date?
    private var batteryIsCharging = false
    private var highCPUSamples = 0

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func value(for metric: MetricKind) -> String {
        switch metric {
        case .download: "↓ \(downloadText)"
        case .upload: "↑ \(uploadText)"
        case .cpu: "CPU \(cpuText)"
        case .memory: "MEM \(memoryText)"
        case .battery: "BAT \(batteryText)"
        }
    }

    func reading(for metric: MetricKind) -> String {
        switch metric {
        case .download: downloadText
        case .upload: uploadText
        case .cpu: cpuText
        case .memory: memoryText
        case .battery: batteryText
        }
    }

    func fraction(for metric: MetricKind) -> Double {
        switch metric {
        case .download, .upload: 0
        case .cpu: cpuFraction
        case .memory: memoryFraction
        case .battery: batteryFraction
        }
    }

    private func refresh() {
        let now = Date()
        let network = SystemSamples.network()
        let cpu = SystemSamples.cpuTicks()

        if let previousNetwork, let previousTime {
            let seconds = max(now.timeIntervalSince(previousTime), 0.1)
            let received = network.received >= previousNetwork.received
                ? network.received - previousNetwork.received : 0
            let sent = network.sent >= previousNetwork.sent
                ? network.sent - previousNetwork.sent : 0
            downloadText = Self.formatSpeed(Double(received) / seconds)
            uploadText = Self.formatSpeed(Double(sent) / seconds)
            downloadHistory.append(Double(received) / seconds)
            if downloadHistory.count > 30 { downloadHistory.removeFirst() }
        }

        if let cpu, let previousCPU {
            let active = cpu.active >= previousCPU.active ? cpu.active - previousCPU.active : 0
            let idle = cpu.idle >= previousCPU.idle ? cpu.idle - previousCPU.idle : 0
            let total = active + idle
            if total > 0 {
                cpuFraction = Double(active) / Double(total)
                cpuText = "\(Int((cpuFraction * 100).rounded()))%"
            }
        }

        if let memory = SystemSamples.memoryFraction() {
            memoryFraction = memory
            memoryText = "\(Int((memory * 100).rounded()))%"
        }

        if let battery = SystemSamples.battery() {
            batteryFraction = battery.fraction
            batteryText = "\(Int((battery.fraction * 100).rounded()))%"
            batteryIsCharging = battery.isCharging
        } else {
            batteryText = "N/A"
        }

        highCPUSamples = cpuFraction >= 0.85 ? min(highCPUSamples + 1, 3) : 0
        if batteryText != "N/A" && batteryFraction < 0.2 && !batteryIsCharging {
            insight = "Battery is low. Connect a charger soon."
            insightSymbol = "battery.25percent"
            priorityMetric = .battery
        } else if highCPUSamples >= 3 {
            insight = "CPU usage is high. Open Activity Monitor for details."
            insightSymbol = "cpu"
            priorityMetric = .cpu
        } else {
            insight = "Live readings refresh every 2 seconds."
            insightSymbol = "checkmark.circle"
            priorityMetric = nil
        }

        previousNetwork = network
        previousCPU = cpu
        previousTime = now
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }
}

private struct NetworkCounters {
    let received: UInt64
    let sent: UInt64
}

private struct CPUTicks {
    let active: UInt64
    let idle: UInt64
}

private enum SystemSamples {
    static func network() -> NetworkCounters {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            return NetworkCounters(received: 0, sent: 0)
        }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let address = current {
            let flags = address.pointee.ifa_flags
            if let socket = address.pointee.ifa_addr,
               socket.pointee.sa_family == UInt8(AF_LINK),
               flags & UInt32(IFF_UP) != 0,
               flags & UInt32(IFF_LOOPBACK) == 0,
               let rawData = address.pointee.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            current = address.pointee.ifa_next
        }
        return NetworkCounters(received: received, sent: sent)
    }

    static func cpuTicks() -> CPUTicks? {
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
        return CPUTicks(active: active, idle: UInt64(ticks.2))
    }

    static func memoryFraction() -> Double? {
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
        let availablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)
        let availableBytes = Double(availablePages) * Double(vm_page_size)
        return min(max(1 - availableBytes / total, 0), 1)
    }

    static func battery() -> (fraction: Double, isCharging: Bool)? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)
                .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            return (min(max(Double(current) / Double(maximum), 0), 1), charging)
        }
        return nil
    }
}
