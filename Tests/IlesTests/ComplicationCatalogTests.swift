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

        test.expectEqual(ProviderBrand.allCases.count, 18, "built-in brand count")
        test.expectEqual(Set(ProviderBrand.allCases.map(\.id)).count, 18, "brand ids are unique")
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

        let demo = IsolatedBox.make()
        defer { demo.tearDown() }
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
            test.expect(recipes.count >= 80, "focused launch catalog retains broad first-party coverage (found \(recipes.count))")
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

    }
}
