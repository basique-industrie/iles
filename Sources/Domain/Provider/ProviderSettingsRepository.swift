import Foundation

/// Repository protocol shared by provider-specific settings stores.
/// App uses JSONSettingsRepository.
public protocol ProviderSettingsRepository: Sendable {}

/// Z.ai-specific settings repository, extending base ProviderSettingsRepository.
/// App uses JSONSettingsRepository.
public protocol ZaiSettingsRepository: ProviderSettingsRepository {
    /// Gets the custom config path for Z.ai (empty string = use default)
    func zaiConfigPath() -> String

    /// Sets the custom config path for Z.ai
    func setZaiConfigPath(_ path: String)

    /// Gets the environment variable name for GLM auth token (empty = no env fallback)
    func glmAuthEnvVar() -> String

    /// Sets the environment variable name for GLM auth token
    func setGlmAuthEnvVar(_ envVar: String)
}

/// Copilot-specific settings repository, extending base ProviderSettingsRepository.
/// Includes both configuration and credentials for GitHub Copilot.
/// App uses JSONSettingsRepository.
public protocol CopilotSettingsRepository: ProviderSettingsRepository {
    // MARK: - Probe Mode

    /// Gets the probe mode for Copilot (billing or copilotAPI)
    func copilotProbeMode() -> CopilotProbeMode

    /// Sets the probe mode for Copilot
    func setCopilotProbeMode(_ mode: CopilotProbeMode)

    // MARK: - Configuration

    /// Gets the environment variable name for GitHub Copilot token (empty = no env fallback)
    func copilotAuthEnvVar() -> String

    /// Sets the environment variable name for GitHub Copilot token
    func setCopilotAuthEnvVar(_ envVar: String)

    // MARK: - Monthly Limit

    /// Gets the monthly premium request limit for Copilot (nil = use default of 50 for Free/Pro)
    func copilotMonthlyLimit() -> Int?

    /// Sets the monthly premium request limit for Copilot
    func setCopilotMonthlyLimit(_ limit: Int?)

    // MARK: - Manual Usage Override (for org-based subscriptions)

    /// Gets the manually entered usage value (nil = use API data)
    /// Can be either a request count or percentage depending on `copilotManualUsageIsPercent()`
    func copilotManualUsageValue() -> Double?

    /// Sets the manually entered usage value
    func setCopilotManualUsageValue(_ value: Double?)

    /// Gets whether the manual usage value is a percentage (true) or request count (false)
    func copilotManualUsageIsPercent() -> Bool

    /// Sets whether the manual usage value is a percentage
    func setCopilotManualUsageIsPercent(_ isPercent: Bool)

    /// Gets whether manual override is enabled (controlled externally, not auto-enabled)
    func copilotManualOverrideEnabled() -> Bool

    /// Sets whether manual override is enabled (must be controlled externally)
    func setCopilotManualOverrideEnabled(_ enabled: Bool)

    /// Gets whether the API returned empty data (persisted state)
    func copilotApiReturnedEmpty() -> Bool

    /// Sets whether the API returned empty data
    func setCopilotApiReturnedEmpty(_ empty: Bool)

    // MARK: - Usage Period Tracking

    /// Gets the last known usage period month (1-12)
    func copilotLastUsagePeriodMonth() -> Int?

    /// Gets the last known usage period year
    func copilotLastUsagePeriodYear() -> Int?

    /// Sets the last known usage period
    func setCopilotLastUsagePeriod(month: Int, year: Int)

    // MARK: - Credentials

    /// Saves the GitHub token
    func saveGithubToken(_ token: String)

    /// Retrieves the GitHub token
    func getGithubToken() -> String?

    /// Deletes the GitHub token
    func deleteGithubToken()

    /// Checks if a GitHub token is saved
    func hasGithubToken() -> Bool

    /// Saves the GitHub username
    func saveGithubUsername(_ username: String)

    /// Retrieves the GitHub username
    func getGithubUsername() -> String?

    /// Deletes the GitHub username
    func deleteGithubUsername()
}

/// Claude-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (CLI vs API).
/// App uses JSONSettingsRepository.
public protocol ClaudeSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Claude (CLI or API)
    func claudeProbeMode() -> ClaudeProbeMode

    /// Sets the probe mode for Claude
    func setClaudeProbeMode(_ mode: ClaudeProbeMode)

    /// Whether to fall back to the CLI probe when the OAuth API probe is unavailable.
    /// Defaults to true. Disable to prevent `claude /usage` from running in API mode.
    func claudeCliFallbackEnabled() -> Bool

    /// Sets whether CLI fallback is enabled in API mode
    func setClaudeCliFallbackEnabled(_ enabled: Bool)
}

/// Codex-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (RPC vs API).
/// App uses JSONSettingsRepository.
public protocol CodexSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Codex (RPC or API)
    func codexProbeMode() -> CodexProbeMode

    /// Sets the probe mode for Codex
    func setCodexProbeMode(_ mode: CodexProbeMode)
}

