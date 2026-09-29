import Domain
import Foundation

/// Fetches live account usage through Harnais' isolated probes.
/// Iles owns scheduling and consumes the command result, never the cached feed.
/// Harnais remains the owner of account configuration and visibility preferences.
public struct HarnaisUsageProbe: UsageProbe {
    public static var defaultConfigurationDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".harnais")
    }

    public static var defaultFeedURL: URL {
        defaultConfigurationDirectory.appendingPathComponent("quotas.json")
    }

    public static var defaultAccountsURL: URL {
        defaultConfigurationDirectory.appendingPathComponent("accounts.json")
    }

    private let configurationDirectory: URL
    private let executor: any CLIExecutor

    public init(
        configurationDirectory: URL = HarnaisUsageProbe.defaultConfigurationDirectory,
        executor: any CLIExecutor = DefaultCLIExecutor(environmentExclusions: [
            "HARNAIS_DATA_DIR", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY", "CODEX_HOME", "CLAUDE_CONFIG_DIR",
        ])
    ) {
        self.configurationDirectory = configurationDirectory
        self.executor = executor
    }

    public func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: configurationDirectory.appendingPathComponent("accounts.json").path)
            && FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    private var helperURL: URL {
        configurationDirectory.appendingPathComponent("bin/harnais")
    }

    public func probe() async throws -> UsageSnapshot {
        // Validate preferences before starting network work. A malformed file
        // must not silently re-enable rings the user hid in Harnais.
        let preferencesURL = configurationDirectory.appendingPathComponent("islands.json")
        let hidden: Set<String>
        if FileManager.default.fileExists(atPath: preferencesURL.path) {
            hidden = Set(try JSONDecoder().decode(Visibility.self, from: Data(contentsOf: preferencesURL)).hiddenTypes)
        } else {
            hidden = []
        }
        try Task.checkCancellation()
        let startedAt = Date()
        let result = try await executor.execute(
            binary: helperURL.path,
            args: ["quotas", "--json"],
            input: nil,
            timeout: 300,
            workingDirectory: configurationDirectory,
            autoResponses: [:]
        )
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ProbeError.executionFailed("Iles could not refresh account usage. Check the Harnais account logins, then retry in Iles.")
        }
        let snapshot = try Self.parse(Data(result.output.utf8), hiddenTypes: hidden)
        // The CLI emits second-resolution timestamps. Reject an obsolete helper
        // returning cached JSON rather than giving old values a new local date.
        guard snapshot.capturedAt >= startedAt.addingTimeInterval(-2),
              snapshot.capturedAt <= Date().addingTimeInterval(5) else {
            throw ProbeError.executionFailed("The account probe returned an old sample. Update Harnais, then retry in Iles.")
        }
        return snapshot
    }

    public static func parse(_ data: Data, hiddenTypes: Set<String> = []) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        let feed: Feed
        do {
            feed = try decoder.decode(Feed.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Malformed Harnais quotas JSON: \(error.localizedDescription)")
        }

        var quotas: [UsageQuota] = []
        var seenTypes: Set<String> = []
        var accountErrors: [String] = []
        for account in feed.accounts {
            if let error = account.error, !error.isEmpty {
                accountErrors.append(error)
                if account.quotas.isEmpty {
                    AppLog.probes.warning(
                        "Harnais skipped account \(account.id) (\(account.provider))"
                    )
                    continue
                }
            }
            let group = account.groupTitle
            for quota in account.quotas where quota.percentRemaining.isFinite {
                let typeLabel = uniqueTypeLabel(quota.type, seen: &seenTypes)
                quotas.append(
                    UsageQuota(
                        percentRemaining: quota.percentRemaining,
                        quotaType: QuotaType(quotaKey: typeLabel) ?? .timeLimit(typeLabel),
                        providerId: Self.upstreamProviderID(account.provider),
                        resetsAt: quota.resetsAt,
                        resetText: quota.resetText,
                        group: Self.privacySafeGroup(quota.group, fallback: group),
                        compactTitle: quota.compactTitle,
                        menuBarTitle: quota.menuBarTitle,
                        accountID: account.id,
                        resetCredits: account.resetCredits
                    )
                )
            }
        }

        if quotas.isEmpty {
            if let first = accountErrors.first {
                throw ProbeError.executionFailed(first)
            }
            throw ProbeError.noData
        }

        return UsageSnapshot(
            providerId: ProviderIdentity.harnais.rawValue,
            quotas: quotas,
            capturedAt: feed.capturedAt,
            loginMethod: "Harnais",
            hiddenQuotaTypes: hiddenTypes
        )
    }

    private static func uniqueTypeLabel(_ type: String, seen: inout Set<String>) -> String {
        var typeLabel = type
        if seen.contains(typeLabel) {
            var suffix = 2
            while seen.contains("\(typeLabel) (\(suffix))") { suffix += 1 }
            typeLabel = "\(typeLabel) (\(suffix))"
        }
        seen.insert(typeLabel)
        return typeLabel
    }

    private static func privacySafeGroup(_ published: String?, fallback: String) -> String {
        if let published, !published.isEmpty, !published.contains("@") {
            return published
        }
        return fallback
    }

    private static func upstreamProviderID(_ provider: String) -> String {
        ProviderIdentity.mappedFromHarnais(providerId: provider)?.rawValue
            ?? ProviderIdentity.harnais.rawValue
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO-8601 date: \(raw)"
        )
    }

    private struct Visibility: Decodable {
        var hiddenTypes: [String]
    }

    private struct Feed: Codable {
        var schemaVersion: Int?
        var capturedAt: Date
        var accounts: [Account]
    }

    private struct Account: Codable {
        var id: String
        var provider: String
        var label: String
        var quotas: [Quota]
        var error: String?
        var resetCredits: ResetCredits?

        var groupTitle: String {
            let name = ProviderIdentity(rawValue: provider)?.displayName ?? provider.capitalized
            return "\(name) · \(label)"
        }
    }

    private struct Quota: Codable {
        var type: String
        var percentRemaining: Double
        var resetsAt: Date?
        var resetText: String?
        var group: String?
        var compactTitle: String?
        var menuBarTitle: String?
    }
}
