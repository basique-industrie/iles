import Domain
import Foundation

extension ClaudeUsageProbe {
    // MARK: - Parsing

    /// Parses Claude CLI /usage output into a UsageSnapshot (for testing).
    /// Uses a no-op resolver by default so tests don't read real `~/.claude.json`.
    public static func parse(_ text: String, accountInfoResolver: any AccountInfoResolving = NoOpAccountInfoResolver()) throws -> UsageSnapshot {
        let probe = ClaudeUsageProbe(accountInfoResolver: accountInfoResolver)
        return try probe.parseClaudeOutput(text)
    }

    /// Parses Claude CLI /cost output into a UsageSnapshot (for testing)
    public static func parseCost(_ text: String) throws -> UsageSnapshot {
        let probe = ClaudeUsageProbe(accountInfoResolver: NoOpAccountInfoResolver())
        return try probe.parseCostOutput(text)
    }

    /// Parses /cost command output for API Usage Billing accounts.
    /// Format:
    /// ```
    /// Total cost:            $0.55
    /// Total duration (API):  6m 19.7s
    /// Total duration (wall): 6h 33m 10.2s
    /// Total code changes:    0 lines added, 0 lines removed
    /// ```
    internal func parseCostOutput(_ text: String) throws -> UsageSnapshot {
        let clean = renderTerminalOutput(text)

        // Extract total cost: "$0.55" or "0.55"
        guard let cost = extractCostValue(clean) else {
            AppLog.probes.error("Claude /cost parse failed: could not find 'Total cost' in output")
            throw ProbeError.parseFailed("Could not find total cost")
        }

        // Extract API duration in seconds
        let apiDuration = extractApiDuration(clean)

        let costUsage = CostUsage(
            totalCost: cost,
            budget: nil,
            apiDuration: apiDuration,
            providerId: ProviderIdentity.claude.rawValue,
            capturedAt: Date(),
            resetsAt: nil,
            resetText: nil
        )

        return UsageSnapshot(
            providerId: ProviderIdentity.claude.rawValue,
            quotas: [],
            capturedAt: Date(),
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: .claudeApi,
            costUsage: costUsage
        )
    }