/// Kimi-specific settings repository, extending base ProviderSettingsRepository.
/// Includes configuration for probe mode (CLI vs API).
/// App uses JSONSettingsRepository.
public protocol KimiSettingsRepository: ProviderSettingsRepository {
    /// Gets the probe mode for Kimi (CLI or API)
    func kimiProbeMode() -> KimiProbeMode

    /// Sets the probe mode for Kimi
    func setKimiProbeMode(_ mode: KimiProbeMode)
}

/// MiniMax-specific settings repository, extending base ProviderSettingsRepository.
/// Stores API key and region configuration for MiniMax Coding Plan quota monitoring.
/// App uses JSONSettingsRepository.
public protocol MiniMaxSettingsRepository: ProviderSettingsRepository {
    /// Gets the API region (international or China; defaults to China).
    func minimaxRegion() -> MiniMaxRegion

    /// Sets the API region (设置 API 区域)
    func setMinimaxRegion(_ region: MiniMaxRegion)

    /// Gets the environment variable name for MiniMax API key (empty = use default MINIMAX_API_KEY)
    func minimaxAuthEnvVar() -> String

    /// Sets the environment variable name for MiniMax API key
    func setMinimaxAuthEnvVar(_ envVar: String)

    /// Saves the MiniMax API key (for Settings UI input)
    func saveMinimaxApiKey(_ key: String)

    /// Retrieves the MiniMax API key
    func getMinimaxApiKey() -> String?

    /// Deletes the MiniMax API key
    func deleteMinimaxApiKey()

    /// Checks if a MiniMax API key is saved
    func hasMinimaxApiKey() -> Bool
}

/// DeepSeek-specific settings repository, extending base ProviderSettingsRepository.
/// Stores the API key and env-var name for DeepSeek balance monitoring.
public protocol DeepSeekSettingsRepository: ProviderSettingsRepository {
    /// Gets the environment variable name for DeepSeek API key (empty = use default DEEPSEEK_API_KEY)
    func deepseekAuthEnvVar() -> String

    /// Sets the environment variable name for DeepSeek API key
    func setDeepSeekAuthEnvVar(_ envVar: String)

    /// Saves the DeepSeek API key (for Settings UI input)
    func saveDeepSeekApiKey(_ key: String)

    /// Retrieves the DeepSeek API key
    func getDeepSeekApiKey() -> String?

    /// Deletes the DeepSeek API key
    func deleteDeepSeekApiKey()

    /// Checks if a DeepSeek API key is saved
    func hasDeepSeekApiKey() -> Bool
}

/// Alibaba Coding Plan-specific settings repository, extending base ProviderSettingsRepository.
/// Stores region, cookie source, manual cookie, and API key for Alibaba Coding Plan quota monitoring.
public protocol AlibabaSettingsRepository: ProviderSettingsRepository {
    /// Gets the API region (international or chinaMainland, default: international)
    func alibabaRegion() -> AlibabaRegion

    /// Sets the API region
    func setAlibabaRegion(_ region: AlibabaRegion)

    /// Gets the cookie source (auto from browser or manual)
    func alibabaCookieSource() -> AlibabaCookieSource

    /// Sets the cookie source
    func setAlibabaCookieSource(_ source: AlibabaCookieSource)

    /// Saves a manually entered cookie string
    func saveAlibabaManualCookie(_ cookie: String)

    /// Retrieves the manually entered cookie string
    func getAlibabaManualCookie() -> String?

    /// Saves the Alibaba API key
    func saveAlibabaApiKey(_ key: String)

    /// Retrieves the Alibaba API key
    func getAlibabaApiKey() -> String?

    /// Deletes the Alibaba API key
    func deleteAlibabaApiKey()

    /// Checks if an Alibaba API key is saved
    func hasAlibabaApiKey() -> Bool
}

/// Vercel AI Gateway-specific settings repository, extending base ProviderSettingsRepository.
/// App uses JSONSettingsRepository.
public protocol VercelSettingsRepository: ProviderSettingsRepository {
    /// Gets the environment variable name for the AI Gateway API key (empty = use default AI_GATEWAY_API_KEY)
    func vercelAuthEnvVar() -> String

    /// Sets the environment variable name for the AI Gateway API key
    func setVercelAuthEnvVar(_ envVar: String)

    /// Saves the AI Gateway API key (for Settings UI input)
    func saveVercelApiKey(_ key: String)

    /// Retrieves the AI Gateway API key
    func getVercelApiKey() -> String?

    /// Deletes the AI Gateway API key.
    /// - Returns: `true` when the credential is absent after the operation.
    @discardableResult
    func deleteVercelApiKey() -> Bool

    /// Checks if an AI Gateway API key is saved
    func hasVercelApiKey() -> Bool
}
