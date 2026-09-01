import Domain
import Foundation

extension ClaudeUsageProbe {
    // MARK: - Account Type Detection

    /// Detects the account tier from the /usage header line.
    /// Format: "Opus 4.5 · Claude Max · email@example.com's Organization"
    /// or "Opus 4.5 · Claude Pro · email@example.com's Organization"
    internal func detectAccountType(_ text: String) -> AccountTier {
        let lower = text.lowercased()
        AppLog.probes.debug("Detecting account tier from /usage output...")

        // Check for Claude Pro in header (e.g., "Opus 4.5 · Claude Pro")
        if lower.contains("· claude pro") || lower.contains("·claude pro") {
            AppLog.probes.info("Detected Claude Pro account from header")
            return .claudePro
        }

        // Check for Claude Max in header (e.g., "Opus 4.5 · Claude Max")
        if lower.contains("· claude max") || lower.contains("·claude max") {
            AppLog.probes.info("Detected Claude Max account from header")
            return .claudeMax
        }

        // Pay-as-you-go API accounts are detected by extractUsageError() via the
        // "/usage is only available for subscription plans" message — not here.
        // The "API Usage Billing" header substring is NOT a reliable classifier on its
        // own: subscription accounts with Extra Usage credits show the same substring
        // alongside valid quota bars. We classify only by Pro/Max header and quota
        // presence, defaulting to .claudeMax for any subscription-like output.

        // Fallback: Check for presence of quota data (subscription accounts have quotas)
        let hasSessionQuota = lower.contains("current session") && (lower.contains("% left") || lower.contains("% used"))
        if hasSessionQuota {
            AppLog.probes.info("Detected subscription account from quota data, defaulting to Max")
            return .claudeMax
        }

        // Default to Max if we can't determine
        AppLog.probes.warning("Could not determine account tier, defaulting to Max")
        return .claudeMax
    }

    // MARK: - Extra Usage Parsing

    /// Extracts Extra usage information from Pro accounts.
    /// Format: "Extra usage\n█████ 27% used\n$5.41 / $20.00 spent · Resets Jan 1, 2026"
    internal func extractExtraUsage(_ text: String) -> CostUsage? {
        let lines = text.components(separatedBy: .newlines)
        let lower = text.lowercased()

        // Check if Extra usage section exists
        guard lower.contains("extra usage") else {
            return nil
        }

        // Check if Extra usage is not enabled
        if lower.contains("extra usage not enabled") {
            AppLog.probes.debug("Extra usage not enabled for this account")
            return nil
        }

        // Find the Extra usage section
        var extraUsageIndex: Int?
        for (idx, line) in lines.enumerated() where line.lowercased().contains("extra usage") {
            extraUsageIndex = idx
            break
        }

        guard let startIndex = extraUsageIndex else {
            return nil
        }

        // Look for cost pattern in subsequent lines: "$5.41 / $20.00 spent"
        let window = lines.dropFirst(startIndex).prefix(10)
        for line in window {
            if let costInfo = parseExtraUsageCostLine(line) {
                let resetText = extractReset(labelSubstring: "Extra usage", text: text)
                let resetDate = parseResetDate(resetText)

                return CostUsage(
                    totalCost: costInfo.spent,
                    budget: costInfo.budget,
                    apiDuration: 0,
                    providerId: ProviderIdentity.claude.rawValue,
                    kind: .extraUsage,
                    capturedAt: Date(),
                    resetsAt: resetDate,
                    resetText: cleanResetText(resetText)
                )
            }
        }

        return nil
    }

    /// Parses a cost line like "$5.41 / $20.00 spent" and returns (spent, budget)
    internal func parseExtraUsageCostLine(_ line: String) -> (spent: Decimal, budget: Decimal)? {
        // Pattern: "$5.41 / $20.00 spent" or "5.41 / 20.00 spent"
        let pattern = #"\$?([\d,]+\.?\d*)\s*/\s*\$?([\d,]+\.?\d*)\s*spent"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let spentRange = Range(match.range(at: 1), in: line),
              let budgetRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let spentStr = String(line[spentRange]).replacingOccurrences(of: ",", with: "")
        let budgetStr = String(line[budgetRange]).replacingOccurrences(of: ",", with: "")

        guard let spent = Decimal(string: spentStr),
              let budget = Decimal(string: budgetStr) else {
            return nil
        }

        return (spent, budget)
    }

}