    /// Extracts the total cost value from /cost output
    /// Looks for "Total cost:" followed by a dollar amount
    internal func extractCostValue(_ text: String) -> Decimal? {
        // Pattern: "Total cost:" followed by optional whitespace and "$X.XX"
        let pattern = #"total\s+cost:\s*\$?([\d,]+\.?\d*)"#
        guard let match = extractFirst(pattern: pattern, text: text) else {
            return nil
        }
        let cleanValue = match.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleanValue)
    }

    /// Extracts the API duration in seconds from /cost output
    /// Looks for "Total duration (API):" followed by a time string like "6m 19.7s"
    internal func extractApiDuration(_ text: String) -> TimeInterval {
        // Find the API duration line
        let pattern = #"total\s+duration\s*\(api\):\s*(.+?)(?:\n|$)"#
        guard let durationStr = extractFirst(pattern: pattern, text: text) else {
            return 0
        }

        return parseDurationString(durationStr)
    }

    /// Parses a duration string like "6m 19.7s" or "2h 30m 15s" into seconds
    internal func parseDurationString(_ text: String) -> TimeInterval {
        var totalSeconds: TimeInterval = 0

        // Extract hours
        if let hourMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*h"#, options: [.regularExpression, .caseInsensitive]) {
            let hourStr = String(text[hourMatch]).filter { $0.isNumber || $0 == "." }
            if let hours = Double(hourStr) {
                totalSeconds += hours * 3600
            }
        }

        // Extract minutes
        if let minMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*m(?!s)"#, options: [.regularExpression, .caseInsensitive]) {
            let minStr = String(text[minMatch]).filter { $0.isNumber || $0 == "." }
            if let minutes = Double(minStr) {
                totalSeconds += minutes * 60
            }
        }

        // Extract seconds
        if let secMatch = text.range(of: #"(\d+(?:\.\d+)?)\s*s"#, options: [.regularExpression, .caseInsensitive]) {
            let secStr = String(text[secMatch]).filter { $0.isNumber || $0 == "." }
            if let seconds = Double(secStr) {
                totalSeconds += seconds
            }
        }

        return totalSeconds
    }

    func parseClaudeOutput(_ text: String) throws -> UsageSnapshot {
        let clean = renderTerminalOutput(text)

        AppLog.probes.debug("Claude /usage output normalized (\(text.count) input characters, \(clean.count) normalized)")

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Detect account type from header (e.g., "Opus 4.5 · Claude Max" or "Opus 4.5 · Claude Pro")
        let accountTier = detectAccountType(clean)
        // Account info (email, org) comes from ~/.claude.json via resolver
        // CLI /usage tab no longer includes account details since v2.1.79+
        let accountInfo = accountInfoResolver.resolve()

        // Note: pay-as-you-go API accounts are caught earlier by extractUsageError()
        // via the "/usage is only available for subscription plans" message and routed
        // to /cost. detectAccountType() classifies by header/quota only.

        // Extract percentages
        let sessionPct = extractPercent(labelSubstring: "Current session", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Current week (all models)", text: clean)
        // Check for model-specific quota (Opus, Sonnet, or Fable)
        let opusPct = extractPercent(labelSubstring: "Current week (Opus)", text: clean)
        let sonnetPct = extractPercent(labelSubstrings: [
            "Current week (Sonnet only)",
            "Current week (Sonnet)",
        ], text: clean)
        // Paren-open anchor also matches a future "Current week (Fable 5)" label
        let fablePct = extractPercent(labelSubstring: "Current week (Fable", text: clean)

        guard let sessionPct else {
            AppLog.probes.error("Claude parse failed: could not find 'Current session' percentage in output")
            throw ProbeError.parseFailed("Could not find session usage")
        }

        // Extract reset times
        let sessionReset = extractReset(labelSubstring: "Current session", text: clean)
        let weeklyReset = extractReset(labelSubstring: "Current week", text: clean)

        // Build quotas
        var quotas: [UsageQuota] = []

        quotas.append(UsageQuota(
            percentRemaining: Double(sessionPct),
            quotaType: .session,
            providerId: ProviderIdentity.claude.rawValue,
            resetsAt: parseResetDate(sessionReset),
            resetText: cleanResetText(sessionReset)
        ))

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                providerId: ProviderIdentity.claude.rawValue,
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let opusPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(opusPct),
                quotaType: .modelSpecific("opus"),
                providerId: ProviderIdentity.claude.rawValue,
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let sonnetPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(sonnetPct),
                quotaType: .modelSpecific("sonnet"),
                providerId: ProviderIdentity.claude.rawValue,
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let fablePct {
            // Promotional Fable window can reset at a different time than the
            // all-models weekly, so anchor on its own section before falling back.
            // The model key must match what the API probe derives from the scoped
            // limit's display name ("fable").
            let fableReset = extractReset(labelSubstring: "Current week (Fable", text: clean) ?? weeklyReset
            quotas.append(UsageQuota(
                percentRemaining: Double(fablePct),
                quotaType: .modelSpecific("fable"),
                providerId: ProviderIdentity.claude.rawValue,
                resetsAt: parseResetDate(fableReset),
                resetText: cleanResetText(fableReset)
            ))
        }

        // Extract Extra usage for Pro accounts (if enabled)
        let extraUsage = extractExtraUsage(clean)

        return UsageSnapshot(
            providerId: ProviderIdentity.claude.rawValue,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: accountInfo?.email,
            accountOrganization: accountInfo?.organization,
            loginMethod: accountInfo?.loginMethod,
            accountTier: accountTier,
            costUsage: extraUsage
        )
    }

}
