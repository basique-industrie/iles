import Foundation

/// An AIProvider backed by an extension manifest and script-based probes.
/// Each section has its own probe; refresh runs all probes and merges results.
@MainActor
@Observable
public final class ExtensionProvider: AIProvider {
    // MARK: - Identity

    public let id: String
    public let name: String
    public let cliCommand: String = ""
    public let dashboardURL: URL?
    public let statusPageURL: URL?

    /// The parsed extension manifest
    public let manifest: ExtensionManifest
    public let fingerprint: String
    public let scriptCommands: [String]

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Dependencies

    /// Section-keyed probes (section.id → probe)
    private let probes: [String: any UsageProbe]
    private let settingsRepository: ProviderSettingsRepository
    private let trustRepository: any ExtensionTrustRepository

    public var requiresTrust: Bool { !scriptCommands.isEmpty }
    public var isTrusted: Bool {
        !requiresTrust || trustRepository.isTrusted(extensionID: manifest.id, fingerprint: fingerprint)
    }

    // MARK: - Init

    public init(
        manifest: ExtensionManifest,
        probes: [String: any UsageProbe],
        settingsRepository: ProviderSettingsRepository,
        fingerprint: String,
        scriptCommands: [String],
        trustRepository: any ExtensionTrustRepository
    ) {
        self.manifest = manifest
        self.id = "ext-\(manifest.id)"
        self.name = manifest.name
        self.dashboardURL = manifest.dashboardURL
        self.statusPageURL = manifest.statusPageURL
        self.probes = probes
        self.settingsRepository = settingsRepository
        self.fingerprint = fingerprint
        self.scriptCommands = scriptCommands
        self.trustRepository = trustRepository
    }

    // MARK: - AIProvider

    public func isAvailable() async -> Bool {
        guard isTrusted else { return false }
        for probe in probes.values {
            if await probe.isAvailable() {
                return true
            }
        }
        return false
    }

    public func setTrusted(_ trusted: Bool) {
        trustRepository.setTrusted(trusted, extensionID: manifest.id, fingerprint: fingerprint)
        if !trusted {
            snapshot = nil
            lastError = nil
        }
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        // Run all section probes concurrently
        let probeEntries = Array(probes)
        let probeResults = await withTaskGroup(of: (String, UsageSnapshot?, String?).self) { group in
            for (sectionId, probe) in probeEntries {
                group.addTask {
                    do {
                        let snapshot = try await probe.probe()
                        return (sectionId, snapshot, nil)
                    } catch {
                        return (sectionId, nil, error.localizedDescription)
                    }
                }
            }

            var collected: [(String, UsageSnapshot?, String?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        let results = probeResults.compactMap { sectionID, snapshot, _ in
            snapshot.map { (sectionID, $0) }
        }

        guard !results.isEmpty else {
            let error = ProbeError.noData
            lastError = error
            throw error
        }

        let merged = mergeSnapshots(results.map(\.1))
        snapshot = merged
        let failures = probeResults.compactMap { sectionID, _, error in
            error.map { "\(sectionID): \($0)" }
        }
        lastError = failures.isEmpty
            ? nil
            : ProbeError.executionFailed("Some extension sections failed — \(failures.joined(separator: "; "))")
        return merged
    }

    // MARK: - Private

    private func mergeSnapshots(_ snapshots: [UsageSnapshot]) -> UsageSnapshot {
        var allQuotas: [UsageQuota] = []
        var costUsage: CostUsage?
        var dailyReport: DailyUsageReport?
        var metrics: [ExtensionMetric] = []

        for s in snapshots {
            allQuotas.append(contentsOf: s.quotas)
            if let cost = s.costUsage { costUsage = cost }
            if let daily = s.dailyUsageReport { dailyReport = daily }
            if let m = s.extensionMetrics { metrics.append(contentsOf: m) }
        }

        return UsageSnapshot(
            providerId: id,
            quotas: allQuotas,
            capturedAt: Date(),
            costUsage: costUsage,
            dailyUsageReport: dailyReport,
            extensionMetrics: metrics.isEmpty ? nil : metrics
        )
    }
}
