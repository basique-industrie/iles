import AppKit
import Domain
import Foundation
import Infrastructure
import IslandGeometry
import Observation
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runRuntimeAndPresentationTests(_ test: TestHarness) async {
        // MARK: Hooks / probe loopback

        let startJSON = Data("""
        {"session_id":"s1","hook_event_name":"SessionStart","cwd":"/tmp/iles-project"}
        """.utf8)
        let parsed = SessionEventParser.parse(startJSON)
        test.expect(parsed?.sessionId == "s1", "parse session id")
        test.expect(parsed?.eventName == .sessionStart, "parse event name")
        test.expect(parsed?.cwd == "/tmp/iles-project", "parse cwd")
        test.expect(SessionEventParser.parse(Data("not-json".utf8)) == nil, "reject junk")
        test.expect(
            SessionEvent(sessionId: "p", eventName: .sessionEnd, cwd: "/tmp/Iles/Probe").isIlesProbe,
            "Iles probe cwd is filtered"
        )
        test.expect(
            !SessionEvent(sessionId: "p", eventName: .sessionEnd, cwd: "/tmp/iles-project").isIlesProbe,
            "real session cwd is kept"
        )

        do {
            let battery = BatteryComplicationSource.snapshot(from: [
                "Is Present": NSNumber(value: true),
                "Current Capacity": NSNumber(value: 64),
                "Max Capacity": NSNumber(value: 100),
                "Is Charging": NSNumber(value: false),
                "Power Source State": "Battery Power",
                "Time to Empty": NSNumber(value: 214),
                "BatteryHealth": "Good",
            ])
            test.expectEqual(battery.values["level"]?.displayText, "64%", "battery decodes NSNumber capacity")
            test.expectEqual(battery.values["power"]?.displayText, "Battery", "battery normalizes the IOKit power label")
            test.expectEqual(battery.values["remaining"]?.displayText, "3h 34m", "battery exposes time remaining")
            test.expectEqual(battery.values["health"]?.displayText, "Good", "battery exposes health")

            let unavailable = BatteryComplicationSource.snapshot(from: nil)
            test.expect(unavailable.errorDescription != nil, "missing battery has an actionable source error")
        }

        do {
            let monitor = SessionMonitor()
            let disabled = SessionComplicationSource(monitor: monitor, isTrackingEnabled: { false })
            test.expectEqual(disabled.currentSnapshot.values["state"]?.displayText, "Off", "disabled session tracking is not reported as idle")
            test.expect(disabled.currentSnapshot.errorDescription != nil, "disabled session tracking explains its setup")

            let enabled = SessionComplicationSource(monitor: monitor, isTrackingEnabled: { true })
            test.expectEqual(enabled.currentSnapshot.values["state"]?.displayText, "Idle", "enabled tracker reports no active session as idle")
            monitor.processEvent(SessionEvent(sessionId: "live", eventName: .sessionStart, cwd: "/tmp/project"))
            test.expectEqual(
                enabled.currentSnapshot.values["state"],
                .status(label: "Active", level: .healthy),
                "session source follows live hook events"
            )
            monitor.processEvent(SessionEvent(sessionId: "live", eventName: .stop, cwd: "/tmp/project"))
            test.expectEqual(
                enabled.currentSnapshot.values["state"],
                .status(label: "Stopped", level: .inactive),
                "stopped sessions no longer look active"
            )
        }

        // MARK: Complication runtime — repeated sources and selection

        do {
            var schedule = LocalSourceRefreshSchedule(
                fastSourceIDs: ["system.mac"],
                slowSourceIDs: ["developer.git", "calendar.events"],
                tracksActiveSession: false
            )
            test.expectEqual(schedule.tickInterval, 2, "live local metrics use a responsive cadence")
            for tick in 1...14 {
                test.expectEqual(
                    schedule.sourceIDsForNextTick(),
                    ["system.mac"],
                    "slow local sources stay out of fast tick \(tick)"
                )
            }
            test.expectEqual(
                schedule.sourceIDsForNextTick(),
                ["system.mac", "developer.git", "calendar.events"],
                "slow local sources join only the thirty-second tick"
            )

            var slowOnly = LocalSourceRefreshSchedule(
                fastSourceIDs: [],
                slowSourceIDs: ["system.battery"],
                tracksActiveSession: false
            )
            test.expectEqual(slowOnly.tickInterval, 30, "slow-only sources do not create a fast timer")
            test.expectEqual(
                slowOnly.sourceIDsForNextTick(),
                ["system.battery"],
                "slow-only sources refresh on their first scheduled tick"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            _ = workspace.addComplication(
                to: islandID,
                sourceID: "codex",
                metricIDs: ["quota.session"],
                family: .ring
            )
            let codex = CountingProvider(id: "codex")
            let runtime = IslandRuntime.testing(
                providers: [codex],
                workspaceStore: workspace
            )

            runtime.start()
            for _ in 0..<20 where codex.refreshCalls.isEmpty {
                await Task.yield()
            }
            runtime.stop()

            test.expectEqual(codex.refreshCalls.count, 1, "startup refreshes referenced sources immediately")
            test.expect(
                codex.refreshCalls.first == .interactive,
                "startup builds the complete provider snapshot before the first periodic tick"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            let claude = CountingProvider(id: "claude")
            let codex = CountingProvider(id: "codex")
            let runtime = IslandRuntime.testing(
                providers: [claude, codex],
                workspaceStore: workspace
            )
            let invalidations = LockedCounter()
            withObservationTracking {
                _ = runtime.snapshot(sourceID: "claude")
            } onChange: {
                invalidations.increment()
            }

            await runtime.refreshProvider("codex")?.value
            test.expectEqual(
                invalidations.value,
                0,
                "refreshing one source does not invalidate views observing another source"
            )
            await runtime.refreshProvider("claude")?.value
            test.expectEqual(
                invalidations.value,
                1,
                "refreshing a source invalidates its own observing views"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.settings.setRefreshInterval(.off)
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            _ = workspace.addComplication(
                to: islandID,
                sourceID: "claude",
                metricIDs: ["quota.weekly"],
                family: .ring
            )
            let claude = CountingProvider(id: "claude")
            let codex = CountingProvider(id: "codex")
            let cursor = CountingProvider(id: "cursor")
            let runtime = IslandRuntime.testing(
                providers: [claude, codex, cursor],
                workspaceStore: workspace
            )

            let first = workspace.islands[0].complications[0]
            runtime.hoverSelect(islandID: islandID, complicationID: first.id)
            test.expectEqual(claude.refreshCalls.count, 0, "hover selection does not start a probe")
            test.expectEqual(runtime.selection?.complicationID, first.id, "selection identifies a complication instance")

            _ = await runtime.sourceRegistry.refresh(
                sourceIDs: ["claude", "claude", "claude"],
                kind: .interactive
            )
            test.expectEqual(claude.refreshCalls.count, 1, "repeated complication source refreshes once per cycle")

            await runtime.refreshProvider("codex")?.value
            test.expectEqual(codex.refreshCalls.count, 1, "manual source refresh runs once")
            test.expect(codex.refreshCalls.first == .interactive, "manual refresh performs a full interactive probe")

            claude.snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "claude"),
                    UsageQuota(percentRemaining: 20, quotaType: .weekly, providerId: "claude"),
                ],
                capturedAt: Date()
            )
            claude.lastError = ProbeError.noData
            let lastKnown = ProviderComplicationSource(provider: claude).currentSnapshot
            test.expectEqual(lastKnown.quality, .stale, "provider failures mark retained values as last-known data")
            test.expectEqual(lastKnown.availability.state, .temporarilyUnavailable, "provider failures remain retryable after a successful snapshot")
            claude.lastError = nil
            let dual = ComplicationConfiguration(
                sourceID: "claude",
                metricIDs: ["quota.session", "quota.weekly"],
                family: .dualRing,
                slotValueModes: [.used, .remaining]
            )
            let dualValues = runtime.values(for: dual)
            test.expectEqual(dualValues.count, 2, "dual ring resolves both provider metrics")
            test.expectEqual(dualValues.first?.displayText, "60%", "outer ring independently shows quota used")
            test.expectEqual(dualValues.last?.displayText, "20%", "inner ring independently shows quota remaining")
        }

        // MARK: Settings presentation and preview behavior

        test.expectEqual(
            ComplicationFamily.summary.designDescription,
            "Two or three related values joined into one compact glance.",
            "summary style explains its multi-value purpose"
        )
        test.expectEqual(
            ComplicationFamily.cluster.fitDescription(for: .gauge),
            "Three progress rings",
            "trio style communicates its bounded-gauge contract"
        )
        test.expectEqual(
            ComplicationAction.refresh.displayName,
            "Refresh Source",
            "complication actions use concise settings labels"
        )
        test.expectEqual(
            CompactDurationFormatter.hoursMinutes(5_400),
            "1h 30m",
            "shared duration formatter preserves hours and minutes"
        )
        test.expectEqual(
            CompactDurationFormatter.hoursMinutes(7_200, includesZeroMinutes: false),
            "2h",
            "shared duration formatter can omit redundant zero minutes"
        )
        test.expectEqual(
            CompactDurationFormatter.largestUnit(172_900),
            "2d",
            "shared duration formatter picks the largest useful unit"
        )
        test.expectEqual(
            CompactDurationFormatter.largestUnit(-1),
            "0m",
            "shared duration formatter clamps negative intervals"
        )

        do {
            let quota = ComplicationMetricFallback.descriptors(
                metricIDs: ["quota.session"],
                family: .ring
            )
            test.expectEqual(quota.first?.kind, .gauge, "loading providers retain quota metric semantics")
            test.expect(
                quota.first.map { ComplicationRecipeValidator.family(.ring, supports: $0.kind, metric: $0) } == true,
                "loading quota providers keep ring styles available"
            )

            let duration = ComplicationMetricFallback.descriptors(
                metricIDs: ["daily.working-time"],
                family: .countdown
            )
            test.expectEqual(duration.first?.kind, .duration, "loading providers retain duration metric semantics")
            test.expect(
                duration.first.map { ComplicationRecipeValidator.family(.countdown, supports: $0.kind, metric: $0) } == true,
                "loading duration providers keep countdown styles available"
            )
        }

        do {
            let recipe = ComplicationRecipe(
                id: "preview.remaining",
                name: "Remaining",
                summary: "Preview a transformed fixture.",
                question: "How much remains?",
                sourceID: "test",
                family: .ring,
                slots: [ComplicationMetricSlot(metricID: "quota", transforms: [.remaining])],
                fixtures: [
                    ComplicationFixture(
                        name: "Typical",
                        state: .normal,
                        values: ["quota": .gauge(value: 30, range: 0...100, label: "30%")]
                    ),
                ]
            )
            test.expectEqual(
                ComplicationPreviewFixture.values(for: recipe, sourceID: "test").first?.displayText,
                "70%",
                "settings previews resolve recipe transforms instead of showing raw fixtures"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            let runtime = IslandRuntime.testing(
                providers: [],
                workspaceStore: workspace
            )
            var previews: [(UUID, Double?)] = []
            runtime.islandTopGapPreviewHandler = { previews.append(($0, $1)) }
            let islandID = workspace.islands[0].id
            let initialTopGap = workspace.island(id: islandID)?.placement.topGap
            runtime.previewIslandTopGap(islandID, value: 72)
            runtime.previewIslandTopGap(islandID, value: nil)
            test.expectEqual(previews.count, 2, "top-spacing preview forwards live and completion updates")
            test.expectEqual(previews.first?.0, islandID, "top-spacing preview targets the selected island")
            test.expectEqual(previews.first?.1, 72, "top-spacing preview forwards the live value")
            test.expect(previews.last?.1 == nil, "top-spacing preview clears the transient override")
            test.expectEqual(
                workspace.island(id: islandID)?.placement.topGap,
                initialTopGap,
                "top-spacing previews do not mutate persisted workspace state"
            )
        }
    }
}
