import Foundation
import Observation

/// Codex AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: RPC (default) and API.
@MainActor
@Observable
public final class CodexProvider: AIProvider {
    // MARK: - Identity

    public let id: String = ProviderIdentity.codex.rawValue
    public let name: String = ProviderIdentity.codex.displayName
    public let cliCommand: String = "codex"

    public var dashboardURL: URL? {
        URL(string: "https://platform.openai.com/usage")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.openai.com")
    }
    // MARK: - State (Observable)

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Probe Mode

    /// The current probe mode (RPC or API)
    public var probeMode: CodexProbeMode {
        get {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                return codexSettings.codexProbeMode()
            }
            return .rpc
        }
        set {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                codexSettings.setCodexProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The RPC probe for fetching usage data via `codex app-server`
    private let rpcProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .rpc:
            return rpcProbe
        case .api:
            // Fall back to RPC if API probe not available
            return apiProbe ?? rpcProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Codex provider with an RPC probe and an optional API probe.
    /// - Parameters:
    ///   - rpcProbe: The RPC probe for fetching usage via `codex app-server`
    ///   - apiProbe: The optional API probe for fetching usage via HTTP API
    ///   - settingsRepository: The repository for persisting settings
    public init(
        rpcProbe: any UsageProbe,
        apiProbe: (any UsageProbe)? = nil,
        settingsRepository: any CodexSettingsRepository
    ) {
        self.rpcProbe = rpcProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await activeProbe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }

    /// Whether API mode is available (API probe was provided)
    public var supportsApiMode: Bool {
        apiProbe != nil
    }
}
