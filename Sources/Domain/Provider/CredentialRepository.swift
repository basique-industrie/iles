import Foundation

/// Protocol for storing and retrieving credentials.
/// The app uses Keychain; tests can inject an in-memory implementation.
public protocol CredentialRepository: Sendable {
    /// Saves a credential value for the given key.
    func save(_ value: String, forKey key: String)

    /// Retrieves a credential value for the given key.
    func get(forKey key: String) -> String?

    /// Deletes the credential for the given key.
    /// - Returns: `true` when the credential is absent after the operation.
    @discardableResult
    func delete(forKey key: String) -> Bool

    /// Checks if a credential exists for the given key.
    func exists(forKey key: String) -> Bool
}

/// Well-known credential keys
public enum CredentialKey {
    public static let githubToken = "github-copilot-token"
    public static let alibabaApiKey = "alibaba-api-key"
    public static let alibabaManualCookie = "alibaba-manual-cookie"
    public static let deepSeekApiKey = "deepseek-api-key"
    public static let kimiAuthToken = "kimi-auth-token"
    public static let miniMaxApiKey = "minimax-api-key"
    public static let vercelApiKey = "vercel-ai-gateway-api-key"
}
