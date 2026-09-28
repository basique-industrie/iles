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

    static let harnais = DemoUsageProbe(
        snapshot: UsageSnapshot(
            providerId: ProviderIdentity.harnais.rawValue,
            quotas: [
                UsageQuota(
                    percentRemaining: 62,
                    quotaType: .timeLimit("Claude · work 5h"),
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: Date().addingTimeInterval(2 * 3600),
                    resetText: "Resets in 2h",
                    group: "Claude · Work",
                    compactTitle: "5h",
                    menuBarTitle: "Claude 5h"
                ),
                UsageQuota(
                    percentRemaining: 81,
                    quotaType: .timeLimit("Claude · work 7d"),
                    providerId: ProviderIdentity.claude.rawValue,
                    resetsAt: Date().addingTimeInterval(4 * 86_400),
                    resetText: "Resets in 4d",
                    group: "Claude · Work",
                    compactTitle: "7d",
                    menuBarTitle: "Claude 7d"
                ),
                UsageQuota(
                    percentRemaining: 44,
                    quotaType: .timeLimit("Codex · personal 5h"),
                    providerId: ProviderIdentity.codex.rawValue,
                    resetsAt: Date().addingTimeInterval(90 * 60),
                    resetText: "Resets in 90m",
                    group: "Codex · Personal",
                    compactTitle: "5h",
                    menuBarTitle: "Codex 5h"
                ),
                UsageQuota(
                    percentRemaining: 70,
                    quotaType: .timeLimit("Codex · personal 7d"),
                    providerId: ProviderIdentity.codex.rawValue,
                    resetsAt: Date().addingTimeInterval(5 * 86_400),
                    resetText: "Resets in 5d",
                    group: "Codex · Personal",
                    compactTitle: "7d",
                    menuBarTitle: "Codex 7d"
                ),
                UsageQuota(
                    percentRemaining: 65,
                    quotaType: .timeLimit("Cursor · Default Models"),
                    providerId: ProviderIdentity.cursor.rawValue,
                    resetsAt: Date().addingTimeInterval(12 * 86_400),
                    resetText: "Resets in 12d",
                    group: "Cursor · Default",
                    compactTitle: "Models",
                    menuBarTitle: "Cursor Models"
                ),
            ],
            capturedAt: Date(),
            loginMethod: "Harnais"
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
