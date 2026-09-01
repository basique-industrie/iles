import Foundation
import Observation

/// DeepSeek AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
@MainActor
@Observable
public final class DeepSeekProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = ProviderIdentity.deepseek.rawValue
    public let name: String = ProviderIdentity.deepseek.displayName
    public let cliCommand: String = "" // API-only provider, no CLI

    public var dashboardURL: URL? {
        URL(string: "https://platform.deepseek.com/usage")
    }

    public var statusPageURL: URL? {
        nil
    }
    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable)
    public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh
    public private(set) var lastError: Error?

    // MARK: - Internal

    /// The probe used to fetch usage data
    private let probe: any UsageProbe
    private let settingsRepository: any DeepSeekSettingsRepository

    // MARK: - Initialization

    /// Creates a DeepSeek provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any DeepSeekSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }
}
