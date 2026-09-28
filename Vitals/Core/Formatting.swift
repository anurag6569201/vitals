import Combine
import Foundation

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func cpu(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func diskBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        if bytesPerSecond >= 1_000 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    /// "2h 10m", "45m", "3d 4h"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    static func watts(_ value: Double) -> String {
        String(format: value >= 10 ? "%.0f W" : "%.1f W", value)
    }

    /// Short app name for the menu bar ("Google Chrome" -> "Chrome").
    static func shortName(_ name: String) -> String {
        let trimmed = name.replacingOccurrences(of: "Google ", with: "")
            .replacingOccurrences(of: "Microsoft ", with: "")
            .replacingOccurrences(of: "Adobe ", with: "")
        if trimmed.count <= 14 { return trimmed }
        return String(trimmed.prefix(13)) + "…"
    }
}
