import Domain
import Foundation

extension FirstPartyComplicationCatalog {
    static func providerRecipes(sourceID: String, metrics: [ComplicationMetricDescriptor]) -> [ComplicationRecipe] {
        let ids = Set(metrics.map(\.id))
        var recipes: [ComplicationRecipe] = []

        func gaugeFixture(_ metricID: String, value: Double = 42) -> [ComplicationFixture] {
            [
                ComplicationFixture(
                    name: "Typical",
                    state: .normal,
                    values: [metricID: .gauge(value: value, range: 0...100, label: "\(Int(value))%")]
                ),
                ComplicationFixture(
                    name: "Warning",
                    state: .warning,
                    values: [metricID: .gauge(value: 78, range: 0...100, label: "78%")]
                ),
                ComplicationFixture(
                    name: "Critical",
                    state: .critical,
                    values: [metricID: .gauge(value: 94, range: 0...100, label: "94%")]
                ),
            ]
        }

        func quotaRecipe(
            id suffix: String,
            name: String,
            summary: String,
            question: String,
            metricID: String,
            transforms: [ComplicationTransform] = [],
            rank: Int,
            featured: Bool = false,
            capabilities: [ComplicationCapability] = [.quota]
        ) -> ComplicationRecipe {
            ComplicationRecipe(
                id: "\(sourceID).\(suffix)",
                name: name,
                summary: summary,
                question: question,
                sourceID: sourceID,
                category: .ai,
                tags: ["AI", "quota", "usage", "credits", "limit"],
                family: .ring,
                compatibleFamilies: [.ring, .value, .trend],
                slots: [ComplicationMetricSlot(metricID: metricID, transforms: transforms)],
                labelStyle: .percentage,
                requiredCapabilities: capabilities,
                rank: rank,
                isFeatured: featured,
                fixtures: gaugeFixture(metricID)
            )
        }

        let namedQuotaMetrics = metrics.filter { $0.id.hasPrefix("quota.key.") }
        var windowMetrics: [ComplicationMetricDescriptor] = []

        if let session = metrics.first(where: { $0.id == "quota.session" }) {
            windowMetrics.append(session)
            recipes.append(quotaRecipe(
                id: "session",
                name: "Session Usage",
                summary: "Your current rolling session allowance, shown as used or remaining.",
                question: "How much room is left in my current session window?",
                metricID: session.id,
                rank: 100,
                featured: true
            ))
        }
        if let weekly = metrics.first(where: { $0.id == "quota.weekly" }) {
            windowMetrics.append(weekly)
            recipes.append(quotaRecipe(
                id: "weekly",
                name: "Weekly Usage",
                summary: "Your weekly allowance, shown as used or remaining.",
                question: "How much room is left in my weekly window?",
                metricID: weekly.id,
                rank: 96
            ))
        }

        for metric in namedQuotaMetrics {
            windowMetrics.append(metric)
            let key = String(metric.id.dropFirst("quota.key.".count))
            let component = stableIDComponent(key)
            recipes.append(quotaRecipe(
                id: "quota-\(component)",
                name: metric.name,
                summary: "\(metric.name), shown as used or remaining.",
                question: "What is my current \(metric.name.lowercased()) level?",
                metricID: metric.id,
                rank: 94
            ))
        }

        if ids.isSuperset(of: ["quota.session", "quota.weekly"]) {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).session-weekly",
                    name: "Session + Weekly",
                    summary: "The two most important usage windows in one glance.",
                    question: "Are either of my active quota windows close to their limit?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "session", "weekly", "combined"],
                    family: .dualRing,
                    compatibleFamilies: [.dualRing, .summary],
                    slots: [
                        ComplicationMetricSlot(metricID: "quota.session"),
                        ComplicationMetricSlot(metricID: "quota.weekly"),
                    ],
                    labelStyle: .percentage,
                    requiredCapabilities: [.quota],
                    rank: 98,
                    isFeatured: true,
                    fixtures: [
                        ComplicationFixture(
                            name: "Typical",
                            state: .normal,
                            values: [
                                "quota.session": .gauge(value: 34, range: 0...100, label: "34%"),
                                "quota.weekly": .gauge(value: 61, range: 0...100, label: "61%"),
                            ]
                        ),
                    ]
                )
            )
        } else if windowMetrics.count >= 2 {
            let pair = Array(windowMetrics.prefix(2))
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).quota-pair",
                    name: "\(pair[0].name) + \(pair[1].name)",
                    summary: "The two most useful provider limits in one nested glance.",
                    question: "Which of my main limits needs attention first?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "limits", "combined"],
                    family: .dualRing,
                    compatibleFamilies: [.dualRing, .summary],
                    slots: pair.map { ComplicationMetricSlot(metricID: $0.id) },
                    labelStyle: .percentage,
                    requiredCapabilities: [.quota],
                    rank: 98,
                    isFeatured: true,
                    fixtures: [
                        ComplicationFixture(
                            name: "Typical",
                            state: .normal,
                            values: [
                                pair[0].id: .gauge(value: 34, range: 0...100, label: "34%"),
                                pair[1].id: .gauge(value: 61, range: 0...100, label: "61%"),
                            ]
                        ),
                    ]
                )
            )
        }

        if windowMetrics.count >= 3 {
            let trio = Array(windowMetrics.prefix(3))
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).quota-trio",
                    name: "Quota Trio",
                    summary: "Three bounded provider limits shown as truthful concentric progress rings.",
                    question: "How are my three main provider limits tracking?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "limits", "trio"],
                    family: .cluster,
                    compatibleFamilies: [.cluster],
                    slots: trio.map { ComplicationMetricSlot(metricID: $0.id) },
                    labelStyle: .compact,
                    requiredCapabilities: [.quota],
                    rank: 95,
                    fixtures: [
                        ComplicationFixture(
                            name: "Typical",
                            state: .normal,
                            values: Dictionary(uniqueKeysWithValues: zip(trio, [28.0, 52.0, 74.0]).map {
                                ($0.0.id, .gauge(value: $0.1, range: 0...100, label: "\(Int($0.1))%"))
                            })
                        ),
                    ]
                )
            )
        }

        if ids.contains("status.overall") {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).quota-health",
                    name: "Quota Health",
                    summary: "The most urgent quota state reported by this provider.",
                    question: "Does any quota need my attention?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "health", "warning", "critical"],
                    family: .status,
                    compatibleFamilies: [.status, .activity],
                    slots: [ComplicationMetricSlot(metricID: "status.overall")],
                    labelStyle: .compact,
                    requiredCapabilities: [.quota, .status],
                    rank: 97,
                    isFeatured: true,
                    fixtures: [
                        ComplicationFixture(
                            name: "Healthy",
                            state: .normal,
                            values: ["status.overall": .status(label: "All Healthy", level: .healthy)]
                        ),
                        ComplicationFixture(
                            name: "Critical",
                            state: .critical,
                            values: ["status.overall": .status(label: "Weekly Critical", level: .critical)]
                        ),
                    ]
                )
            )
        }

        if ids.contains("reset.next") {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).next-reset",
                    name: "Next Quota Reset",
                    summary: "A live countdown to the next known quota renewal.",
                    question: "When will more quota become available?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "reset", "countdown", "renewal"],
                    family: .countdown,
                    compatibleFamilies: [.countdown, .value],
                    slots: [ComplicationMetricSlot(metricID: "reset.next", transforms: [.countdown])],
                    labelStyle: .compact,
                    requiredCapabilities: [.resetDate],
                    rank: 92,
                    fixtures: [
                        ComplicationFixture(
                            name: "Soon",
                            state: .normal,
                            values: ["reset.next": .date(Date().addingTimeInterval(1_800), label: "5h · 30m")]
                        ),
                    ]
                )
            )
        }

        if ids.contains("pace.primary") {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).burn-pace",
                    name: "Quota Burn Pace",
                    summary: "Whether quota is being consumed faster than its window is passing.",
                    question: "Am I using quota at a sustainable pace?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "quota", "pace", "rate", "forecast"],
                    family: .trend,
                    compatibleFamilies: [.trend, .value],
                    slots: [ComplicationMetricSlot(metricID: "pace.primary")],
                    labelStyle: .value,
                    requiredCapabilities: [.quota, .resetDate],
                    rank: 91,
                    fixtures: [
                        ComplicationFixture(
                            name: "On track",
                            state: .normal,
                            values: ["pace.primary": .value("1.0", unit: "×")]
                        ),
                        ComplicationFixture(
                            name: "Running hot",
                            state: .warning,
                            values: ["pace.primary": .value("1.8", unit: "×")]
                        ),
                    ]
                )
            )
        }

        if ids.contains("cost.total") {
            recipes.append(valueRecipe(
                id: "\(sourceID).total-cost",
                name: "Total Cost",
                summary: "Current spend reported by the provider.",
                question: "How much have I spent?",
                sourceID: sourceID,
                metricID: "cost.total",
                tags: ["AI", "cost", "spend", "budget"],
                rank: 88,
                capabilities: [.cost]
            ))
        }
        if ids.contains("cost.budget.remaining") {
            recipes.append(valueRecipe(
                id: "\(sourceID).budget-remaining",
                name: "Budget Remaining",
                summary: "Money left in the provider's configured budget.",
                question: "How much budget remains?",
                sourceID: sourceID,
                metricID: "cost.budget.remaining",
                tags: ["AI", "cost", "budget", "remaining"],
                rank: 90,
                capabilities: [.cost]
            ))
        }
        if ids.contains("cost.budget.used") {
            recipes.append(quotaRecipe(
                id: "budget-used",
                name: "Budget Used",
                summary: "The share of the provider budget already spent.",
                question: "How much of my budget have I spent?",
                metricID: "cost.budget.used",
                rank: 89,
                capabilities: [.cost]
            ))
        }

        for metric in metrics where metric.id.hasPrefix("balance.key.") {
            let key = String(metric.id.dropFirst("balance.key.".count))
            recipes.append(valueRecipe(
                id: "\(sourceID).balance-\(stableIDComponent(key))",
                name: metric.name,
                summary: "The exact unbounded credit balance reported by this provider.",
                question: "How much credit remains?",
                sourceID: sourceID,
                metricID: metric.id,
                tags: ["AI", "credits", "balance", "currency"],
                rank: 100,
                capabilities: [],
                fixtureValue: .value("42.00", unit: metric.unit)
            ))
        }

        let dailyValueRecipes: [(String, String, String, Int)] = [
            ("daily.cost", "Cost Today", "How much have I spent today?", 93),
            ("daily.tokens", "Tokens Today", "How many tokens have I used today?", 92),
            ("daily.sessions", "Sessions Today", "How many coding sessions have I run today?", 90),
            ("daily.working-time", "Working Time Today", "How long have I worked with this provider today?", 89),
        ]
        for item in dailyValueRecipes where ids.contains(item.0) {
            let fixture: ComplicationValue = switch item.0 {
            case "daily.cost": .value("4.20", unit: "USD")
            case "daily.tokens": .value("82K", unit: nil)
            case "daily.sessions": .value("3", unit: nil)
            case "daily.working-time": .duration(7_200, label: "2h")
            default: .value("—", unit: nil)
            }
            recipes.append(valueRecipe(
                id: "\(sourceID).\(item.0.replacingOccurrences(of: ".", with: "-"))",
                name: item.1,
                summary: "Today's local usage from completed and active coding sessions.",
                question: item.2,
                sourceID: sourceID,
                metricID: item.0,
                tags: ["AI", "today", "daily", "usage"],
                rank: item.3,
                capabilities: [.shortHistory],
                fixtureValue: fixture
            ))
        }
        if ids.isSuperset(of: ["daily.cost", "daily.tokens", "daily.sessions"]) {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).daily-summary",
                    name: "Today's Usage",
                    summary: "Cost, tokens, and session count in one compact summary.",
                    question: "What have I used today?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "today", "cost", "tokens", "sessions"],
                    family: .summary,
                    compatibleFamilies: [.summary],
                    slots: ["daily.cost", "daily.tokens", "daily.sessions"].map {
                        ComplicationMetricSlot(metricID: $0)
                    },
                    labelStyle: .compact,
                    requiredCapabilities: [.shortHistory],
                    rank: 95,
                    isFeatured: sourceID == "mistral",
                    fixtures: [
                        ComplicationFixture(
                            name: "Typical",
                            state: .normal,
                            values: [
                                "daily.cost": .value("4.20", unit: "USD"),
                                "daily.tokens": .value("82K", unit: nil),
                                "daily.sessions": .value("3", unit: nil),
                            ]
                        ),
                    ]
                )
            )
        }
        if ids.contains("daily.cost") {
            recipes.append(
                ComplicationRecipe(
                    id: "\(sourceID).daily-cost-trend",
                    name: "Daily Cost Trend",
                    summary: "Whether today's local session cost is moving above or below recent samples.",
                    question: "Is my daily AI cost increasing?",
                    sourceID: sourceID,
                    category: .ai,
                    tags: ["AI", "cost", "today", "trend"],
                    family: .trend,
                    compatibleFamilies: [.trend, .value],
                    slots: [ComplicationMetricSlot(metricID: "daily.cost")],
                    labelStyle: .value,
                    requiredCapabilities: [.shortHistory],
                    rank: 91,
                    fixtures: [
                        ComplicationFixture(
                            name: "Typical",
                            state: .normal,
                            values: ["daily.cost": .value("4.20", unit: "USD")]
                        ),
                    ]
                )
            )
        }

        return recipes.sorted { lhs, rhs in
            if lhs.rank == rhs.rank { return lhs.name < rhs.name }
            return lhs.rank > rhs.rank
        }
    }
}
