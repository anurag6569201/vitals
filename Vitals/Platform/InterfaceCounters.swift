import Darwin
import Foundation

/// Per-interface byte counters since the Mac started.
///
/// Uses the 64-bit counters from `sysctl(NET_RT_IFLIST2)`. Some drivers (Wi‑Fi) still roll
/// over at 4 GiB, so totals before Vitals started can't be trusted; deltas use `delta(_:since:)`.
enum InterfaceCounters {
    /// Not internet traffic (loopback, AirDrop, bridges, Thunderbolt networking…).
    static let skippedPrefixes = ["lo", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap", "XHC"]
    /// Tunnels whose traffic is also counted on the physical link.
    static let tunnelPrefixes = ["utun", "ipsec", "ppp"]

    static func read() -> [String: (down: UInt64, up: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (down: UInt64, up: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if !skippedPrefixes.contains(where: { name.hasPrefix($0) }) {
                            result[name] = (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    /// Bytes moved between two readings of one counter. Wi‑Fi drivers keep only 32 bits even in
    /// the 64-bit API, so the counter rolls over every 4 GiB: treat a drop below a 32-bit value
    /// as a rollover, not a reset. (Sampling every few seconds catches every rollover.)
    static func delta(_ new: UInt64, since old: UInt64) -> UInt64 {
        if new >= old { return new - old }
        if old <= UInt64(UInt32.max) { return (UInt64(UInt32.max) - old) + new + 1 }
        return new   // counter reset (interface recreated)
    }

    static func isTunnel(_ name: String) -> Bool {
        tunnelPrefixes.contains { name.hasPrefix($0) }
    }
}
