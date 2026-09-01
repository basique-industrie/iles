import Foundation

extension OmpUsageProbe {
    struct UsagePayload: Decodable {
        let reports: [UsageReport]
        let accountsWithoutUsage: [UnreportedAccount]?
    }

    /// A stored credential for a usage-capable provider that produced no
    /// attributable usage report (`accountsWithoutUsage` in the payload).
    struct UnreportedAccount: Decodable {
        let provider: String
        let type: String?
        let email: String?
        let accountId: String?
        let orgId: String?
        let projectId: String?
        let enterpriseUrl: String?

        /// Mirrors `omp usage`'s own labeling of accounts without usage.
        var identityLabel: String {
            if type == "api_key" { return "API key" }
            for value in [email, accountId, projectId, enterpriseUrl] {
                if let value, !value.isEmpty { return value }
            }
            return "OAuth account"
        }
    }

    struct UsageReport: Decodable {
        let provider: String
        let limits: [UsageLimit]
        let metadata: ReportMetadata?

        /// Account identity used for exact matching. Some providers place it
        /// on limit scopes; project ids remain deliberately excluded.
        var matchableAccountId: String? {
            if let accountId = metadata?.accountId, !accountId.isEmpty {
                return accountId
            }
            for limit in limits {
                if let accountId = limit.scope?.accountId, !accountId.isEmpty {
                    return accountId
                }
            }
            return nil
        }

        /// Full identity of this account, mirroring `omp usage`'s own
        /// `reportAccountLabel`: metadata email → accountId → projectId,
        /// then any limit's scoped accountId/projectId (Gemini/Kimi carry
        /// identity in limit scopes rather than metadata).
        var identityLabel: String? {
            for value in [metadata?.email, metadata?.accountId, metadata?.projectId] {
                if let value, !value.isEmpty { return value }
            }
            for limit in limits {
                if let scoped = limit.scope?.accountId ?? limit.scope?.projectId, !scoped.isEmpty {
                    return scoped
                }
            }
            return nil
        }

        /// A short, stable token for quota-label discrimination: the email
        /// local part, or a prefix of whatever identity the report carries.
        var accountDiscriminator: String? {
            guard let identity = identityLabel else { return nil }
            let localPart = identity.split(separator: "@").first ?? Substring(identity)
            if localPart.count < identity.count {
                return String(localPart.prefix(16))
            }
            return String(identity.prefix(8))
        }
    }

    struct ReportMetadata: Decodable {
        let email: String?
        let accountId: String?
        let projectId: String?
        let planType: String?
    }

    struct UsageLimit: Decodable {
        let id: String?
        let label: String?
        let scope: LimitScope?
        let window: LimitWindow?
        let amount: LimitAmount?

        var isMonetary: Bool {
            amount?.unit?.caseInsensitiveCompare("usd") == .orderedSame
        }

        var cappedMonetaryAmounts: (used: Decimal, cap: Decimal)? {
            guard isMonetary,
                  let rawLimit = amount?.limit, rawLimit > 0,
                  let used = amount?.roundedUsed,
                  let cap = amount?.roundedLimit
            else { return nil }
            return (used, cap)
        }

        var uncappedMonetaryUsed: Decimal? {
            guard isMonetary, amount?.limit == nil else { return nil }
            return amount?.roundedUsed
        }

        /// Monetary rows get a spend-oriented token without changing
        /// `windowToken`, which remains the grouping key for all meters.
        var labelToken: String {
            guard isMonetary else { return windowToken }
            let token = scope?.windowId ?? window?.id ?? "spend"
            return token.prefix(1).uppercased() + token.dropFirst()
        }

        /// Percent of this window still remaining, preferring explicit
        /// fractions over derived used/limit math.
        var percentRemaining: Double? {
            if let remaining = amount?.remainingFraction {
                return remaining * 100
            }
            if let used = amount?.usedFraction {
                return (1 - used) * 100
            }
            if let used = amount?.used, let limit = amount?.limit, limit > 0 {
                let fraction = (limit - used) / limit * 100
                return NSDecimalNumber(decimal: fraction).doubleValue
            }
            return nil
        }

        /// When this window resets (epoch milliseconds → Date).
        var resetDate: Date? {
            guard let ms = window?.resetsAt else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }

        /// The window length in seconds, when reported.
        var windowDurationSeconds: TimeInterval? {
            guard let ms = window?.durationMs, ms > 0 else { return nil }
            return ms / 1000
        }

        /// Compact window token like "5h", "7d", "1w", "1mo".
        ///
        /// This raw chain is identity: it feeds quota labels (persisted
        /// quota keys) and meter-qualification grouping, so it is never
        /// humanized — display cleanup lives in `displayWindowToken`.
        var windowToken: String {
            scope?.windowId ?? window?.id ?? window?.label ?? "limit"
        }

