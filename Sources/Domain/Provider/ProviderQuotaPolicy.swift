/// Brand rules for which quota is primary, secondary, and shown on hover.
///
/// Lives in Domain so Settings, the island, and probes share one policy
/// instead of repeating Claude/Codex/Cursor switches in the UI.
public enum ProviderQuotaPolicy: Sendable {
    public static let claudeHoverModels: [QuotaType] = [
        .modelSpecific("opus"),
        .modelSpecific("sonnet"),
        .modelSpecific("fable"),
    ]

    public static func curatedTypes(providerId: String) -> [QuotaType] {
        switch ProviderIdentity(rawValue: providerId) {
        case .claude, .codex:
            [.session, .weekly]
        case .cursor:
            [CursorQuotaPool.models, CursorQuotaPool.other]
        default:
            []
        }
    }

    public static func primaryQuota(providerId: String, in snapshot: UsageSnapshot?) -> UsageQuota? {
        guard let snapshot else { return nil }
        switch ProviderIdentity(rawValue: providerId) {
        case .claude, .codex:
            return snapshot.sessionQuota ?? snapshot.quotas.first
        case .cursor:
            return snapshot.quota(for: CursorQuotaPool.models)
                ?? snapshot.quota(for: CursorQuotaPool.monthly)
                ?? snapshot.quotas.first
        default:
            return snapshot.quotas.first
        }
    }

    public static func secondaryQuota(providerId: String, in snapshot: UsageSnapshot?) -> UsageQuota? {
        guard let snapshot else { return nil }
        switch ProviderIdentity(rawValue: providerId) {
        case .claude, .codex:
            return snapshot.weeklyQuota
        case .cursor:
            return snapshot.quota(for: CursorQuotaPool.other)
                ?? snapshot.quota(for: CursorQuotaPool.onDemand)
                ?? snapshot.quotas.dropFirst().first
        default:
            return snapshot.quotas.dropFirst().first
        }
    }

    /// Hover card windows. Claude is session, weekly, then the model cap.
    /// Other providers are the selected ring plus the other brand window.
    public static func hoverQuotas(
        providerId: String,
        in snapshot: UsageSnapshot,
        ring: UsageQuota?
    ) -> [UsageQuota] {
        if ProviderIdentity(rawValue: providerId) == .claude {
            return claudeHoverQuotas(in: snapshot)
        }
        var rows: [UsageQuota] = []
        if let ring {
            rows.append(ring)
        }
        for candidate in [
            primaryQuota(providerId: providerId, in: snapshot),
            secondaryQuota(providerId: providerId, in: snapshot),
        ].compactMap({ $0 }) {
            if candidate.quotaType != ring?.quotaType {
                rows.append(candidate)
            }
            if rows.count == 2 {
                break
            }
        }
        return rows
    }

    public static func showsHoverExtraUsage(providerId: String) -> Bool {
        ProviderIdentity(rawValue: providerId) == .claude
    }

    private static func claudeHoverQuotas(in snapshot: UsageSnapshot) -> [UsageQuota] {
        var rows: [UsageQuota] = []
        if let session = snapshot.sessionQuota {
            rows.append(session)
        }
        if let weekly = snapshot.weeklyQuota {
            rows.append(weekly)
        }
        if let model = claudeHoverModels.compactMap({ snapshot.quota(for: $0) }).first
            ?? snapshot.modelSpecificQuotas.first {
            rows.append(model)
        }
        return rows
    }
}
