import Foundation

/// Account-level credits reported by Harnais, separate from scheduled quota resets.
public struct ResetCredits: Codable, Equatable, Hashable, Sendable {
    public let availableCount: Int
    public let nextExpiresAt: Date?

    public init(availableCount: Int, nextExpiresAt: Date? = nil) {
        self.availableCount = max(0, availableCount)
        self.nextExpiresAt = nextExpiresAt
    }
}

/// Metadata keyed by the same metric ID as the displayed reading.
public struct QuotaResetDetails: Codable, Equatable, Sendable {
    public let resetsAt: Date?
    public let resetText: String?
    public let accountID: String?
    public let resetCredits: ResetCredits?

    public init(resetsAt: Date? = nil, resetText: String? = nil,
                accountID: String? = nil, resetCredits: ResetCredits? = nil) {
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.accountID = accountID
        self.resetCredits = resetCredits
    }
}
