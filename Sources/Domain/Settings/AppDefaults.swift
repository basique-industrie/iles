/// First-launch values shared by settings storage and the island.
public enum AppDefaults: Sendable {
    public static let defaultProviderIdentities: [ProviderIdentity] = [.claude, .codex, .cursor]
    public static let defaultProviderSourceIDs = defaultProviderIdentities.map(\.rawValue)
}
