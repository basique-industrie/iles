import Foundation
import Domain

/// Infrastructure adapter that probes the Oh My Pi CLI (`omp`) for usage quotas.
///
/// Oh My Pi is a coding-agent harness that manages OAuth accounts for multiple
/// upstream providers (Anthropic, OpenAI Codex, Z.ai, ...). `omp usage --json`
/// reports the rate-limit windows for every authenticated account:
///
/// ```json
/// {
///   "generatedAt": 1783869272381,
///   "reports": [
///     {
///       "provider": "anthropic",
///       "limits": [
///         {
///           "label": "Claude 5 Hour",
///           "scope": { "provider": "anthropic", "windowId": "5h" },
///           "window": { "id": "5h", "durationMs": 18000000, "resetsAt": 1783885200000 },
///           "amount": { "usedFraction": 0.08, "remainingFraction": 0.92, "unit": "percent" }
///         }
///       ],
///       "metadata": { "email": "user@example.com" }
///     }
///   ]
/// }
/// ```
///
/// Every limit becomes one `UsageQuota` labeled `"<Provider> [Tier] <window>"`
/// (e.g. "Claude 5h", "Codex Spark 7d"), so the card shows the headroom of
/// every account the harness can rotate through.
public struct OmpUsageProbe: UsageProbe {
    static let providerId = "omp"

    private let ompBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        ompBinary: String = "omp",
        timeout: TimeInterval = 30.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.ompBinary = ompBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? SimpleCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(ompBinary) != nil {
            return true
        }
        AppLog.probes.error("Oh My Pi binary '\(ompBinary)' not found in PATH")
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate(ompBinary) != nil else {
            throw ProbeError.cliNotFound(ompBinary)
        }

        AppLog.probes.info("Starting Oh My Pi probe with `omp usage --json`...")

