import Foundation

/// Shared compact duration labels used by complication sources and settings.
enum CompactDurationFormatter {
    static func hoursMinutes(
        _ interval: TimeInterval,
        rounding: FloatingPointRoundingRule = .down,
        includesZeroMinutes: Bool = true
    ) -> String {
        let minutes = max(Int((interval / 60).rounded(rounding)), 0)
        let hours = minutes / 60
        let remainder = minutes % 60
        guard hours > 0 else { return "\(remainder)m" }
        if remainder == 0, !includesZeroMinutes { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    static func largestUnit(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        let days = seconds / 86_400
        if days > 0 { return "\(days)d" }
        let hours = seconds / 3_600
        if hours > 0 { return "\(hours)h" }
        return "\(seconds / 60)m"
    }
}