        /// Card-title token plus whether it already describes the metered
        /// resource on its own (label-derived tokens do; machine tokens
        /// need the meter prefix when several meters share one window).
        struct DisplayWindowToken {
            let token: String
            let selfDescribing: Bool
        }

        /// Humanized token for the in-section card title.
        ///
        /// Some reporters emit machine window ids next to human labels
        /// (Kimi's 5-hour rate limit arrives as `300time_unit_minute` with
        /// label "5h limit"; its summary row is `default` with label
        /// "Total quota"). Prefer, in order: an already-compact id, a token
        /// derived from the window duration, the limit's own label, the
        /// window label, the raw id. Label-derived tokens drop a leading
        /// provider name (Gemini labels embed it) since the section header
        /// already carries that context. Only the LIMIT's label is
        /// self-describing — a window label ("Monthly") names timing, not
        /// the metered resource, so it keeps the shared-window meter prefix.
        func displayWindowToken(providerName: String) -> DisplayWindowToken {
            let raw = scope?.windowId ?? window?.id
            if let raw, Self.isCompactWindowToken(raw) {
                return DisplayWindowToken(token: raw, selfDescribing: false)
            }
            if let seconds = windowDurationSeconds,
               let derived = Self.compactDurationToken(seconds) {
                return DisplayWindowToken(token: derived, selfDescribing: false)
            }
            if let label, !label.isEmpty {
                return DisplayWindowToken(
                    token: Self.strippingProviderPrefix(label, providerName: providerName),
                    selfDescribing: true
                )
            }
            if let windowLabel = window?.label, !windowLabel.isEmpty {
                return DisplayWindowToken(
                    token: Self.strippingProviderPrefix(windowLabel, providerName: providerName),
                    selfDescribing: false
                )
            }
            return DisplayWindowToken(token: raw ?? "limit", selfDescribing: false)
        }

        /// True for tokens that already read as a compact window ("5h",
        /// "7d", "1mo") and can go on a card verbatim.
        static func isCompactWindowToken(_ token: String) -> Bool {
            token.range(
                of: "^\\d{1,4}(s|m|h|d|w|mo|y)$",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }

        /// Formats a window length as its largest whole unit ("5h", "7d",
        /// "90m"); nil for non-positive lengths and for payload garbage
        /// (non-finite or Int-overflowing durations must degrade to the
        /// label fallback, never trap).
        static func compactDurationToken(_ seconds: TimeInterval) -> String? {
            guard let total = Int(exactly: seconds.rounded()), total > 0 else { return nil }
            if total % 86_400 == 0 { return "\(total / 86_400)d" }
            if total % 3_600 == 0 { return "\(total / 3_600)h" }
            if total % 60 == 0 { return "\(total / 60)m" }
            return "\(total)s"
        }

        /// Drops a leading "<providerName> " from a label-derived token —
        /// the section header already names the provider, and some
        /// reporters (Gemini) embed it in every limit label.
        static func strippingProviderPrefix(_ label: String, providerName: String) -> String {
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > providerName.count + 1,
                  trimmed.lowercased().hasPrefix(providerName.lowercased() + " ")
            else { return trimmed }
            return String(trimmed.dropFirst(providerName.count + 1))
                .trimmingCharacters(in: .whitespaces)
        }

        /// Groups limits that share a (tier, window) on one account, so
        /// multi-meter windows can be told apart in labels.
        var windowGroupKey: String {
            "\(scope?.tier ?? "")|\(windowToken)"
        }

        /// Display name of the metered resource when it isn't the default
        /// percent meter (e.g. "Tokens", "Requests").
        var meterName: String? {
            guard !isMonetary,
                  let unit = amount?.unit, !unit.isEmpty,
                  unit.caseInsensitiveCompare("percent") != .orderedSame
            else { return nil }
            return unit.capitalized
        }
    }

    struct LimitScope: Decodable {
        let provider: String?
        let accountId: String?
        let projectId: String?
        let tier: String?
        let windowId: String?
    }

    struct LimitWindow: Decodable {
        let id: String?
        let label: String?
        let durationMs: Double?
        let resetsAt: Double?
    }

    struct LimitAmount: Decodable {
        /// Monetary fields decode as `Decimal` straight from the JSON number
        /// token, so cent-boundary values like 1.005 never pick up binary
        /// floating-point error before rounding.
        let used: Decimal?
        let limit: Decimal?
        let remaining: Double?
        let usedFraction: Double?
        let remainingFraction: Double?
        let unit: String?

        var roundedUsed: Decimal? {
            Self.roundedMoney(used)
        }

        var roundedLimit: Decimal? {
            Self.roundedMoney(limit)
        }

        private static func roundedMoney(_ value: Decimal?) -> Decimal? {
            guard var decimal = value else { return nil }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &decimal, 2, .plain)
            return rounded
        }
    }
}
