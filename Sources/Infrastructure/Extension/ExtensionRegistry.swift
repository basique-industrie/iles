import Foundation
import Domain

/// Discovers extensions from disk and creates providers for the current source registry.
public final class ExtensionRegistry: Sendable {
    private let extensionsDirectory: URL
    private let scanner: ExtensionDirectoryScanner
    private let settingsRepository: ProviderSettingsRepository
    private let configRepository: (any ExtensionConfigRepository)?
    private let cliExecutor: CLIExecutor?
    private let trustRepository: any ExtensionTrustRepository

    public static var defaultDirectory: URL {
        AppIdentity.current.extensionsDirectory
    }

    public init(
        extensionsDirectory: URL? = nil,
        scanner: ExtensionDirectoryScanner = ExtensionDirectoryScanner(),
        settingsRepository: ProviderSettingsRepository,
        configRepository: (any ExtensionConfigRepository)? = nil,
        cliExecutor: CLIExecutor? = nil,
        trustRepository: any ExtensionTrustRepository = JSONExtensionTrustRepository()
    ) {
        self.extensionsDirectory = extensionsDirectory ?? Self.defaultDirectory
        self.scanner = scanner
        self.settingsRepository = settingsRepository
        self.configRepository = configRepository
        self.cliExecutor = cliExecutor
        self.trustRepository = trustRepository
    }

    /// Scans for extensions and returns the providers to register in the app runtime.
    @MainActor
    public func makeProviders() -> [ExtensionProvider] {
        ensureDirectoryExists()

        let scanResults = scanner.scan(directory: extensionsDirectory)
        return scanResults.map { result in
            ExtensionProvider(
                manifest: result.manifest,
                probes: createProbes(for: result),
                settingsRepository: settingsRepository,
                fingerprint: result.fingerprint,
                scriptCommands: result.manifest.sections.compactMap {
                    guard case .script(let command) = $0.probeConfig else { return nil }
                    return command
                },
                trustRepository: trustRepository
            )
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: extensionsDirectory.path()) {
            try? fm.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        }
    }

    private func createProbes(for result: ExtensionScanResult) -> [String: any UsageProbe] {
        var probes: [String: any UsageProbe] = [:]
        let providerId = "ext-\(result.manifest.id)"

        for section in result.manifest.sections {
            let probe: any UsageProbe
            switch section.probeConfig {
            case .script(let command):
                probe = ScriptProbe(
                    scriptPath: command,
                    sectionID: section.id,
                    extensionDir: result.directory,
                    providerId: providerId,
                    sectionType: section.type,
                    timeout: section.timeout,
                    cliExecutor: cliExecutor,
                    configRepository: configRepository,
                    manifest: result.manifest,
                    fingerprint: result.fingerprint,
                    trustRepository: trustRepository
                )
            case .healthCheck(let url):
                probe = HealthCheckProbe(
                    url: url,
                    providerId: providerId,
                    timeout: section.timeout
                )
            }
            probes[section.id] = probe
        }

        return probes
    }
}
