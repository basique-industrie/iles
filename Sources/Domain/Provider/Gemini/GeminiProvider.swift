import Foundation
import Observation

/// Gemini AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
@MainActor
@Observable
public final class GeminiProvider: AIProvider {
    // MARK: - Identity

    public let id: String = ProviderIdentity.gemini.rawValue
    public let name: String = ProviderIdentity.gemini.displayName
    public let cliCommand: String = "gemini"

    public var dashboardURL: URL? {
        URL(string: "https://aistudio.google.com")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.cloud.google.com")
    }
    // MARK: - State (Observable)

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Internal

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    // MARK: - Initialization

    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

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
