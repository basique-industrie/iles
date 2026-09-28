import Domain
import SwiftUI
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runIslandPresentationTests(_ test: TestHarness) {
        test.expectEqual(ComplicationUsageStyle.clampedProgress(0), 0, "zero usage has no progress fill")
        test.expectEqual(ComplicationUsageStyle.clampedProgress(0.01), 0.01, "tiny usage is never exaggerated")
        test.expectEqual(ComplicationUsageStyle.clampedProgress(1), 1, "full usage fills the complete ring")
        test.expectEqual(ComplicationUsageStyle.clampedProgress(1.4), 1, "over-limit usage cannot overflow the track")
        test.expectEqual(ComplicationUsageStyle.clampedProgress(-1), 0, "negative usage cannot reverse the fill")
        test.expectEqual(ComplicationUsageStyle.clampedProgress(.nan), 0, "invalid samples cannot produce invalid geometry")
        let thresholdMetric = ComplicationMetricDescriptor(
            id: "quota", name: "Usage", kind: .gauge,
            policy: ComplicationMetricPolicy(format: .percentage, direction: .lowerIsBetter, range: 0...100,
                                             thresholds: ComplicationThreshold(warning: 80, critical: 95)))
        let thresholdDescriptor = ComplicationSourceDescriptor(
            id: "codex", name: "Codex", kind: .usage, symbol: "circle", metrics: [thresholdMetric],
            supportedFamilies: [.ring])
        var usageConfig = ComplicationConfiguration(sourceID: "codex", metricIDs: ["quota"])
        let usedStyle = ComplicationUsageStyle(complication: usageConfig, descriptor: thresholdDescriptor)
        test.expectEqual(usedStyle.color(at: 0, value: .gauge(value: 85, range: 0...100, label: "")), Color.orange,
                         "rings and detail bars share the warning color")
        test.expectEqual(usedStyle.color(at: 0, value: .gauge(value: 96, range: 0...100, label: "")), Color.red,
                         "critical usage keeps its alert color")
        usageConfig.slotValueModes = [.remaining]
        let remainingStyle = ComplicationUsageStyle(complication: usageConfig, descriptor: thresholdDescriptor)
        test.expectEqual(remainingStyle.color(at: 0, value: .gauge(value: 15, range: 0...100, label: "")), Color.orange,
                         "remaining mode reverses the warning threshold")
        test.expectEqual(remainingStyle.color(at: 0, value: .gauge(value: 4, range: 0...100, label: "")), Color.red,
                         "remaining mode reverses the critical threshold")
        test.expectEqual(remainingStyle.color(at: 0, value: .gauge(value: 75, range: 0...100, label: "")), remainingStyle.accent(at: 0),
                         "healthy remaining capacity keeps its provider accent")
        let systemValues = Dictionary(uniqueKeysWithValues: (0..<10).map { ("metric\($0)", ComplicationValue.value("42", unit: nil)) })
        let systemSnapshot = SourceSnapshot(sourceID: "system.mac", values: systemValues)
        test.expectEqual(ComplicationDetailView.preferredHeight(snapshot: systemSnapshot, metricIDs: ["metric0"]), 160,
                         "single storage details ignore unrelated system readings when sizing")
        test.expectEqual(ComplicationDetailView.preferredHeight(snapshot: systemSnapshot, metricIDs: ["metric0", "metric1"]), 204,
                         "paired system widgets reserve room for two displayed readings")
        test.expectEqual(ComplicationDetailView.preferredHeight(snapshot: systemSnapshot, metricIDs: []), 204,
                         "generic fallback sizes only its two rendered readings")
        let storageLabel = CompactByteLabel(value: .value("56.74 GB", unit: nil))
        test.expectEqual(storageLabel?.amount, "56.74", "compact storage retains the exact amount")
        test.expectEqual(storageLabel?.unit, "GB", "compact storage places the unit on its own line")
        test.expectEqual(CompactByteLabel(value: .value("56,74\u{202F}Go", unit: nil))?.amount, "56,74",
                         "localized storage labels support nonbreaking spaces")
        test.expectEqual(CompactByteLabel(value: .value("512", unit: "MB"))?.unit, "MB",
                         "structured byte values preserve their explicit unit")
        test.expect(CompactByteLabel(value: .value("—", unit: nil)) == nil,
                    "missing storage never fabricates a unit")
        let sourceID = ProviderIdentity.harnais.rawValue
        let sessionID = "quota.key.time:Claude · old-alias 5h"
        let weeklyID = "quota.key.time:Claude · old-alias 7d"
        func descriptor(_ names: [(String, String)]) -> ComplicationSourceDescriptor {
            ComplicationSourceDescriptor(
                id: sourceID,
                name: "Harnais",
                kind: .usage,
                symbol: "circle",
                metrics: names.map { ComplicationMetricDescriptor(id: $0.0, name: $0.1, kind: .gauge) },
                supportedFamilies: [.ring, .dualRing]
            )
        }
        let renamed = descriptor([
            (sessionID, "Claude · Work 1 · 5h"),
            (weeklyID, "Claude · Work 1 · 7d"),
        ])
        test.expectEqual(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [sessionID, weeklyID], descriptor: renamed),
            "Work 1",
            "island account labels follow current aliases rather than stored keys"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: sessionID, descriptor: renamed),
            "Session",
            "first Claude ring has an explicit session caption"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: weeklyID, descriptor: renamed),
            "Week",
            "weekly rail captions fit without ambiguous single-letter abbreviations"
        )
        test.expectEqual(
            HarnaisGlance.detailSubtitle(sourceID: sourceID, metricIDs: [sessionID, weeklyID], metricName: nil, descriptor: renamed),
            "Work 1",
            "dual-ring details do not imply that both metrics are session usage"
        )
        test.expectEqual(
            HarnaisGlance.detailSubtitle(sourceID: sourceID, metricIDs: [weeklyID], metricName: nil, descriptor: renamed),
            "Work 1 · Weekly",
            "single-ring details retain the focused window"
        )
        test.expect(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [weeklyID], descriptor: nil) == nil,
            "missing descriptors never turn stale metric aliases into account names"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: weeklyID, descriptor: nil),
            "Week",
            "missing descriptors still allow known window captions"
        )
        test.expect(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [weeklyID, "missing"], descriptor: renamed) == nil,
            "partially missing metrics cannot be attributed to a known account"
        )
        let privateNames = descriptor([(weeklyID, "Claude · person@example.com · 7d")])
        test.expect(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [weeklyID], descriptor: privateNames) == nil,
            "mailbox-only identities are omitted instead of displayed"
        )
        let safeAlias = descriptor([(weeklyID, "Claude · Work 2 · person@example.com · 7d")])
        test.expectEqual(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [weeklyID], descriptor: safeAlias),
            "Work 2",
            "safe account aliases survive mailbox removal"
        )
        let mixed = descriptor([
            (sessionID, "Claude · Personal · 5h"),
            (weeklyID, "Claude · Work · 7d"),
        ])
        test.expect(
            HarnaisGlance.accountLabel(sourceID: sourceID, metricIDs: [sessionID, weeklyID], descriptor: mixed) == nil,
            "multi-account widgets are not mislabeled as one account"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: "quota.key.time:Cursor · default Models", descriptor: nil),
            "Models",
            "Cursor primary usage uses the Models caption"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: "quota.key.time:Cursor · default Other", descriptor: nil),
            "Other",
            "Cursor secondary usage uses the Other caption"
        )
        test.expectEqual(
            HarnaisGlance.slotCaption(sourceID: sourceID, metricID: "unknown-private-slug", descriptor: nil),
            "Usage",
            "unknown metrics never leak raw identifiers into rail captions"
        )
    }
}
