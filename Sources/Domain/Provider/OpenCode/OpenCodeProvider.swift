import Foundation
import Observation

/// OpenCode Go — monitors rolling (5h), weekly, and monthly usage via the
/// opencode.ai usage API, falling back to the local opencode DB when no API key is configured.
@MainActor
@Observable
public final class OpenCodeProvider: AIProvider {
    // MARK: - Identity

    public let id: String = ProviderIdentity.openCode.rawValue
    public let name: String = ProviderIdentity.openCode.displayName
    public let cliCommand: String = "opencode"

    public var dashboardURL: URL? {
        URL(string: "https://opencode.ai/auth")
    }

    public var statusPageURL: URL? {
        nil
    }

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Internal

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
    }

    // MARK: - AIProvider

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
