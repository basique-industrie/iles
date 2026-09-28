import Foundation
import Observation

/// Multi-account usage refreshed by Iles through Harnais account probes.
///
/// Iles treats Harnais as one source. Each quota window still carries the
/// upstream Claude, Codex, or Cursor identity so island marks and hover
/// can map onto that account.
@MainActor
@Observable
public final class HarnaisProvider: AIProvider {
    // MARK: - Identity

    public let id: String = ProviderIdentity.harnais.rawValue
    public let name: String = ProviderIdentity.harnais.displayName
    public let cliCommand: String = "harnais"

    public var dashboardURL: URL? { nil }

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Internal

    private let probe: any UsageProbe

    public init(probe: any UsageProbe) {
        self.probe = probe
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
