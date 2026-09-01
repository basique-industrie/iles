import Domain
import Foundation

public protocol KimiTokenProviding: Sendable {
    func resolveToken() throws -> String
}

/// Resolves Kimi auth from `KIMI_AUTH_TOKEN`, then a stored Iles token.
public struct KimiCookieTokenProvider: KimiTokenProviding {
    private let credentials: any CredentialRepository

    public init(credentials: any CredentialRepository = KeychainCredentialRepository.shared) {
        self.credentials = credentials
    }

    public func resolveToken() throws -> String {
        if let envToken = ProcessInfo.processInfo.environment["KIMI_AUTH_TOKEN"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            AppLog.probes.debug("Kimi: Using token from KIMI_AUTH_TOKEN env var")
            return envToken
        }
        if let stored = credentials.get(forKey: CredentialKey.kimiAuthToken),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            AppLog.probes.debug("Kimi: Using token from Iles settings")
            return stored
        }
        AppLog.probes.error("Kimi: No authentication token found")
        throw ProbeError.authenticationRequired
    }
}
