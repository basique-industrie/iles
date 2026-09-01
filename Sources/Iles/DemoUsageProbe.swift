import Domain
import Foundation

/// Static snapshots for `--demo` mode.
struct DemoUsageProbe: UsageProbe {
    let snapshot: UsageSnapshot

    func probe() async throws -> UsageSnapshot { snapshot }
    func isAvailable() async -> Bool { true }

    static let claude = DemoUsageProbe(
        snapshot: UsageSnapshot(
            providerId: ProviderIdentity.claude.rawValue,
            quotas: [
                UsageQuota(
                    percentRemaining: 27,
                    quotaType: .session,
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: Date().addingTimeInterval(51 * 60),
                    resetText: "Resets in 51 min"
                ),
                UsageQuota(
                    percentRemaining: 93,
                    quotaType: .weekly,
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: DemoUsageProbe.nextWeekday(5, hour: 0, minute: 0),
                    resetText: "Resets Thu 12:00 AM"
                ),
                UsageQuota(
                    percentRemaining: 58,
                    quotaType: .modelSpecific("opus"),
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: DemoUsageProbe.nextWeekday(5, hour: 0, minute: 0),
                    resetText: "Resets Thu 12:00 AM"
                ),
                UsageQuota(
                    percentRemaining: 38,
                    quotaType: .modelSpecific("fable"),
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: DemoUsageProbe.nextWeekday(5, hour: 0, minute: 0),
                    resetText: "Resets Thu 12:00 AM"
                ),
            ],
            capturedAt: Date(),
            accountEmail: "jean@example.com",
            accountOrganization: "Anthropic",
            loginMethod: "Claude CLI",
            accountTier: .custom("MAX")
        )
    )

    static let codex = DemoUsageProbe(
        snapshot: UsageSnapshot(
            providerId: ProviderIdentity.codex.rawValue,
            quotas: [
                UsageQuota(
                    percentRemaining: 79,
                    quotaType: .session,
                    providerId: ProviderIdentity.codex.rawValue,
                    resetsAt: Date().addingTimeInterval(3 * 3600 + 12 * 60)
                ),
                UsageQuota(
                    percentRemaining: 64,
                    quotaType: .weekly,
                    providerId: ProviderIdentity.codex.rawValue,
                    resetsAt: DemoUsageProbe.nextWeekday(1, hour: 0, minute: 0)
                ),
            ],
            capturedAt: Date(),
            accountEmail: "jean@openai.com",
            loginMethod: "ChatGPT",
            accountTier: .custom("Pro")
        )
    )

    static func generic(id: String, remaining: Double) -> DemoUsageProbe {
        DemoUsageProbe(
            snapshot: UsageSnapshot(
                providerId: id,
                quotas: [
                    UsageQuota(
                        percentRemaining: remaining,
                        quotaType: .session,
                        providerId: id,
                        resetsAt: Date().addingTimeInterval(2 * 3600)
                    ),
                ],
                capturedAt: Date()
            )
        )
    }

    static let cursor = DemoUsageProbe(
        snapshot: UsageSnapshot(
            providerId: ProviderIdentity.cursor.rawValue,
            quotas: [
                UsageQuota(
                    percentRemaining: 75,
                    quotaType: CursorQuotaPool.models,
                    providerId: ProviderIdentity.cursor.rawValue,
                    resetsAt: DemoUsageProbe.nextMonthStart()
                ),
                UsageQuota(
                    percentRemaining: 9,
                    quotaType: CursorQuotaPool.other,
                    providerId: ProviderIdentity.cursor.rawValue,
                    resetsAt: DemoUsageProbe.nextMonthStart()
                ),
            ],
            capturedAt: Date(),
            accountEmail: "jean@cursor.com",
            loginMethod: "Cursor app",
            accountTier: .custom("ULTRA")
        )
    )

    private static func nextWeekday(_ weekday: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(86_400)
    }

    private static func nextMonthStart() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.date(byAdding: .month, value: 1, to: start) ?? now
    }
}
