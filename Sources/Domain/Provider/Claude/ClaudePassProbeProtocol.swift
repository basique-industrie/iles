import Foundation

/// Protocol for probing Claude guest pass information.
/// Allows for dependency injection and testing.
public protocol ClaudePassProbing: Sendable {
    /// Checks if the pass probe is available
    func isAvailable() async -> Bool

    /// Probes for guest pass information
    func probe() async throws -> ClaudePass
}
