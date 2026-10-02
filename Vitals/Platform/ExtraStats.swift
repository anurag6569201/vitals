import AppKit
import Combine
import CoreWLAN
import Foundation
import IOKit
import Network

/// Extra readings for a wider range of people: gamers (refresh rate, ping), people on Wi‑Fi
/// (signal), creators (disk speed) and laptop users (power draw, battery health).
/// Everything is sampled cheaply, and only while something on screen is showing it.
@MainActor
final class ExtraStats: ObservableObject {
    /// Current refresh rate of the main display, and its maximum (ProMotion goes up to 120 Hz).
    @Published private(set) var refreshHz: Int?
    @Published private(set) var maxRefreshHz: Int?
    /// Wi‑Fi signal in dBm (−30 excellent … −90 unusable) and link speed in Mbps.
    @Published private(set) var wifiRSSI: Int?
    @Published private(set) var wifiRateMbps: Double?
    /// Round-trip time to the internet, in milliseconds. Only measured when switched on.
    @Published private(set) var pingMs: Double?
    /// Disk throughput in bytes per second.
    @Published private(set) var diskRead: Double = 0
    @Published private(set) var diskWrite: Double = 0

    /// Off unless a ping reading is visible: it's the only reading that sends anything.
    var pingEnabled = false
    private var lastPing = Date.distantPast
    private var pinging = false
    private var previousDisk: (read: UInt64, write: UInt64, date: Date)?

    func sample(now: Date = Date()) {
        sampleDisplay()
        sampleWiFi()
        sampleDisk(now: now)
        if pingEnabled, !pinging, now.timeIntervalSince(lastPing) > 8 {
            lastPing = now
            measurePing()
        } else if !pingEnabled, pingMs != nil {
            pingMs = nil
        }
    }

    // MARK: Display

    private func sampleDisplay() {
        guard let screen = NSScreen.main else { return }
        let maxHz = screen.maximumFramesPerSecond
        var current = maxHz
        if let id = screen.displayID, let mode = CGDisplayCopyDisplayMode(id), mode.refreshRate > 0 {
            current = Int(mode.refreshRate.rounded())
        }
        if refreshHz != current { refreshHz = current }
        if maxRefreshHz != maxHz { maxRefreshHz = maxHz }
    }

    // MARK: Wi‑Fi

    private func sampleWiFi() {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            if wifiRSSI != nil { wifiRSSI = nil; wifiRateMbps = nil }
            return
        }
        let rssi = interface.rssiValue()
        let value = rssi == 0 ? nil : rssi
        if wifiRSSI != value { wifiRSSI = value }
        let rate = interface.transmitRate()
        let rateValue = rate > 0 ? rate : nil
        if wifiRateMbps != rateValue { wifiRateMbps = rateValue }
    }

    /// Plain-English signal quality.
    static func quality(rssi: Int) -> String {
        switch rssi {
        case (-55)...: "Excellent"
        case (-67)...: "Good"
        case (-75)...: "Fair"
        default: "Weak"
        }
    }

    // MARK: Disk

    private func sampleDisk(now: Date) {
        guard let totals = Self.readDiskTotals() else { return }
        defer { previousDisk = (totals.read, totals.write, now) }
        guard let old = previousDisk else { return }
        let seconds = max(now.timeIntervalSince(old.date), 0.5)
        let read = totals.read >= old.read ? Double(totals.read - old.read) / seconds : 0
        let write = totals.write >= old.write ? Double(totals.write - old.write) / seconds : 0
        diskRead = read
        diskWrite = write
    }

    /// Bytes read/written by all disks since boot, from the I/O Registry (read-only, no permission).
    nonisolated static func readDiskTotals() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0, found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found ? (read, write) : nil
    }

    // MARK: Ping

    /// Time to open a connection to Apple's connectivity-check server (no data is exchanged).
    private var pingToken = UUID()

    private func measurePing() {
        pinging = true
        let token = UUID()
        pingToken = token
        let start = Date()
        let connection = NWConnection(host: "captive.apple.com", port: 80, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            let value: Double?
            switch state {
            case .ready: value = Date().timeIntervalSince(start) * 1000
            case .failed, .cancelled: value = nil
            default: return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishPing(token: token, value: value, connection: connection) } }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finishPing(token: token, value: nil, connection: connection)
        }
    }

    private func finishPing(token: UUID, value: Double?, connection: NWConnection) {
        guard pingToken == token, pinging else { return }
        pinging = false
        connection.cancel()
        pingMs = value
    }
}
