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
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(repository: JSONIslandWorkspaceRepository(store: box.store))
            let cleanRuntime = IslandRuntime.testing(providers: [], workspaceStore: workspace)
            test.expect(cleanRuntime.descriptor(sourceID: "system.battery") == nil,
                "new workspaces do not advertise the retired battery source")
            workspace.addIsland()
            _ = workspace.addComplication(to: workspace.islands[0].id, sourceID: "system.battery",
                metricIDs: ["level"], family: .ring, recipeID: "system.battery.charge-ring")
            let saved = workspace.workspace
            let restored = IslandWorkspaceStore(repository: JSONIslandWorkspaceRepository(store: box.store))
            let legacyRuntime = IslandRuntime.testing(providers: [], workspaceStore: restored)
            test.expect(legacyRuntime.descriptor(sourceID: "system.battery")?.metrics.contains { $0.id == "level" } == true,
                "saved battery widgets retain their source and metric definitions")
            test.expect(legacyRuntime.descriptor(sourceID: "system.battery")?.complications.contains { $0.id == "system.battery.charge-ring" } == true,
                "saved battery recipes remain resolvable")
            test.expectEqual(restored.workspace, saved, "legacy source compatibility preserves widget identity and settings")
        }


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
                slowSourceIDs: ["developer.git"],
                tracksActiveSession: false
            )
            test.expectEqual(slowOnly.tickInterval, 30, "slow-only sources do not create a fast timer")
            test.expectEqual(
                slowOnly.sourceIDsForNextTick(),
                ["developer.git"],
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
            let harnais = CountingProvider(id: ProviderIdentity.harnais.rawValue)
            let runtime = IslandRuntime.testing(
                providers: [harnais],
                workspaceStore: workspace,
                usesDemoData: false
            )
            test.expect(
                runtime.initialRefreshSourceIDs.contains(ProviderIdentity.harnais.rawValue),
                "Harnais is part of the first refresh even when no island uses it"
            )
            runtime.start()
            for _ in 0..<20 where harnais.refreshCalls.isEmpty {
                await Task.yield()
            }
            runtime.stop()
            test.expectEqual(
                harnais.refreshCalls.count,
                1,
                "startup probes Harnais so Sources has recipes before it is added to an island"
            )
            test.expect(runtime.catalogSources.contains { $0.id == "harnais" },
                "configured Harnais accounts remain available before adding the first widget")

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
            claude.snapshot = UsageSnapshot(providerId: "claude", quotas: [
                UsageQuota(percentRemaining: 20, quotaType: .weekly, providerId: "claude"),
            ], capturedAt: Date())
            let partial = runtime.values(for: dual)
            test.expectEqual(partial.map(\.displayText), ["—", "20%"],
                "a missing outer metric does not move the inner value or its remaining mode")
            test.expectEqual(runtime.quality(for: dual), .unavailable,
                "a partial paired reading does not claim to be fully live")
            test.expectEqual(runtime.resolvedSlots(for: dual).map(\.metricID), ["quota.weekly"],
                "detail rows retain the actual identity of the available metric")
            claude.snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())
            test.expect(runtime.values(for: dual).isEmpty, "fully missing metrics still use the no-data state")

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
                sourceID: ProviderIdentity.harnais.rawValue,
                metricIDs: ["quota.weekly"],
                family: .ring
            )
            let harnais = CountingProvider(id: ProviderIdentity.harnais.rawValue)
            harnais.snapshot = UsageSnapshot(
                providerId: ProviderIdentity.harnais.rawValue,
                quotas: [
                    UsageQuota(
                        percentRemaining: 50,
                        quotaType: .weekly,
                        providerId: ProviderIdentity.harnais.rawValue
                    )
                ],
                capturedAt: Date().addingTimeInterval(-3_600)
            )
            let runtime = IslandRuntime.testing(
                providers: [harnais],
                workspaceStore: workspace,
                usesDemoData: false
            )
            test.expectEqual(
                runtime.quality(for: workspace.islands[0].complications[0]),
                .stale,
                "Harnais rings age from the last successful live probe"
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
                sourceID: "claude",
                metricIDs: ["quota.weekly"],
                family: .ring
            )
            let claude = CountingProvider(id: "claude")
            claude.snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 50, quotaType: .weekly, providerId: "claude")
                ],
                capturedAt: Date().addingTimeInterval(-3_600)
            )
            let runtime = IslandRuntime.testing(
                providers: [claude],
                workspaceStore: workspace
            )
            test.expectEqual(
                runtime.quality(for: workspace.islands[0].complications[0]),
                .stale,
                "direct provider rings still age out"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let harnais = HarnaisProvider(
                probe: DemoUsageProbe.harnais
            )
            _ = try? await harnais.refresh()
            let source = ProviderComplicationSource(provider: harnais)
            let recipes = HarnaisWeeklyStarter.glanceRecipes(
                in: harnais.snapshot!,
                descriptor: source.descriptor
            )
            test.expectEqual(recipes.count, 3, "demo Harnais has three starter glances")
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            workspace.updateIsland(islandID) { $0.followsHarnaisAccounts = true }
            for recipe in recipes.prefix(2) {
                _ = workspace.addComplication(
                    to: islandID,
                    sourceID: recipe.sourceID,
                    metricIDs: recipe.metricIDs,
                    family: recipe.family,
                    labelStyle: recipe.labelStyle,
                    recipeID: recipe.id,
                    tint: recipe.tint,
                    tapAction: recipe.tapAction
                )
            }
            let runtime = IslandRuntime.testing(
                providers: [harnais],
                workspaceStore: workspace,
                usesDemoData: false
            )
            runtime.start()
            test.expectEqual(
                workspace.islands[0].complications.compactMap(\.recipeID),
                recipes.map(\.id),
                "islands with a Harnais weekly stack gain missing Cursor Models"
            )
            runtime.stop()
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let harnais = HarnaisProvider(
                probe: DemoUsageProbe.harnais
            )
            _ = try? await harnais.refresh()
            let source = ProviderComplicationSource(provider: harnais)
            let recipes = HarnaisWeeklyStarter.glanceRecipes(
                in: harnais.snapshot!,
                descriptor: source.descriptor
            )
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            workspace.updateIsland(islandID) { $0.followsHarnaisAccounts = true }
            _ = workspace.addComplication(
                to: islandID,
                sourceID: HarnaisWeeklyStarter.sourceID,
                metricIDs: ["quota.key.time:Claude · Perso 7d"],
                family: .ring,
                labelStyle: .percentage,
                recipeID: "harnais.quota-time-claude-perso-7d"
            )
            let codex = recipes[1]
            _ = workspace.addComplication(
                to: islandID,
                sourceID: codex.sourceID,
                metricIDs: codex.metricIDs,
                family: codex.family,
                labelStyle: codex.labelStyle,
                recipeID: codex.id,
                tint: codex.tint,
                tapAction: codex.tapAction
            )
            let runtime = IslandRuntime.testing(
                providers: [harnais],
                workspaceStore: workspace,
                usesDemoData: false
            )
            runtime.start()
            test.expectEqual(
                workspace.islands[0].complications.compactMap(\.recipeID),
                [recipes[0].id, "harnais.quota-time-claude-perso-7d"] + recipes.dropFirst().map(\.id),
                "following accounts adds current windows without stealing the missing account's widget"
            )
            let beforeRemoval = workspace.islands[0]
            let removedID = beforeRemoval.complications[0].id
            if let removal = workspace.removeComplication(removedID, from: islandID) {
                test.expectEqual(workspace.islands[0].complications.count, beforeRemoval.complications.count - 1,
                    "removing a followed Harnais widget does not recreate it through reconciliation")
                test.expectEqual(workspace.islands[0].followsHarnaisAccounts, false,
                    "manual removal turns the followed collection into a custom island")
                workspace.restoreComplication(removal)
                test.expectEqual(workspace.islands[0], beforeRemoval,
                    "undo restores the original widget, order and account-following preference")
            } else {
                test.expect(false, "followed Harnais widget can be removed")
            }

            runtime.stop()
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(repository: JSONIslandWorkspaceRepository(store: box.store))
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            _ = workspace.addComplication(to: islandID, sourceID: "harnais", metricIDs: ["quota.key.weekly"], family: .ring)
            let savedIDs = workspace.islands[0].complications.map(\.id)
            let harnais = CountingProvider(id: "harnais")
            harnais.snapshot = UsageSnapshot(providerId: "harnais", quotas: [UsageQuota(percentRemaining: 50, quotaType: .weekly, providerId: "codex")], capturedAt: Date(), hiddenQuotaTypes: ["weekly"])
            let runtime = IslandRuntime.testing(providers: [harnais], workspaceStore: workspace, usesDemoData: false)
            test.expect(runtime.visibleComplications(on: workspace.islands[0]).isEmpty, "Harnais hidden rings are excluded from rendering")
            test.expectEqual(workspace.islands[0].complications.map(\.id), savedIDs, "hiding does not delete saved ring IDs")
            harnais.snapshot = UsageSnapshot(providerId: "harnais", quotas: [], capturedAt: Date())
            test.expectEqual(runtime.visibleComplications(on: workspace.islands[0]).map(\.id), savedIDs, "unhiding restores the same ring and order even during missing quota data")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(repository: JSONIslandWorkspaceRepository(store: box.store))
            workspace.addIsland()
            let islandID = workspace.islands[0].id
            _ = workspace.addComplication(to: islandID, sourceID: "harnais", metricIDs: ["quota.weekly"], family: .ring)
            workspace.updateIsland(islandID) { $0.isVisible = false }
            let runtime = IslandRuntime.testing(providers: [CountingProvider(id: "harnais"), CountingProvider(id: "claude"), CountingProvider(id: "codex")], workspaceStore: workspace)
            test.expectEqual(runtime.catalogSources.filter { $0.kind == .usage }.map(\.id), ["harnais"], "AI catalog retains only sources used in saved islands, even hidden ones")
            test.expect(runtime.catalogSources.contains { $0.id == "system.clock" }, "AI reduction keeps non-AI sources available")
            test.expect(runtime.provider(id: "claude") != nil, "catalog reduction preserves installed provider configuration")
            test.expectEqual(runtime.settingsSection, .overview, "settings starts on the overview")
            let widgetID = workspace.islands[0].complications[0].id
            runtime.selection = ComplicationSelection(islandID: islandID, complicationID: widgetID)
            runtime.editSelectedWidget()
            test.expectEqual(runtime.settingsSection, .islands, "floating widget Edit routes to the island editor")
            test.expectEqual(workspace.selectedComplicationID, widgetID, "floating widget Edit selects the same widget")

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

        do {
            let shipped = MenuBarIdentityIcon.image(for: .shipped)
            let development = MenuBarIdentityIcon.image(for: .development)
            test.expect(shipped.isTemplate, "shipped extra is a template mark")
            test.expect(!development.isTemplate, "dev extra keeps its orange color")
            test.expectEqual(shipped.size, development.size, "dev extra uses the same mark size")
            test.expect(
                imageHasChromaticPixels(development),
                "dev extra is tinted instead of a template"
            )
            test.expect(
                !imageHasChromaticPixels(shipped),
                "shipped extra stays a monochrome template"
            )
        }
    }

    private static func imageHasChromaticPixels(_ image: NSImage) -> Bool {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let scale: CGFloat = 2
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return false }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        for y in 0..<height {
            for x in 0..<width {
                guard let color = rep.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else { continue }
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                guard alpha > 0.2 else { continue }
                if abs(red - green) > 0.12 || abs(green - blue) > 0.12 || abs(red - blue) > 0.12 {
                    return true
                }
            }
        }
        return false
    }
}
