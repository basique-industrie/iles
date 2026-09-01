import Foundation
import Domain

/// Infrastructure adapter that probes the Gemini API to fetch usage quotas.
/// Uses OAuth credentials stored by the Gemini CLI.
public struct GeminiUsageProbe: UsageProbe {
    private let homeDirectory: String
    private let timeout: TimeInterval
    private let networkClient: any NetworkClient
    private let maxRetries: Int

    private static let credentialsPath = "/.gemini/oauth_creds.json"

    public init(
        homeDirectory: String = NSHomeDirectory(),
        timeout: TimeInterval = 10.0,
        networkClient: any NetworkClient = NetworkClients.ephemeral,
        maxRetries: Int = 3
    ) {
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.networkClient = networkClient
        self.maxRetries = maxRetries
    }

    public func isAvailable() async -> Bool {
        let credsURL = URL(fileURLWithPath: homeDirectory + Self.credentialsPath)
        return FileManager.default.fileExists(atPath: credsURL.path)
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Gemini probe...")

        let apiProbe = GeminiAPIProbe(
            homeDirectory: homeDirectory,
            timeout: timeout,
            networkClient: networkClient,
            maxRetries: maxRetries
        )
        return try await apiProbe.probe()
    }
}
