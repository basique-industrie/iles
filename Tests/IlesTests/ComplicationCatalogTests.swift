import AppKit
import Domain
import Foundation
import Infrastructure
import IslandGeometry
import Observation
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runComplicationCatalogTests(_ test: TestHarness) async {
        // MARK: Catalog / captions / list IDs

        test.expectEqual(ProviderBrand.allCases.count, 19, "built-in brand count")
        test.expectEqual(Set(ProviderBrand.allCases.map(\.id)).count, 19, "brand ids are unique")
        for brand in ProviderBrand.allCases {
            test.expect(!brand.setupInstruction.isEmpty, "\(brand.title) explains how to connect")
            let resource = brand.iconResource
            let url = Bundle.module.url(forResource: resource.name, withExtension: resource.ext)
            test.expect(url != nil, "missing icon \(resource.name).\(resource.ext)")
            test.expect(
                url.flatMap(NSImage.init(contentsOf:))?.representations.isEmpty == false,
                "icon \(resource.name).\(resource.ext) must decode for AppKit vector rendering"
            )
        }
        test.expect(ProviderBrand.claude.hasInAppConfiguration, "Claude exposes its probe settings in app")
        test.expect(
            Bundle.module.url(forResource: "GitHubIcon", withExtension: "svg") != nil,
            "official GitHub source mark is bundled"
        )
        runPackagedResourceBundleTests(test)

        let demo = IsolatedBox.make()
        defer { demo.tearDown() }
        do {
            let provider = CountingProvider(id: "loading-test")
            provider.delay = .milliseconds(100)
            let registry = ComplicationSourceRegistry(
                providers: [provider], sessionMonitor: SessionMonitor(), settingsStore: demo.store
            )
            var refresh: Task<[String: SourceSnapshot], Never>?
            await withCheckedContinuation { continuation in
                provider.onRefreshStart = { continuation.resume() }
                refresh = Task { await registry.refresh(sourceIDs: [provider.id], kind: .interactive) }
            }
            test.expect(registry.refreshingSourceIDs.contains(provider.id), "source refresh is observable even when provider has no syncing flag")
            _ = await refresh?.value
            test.expect(registry.refreshingSourceIDs.isEmpty, "loading indication ends after refresh")
            await withCheckedContinuation { continuation in
                provider.onRefreshStart = { continuation.resume() }
                refresh = Task { await registry.refresh(sourceIDs: [provider.id], kind: .interactive) }
            }
            registry.cancelRefreshes()
            test.expect(registry.refreshingSourceIDs.isEmpty, "cancelled sources cannot leave a permanent spinner")
            _ = await refresh?.value
        }
        let demoProviders = IslandProviders.makeAll(demo: true, settings: demo.settings)
        test.expectEqual(demoProviders.count, ProviderBrand.launchCases.count, "demo builds every supported launch provider")
        test.expectEqual(
            Set(demoProviders.map(\.id)),
            Set(ProviderBrand.launchCases.map(\.id)),
            "demo ids match supported launch brands"
        )
        test.expectEqual(
            Set(ProviderBrand.allCases.map(\.id)),
            Set(ProviderIdentity.allCases.map(\.rawValue)),
            "brand ids match domain identities"
        )
        test.expectEqual(
            ProviderIdentity.mappedFromHarnais(
                providerId: "harnais",
                group: "Claude · work@example.com"
            ),
            .claude,
            "Harnais group titles map to Claude"
        )
        test.expectEqual(
            ProviderIdentity.mappedFromHarnais(
                providerId: "harnais",
                label: "quota.key.time:Codex · personal 7d"
            ),
            .codex,
            "Harnais metric ids map to Codex"
        )
        test.expectEqual(
            ProviderIdentity.mappedFromHarnais(providerId: "cursor"),
            .cursor,
            "Harnais upstream provider ids stay Cursor"
        )
        test.expectEqual(
            ProviderIdentity.mappedFromHarnais(providerId: "harnais"),
            nil,
            "Harnais itself is not an upstream glance brand"
        )
        test.expectEqual(
            AppDefaults.defaultProviderSourceIDs,
            [
                ProviderIdentity.claude.rawValue,
                ProviderIdentity.codex.rawValue,
                ProviderIdentity.cursor.rawValue,
            ],
            "first-launch island is Claude, Codex, Cursor"
        )
        test.expectEqual(
            ComplicationMetricDescriptor.fallbackName(for: "quota.key.model:fable"),
            "Fable",
            "persisted model quota keys have a safe display name"
        )
        test.expectEqual(
            ComplicationMetricDescriptor.fallbackName(for: "responseCode"),
            "Response Code",
            "unknown metric keys are humanized instead of exposed"
        )

        if let demoClaude = demoProviders.first(where: { $0.id == ProviderIdentity.claude.rawValue }) {
            _ = try? await demoClaude.refresh(.interactive)
            let demoSource = ProviderComplicationSource(provider: demoClaude)
            test.expect(
                demoSource.currentSnapshot.values["quota.key.model:fable"] != nil,
                "Claude demo data covers the Fable model complication"
            )
            test.expectEqual(
                demoSource.descriptor.metricName(for: "quota.key.model:fable"),
                "Fable",
                "Claude exposes a friendly Fable metric name"
            )
            let fableRecipe = demoSource.descriptor.complications.first {
                $0.id == "claude.quota-model-fable"
            }
            test.expect(fableRecipe != nil, "provider-specific quota windows are discoverable catalog recipes")
            test.expectEqual(
                fableRecipe?.metricIDs,
                ["quota.key.model:fable"],
                "Fable catalog recipe targets its stable metric"
            )
        } else {
            test.expect(false, "Claude demo provider is available")
        }

        if let demoHarnais = demoProviders.first(where: { $0.id == ProviderIdentity.harnais.rawValue }) {
            _ = try? await demoHarnais.refresh()
            let demoSource = ProviderComplicationSource(provider: demoHarnais)
            let groups = demoSource.currentSnapshot.quotaGroups ?? []
            test.expectEqual(groups.map(\.title), ["Claude · Work", "Codex · Personal", "Cursor · Default"], "Harnais details group windows by account")
            test.expect(groups.allSatisfy { !$0.title.contains("@") }, "Harnais groups never include mailboxes")
            test.expectEqual(groups.first?.metricIDs.count, 2, "Claude work group has two windows")
            test.expect(
                demoSource.descriptor.complications.contains { $0.id == "harnais.quota-pair" },
                "Harnais exposes a combined quota recipe"
            )
            let weekly = HarnaisWeeklyStarter.glanceQuotas(in: demoHarnais.snapshot!)
            test.expectEqual(weekly.count, 3, "Harnais weekly starter keeps one window per account")
            test.expect(weekly.allSatisfy(\.isAccountGlanceWindow), "Harnais starter skips 5h windows")
            test.expect(
                weekly.contains { $0.compactTitle == "Models" },
                "Harnais starter uses Cursor Models when there is no 7d window"
            )
            let weeklyRecipeIDs = weekly.map(HarnaisWeeklyStarter.recipeID(for:))
            test.expectEqual(
                weeklyRecipeIDs,
                [
                    "harnais.quota-time-claude-work-7d",
                    "harnais.quota-time-codex-personal-7d",
                    "harnais.quota-time-cursor-default-models",
                ],
                "Harnais weekly starter binds the 7d recipe for each account"
            )
            for recipeID in weeklyRecipeIDs {
                test.expect(
                    demoSource.descriptor.complications.contains { $0.id == recipeID },
                    "Harnais catalog includes weekly starter recipe \(recipeID)"
                )
            }
            test.expectEqual(
                demoSource.descriptor.metrics.first { $0.id == "quota.key.time:Claude · work 7d" }?.name,
                "Claude · Work · 7d",
                "Harnais weekly metrics use the account label, not the mailbox"
            )
            test.expectEqual(
                HarnaisGlance.resolvedBrand(
                    sourceID: ProviderIdentity.harnais.rawValue,
                    metricIDs: ["quota.key.time:Claude · work 7d"],
                    descriptor: demoSource.descriptor
                ),
                .claude,
                "Harnais Claude windows use the Claude mark"
            )
            test.expectEqual(
                HarnaisGlance.resolvedBrand(
                    sourceID: ProviderIdentity.harnais.rawValue,
                    metricIDs: ["quota.key.time:Codex · personal 7d"],
                    descriptor: demoSource.descriptor
                ),
                .codex,
                "Harnais Codex windows use the Codex mark"
            )
            test.expectEqual(
                HarnaisGlance.resolvedBrand(
                    sourceID: ProviderIdentity.harnais.rawValue,
                    metricIDs: ["quota.key.time:Cursor · Default Models"],
                    descriptor: demoSource.descriptor
                ),
                .cursor,
                "Harnais Cursor windows use the Cursor mark"
            )
            let claudeGroup = demoSource.currentSnapshot.focusedQuotaGroups(
                matching: ["quota.key.time:Claude · work 7d"]
            )
            test.expectEqual(
                claudeGroup.map(\.title),
                ["Claude · Work"],
                "Harnais hover zooms to the hovered account, not the whole feed"
            )
            test.expectEqual(claudeGroup.first?.metricIDs.count, 2, "Harnais hover keeps that account's windows")
            test.expectEqual(
                demoSource.currentSnapshot.focusedQuotaGroups(
                    matching: ["missing"]
                ).count,
                0,
                "unknown hover does not dump every account"
            )
            test.expectEqual(
                HarnaisGlance.windowCaption(
                    metricID: "quota.key.time:Claude · work 7d",
                    metricName: "Claude · Work · 7d"
                ),
                "Weekly",
                "Harnais hover rows use the window, not the mailbox"
            )
            let glanceRecipes = HarnaisWeeklyStarter.glanceRecipes(
                in: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor
            )
            test.expectEqual(glanceRecipes.count, 3, "Harnais starter recipes match the demo accounts")
            let emptyIsland = IslandConfiguration(name: "Empty")
            test.expectEqual(
                HarnaisWeeklyStarter.missingRecipes(
                    on: emptyIsland,
                    snapshot: demoHarnais.snapshot!,
                    descriptor: demoSource.descriptor
                ).count,
                0,
                "empty islands do not get Harnais glances injected"
            )
            let oneRing = IslandConfiguration(
                name: "One",
                complications: [
                    ComplicationConfiguration(
                        recipeID: glanceRecipes[0].id,
                        sourceID: glanceRecipes[0].sourceID,
                        metricIDs: glanceRecipes[0].metricIDs,
                        family: glanceRecipes[0].family,
                        labelStyle: glanceRecipes[0].labelStyle
                    )
                ]
            )
            test.expectEqual(
                HarnaisWeeklyStarter.missingRecipes(
                    on: oneRing,
                    snapshot: demoHarnais.snapshot!,
                    descriptor: demoSource.descriptor
                ).count,
                0,
                "a single Harnais ring is not treated as the weekly collection"
            )
            var followingOne = oneRing
            followingOne.followsHarnaisAccounts = true
            test.expectEqual(HarnaisWeeklyStarter.missingRecipes(on: followingOne, snapshot: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor).count, 2, "explicit account following works even when an island starts with one account")
            let partialIsland = IslandConfiguration(
                name: "Stack",
                followsHarnaisAccounts: true,
                complications: glanceRecipes.prefix(2).map { recipe in
                    ComplicationConfiguration(
                        recipeID: recipe.id,
                        sourceID: recipe.sourceID,
                        metricIDs: recipe.metricIDs,
                        family: recipe.family,
                        labelStyle: recipe.labelStyle
                    )
                }
            )
            test.expectEqual(
                HarnaisWeeklyStarter.missingRecipes(
                    on: partialIsland,
                    snapshot: demoHarnais.snapshot!,
                    descriptor: demoSource.descriptor
                ).map(\.id),
                [glanceRecipes[2].id],
                "existing Harnais weekly stacks pick up Cursor Models"
            )
            let outOfOrder = IslandConfiguration(
                name: "Out of order",
                followsHarnaisAccounts: true,
                complications: [glanceRecipes[0], glanceRecipes[2]].map { recipe in
                    ComplicationConfiguration(
                        recipeID: recipe.id,
                        sourceID: recipe.sourceID,
                        metricIDs: recipe.metricIDs,
                        family: recipe.family,
                        labelStyle: recipe.labelStyle
                    )
                }
            )
            var customIsland = partialIsland
            customIsland.followsHarnaisAccounts = false
            test.expect(HarnaisWeeklyStarter.missingRecipes(on: customIsland, snapshot: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor).isEmpty, "custom account islands never expand back into a full starter stack")
            customIsland.followsHarnaisAccounts = nil
            test.expect(HarnaisWeeklyStarter.missingRecipes(on: customIsland, snapshot: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor).isEmpty, "legacy layouts without an explicit follow preference stay unchanged")
            let inserted = HarnaisWeeklyStarter.missingRecipes(
                on: outOfOrder,
                snapshot: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor
            )
            test.expectEqual(inserted.map(\.id), [glanceRecipes[1].id], "gap in the weekly stack is the missing Codex glance")
            test.expectEqual(
                HarnaisWeeklyStarter.insertionIndex(
                    for: glanceRecipes[1],
                    on: outOfOrder,
                    wanted: glanceRecipes
                ),
                1,
                "missing Harnais glances insert in account order"
            )
            let live = HarnaisWeeklyStarter.liveNamedRecipes(
                in: demoHarnais.snapshot!,
                descriptor: demoSource.descriptor
            )
            test.expect(
                live.contains { $0.id == glanceRecipes[0].id },
                "live named recipes include the Claude weekly glance"
            )
            let work = glanceRecipes[0]
            let drifted = IslandConfiguration(
                name: "Drifted",
                complications: [
                    ComplicationConfiguration(
                        recipeID: work.id,
                        sourceID: work.sourceID,
                        metricIDs: ["quota.key.time:Claude · Work 7d"],
                        family: work.family,
                        labelStyle: work.labelStyle
                    )
                ]
            )
            test.expectEqual(
                HarnaisWeeklyStarter.rebindPairs(on: drifted, live: live).map(\.recipe.metricIDs),
                [work.metricIDs],
                "Harnais rings whose type key casing drifted keep the same recipe"
            )
            let perso = IslandConfiguration(
                name: "Renamed",
                complications: [
                    ComplicationConfiguration(
                        recipeID: "harnais.quota-time-claude-perso-7d",
                        sourceID: HarnaisWeeklyStarter.sourceID,
                        metricIDs: ["quota.key.time:Claude · Perso 7d"],
                        family: .ring,
                        labelStyle: .percentage
                    ),
                    ComplicationConfiguration(
                        recipeID: glanceRecipes[1].id,
                        sourceID: glanceRecipes[1].sourceID,
                        metricIDs: glanceRecipes[1].metricIDs,
                        family: glanceRecipes[1].family,
                        labelStyle: glanceRecipes[1].labelStyle
                    )
                ]
            )
            test.expectEqual(
                HarnaisWeeklyStarter.rebindPairs(on: perso, live: live),
                [],
                "a missing account never rebinds to another account with the same provider and window"
            )
            var customPair = perso
            customPair.complications[0].recipeID = nil
            customPair.complications[0].family = .dualRing
            customPair.complications[0].metricIDs = ["quota.key.time:Claude · Perso 5h", "quota.key.time:Claude · Perso 7d"]
            test.expectEqual(HarnaisWeeklyStarter.rebindPairs(on: customPair, live: live), [],
                "a temporarily missing custom pair keeps both saved metric slots")
            let orphaned = IslandConfiguration(
                name: "Orphan",
                complications: [
                    ComplicationConfiguration(
                        recipeID: "harnais.quota-time-claude-perso-7d",
                        sourceID: HarnaisWeeklyStarter.sourceID,
                        metricIDs: ["quota.key.time:Claude · Perso 7d"],
                        family: .ring,
                        labelStyle: .percentage
                    ),
                    ComplicationConfiguration(
                        recipeID: work.id,
                        sourceID: work.sourceID,
                        metricIDs: work.metricIDs,
                        family: work.family,
                        labelStyle: work.labelStyle
                    ),
                    ComplicationConfiguration(
                        recipeID: glanceRecipes[1].id,
                        sourceID: glanceRecipes[1].sourceID,
                        metricIDs: glanceRecipes[1].metricIDs,
                        family: glanceRecipes[1].family,
                        labelStyle: glanceRecipes[1].labelStyle
                    )
                ]
            )
            test.expectEqual(
                HarnaisWeeklyStarter.rebindPairs(on: orphaned, live: live).map(\.recipe.id),
                [],
                "an extra Claude weekly is not stolen from a still-published Work ring"
            )
            test.expectEqual(
                HarnaisWeeklyStarter.rebindPairs(on: perso, live: []),
                [],
                "an empty Harnais feed does not retarget rings"
            )
        } else {
            test.expect(false, "Harnais demo provider is available")
        }

        do {
            let provider = CountingProvider(id: ProviderIdentity.deepseek.rawValue)
            provider.snapshot = UsageSnapshot(
                providerId: provider.id,
                quotas: [
                    UsageQuota(
                        percentRemaining: 100,
                        quotaType: .modelSpecific("Balance"),
                        providerId: provider.id,
                        dollarRemaining: 42,
                        currency: "CNY"
                    ),
                ],
                capturedAt: Date()
            )
            let source = ProviderComplicationSource(provider: provider)
            test.expect(
                source.descriptor.metrics.contains { $0.id.hasPrefix("balance.key.") && $0.kind == .value },
                "unbounded provider credits are exposed as currency values"
            )
            test.expect(
                !source.descriptor.metrics.contains { $0.id.hasPrefix("quota.") && $0.kind == .gauge },
                "unbounded provider credits never become fake percentage quotas"
            )
            test.expect(
                source.descriptor.complications.contains { $0.family == .value && $0.id.contains("balance-") },
                "unbounded provider credits have a value complication"
            )
            test.expectEqual(
                source.currentSnapshot.values.values.first?.displayText,
                "¥42.00",
                "currency balance keeps the provider-reported currency"
            )

            provider.snapshot = UsageSnapshot(
                providerId: provider.id,
                quotas: [
                    UsageQuota(
                        percentRemaining: 55,
                        quotaType: .weekly,
                        providerId: provider.id
                    ),
                ],
                capturedAt: Date().addingTimeInterval(1)
            )
            test.expect(
                source.descriptor.metrics.contains { $0.id == "quota.weekly" },
                "cached provider descriptors invalidate when a new snapshot arrives"
            )
        }

        do {
            let provider = CountingProvider(id: ProviderIdentity.mistral.rawValue)
            provider.snapshot = UsageSnapshot(
                providerId: provider.id,
                quotas: [],
                capturedAt: Date(),
                dailyUsageReport: DailyUsageReport(
                    today: DailyUsageStat(
                        date: Date(),
                        totalCost: 4.2,
                        totalTokens: 82_000,
                        workingTime: 7_200,
                        sessionCount: 3
                    ),
                    previous: .empty(for: Date().addingTimeInterval(-86_400))
                )
            )
            let source = ProviderComplicationSource(provider: provider)
            test.expectEqual(
                source.descriptor.complications.first { $0.id == "mistral.daily-summary" }?.family,
                .summary,
                "Mistral daily report produces a compact usage summary"
            )
            test.expectEqual(source.currentSnapshot.values["daily.tokens"]?.displayText, "82.0K", "daily token value is mapped")
            test.expectEqual(source.currentSnapshot.values["daily.sessions"]?.displayText, "3", "daily session count is mapped")
            test.expect(
                !source.descriptor.complications.contains { $0.id.contains("primary") },
                "Mistral never advertises a placeholder quota"
            )
        }

        do {
            let provider = CountingProvider(id: ProviderIdentity.gemini.rawValue)
            provider.snapshot = UsageSnapshot(
                providerId: provider.id,
                quotas: [
                    UsageQuota(percentRemaining: 70, quotaType: .modelSpecific("Pro"), providerId: provider.id, resetsAt: Date().addingTimeInterval(3_600)),
                    UsageQuota(percentRemaining: 8, quotaType: .modelSpecific("Flash"), providerId: provider.id, resetsAt: Date().addingTimeInterval(7_200)),
                ],
                capturedAt: Date()
            )
            let source = ProviderComplicationSource(provider: provider)
            test.expectEqual(
                source.currentSnapshot.values["status.overall"]?.displayText,
                "Flash Critical",
                "quota health identifies the constrained window"
            )
            test.expect(
                source.currentSnapshot.values["reset.next"]?.displayText.hasPrefix("Pro · ") == true,
                "quota reset identifies the window that resets"
            )
            test.expect(!source.descriptor.metrics.contains { $0.id == "pace.primary" }, "model pace is hidden when its window duration is inferred")
        }

        do {
            let catalog = ComplicationSourceRegistry(
                providers: demoProviders,
                sessionMonitor: SessionMonitor(),
                settingsStore: demo.store
            )
            let descriptors = catalog.descriptors.filter { $0.kind != .extensionSource }
            let recipes = descriptors.flatMap(\.complications)
            test.expectEqual(
                recipes.count,
                92,
                "first-party launch catalog recipe count (update README when this changes)"
            )
            let scopedRecipeIDs = descriptors.flatMap { descriptor in
                descriptor.complications.map { "\(descriptor.id)::\($0.id)" }
            }
            test.expectEqual(Set(scopedRecipeIDs).count, recipes.count, "catalog recipe identifiers are unique within each source instance")
            test.expectEqual(Set(ComplicationFamily.allCases).count, 9, "catalog exposes nine truthful visual families")
            test.expect(Set(recipes.map(\.category)).isSuperset(of: [.ai, .sessions, .time, .mac, .focus, .developer, .services]), "all seven launch packs have recipes")
            let duplicateDirectionSuffixes = [".primary-used", ".primary-remaining", ".session-used", ".session-remaining", ".weekly-used", ".weekly-remaining"]
            test.expect(
                !recipes.contains { recipe in duplicateDirectionSuffixes.contains { recipe.id.hasSuffix($0) } },
                "Used and Remaining are configured per data slot, not duplicated as recipes"
            )
            for descriptor in descriptors {
                for recipe in descriptor.complications {
                    let issues = ComplicationRecipeValidator.issues(in: recipe, source: descriptor)
                    test.expect(issues.isEmpty, "\(recipe.id) passes strict catalog validation: \(issues)")
                    if recipe.family == .cluster {
                        let metricKinds = recipe.metricIDs.compactMap { metricID in
                            descriptor.metrics.first(where: { $0.id == metricID })?.kind
                        }
                        test.expectEqual(metricKinds.count, 3, "\(recipe.id) trio ring binds exactly three metrics")
                        test.expect(metricKinds.allSatisfy { $0 == .gauge }, "\(recipe.id) trio ring uses only bounded gauges")
                    }
                }
                if descriptor.kind != .usage {
                    let missingSymbols = descriptor.metrics.filter { $0.symbol == nil }.map(\.id)
                    test.expect(
                        missingSymbols.isEmpty,
                        "\(descriptor.id) gives every built-in metric a semantic glyph: \(missingSymbols)"
                    )
                    let catalogMetricIDs = Set(descriptor.complications.flatMap(\.metricIDs))
                    let missing = descriptor.metrics.map(\.id).filter { !catalogMetricIDs.contains($0) }
                    let intentionalDetailMetrics: [String: Set<String>] = [
                        "system.mac": ["networkType", "lowPower", "uptime"],
                        "productivity.focus": ["elapsed"],
                        "developer.git": ["staged", "unstaged", "untracked"],
                        "developer.github": ["workflow", "lastRun", "environment"],
                        "calendar.reminders": ["state"],
                    ]
                    let unreviewed = missing.filter {
                        intentionalDetailMetrics[descriptor.sourceKindID]?.contains($0) != true
                    }
                    test.expect(
                        unreviewed.isEmpty,
                        "\(descriptor.id) exposes every glance-worthy metric through a reviewed recipe: \(unreviewed)"
                    )
                }
            }
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let clock = LockedDate(Date(timeIntervalSince1970: 1_800_000_000))
            let focus = FocusComplicationSource(store: box.store, now: { clock.value })
            focus.startFocus(minutes: 25)
            clock.advance(by: 10 * 60)
            let active = focus.currentSnapshot
            test.expectEqual(active.values["progress"]?.progress, 0.4, "focus timer reports live interval progress")
            test.expectEqual(active.values["remaining"]?.displayText, "15m", "focus timer reports remaining duration")
            focus.stop()
            test.expectEqual(focus.currentSnapshot.values["sessions"]?.displayText, "0", "stopping early does not count a completed focus session")
            focus.startFocus(minutes: 1)
            clock.advance(by: 60)
            test.expectEqual(focus.currentSnapshot.values["sessions"]?.displayText, "1", "finishing a focus interval records the session")

            let service = ServiceMonitorComplicationSource(store: box.store)
            test.expect(!service.setEndpoint("file:///tmp/health"), "service monitor rejects non-network URLs")
            test.expect(service.setEndpoint("https://example.com/health"), "service monitor accepts an HTTPS endpoint")
            test.expectEqual(service.endpoint?.host, "example.com", "service monitor persists the normalized endpoint")
            service.clearEndpoint()
            test.expectEqual(service.currentSnapshot.availability.state, .setupRequired, "cleared service returns to setup state")

            let git = GitComplicationSource(store: box.store)
            test.expectEqual(
                GitComplicationSource.branchName(from: "## feature/catalog.v2...origin/feature/catalog.v2 [ahead 1]"),
                "feature/catalog.v2",
                "Git branch parsing preserves periods in branch names"
            )
            test.expectEqual(
                GitComplicationSource.branchName(from: "## No commits yet on main"),
                "main",
                "Git branch parsing handles repositories without commits"
            )
            git.setRepository(projectRoot())
            let gitSnapshot = await git.refresh(.interactive)
            test.expect(gitSnapshot.values["branch"] != nil, "local Git source reads the selected repository")
            test.expect(gitSnapshot.values["status"]?.kind == .status, "local Git source emits typed repository status")

            let githubExecutor = RecordingCLIExecutor { arguments in
                if arguments == ["auth", "status", "--hostname", "github.com"] { return CLIResult(output: "") }
                let endpoint = arguments.last ?? ""
                let output: String
                switch endpoint {
                case let value where value.contains("actions/runs?"):
                    output = #"{"workflow_runs":[{"id":12,"status":"completed","conclusion":"success","name":"CI","updated_at":"2026-08-30T10:00:00Z"}]}"#
                case let value where value.contains("/jobs?"):
                    output = #"{"jobs":[{"conclusion":"success"},{"conclusion":"failure"}]}"#
                case let value where value.contains("pulls?"):
                    output = #"[{"requested_reviewers":[{"login":"reviewer"}]}]"#
                case "user":
                    output = #"{"login":"reviewer"}"#
                case let value where value.contains("/statuses?"):
                    output = #"[{"state":"success","environment":"production"}]"#
                case let value where value.contains("deployments?"):
                    output = #"[{"id":7,"environment":"production"}]"#
                default:
                    output = "{}"
                }
                return CLIResult(output: output)
            }
            let github = GitHubComplicationSource(store: box.store, cliExecutor: githubExecutor)
            test.expect(github.setRepository("https://github.com/openai/example.git"), "GitHub source accepts repository URLs")
            test.expect(!github.setRepository("openai/example?inject=true"), "GitHub source rejects endpoint syntax in repository names")
            test.expectEqual(
                GitHubComplicationSource.selectableRepository(from: "https://github.com/basique-industrie/iles.git"),
                "basique-industrie/iles",
                "typed GitHub URLs normalize to owner/repository"
            )

            let listExecutor = RecordingCLIExecutor { arguments in
                if arguments == ["auth", "status", "--hostname", "github.com"] { return CLIResult(output: "") }
                if arguments.contains(where: { $0.contains("user/repos") }) {
                    return CLIResult(output: #"[{"full_name":"basique-industrie/iles","private":false},{"full_name":"jean-humann/gwnative","private":true},{"full_name":"bad"},{"full_name":"owner/name?x=1"}]"#)
                }
                return CLIResult(output: "[]", exitCode: 1)
            }
            let listed = await GitHubComplicationSource.listAccessibleRepositories(cliExecutor: listExecutor)
            test.expectEqual(
                listed,
                .repositories([
                    GitHubRepositoryChoice(nameWithOwner: "basique-industrie/iles", isPrivate: false),
                    GitHubRepositoryChoice(nameWithOwner: "jean-humann/gwnative", isPrivate: true),
                ]),
                "GitHub source lists accessible repositories from gh"
            )

            let fallbackExecutor = RecordingCLIExecutor { arguments in
                if arguments == ["auth", "status", "--hostname", "github.com"] { return CLIResult(output: "") }
                if arguments.starts(with: ["repo", "list"]) {
                    return CLIResult(output: #"[{"nameWithOwner":"owner/fallback","isPrivate":false}]"#)
                }
                return CLIResult(output: "{}", exitCode: 1)
            }
            let fallback = await GitHubComplicationSource.listAccessibleRepositories(cliExecutor: fallbackExecutor)
            test.expectEqual(
                fallback,
                .repositories([GitHubRepositoryChoice(nameWithOwner: "owner/fallback", isPrivate: false)]),
                "GitHub source falls back to gh repo list when the user API is unavailable"
            )

            let signedOut = RecordingCLIExecutor { _ in CLIResult(output: "", exitCode: 1) }
            let signedOutList = await GitHubComplicationSource.listAccessibleRepositories(cliExecutor: signedOut)
            test.expectEqual(signedOutList, .unauthenticated, "GitHub listing requires an authenticated gh session")

            let noisyList = RecordingCLIExecutor { arguments in
                if arguments == ["auth", "status", "--hostname", "github.com"] { return CLIResult(output: "") }
                if arguments.contains(where: { $0.contains("user/repos") }) {
                    return CLIResult(
                        output: "A new release of gh is available: 2.99.0\n[{\"full_name\":\"owner/from-notice\",\"private\":false}]\n"
                    )
                }
                return CLIResult(output: "[]", exitCode: 1)
            }
            let noisy = await GitHubComplicationSource.listAccessibleRepositories(cliExecutor: noisyList)
            test.expectEqual(
                noisy,
                .repositories([GitHubRepositoryChoice(nameWithOwner: "owner/from-notice", isPrivate: false)]),
                "GitHub listing reads JSON when gh prints a notice before the payload"
            )
            let githubSnapshot = await github.refresh(.interactive)
            test.expectEqual(githubSnapshot.values["ci"]?.displayText, "Passing", "GitHub source maps successful Actions runs")
            test.expectEqual(githubSnapshot.values["reviews"]?.displayText, "1", "GitHub source counts requested reviews")
            test.expectEqual(githubSnapshot.values["deployment"]?.displayText, "Deployed", "GitHub source maps deployment status")
            test.expectEqual(githubSnapshot.values["failingJobs"]?.displayText, "1", "GitHub source counts failing jobs")
            test.expect(githubExecutor.executionCount >= 6, "GitHub source uses the bounded command executor for every request")

            let mac = MacSystemComplicationSource()
            let macSnapshot = mac.currentSnapshot
            test.expectEqual(macSnapshot.sourceID, "system.mac", "Mac health source produces its own snapshot")
            test.expect(macSnapshot.values["memory"]?.kind == .gauge, "Mac health source emits typed memory utilization")
            test.expect(macSnapshot.values["thermal"]?.kind == .status, "Mac health source emits typed thermal state")
            test.expect(macSnapshot.values["storageAvailable"]?.kind == .gauge, "Mac health exposes storage available as a percentage")
            test.expect(
                mac.descriptor.complications.contains { $0.id == "system.mac.storage-available" },
                "storage available is a first-class ring recipe"
            )
            if let used = macSnapshot.values["storage"]?.progress,
               let available = macSnapshot.values["storageAvailable"]?.progress {
                test.expect(abs(used + available - 1) < 0.001, "storage used and available percentages are complementary")
            }

            let instanceRegistry = ComplicationSourceRegistry(
                providers: [],
                sessionMonitor: SessionMonitor(),
                settingsStore: box.store
            )
            let secondGitID = instanceRegistry.addSource(kind: .gitRepository)
            let secondGitHubID = instanceRegistry.addSource(kind: .githubRepository)
            let secondEndpointID = instanceRegistry.addSource(kind: .healthEndpoint)
            test.expect(secondGitID != "developer.git", "additional Git repositories receive independent source IDs")
            test.expect(secondGitHubID != "developer.github", "additional GitHub repositories receive independent source IDs")
            test.expect(secondEndpointID != "services.endpoint", "additional health endpoints receive independent source IDs")
            for id in [secondGitID, secondGitHubID, secondEndpointID] {
                let descriptor = instanceRegistry.descriptor(sourceID: id)
                test.expect(descriptor?.allowsMultipleInstances == true, "\(id) advertises multi-instance source behavior")
                test.expect(
                    descriptor?.complications.allSatisfy { $0.sourceID == id } == true,
                    "\(id) binds every kind recipe to its concrete source instance"
                )
            }
            let restoredRegistry = ComplicationSourceRegistry(
                providers: [],
                sessionMonitor: SessionMonitor(),
                settingsStore: box.store
            )
            test.expect(restoredRegistry.source(id: secondGitID) != nil, "additional source instances persist across registry creation")
            test.expect(instanceRegistry.removeSource(id: secondEndpointID), "an unused additional source instance can be removed")
        }

        let gauge = ComplicationValue.gauge(value: 73, range: 0...100, label: "73%")
        test.expectEqual(gauge.displayText, "73%", "gauge keeps its glance label")
        test.expectEqual(gauge.progress, 0.73, "gauge normalizes its range")
        test.expectEqual(
            ComplicationTransformEngine.present(gauge, as: .used).displayText,
            "73%",
            "used presentation keeps canonical consumed progress"
        )
        test.expectEqual(
            ComplicationTransformEngine.present(gauge, as: .remaining).displayText,
            "27%",
            "remaining presentation complements one bounded data slot"
        )

        do {
            let recipe = ComplicationRecipe(
                id: "test.remaining",
                name: "Remaining",
                summary: "Quota still available.",
                question: "How much remains?",
                sourceID: "test",
                category: .ai,
                tags: ["quota"],
                family: .ring,
                compatibleFamilies: [.ring, .value],
                slots: [
                    ComplicationMetricSlot(metricID: "used", transforms: [.remaining]),
                ],
                fixtures: [
                    ComplicationFixture(
                        name: "Normal",
                        state: .normal,
                        values: ["used": .gauge(value: 70, range: 0...100, label: "70%")]
                    ),
                ]
            )
            let source = ComplicationSourceDescriptor(
                id: "test",
                name: "Test",
                kind: .usage,
                symbol: "gauge",
                metrics: [ComplicationMetricDescriptor(id: "used", name: "Used", kind: .gauge)],
                supportedFamilies: [.ring, .value],
                complications: [recipe],
                capabilities: [.quota]
            )
            let snapshot = SourceSnapshot(
                sourceID: "test",
                values: ["used": .gauge(value: 70, range: 0...100, label: "70%")]
            )
            test.expectEqual(
                ComplicationTransformEngine.resolve(recipe: recipe, snapshot: snapshot).first?.displayText,
                "30%",
                "recipe transformations derive remaining quota from one raw metric"
            )
            test.expectEqual(
                ComplicationRecipeValidator.issues(in: recipe, source: source),
                [],
                "complete catalog recipe validates"
            )
            let incompatibleRecipe = ComplicationRecipe(
                id: "test.invalid-ring",
                name: "Invalid Ring",
                summary: "A deliberately invalid recipe.",
                question: "Does validation reject a date ring?",
                sourceID: "test",
                category: .time,
                family: .ring,
                slots: [ComplicationMetricSlot(metricID: "date")],
                fixtures: [
                    ComplicationFixture(
                        name: "Typical",
                        state: .normal,
                        values: ["date": .date(Date(), label: "Now")]
                    ),
                ]
            )
            let incompatibleSource = ComplicationSourceDescriptor(
                id: "test",
                name: "Test",
                kind: .time,
                symbol: "clock",
                metrics: [ComplicationMetricDescriptor(id: "date", name: "Date", kind: .date)],
                supportedFamilies: [.ring]
            )
            test.expect(
                ComplicationRecipeValidator.issues(in: incompatibleRecipe, source: incompatibleSource)
                    .contains(.incompatibleMetricKinds(["date"])),
                "catalog validation rejects a family that cannot render its transformed metric"
            )
            let currentOnly = ComplicationMetricDescriptor(
                id: "current",
                name: "Current value",
                kind: .value,
                policy: ComplicationMetricPolicy(format: .count)
            )
            test.expect(
                !ComplicationRecipeValidator.family(.trend, supports: currentOnly.kind, metric: currentOnly),
                "trend is hidden when a metric has neither history nor thresholds"
            )
            test.expect(
                !ComplicationRecipeValidator.family(.countdown, supports: gauge.kind),
                "countdown is hidden for percentages without time semantics"
            )
            test.expectEqual(
                ComplicationMetricDirection.lowerIsBetter.transformed(by: [.remaining]),
                .higherIsBetter,
                "remaining values invert metric health direction"
            )
            test.expectEqual(
                ComplicationMetricDirection.lowerIsBetter.transformed(by: [.remaining, .remaining]),
                .lowerIsBetter,
                "two complementary presentations restore the original health direction"
            )
            test.expectEqual(
                ComplicationThreshold(warning: 75, critical: 90).transformed(by: [.remaining]),
                ComplicationThreshold(warning: 25, critical: 10),
                "remaining values invert warning and critical thresholds"
            )

            var history = ComplicationHistoryBuffer(retention: 3_600, maximumPointsPerMetric: 2)
            let historyMetric = ComplicationMetricDescriptor(
                id: "used",
                name: "Used",
                kind: .gauge,
                policy: ComplicationMetricPolicy(format: .percentage, keepsHistory: true)
            )
            history.record(sourceID: "test", snapshot: snapshot, metrics: [historyMetric])
            history.record(
                sourceID: "test",
                snapshot: SourceSnapshot(
                    sourceID: "test",
                    capturedAt: snapshot.capturedAt.addingTimeInterval(60),
                    values: ["used": .gauge(value: 72, range: 0...100, label: "72%")]
                ),
                metrics: [historyMetric]
            )
            history.record(
                sourceID: "test",
                snapshot: SourceSnapshot(
                    sourceID: "test",
                    capturedAt: snapshot.capturedAt.addingTimeInterval(120),
                    values: ["used": .gauge(value: 74, range: 0...100, label: "74%")]
                ),
                metrics: [historyMetric]
            )
            test.expectEqual(history.pointCount(sourceID: "test", metricID: "used"), 2, "metric history is bounded")

            var sampledHistory = ComplicationHistoryBuffer(minimumSampleInterval: 30)
            sampledHistory.record(sourceID: "test", snapshot: snapshot, metrics: [historyMetric])
            sampledHistory.record(
                sourceID: "test",
                snapshot: SourceSnapshot(
                    sourceID: "test",
                    capturedAt: snapshot.capturedAt.addingTimeInterval(2),
                    values: ["used": .gauge(value: 71, range: 0...100, label: "71%")]
                ),
                metrics: [historyMetric]
            )
            test.expectEqual(
                sampledHistory.pointCount(sourceID: "test", metricID: "used"),
                1,
                "live metrics are downsampled before entering bounded history"
            )
            let currentDate = snapshot.capturedAt.addingTimeInterval(120)
            let previousContext = history.context(sourceID: "test", now: currentDate, before: currentDate)
            test.expectEqual(previousContext.history["used"]?.last?.value, 72, "transform context excludes the current sample")
            let deltaRecipe = ComplicationRecipe(
                id: "test.delta",
                name: "Delta",
                sourceID: "test",
                family: .trend,
                slots: [ComplicationMetricSlot(metricID: "used", transforms: [.delta])]
            )
            test.expectEqual(
                ComplicationTransformEngine.resolve(
                    recipe: deltaRecipe,
                    snapshot: SourceSnapshot(
                        sourceID: "test",
                        capturedAt: currentDate,
                        values: ["used": .gauge(value: 74, range: 0...100, label: "74%")]
                    ),
                    context: previousContext
                ).first?.displayText,
                "2",
                "delta compares the latest value with the prior sample"
            )

            let future = Date(timeIntervalSince1970: 7_200)
            let countdown = ComplicationRecipe(
                id: "test.countdown",
                name: "Countdown",
                summary: "Time until an event.",
                question: "When does it happen?",
                sourceID: "test",
                category: .time,
                family: .countdown,
                slots: [ComplicationMetricSlot(metricID: "date", transforms: [.countdown])],
                labelStyle: .compact,
                fixtures: [ComplicationFixture(name: "Normal", state: .normal, values: [:])]
            )
            let countdownSnapshot = SourceSnapshot(
                sourceID: "test",
                values: ["date": .date(future, label: "Later")]
            )
            test.expectEqual(
                ComplicationTransformEngine.resolve(
                    recipe: countdown,
                    snapshot: countdownSnapshot,
                    context: ComplicationTransformContext(now: Date(timeIntervalSince1970: 0))
                ).first?.displayText,
                "2h",
                "countdown recipes derive compact time labels"
            )
        }

        let dual = ComplicationConfiguration(
            sourceID: "claude",
            metricIDs: ["quota.session", "quota.weekly", "quota.extra"],
            family: .dualRing,
            slotTints: [
                ComplicationTint(style: .custom, hex: "FF5500"),
                ComplicationTint(style: .custom, hex: "44AAFF"),
            ],
            slotValueModes: [.remaining, .used, .remaining]
        )
        test.expectEqual(dual.metricIDs.count, 2, "dual-ring metric count is bounded")
        test.expectEqual(dual.slotTints.count, 2, "dual rings retain one tint per visible ring")
        test.expectEqual(dual.slotValueModes, [.remaining, .used], "dual rings retain one usage value mode per slot")
        if let encoded = try? JSONEncoder().encode(dual),
           let decoded = try? JSONDecoder().decode(ComplicationConfiguration.self, from: encoded) {
            test.expectEqual(decoded.slotTints, dual.slotTints, "per-ring colors persist with the complication")
            test.expectEqual(decoded.slotValueModes, dual.slotValueModes, "per-ring usage value modes persist with the complication")
        } else {
            test.expect(false, "per-ring options encode and decode")
        }
        var changedFamily = dual
        changedFamily.setFamily(.ring)
        test.expectEqual(changedFamily.metricIDs.count, 1, "single-metric families discard extra metrics")
        test.expect(changedFamily.slotTints.isEmpty, "single-metric families discard unused slot colors")
        test.expectEqual(changedFamily.slotValueModes, [.remaining], "single-metric families discard unused value modes")
        test.expectEqual(
            ComplicationValueMode.remainingDefaults(
                sourceID: "claude",
                metricIDs: ["quota.session", "quota.weekly"],
                family: .dualRing
            ),
            [.remaining, .remaining],
            "new quota rings default to remaining"
        )
        test.expect(
            ComplicationValueMode.remainingDefaults(
                sourceID: "system.mac",
                metricIDs: ["cpu"],
                family: .ring
            ).isEmpty,
            "non-quota rings keep the used decode fallback"
        )

        do {
            let json = Data("""
            {
              "membershipType": "ultra",
              "billingCycleEnd": "2026-09-17T00:00:00.000Z",
              "isUnlimited": false,
              "autoModelSelectedDisplayMessage": "You've used 25% of your included total usage",
              "namedModelSelectedDisplayMessage": "You've used 91% of your included API usage",
              "individualUsage": {
                "plan": {
                  "enabled": true,
                  "used": 40595,
                  "limit": 119198,
                  "remaining": 78603,
                  "autoPercentUsed": 25,
                  "apiPercentUsed": 91,
                  "totalPercentUsed": 34
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
              }
            }
            """.utf8)
            let snapshot = try CursorUsageProbe.parseUsageSummary(json)
            test.expectEqual(snapshot.quotas.count, 2, "Cursor dashboard is two pools, not one combined request bar")
            let models = snapshot.quota(for: CursorQuotaPool.models)
            let other = snapshot.quota(for: CursorQuotaPool.other)
            test.expect(models != nil, "Cursor Models pool")
            test.expect(other != nil, "Other Models pool")
            test.expect(abs((models?.percentUsed ?? -1) - 25) < 0.01, "Cursor Models is 25% used")
            test.expect(abs((other?.percentUsed ?? -1) - 91) < 0.01, "Other Models is 91% used")
            test.expect(snapshot.quota(for: CursorQuotaPool.monthly) == nil, "combined request count is not a dashboard bar")
            test.expectEqual(
                ProviderBrand.cursor.primaryQuota(in: snapshot)?.quotaType,
                CursorQuotaPool.models,
                "island ring uses Cursor Models"
            )
            test.expectEqual(
                ProviderBrand.cursor.secondaryQuota(in: snapshot)?.quotaType,
                CursorQuotaPool.other,
                "hover card second row is Other Models"
            )
            let claudeSnapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 98, quotaType: .session, providerId: "claude"),
                    UsageQuota(percentRemaining: 23, quotaType: .weekly, providerId: "claude"),
                    UsageQuota(percentRemaining: 41, quotaType: .modelSpecific("opus"), providerId: "claude"),
                    UsageQuota(percentRemaining: 80, quotaType: .modelSpecific("sonnet"), providerId: "claude"),
                ],
                capturedAt: Date()
            )
            test.expectEqual(
                ProviderQuotaPolicy.hoverQuotas(
                    providerId: "claude",
                    in: claudeSnapshot,
                    ring: claudeSnapshot.weeklyQuota
                ).map(\.quotaType),
                [.session, .weekly, .modelSpecific("opus")],
                "claude hover is session, weekly, opus"
            )
        } catch {
            test.expect(false, "ultra two-pool parse: \(error)")
        }

        do {
            let json = Data("""
            {
              "membershipType": "pro",
              "isUnlimited": false,
              "individualUsage": {
                "plan": {
                  "enabled": true,
                  "used": 40595,
                  "limit": 119198,
                  "remaining": 78603
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
              }
            }
            """.utf8)
            let snapshot = try CursorUsageProbe.parseUsageSummary(json)
            test.expectEqual(snapshot.quotas.count, 1, "limit-based plan is one monthly bar")
            let used = snapshot.quotas[0].percentUsed
            test.expect(abs(used - (40595.0 / 119198.0 * 100)) < 0.01, "limit-based percent matches used/limit")
            test.expectEqual(Int(snapshot.quotas[0].percentUsed.rounded()), 34, "40595/119198 rounds to 34%")
        } catch {
            test.expect(false, "limit-based plan parse: \(error)")
        }

        do {
            let json = Data("""
            {
              "membershipType": "enterprise",
              "limitType": "team",
              "isUnlimited": false,
              "autoModelSelectedDisplayMessage": "You've used 25% of your included total usage",
              "namedModelSelectedDisplayMessage": "You've used 91% of your included API usage",
              "individualUsage": {}
            }
            """.utf8)
            let snapshot = try CursorUsageProbe.parseUsageSummary(json)
            test.expectEqual(snapshot.quotas.count, 2, "team accounts expose the two pools via display messages")
            test.expect(abs((snapshot.quota(for: CursorQuotaPool.models)?.percentUsed ?? -1) - 25) < 0.01, "message Cursor Models")
            test.expect(abs((snapshot.quota(for: CursorQuotaPool.other)?.percentUsed ?? -1) - 91) < 0.01, "message Other Models")
        } catch {
            test.expect(false, "message-only parse: \(error)")
        }

        do {
            let json = Data("""
            {
              "schemaVersion": 1,
              "capturedAt": "2026-09-13T12:00:00Z",
              "accounts": [
                {
                  "id": "a1",
                  "provider": "claude",
                  "label": "Work",
                  "email": "work@example.com",
                  "quotas": [
                    {
                      "type": "time:Claude · work 5h",
                      "percentRemaining": 62,
                      "resetsAt": "2026-09-13T14:00:00Z",
                      "resetText": "Resets in 2h",
                      "group": "Claude · work@example.com",
                      "compactTitle": "5h",
                      "menuBarTitle": "Claude 5h"
                    }
                  ]
                },
                {
                  "id": "a2",
                  "provider": "codex",
                  "label": "Personal",
                  "quotas": [
                    {
                      "type": "time:Codex · personal 5h",
                      "percentRemaining": 44
                    }
                  ]
                }
              ]
            }
            """.utf8)
            let snapshot = try HarnaisUsageProbe.parse(json)
            test.expectEqual(snapshot.quotas.count, 2, "Harnais feed maps one quota per window")
            test.expectEqual(snapshot.quotas[0].group, "Claude · Work", "Harnais groups use the account label, not the mailbox")
            test.expectEqual(snapshot.quotas[0].providerId, "claude", "Harnais windows keep the upstream provider")
            test.expectEqual(snapshot.quotas[0].quotaType, .timeLimit("Claude · work 5h"), "Harnais type keys stay time windows")
            test.expectEqual(snapshot.quotas[0].compactTitle, "5h", "Harnais compact titles survive decode")
            test.expectEqual(snapshot.quotas[1].group, "Codex · Personal", "Harnais fills a group from provider and label")
            test.expectEqual(snapshot.quotas[1].providerId, "codex", "Harnais Codex windows keep the upstream provider")
            test.expect(snapshot.quotas.allSatisfy { $0.group?.contains("@") != true }, "parsed Harnais groups never include mailboxes")
            test.expectEqual(snapshot.accountEmail, nil, "Harnais snapshots never copy mailboxes")
            let hiddenSnapshot = try HarnaisUsageProbe.parse(json, hiddenTypes: ["time:Claude · work 5h"])
            test.expectEqual(hiddenSnapshot.quotas.count, 2, "visibility preserves all quota definitions")
            test.expectEqual(hiddenSnapshot.hiddenQuotaTypes, ["time:Claude · work 5h"], "native Harnais carries visibility separately")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let feedURL = directory.appendingPathComponent("quotas.json")
            let preferencesURL = directory.appendingPathComponent("islands.json")
            try json.write(to: feedURL)
            let liveJSON = String(decoding: json, as: UTF8.self).replacingOccurrences(
                of: "2026-09-13T12:00:00Z", with: ISO8601DateFormatter().string(from: Date())
            )
            let executor = RecordingCLIExecutor(result: CLIResult(output: liveJSON))
            let probe = HarnaisUsageProbe(configurationDirectory: directory, executor: executor)
            let withoutPreferences = try await probe.probe()
            test.expect(withoutPreferences.hiddenQuotaTypes.isEmpty, "missing visibility file defaults to visible")
            try Data(#"{"schemaVersion":1,"hiddenTypes":["time:Claude · work 5h"]}"#.utf8).write(to: preferencesURL)
            let withPreferences = try await probe.probe()
            test.expectEqual(withPreferences.hiddenQuotaTypes, hiddenSnapshot.hiddenQuotaTypes, "probe reads preferences beside its feed")
            test.expectEqual(withPreferences.quotas, withoutPreferences.quotas, "reading visibility never drops quota data")
            try Data("invalid".utf8).write(to: preferencesURL)
            do {
                _ = try await probe.probe()
                test.expect(false, "invalid visibility must not silently enable hidden rings")
            } catch {
                test.expect(true, "invalid visibility fails the read and preserves the prior provider snapshot")
            }


        } catch {
            test.expect(false, "Harnais quotas.json parse: \(error)")
        }

        do {
            let json = Data("""
            {
              "schemaVersion": 1,
              "capturedAt": "2026-09-13T12:00:00.250Z",
              "accounts": [
                {
                  "id": "c1",
                  "provider": "cursor",
                  "label": "Default",
                  "quotas": [
                    {
                      "type": "time:Cursor · Default Models",
                      "percentRemaining": 65
                    }
                  ]
                }
              ]
            }
            """.utf8)
            let snapshot = try HarnaisUsageProbe.parse(json)
            test.expectEqual(snapshot.quotas.count, 1, "fractional capturedAt still parses")
            test.expect(snapshot.quotas[0].isAccountGlanceWindow, "Cursor Models is a glance window without compactTitle")
            test.expectEqual(snapshot.quotas[0].windowKind, .models, "Cursor Models type names map to Models")
        } catch {
            test.expect(false, "Harnais fractional date parse: \(error)")
        }

        do {
            let json = Data("""
            {
              "capturedAt": "2026-09-13T12:00:00Z",
              "accounts": [
                {
                  "id": "bad",
                  "provider": "claude",
                  "label": "Work",
                  "error": "session expired",
                  "quotas": []
                }
              ]
            }
            """.utf8)
            _ = try HarnaisUsageProbe.parse(json)
            test.expect(false, "Harnais should fail when every account is an error")
        } catch ProbeError.executionFailed(let message) {
            test.expectEqual(message, "session expired", "Harnais surfaces the account error")
        } catch {
            test.expect(false, "Harnais account error: \(error)")
        }

        do {
            let models = UsageQuota(
                percentRemaining: 40,
                quotaType: .timeLimit("Cursor · Default Models"),
                providerId: "cursor"
            )
            let weekly = UsageQuota(
                percentRemaining: 80,
                quotaType: .timeLimit("Claude · work 7d"),
                providerId: "claude",
                compactTitle: "7d"
            )
            let session = UsageQuota(
                percentRemaining: 10,
                quotaType: .timeLimit("Claude · work 5h"),
                providerId: "claude",
                compactTitle: "5h"
            )
            test.expectEqual(models.windowKind, .models, "Models token from the type name")
            test.expect(models.isAccountGlanceWindow, "Models is an account glance")
            test.expectEqual(weekly.windowKind, .weekly, "compact 7d is weekly")
            test.expectEqual(session.windowKind, .session, "compact 5h is session")
            test.expect(!session.isAccountGlanceWindow, "5h is not the account glance")
        }

    }

    /// Packaged apps resolve marks from `Contents/Resources/Iles_IlesCore.bundle`,
    /// not from SPM's `Bundle.module` next to the `.app`.
    @MainActor
    private static func runPackagedResourceBundleTests(_ test: TestHarness) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iles-resource-bundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let svg = projectRoot().appendingPathComponent("Sources/Iles/Resources/GitHubIcon.svg")
        guard let svgData = try? Data(contentsOf: svg), !svgData.isEmpty else {
            test.expect(false, "GitHubIcon.svg is available to build a packaged resource bundle")
            return
        }

        let appURL = root.appendingPathComponent("Iles.app")
        let emptyModuleURL = root.appendingPathComponent("Empty.bundle")
        do {
            try writeFakeApplication(
                at: appURL,
                resourceFiles: ["GitHubIcon.svg": svgData]
            )
            try writeBundle(at: emptyModuleURL, identifier: "com.jean.iles.empty-module")
        } catch {
            test.expect(false, "packaged resource-bundle fixture: \(error.localizedDescription)")
            return
        }

        guard let application = Bundle(url: appURL),
              let emptyModule = Bundle(url: emptyModuleURL)
        else {
            test.expect(false, "fake application and empty module bundles load")
            return
        }

        var fallbackEvaluated = false
        func moduleFallback() -> Bundle {
            fallbackEvaluated = true
            return emptyModule
        }
        let packaged = IlesResourceBundle.resolve(applicationBundle: application, moduleBundle: moduleFallback())
        test.expect(!fallbackEvaluated, "packaged lookup never evaluates the build-machine module fallback")
        test.expect(
            packaged.bundleURL.path.hasSuffix("Contents/Resources/Iles_IlesCore.bundle"),
            "packaged layout resolves Iles_IlesCore.bundle from Contents/Resources"
        )
        test.expect(
            packaged.url(forResource: "GitHubIcon", withExtension: "svg") != nil,
            "packaged resource bundle exposes GitHubIcon.svg"
        )
        test.expect(
            packaged.url(forResource: "GitHubIcon", withExtension: "svg").flatMap(NSImage.init(contentsOf:))?
                .representations.isEmpty == false,
            "packaged GitHubIcon.svg decodes"
        )

        let missingAppURL = root.appendingPathComponent("Missing.app")
        do {
            try writeFakeApplication(at: missingAppURL, resourceFiles: [:])
        } catch {
            test.expect(false, "missing-resource application fixture: \(error.localizedDescription)")
            return
        }
        guard let missingApplication = Bundle(url: missingAppURL) else {
            test.expect(false, "application without a resource bundle still loads")
            return
        }
        let fallback = IlesResourceBundle.resolve(
            applicationBundle: missingApplication,
            moduleBundle: moduleFallback()
        )
        test.expect(fallbackEvaluated, "development lookup evaluates the module fallback only when needed")
        test.expectEqual(
            fallback.bundleURL.path,
            emptyModule.bundleURL.path,
            "missing packaged bundle falls back to the module bundle"
        )
    }

    private static func writeFakeApplication(at appURL: URL, resourceFiles: [String: Data]) throws {
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let core = resources.appendingPathComponent("Iles_IlesCore.bundle", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try Data("#".utf8).write(to: macos.appendingPathComponent("Iles"))
        try writePlist(
            [
                "CFBundleIdentifier": "com.jean.iles.resource-bundle-test",
                "CFBundleName": "Iles",
                "CFBundleExecutable": "Iles",
                "CFBundlePackageType": "APPL",
                "CFBundleInfoDictionaryVersion": "6.0",
            ],
            to: contents.appendingPathComponent("Info.plist")
        )
        if !resourceFiles.isEmpty {
            try writeBundle(
                at: core,
                identifier: "Iles_IlesCore",
                files: resourceFiles
            )
        }
    }

    private static func writeBundle(
        at url: URL,
        identifier: String,
        files: [String: Data] = [:]
    ) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try writePlist(
            [
                "CFBundleIdentifier": identifier,
                "CFBundleName": url.deletingPathExtension().lastPathComponent,
                "CFBundlePackageType": "BNDL",
                "CFBundleInfoDictionaryVersion": "6.0",
            ],
            to: url.appendingPathComponent("Info.plist")
        )
        for (name, data) in files {
            try data.write(to: url.appendingPathComponent(name))
        }
    }

    private static func writePlist(_ values: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: url)
    }
}
