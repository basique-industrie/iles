import Domain
import Foundation

enum HarnaisRefreshPolicy {
    /// Allow two scheduled attempts, matching the monitor's battery cadence.
    /// Manual-only values still age, but they never inherit Harnais' feed age.
    static func staleAfter(interval: RefreshInterval, onBattery: Bool) -> TimeInterval {
        guard let seconds = interval.seconds else { return 900 }
        return max(240, Double(seconds * (onBattery ? 2 : 1) * 2))
    }
}
