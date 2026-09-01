import Foundation

/// Constants for hook configuration
public enum HookConstants {
    /// Use an ephemeral loopback port by default to avoid a predictable listener.
    public static let defaultPort: UInt16 = 0
}

/// Settings repository for hook configuration.
/// Standalone protocol (not extending ProviderSettingsRepository) since hooks aren't a provider.
public protocol HookSettingsRepository: Sendable {
    /// Whether hooks are enabled
    func isHookEnabled() -> Bool

    /// Sets whether hooks are enabled
    func setHookEnabled(_ enabled: Bool)

    /// The port number for the hook HTTP server (0 = auto-assign)
    func hookPort() -> Int

    /// Sets the port number for the hook HTTP server
    func setHookPort(_ port: Int)
}
