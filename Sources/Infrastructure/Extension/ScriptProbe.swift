import Foundation
import Domain

/// A UsageProbe that executes an external script and parses its JSON output.
/// Used by extension providers to probe custom data sources.
public final class ScriptProbe: UsageProbe, @unchecked Sendable {
    private let scriptPath: String
    private let sectionID: String
    private let extensionDir: URL
    private let providerId: String
    private let sectionType: SectionType
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor?
    private let configRepository: (any ExtensionConfigRepository)?
    private let manifest: ExtensionManifest?
    private let fingerprint: String?
    private let trustRepository: (any ExtensionTrustRepository)?
    private static let maximumOutputBytes = 1_048_576

    public init(
        scriptPath: String,
        sectionID: String = "status",
        extensionDir: URL,
        providerId: String,
        sectionType: SectionType,
        timeout: TimeInterval = 10,
        cliExecutor: CLIExecutor? = nil,
        configRepository: (any ExtensionConfigRepository)? = nil,
        manifest: ExtensionManifest? = nil,
        fingerprint: String? = nil,
        trustRepository: (any ExtensionTrustRepository)? = nil
    ) {
        self.scriptPath = scriptPath
        self.sectionID = sectionID
        self.extensionDir = extensionDir
        self.providerId = providerId
        self.sectionType = sectionType
        self.timeout = timeout
        self.cliExecutor = cliExecutor
        self.configRepository = configRepository
        self.manifest = manifest
        self.fingerprint = fingerprint
        self.trustRepository = trustRepository
    }

    public func probe() async throws -> UsageSnapshot {
        if let manifest, let fingerprint, let trustRepository {
            guard let currentFingerprint = ExtensionDirectoryScanner.fingerprint(directory: extensionDir),
                  currentFingerprint == fingerprint,
                  trustRepository.isTrusted(extensionID: manifest.id, fingerprint: currentFingerprint)
            else {
                throw ProbeError.executionFailed(
                    "Extension '\(manifest.name)' changed and must be reviewed before its script can run"
                )
            }
        }
        let resolvedPath = resolveScriptPath()
        guard !resolvedPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            throw ProbeError.executionFailed("Extension probe is missing or is not executable")
        }

        let result: CLIResult
        if let cliExecutor {
            result = try await cliExecutor.execute(
                binary: resolvedPath,
                args: [],
                input: nil,
                timeout: timeout,
                workingDirectory: extensionDir,
                autoResponses: [:]
            )
        } else {
            let output = try await SubprocessSupport.run(
                executablePath: resolvedPath,
                arguments: [],
                environment: executionEnvironment(for: resolvedPath),
                workingDirectory: extensionDir.path,
                outputLimit: Self.maximumOutputBytes,
                timeout: timeout
            )
            guard !output.wasTruncated else {
                throw ProbeError.parseFailed("Extension probe output exceeds the 1 MB safety limit")
            }
            result = CLIResult(
                output: output.standardOutput + output.standardError,
                exitCode: output.exitCode
            )
        }

        guard result.output.utf8.count <= Self.maximumOutputBytes else {
            throw ProbeError.parseFailed("Extension probe output exceeds the 1 MB safety limit")
        }

        guard result.exitCode == 0 else {
            throw ProbeError.executionFailed("Extension probe exited with code \(result.exitCode)")
        }

        guard let data = result.output.data(using: .utf8) else {
            throw ProbeError.parseFailed("Extension probe output is not valid UTF-8")
        }

        let sectionData = try SectionData.decode(from: data, type: sectionType, providerId: providerId)
        return sectionDataToSnapshot(sectionData)
    }

    public func isAvailable() async -> Bool {
        let resolvedPath = resolveScriptPath()
        return FileManager.default.fileExists(atPath: resolvedPath)
    }

    // MARK: - Private

    private func executionEnvironment(for resolvedPath: String) -> [String: String] {
        var environment = SimpleCLIExecutor.augmentedEnvironment(binaryPath: resolvedPath)
        guard let configRepository, let manifest else { return environment }
        let values = configRepository.allValues(
            forExtensionId: manifest.id,
            fields: manifest.configFields
        )
        for field in manifest.configFields {
            if let value = values[field.id] {
                environment[field.environmentVariableName] = value
            }
        }
        return environment
    }

    private func resolveScriptPath() -> String {
        let root = extensionDir.resolvingSymlinksInPath().standardizedFileURL
        let resolved = root.appending(path: scriptPath).resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else { return "" }
        return resolved.path()
    }

    private func sectionDataToSnapshot(_ data: SectionData) -> UsageSnapshot {
        switch data {
        case .quotas(let quotas):
            return UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: Date())
        case .cost(let costUsage):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), costUsage: costUsage)
        case .daily(let report):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), dailyUsageReport: report)
        case .metrics(let metrics):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), extensionMetrics: metrics)
        case .status(let status):
            return UsageSnapshot(
                providerId: providerId,
                quotas: [],
                capturedAt: Date(),
                extensionMetrics: [
                    ExtensionMetric(
                        id: sectionID,
                        label: "Status",
                        value: status.text,
                        unit: "",
                        kind: .status,
                        statusLevel: status.level
                    ),
                ]
            )
        }
    }
}
