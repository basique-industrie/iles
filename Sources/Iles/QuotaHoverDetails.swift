import Domain
import Foundation

/// Keeps account credits and window dates scoped to the readings in this hover.
struct QuotaHoverDetails {
    struct Bank: Identifiable {
        let id: String
        let title: String?
        let credits: ResetCredits

        var caption: String {
            credits.availableCount == 1 ? "1 banked reset" : "\(credits.availableCount) banked resets"
        }

        func expiryCaption(now: Date = Date()) -> String? {
            guard credits.availableCount > 0 else { return nil }
            guard let date = credits.nextExpiresAt else { return "Expiry not reported" }
            let prefix = date > now ? "Next expires" : "Expiry reached"
            return "\(prefix) \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    let metricIDs: [String]
    let resetMetricIDs: Set<String>
    let banks: [Bank]

    init(snapshot: SourceSnapshot, selectedIDs: [String], descriptor: ComplicationSourceDescriptor? = nil) {
        let groups = snapshot.focusedQuotaGroups(matching: selectedIDs)
        var seen = Set<String>()
        let ids = (selectedIDs + groups.flatMap(\.metricIDs)).filter { seen.insert($0).inserted }
        metricIDs = ids
        resetMetricIDs = Set(ids.filter { id in
            guard let details = snapshot.quotaResetDetails?[id] else { return false }
            let name = descriptor?.metricName(for: id) ?? id
            guard name.lowercased().hasSuffix("fable"), let date = details.resetsAt else { return true }
            return !ids.contains { otherID in
                guard otherID != id,
                      QuotaWindowKind.inferred(from: descriptor?.metricName(for: otherID) ?? otherID) == .weekly,
                      let other = snapshot.quotaResetDetails?[otherID], let otherDate = other.resetsAt,
                      abs(date.timeIntervalSince(otherDate)) <= 60
                else { return false }
                if let accountID = details.accountID { return accountID == other.accountID }
                return groups.contains { $0.metricIDs.contains(id) && $0.metricIDs.contains(otherID) }
            }
        })
        var accounts = Set<String>()
        banks = metricIDs.compactMap { id in
            guard let details = snapshot.quotaResetDetails?[id], let credits = details.resetCredits,
                  let accountID = details.accountID, accounts.insert(accountID).inserted
            else { return nil }
            let title = groups.first { $0.metricIDs.contains(id) }?.title
            return Bank(id: accountID, title: UsageQuota.privacySafeTitle(title), credits: credits)
        }
    }

    static func resetCaption(_ details: QuotaResetDetails, now: Date = Date()) -> String {
        if let date = details.resetsAt {
            let interval = date.timeIntervalSince(now)
            guard interval > 0 else { return "Reset due · refresh usage" }
            guard interval >= 60 else { return "Resets in less than a minute" }
            let minutes = Int(ceil(interval / 60))
            let days = minutes / 1_440
            let hours = (minutes % 1_440) / 60
            let remainder = minutes % 60
            let parts = [(days, "d"), (hours, "h"), (remainder, "m")]
                .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
            return "Resets in \(parts.joined(separator: " "))"
        }
        if let text = details.resetText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        return "Reset not reported"
    }
}