        let result: CLIResult
        do {
            result = try await cliExecutor.execute(
                binary: ompBinary,
                args: ["usage", "--json"],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch let error as ProbeError {
            throw error
        } catch {
            AppLog.probes.error("Oh My Pi probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            // Never surface raw CLI output: usage output carries account
            // emails/ids, and this message reaches the UI via `lastError`.
            throw ProbeError.executionFailed("omp usage exited with code \(result.exitCode)")
        }

        let snapshot = try Self.parse(result.output)

        AppLog.probes.info("Oh My Pi probe success: \(snapshot.quotas.count) quotas found")

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses `omp usage --json` output into a UsageSnapshot.
    ///
    /// The command prints a single JSON object; stray status lines around it
    /// (or stderr noise appended by the executor) are tolerated by slicing
    /// from the first `{` to the last `}`.
    public static func parse(_ text: String) throws -> UsageSnapshot {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else {
            throw ProbeError.parseFailed("No JSON object in omp usage output")
        }
        return try parseResponse(Data(text[start...end].utf8))
    }

    /// Parses the raw JSON payload into a UsageSnapshot.
    static func parseResponse(_ data: Data) throws -> UsageSnapshot {
        let payload: UsagePayload
        do {
            payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Malformed omp usage JSON: \(error.localizedDescription)")
        }

        // Multiple accounts on the same upstream provider need a discriminator
        // so labels — and therefore persisted quota keys, which the UI also
        // uses as stable identifiers — stay unique.
        var providerReportCounts: [String: Int] = [:]
        for report in payload.reports {
            providerReportCounts[report.provider, default: 0] += 1
        }

        var quotas: [UsageQuota] = []
        var seenLabels: Set<String> = []
        var accountRows: [ExtensionMetric] = []
        var seenRowLabels: Set<String> = []
        var seenGroupTitles: Set<String> = []
        var seenMenuBarTitles: Set<String> = []

        for (index, report) in payload.reports.enumerated() {
            let needsDiscriminator = providerReportCounts[report.provider, default: 0] > 1
            let discriminator = needsDiscriminator
                ? (report.accountDiscriminator ?? "#\(index + 1)")
                : nil

            // Two meters can share one window on the same account (e.g. Z.ai
            // token and request quotas, both "5h") — qualify those with the
            // metered unit instead of degrading to a bare ordinal.
            let windowGroupCounts = Dictionary(grouping: report.limits, by: \.windowGroupKey)
                .mapValues(\.count)

            let quotaCountBefore = quotas.count
            let accountRowCountBefore = accountRows.count

            let providerName = Self.upstreamDisplayName(report.provider)
            let group = discriminator.map { "\(providerName) · \($0)" } ?? providerName

            for limit in report.limits {
                if let dollarUsed = limit.uncappedMonetaryUsed {
                    accountRows.append(Self.uncappedSpendRow(
                        upstreamProvider: report.provider,
                        limit: limit,
                        dollarUsed: dollarUsed,
                        discriminator: discriminator,
                        group: group,
                        seenLabels: &seenRowLabels
                    ))
                    continue
                }

                let monetaryAmounts = limit.cappedMonetaryAmounts
                if limit.isMonetary, monetaryAmounts == nil {
                    continue
                }
                guard let percentRemaining = limit.percentRemaining else { continue }

                let needsMeter = windowGroupCounts[limit.windowGroupKey, default: 0] > 1
                let meter = needsMeter ? limit.meterName : nil
                var label = Self.quotaLabel(
                    upstreamProvider: report.provider,
                    limit: limit,
                    meter: meter,
                    discriminator: discriminator
                )
                // Final guard: whatever slips through still gets a unique key.
                if seenLabels.contains(label) {
                    var suffix = 2
                    while seenLabels.contains("\(label) (\(suffix))") { suffix += 1 }
                    label = "\(label) (\(suffix))"
                }
                seenLabels.insert(label)

                quotas.append(
                    UsageQuota(
                        percentRemaining: percentRemaining,
                        quotaType: .timeLimit(label),
                        providerId: providerId,
                        resetsAt: limit.resetDate,
                        windowDuration: limit.windowDurationSeconds,
                        dollarUsed: monetaryAmounts?.used,
                        dollarCap: monetaryAmounts?.cap,
                        group: group,
                        compactTitle: Self.compactTitle(limit: limit, meter: meter, providerName: providerName),
                        menuBarTitle: Self.menuBarTitle(label: label, discriminator: discriminator)
                            .map { Self.uniqueLabel($0, seen: &seenMenuBarTitles) }
                    )
                )
            }

            if quotas.count > quotaCountBefore || accountRows.count > accountRowCountBefore {
                // Reserve the emitted quota-group title so a later note
                // section can never silently collide with it.
                seenGroupTitles.insert(group)
            } else {
                // Some providers deliberately report zero limits (e.g. Ollama
                // has no standalone quota API) — a report exists, so the
                // account is absent from `accountsWithoutUsage`. Still list it.
                let identity = report.identityLabel ?? discriminator ?? "account \(index + 1)"
                accountRows.append(Self.accountRow(
                    label: Self.uniqueLabel(
                        "\(providerName) · \(identity)",
                        seen: &seenRowLabels
                    ),
                    group: Self.uniqueLabel(
                        "\(providerName) · \(Self.shortIdentity(identity))",
                        seen: &seenGroupTitles
                    )
                ))
            }
        }

        // Credentials the harness holds for usage-capable providers that
        // produced no attributable report (expired session, fetch failure).
        // Surface genuinely unmatched credentials as explicit
        // "No usage reported" rows — never as fake quotas.
        var emittedUnreportedAccounts: [UnreportedAccount] = []
        for account in payload.accountsWithoutUsage ?? [] {
            let matchesReport = payload.reports.contains { report in
                Self.emailOrAccountIdMatch(
                    provider: account.provider,
                    email: account.email,
                    accountId: account.accountId,
                    orgId: account.orgId,
                    otherProvider: report.provider,
                    otherEmail: report.metadata?.email,
                    otherAccountId: report.matchableAccountId
                )
            }
            let duplicatesRow = emittedUnreportedAccounts.contains { emitted in
                guard !Self.hasOrganization(emitted.orgId) else { return false }
                return Self.emailOrAccountIdMatch(
                    provider: account.provider,
                    email: account.email,
                    accountId: account.accountId,
                    orgId: account.orgId,
                    otherProvider: emitted.provider,
                    otherEmail: emitted.email,
                    otherAccountId: emitted.accountId
                )
            }
            guard !matchesReport, !duplicatesRow else { continue }

            emittedUnreportedAccounts.append(account)
            let providerName = Self.upstreamDisplayName(account.provider)
            accountRows.append(Self.accountRow(
                label: Self.uniqueLabel(
                    "\(providerName) · \(account.identityLabel)",
                    seen: &seenRowLabels
                ),
                group: Self.uniqueLabel(
                    "\(providerName) · \(Self.shortIdentity(account.identityLabel))",
                    seen: &seenGroupTitles
                )
            ))
        }
        guard !quotas.isEmpty || !accountRows.isEmpty else {
            throw ProbeError.noData
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: Self.singleDistinctEmail(in: payload),
            extensionMetrics: accountRows.isEmpty ? nil : accountRows
        )
    }

    /// Provider-scoped identity match for defensively omitting only org-less
    /// stale credential rows. Org-scoped credentials represent distinct limit
    /// pools and remain visible even when an email or account id matches.
    /// For org-less rows, normalized email is authoritative when both sides
    /// have one; exact account id is the fallback when either email is absent.
    private static func emailOrAccountIdMatch(
        provider: String,
        email: String?,
        accountId: String?,
        orgId: String?,
        otherProvider: String,
        otherEmail: String?,
        otherAccountId: String?
    ) -> Bool {
        guard provider == otherProvider else { return false }
        guard !Self.hasOrganization(orgId) else { return false }

        if let email = Self.normalizedEmail(email),
           let otherEmail = Self.normalizedEmail(otherEmail) {
            return email == otherEmail
        }

        guard let accountId, !accountId.isEmpty,
              let otherAccountId, !otherAccountId.isEmpty else {
            return false
        }
        return accountId == otherAccountId
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func hasOrganization(_ orgId: String?) -> Bool {
        guard let orgId else { return false }
        return !orgId.isEmpty
    }

    /// Returns `label`, suffixed if needed so it is unique within `seen`.
    /// Row labels double as UI list identifiers and must never collide.
    private static func uniqueLabel(_ base: String, seen: inout Set<String>) -> String {
        var label = base
        if seen.contains(label) {
            var suffix = 2
            while seen.contains("\(label) (\(suffix))") { suffix += 1 }
            label = "\(label) (\(suffix))"
        }
        seen.insert(label)
        return label
    }

    /// A display row for an account that has no usable quota data; `group`
    /// places it under its own account section in grouped rendering.
    private static func accountRow(label: String, group: String) -> ExtensionMetric {
        ExtensionMetric(
            label: label,
            value: "No usage reported",
            unit: "",
            icon: "person.crop.circle.badge.questionmark",
            group: group
        )
    }

    /// A note row for an uncapped monetary meter. It intentionally does not
    /// fabricate a percentage-based quota.
    private static func uncappedSpendRow(
        upstreamProvider: String,
        limit: UsageLimit,
        dollarUsed: Decimal,
        discriminator: String?,
        group: String,
        seenLabels: inout Set<String>
    ) -> ExtensionMetric {
        var labelParts = [upstreamDisplayName(upstreamProvider), limit.labelToken, "Usage"]
        if let discriminator, !discriminator.isEmpty {
            labelParts.append("· \(discriminator)")
        }

        return ExtensionMetric(
            label: uniqueLabel(labelParts.joined(separator: " "), seen: &seenLabels),
            value: "\(limit.labelToken) usage \(formatMoney(dollarUsed)) spent · no cap",
            unit: "",
            icon: "dollarsign.circle",
            group: group
        )
    }

    private static func formatMoney(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "$\(value)"
    }

    /// Shortens an account identity for section headers: the email local
    /// part, or a prefix of opaque ids — mirroring quota discriminators.
    static func shortIdentity(_ identity: String) -> String {
        let localPart = identity.split(separator: "@").first ?? Substring(identity)
        if localPart.count < identity.count {
            return String(localPart.prefix(16))
        }
        return String(identity.prefix(16))
    }

    // MARK: - Label Building

    /// Builds a compact, unique quota label like "Claude 5h" or "Codex Spark 7d".
    /// Labels are purely presentational; pace math gets its window length
    /// from the payload's `window.durationMs` (see `UsageQuota.windowDuration`).
    static func quotaLabel(
        upstreamProvider: String,
        limit: UsageLimit,
        meter: String?,
        discriminator: String?
    ) -> String {
        var parts: [String] = [Self.upstreamDisplayName(upstreamProvider)]
        if let tier = limit.scope?.tier, !tier.isEmpty {
            parts.append(tier.capitalized)
        }
        if let meter, !meter.isEmpty {
            parts.append(meter)
        }
        parts.append(limit.labelToken)
        if let discriminator, !discriminator.isEmpty {
            parts.append("· \(discriminator)")
        }
        return parts.joined(separator: " ")
    }

    /// Builds the short in-section card title (e.g. "5h", "Spark 7d",
    /// "Tokens 5h") — the provider/account context lives in the section
    /// header (`UsageQuota.group`), so it is not repeated per card.
    /// Purely presentational: quota labels and persisted quota keys keep
    /// the raw window token (see `UsageQuota.compactTitle`).
    static func compactTitle(limit: UsageLimit, meter: String?, providerName: String) -> String {
        var parts: [String] = []
        if let tier = limit.scope?.tier, !tier.isEmpty {
            parts.append(tier.capitalized)
        }
        // Monetary rows keep their spend-oriented `labelToken` contract
        // ("Extra", "Monthly", "Spend") — window humanization only applies
        // to window/rate meters.
        if limit.isMonetary {
            if let meter, !meter.isEmpty {
                parts.append(meter)
            }
            parts.append(limit.labelToken)
            return parts.joined(separator: " ")
        }
        let display = limit.displayWindowToken(providerName: providerName)
        // A label-derived token already names the metered resource
        // ("Premium Requests"); prefixing the meter would duplicate it.
        if let meter, !meter.isEmpty, !display.selfDescribing {
            parts.append(meter)
        }
        parts.append(display.token)
        return parts.joined(separator: " ")
    }

    /// Menu-bar variant of a quota label: identical text with a long account
    /// discriminator truncated to a short prefix plus an ellipsis
    /// ("Claude 7d · jkjk987654321012" → "Claude 7d · jkjk987…"). The menu
    /// bar renders the whole label as a window prefix, and a 16-character
    /// token wastes most of its width. Returns nil when the label carries no
    /// discriminator or it is already short enough — the menu bar then falls
    /// back to the full label. Distinct discriminators can share a condensed
    /// prefix without tripping the full-label "(2)" guard, so callers must
    /// uniquify the result (`uniqueLabel`) before display. Purely
    /// presentational: quota labels and persisted quota keys keep the full
    /// discriminator.
    static func menuBarTitle(label: String, discriminator: String?) -> String? {
        guard let discriminator, !discriminator.isEmpty else { return nil }
        let condensed = condensedDiscriminator(discriminator)
        guard condensed != discriminator else { return nil }
        return label.replacingOccurrences(of: "· \(discriminator)", with: "· \(condensed)")
    }

    /// Truncates a quota-label discriminator for menu bar display: tokens
    /// longer than 8 characters keep their first 7 plus an ellipsis. The
    /// 8-character budget already covers every opaque-id discriminator
    /// (`accountDiscriminator` caps those at 8), so only long email local
    /// parts get shortened.
    static func condensedDiscriminator(_ discriminator: String) -> String {
        guard discriminator.count > 8 else { return discriminator }
        return "\(discriminator.prefix(7))…"
    }

    /// Maps Oh My Pi upstream provider ids to short display names.
    /// The cases cover every id omp v16.4.6's usage registry emits
    /// (`@oh-my-pi/pi-ai/src/usage/*`); unknown ids are title-cased.
    static func upstreamDisplayName(_ id: String) -> String {
        switch id {
        case "anthropic": return ProviderIdentity.claude.displayName
        case "openai-codex": return ProviderIdentity.codex.displayName
        case ProviderIdentity.zai.rawValue: return ProviderIdentity.zai.displayName
        case "google-gemini-cli": return ProviderIdentity.gemini.displayName
        case "google-antigravity": return ProviderIdentity.antigravity.displayName
        case "github-copilot": return ProviderIdentity.copilot.displayName
        case "kimi-code": return ProviderIdentity.kimi.displayName
        case "minimax-code": return ProviderIdentity.minimax.displayName
        case "minimax-code-cn": return "MiniMax CN"
        case ProviderIdentity.openCode.rawValue: return ProviderIdentity.openCode.displayName
        default:
            // Title-case unknown ids: "some-provider" → "Some Provider"
            return id.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// The single distinct account email across all reports and unreported
    /// accounts, or nil when the harness spans several (no one email would
    /// be truthful).
    private static func singleDistinctEmail(in payload: UsagePayload) -> String? {
        var emails = Set(payload.reports.compactMap { $0.metadata?.email })
        emails.formUnion((payload.accountsWithoutUsage ?? []).compactMap(\.email))
        return emails.count == 1 ? emails.first : nil
    }

}
