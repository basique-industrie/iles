import Domain
import Foundation
import IOKit.ps

@MainActor
final class BatteryComplicationSource: ComplicationSource {
    let descriptor = ComplicationSourceDescriptor(
        id: "system.battery",
        name: "Mac Battery",
        kind: .system,
        symbol: "battery.75percent",
        metrics: [
            ComplicationMetricDescriptor(
                id: "level",
                name: "Charge level",
                kind: .gauge,
                symbol: "battery.75percent",
                unit: "%",
                policy: ComplicationMetricPolicy(
                    format: .percentage,
                    direction: .higherIsBetter,
                    range: 0...100,
                    thresholds: ComplicationThreshold(warning: 20, critical: 10),
                    refreshClass: .periodicLocal,
                    staleAfter: 60
                )
            ),
            ComplicationMetricDescriptor(id: "power", name: "Power state", kind: .status, symbol: "bolt"),
            ComplicationMetricDescriptor(id: "remaining", name: "Time remaining", kind: .duration, symbol: "timer"),
            ComplicationMetricDescriptor(id: "health", name: "Battery health", kind: .status, symbol: "heart.text.square"),
        ],
        supportedFamilies: [.ring, .value, .status, .countdown, .summary],
        complications: FirstPartyComplicationCatalog.batteryRecipes,
        capabilities: [.systemHealth]
    )

    /// IOKit values are cheap local reads. Returning a fresh snapshot avoids a
    /// battery complication becoming permanently stale when provider refresh is off.
    var currentSnapshot: SourceSnapshot { readSnapshot() }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot { readSnapshot() }

    private func readSnapshot() -> SourceSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let description = sources.lazy.compactMap({ source in
                  IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
              }).first(where: { Self.bool($0[kIOPSIsPresentKey]) != false })
        else {
            return Self.snapshot(from: nil)
        }
        return Self.snapshot(from: description)
    }

    static func snapshot(
        from description: [String: Any]?,
        capturedAt: Date = Date()
    ) -> SourceSnapshot {
        guard let description,
              bool(description[kIOPSIsPresentKey]) != false,
              let current = number(description[kIOPSCurrentCapacityKey]),
              let maximum = number(description[kIOPSMaxCapacityKey]),
              maximum > 0
        else {
            return SourceSnapshot(
                sourceID: "system.battery",
                capturedAt: capturedAt,
                values: ["power": .status(label: "Unavailable", level: .inactive)],
                errorDescription: "No internal battery was detected on this Mac.",
                quality: .unavailable,
                availability: ComplicationAvailability(
                    state: .unsupported,
                    message: "This Mac has no internal battery.",
                    recoveryAction: .none
                )
            )
        }

        let percent = min(max(current / maximum * 100, 0), 100)
        let charging = bool(description[kIOPSIsChargingKey]) ?? false
        let rawPowerState = description[kIOPSPowerSourceStateKey] as? String
        let powerLabel: String
        if charging {
            powerLabel = "Charging"
        } else if rawPowerState == kIOPSACPowerValue {
            powerLabel = "Plugged"
        } else {
            powerLabel = "Battery"
        }

        let powerLevel: StatusLevel
        if percent <= 10, !charging {
            powerLevel = .critical
        } else if percent <= 20, !charging {
            powerLevel = .warning
        } else {
            powerLevel = .healthy
        }

        var values: [String: ComplicationValue] = [
            "level": .gauge(value: percent, range: 0...100, label: "\(Int(percent.rounded()))%"),
            "power": .status(label: powerLabel, level: powerLevel),
        ]

        let rawMinutes = charging
            ? number(description[kIOPSTimeToFullChargeKey])
            : number(description[kIOPSTimeToEmptyKey])
        if let rawMinutes, rawMinutes >= 0 {
            let seconds = rawMinutes * 60
            values["remaining"] = .duration(
                seconds,
                label: CompactDurationFormatter.hoursMinutes(
                    seconds,
                    rounding: .toNearestOrAwayFromZero
                )
            )
        }

        if let health = description[kIOPSBatteryHealthKey] as? String, !health.isEmpty {
            let normalized = health.lowercased()
            let level: StatusLevel = normalized == kIOPSGoodValue.lowercased() ? .healthy : .warning
            values["health"] = .status(label: health, level: level)
        }

        return SourceSnapshot(
            sourceID: "system.battery",
            capturedAt: capturedAt,
            values: values
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

}
