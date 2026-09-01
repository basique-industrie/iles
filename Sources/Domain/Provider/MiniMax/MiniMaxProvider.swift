import Foundation
import Observation

/// MiniMax AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
@MainActor
@Observable
public final class MiniMaxProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = ProviderIdentity.minimax.rawValue
    public let name: String = ProviderIdentity.minimax.displayName
    public let cliCommand: String = "" // API-only provider, no CLI (纯 API 提供者，无 CLI)

    public var dashboardURL: URL? {
        settingsRepository.minimaxRegion().dashboardURL
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
    private let settingsRepository: any MiniMaxSettingsRepository

    // MARK: - Initialization

    /// Creates a MiniMax provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any MiniMaxSettingsRepository) {
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
