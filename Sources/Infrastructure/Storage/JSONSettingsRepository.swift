import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols) + HookSettingsRepository.
///
/// Backed by `JSONSettingsStore` for preferences and Keychain for secrets.
public final class JSONSettingsRepository:
    AppSettingsRepository,
    ZaiSettingsRepository,
    CopilotSettingsRepository,
    ClaudeSettingsRepository,
    CodexSettingsRepository,
    KimiSettingsRepository,
    MiniMaxSettingsRepository,
    AlibabaSettingsRepository,
    VercelSettingsRepository,
    HookSettingsRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let secureCredentials: any CredentialRepository

    private func saveCredential(_ value: String, forKey key: String) {
        if value.isEmpty {
            secureCredentials.delete(forKey: key)
        } else {
            secureCredentials.save(value, forKey: key)
        }
    }

    public init(
        store: JSONSettingsStore,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared
    ) {
        self.store = store
        self.secureCredentials = secureCredentials
    }

    // MARK: - AppSettingsRepository

    public func refreshInterval() -> RefreshInterval {
        guard let raw: String = store.read(key: "app.refreshInterval") else { return .tenMinutes }
        return RefreshInterval(rawValue: raw) ?? .tenMinutes
    }

    public func setRefreshInterval(_ interval: RefreshInterval) {
        store.write(value: interval.rawValue, key: "app.refreshInterval")
    }

    public func claudeApiBudgetEnabled() -> Bool {
        store.read(key: "app.claudeApiBudgetEnabled") ?? false
    }

    public func setClaudeApiBudgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.claudeApiBudgetEnabled")
    }

    public func claudeApiBudget() -> Double {
        store.read(key: "app.claudeApiBudget") ?? 0
    }

    public func setClaudeApiBudget(_ amount: Double) {
        store.write(value: amount, key: "app.claudeApiBudget")
    }

    public func emptyWorkspaceHintDismissed() -> Bool {
        store.read(key: "app.emptyWorkspaceHintDismissed") ?? false
    }

    public func setEmptyWorkspaceHintDismissed(_ dismissed: Bool) {
        store.write(value: dismissed, key: "app.emptyWorkspaceHintDismissed")
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let raw: String = store.read(key: "claude.probeMode"),
              let mode = ClaudeProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        store.write(value: mode.rawValue, key: "claude.probeMode")
    }

    public func claudeCliFallbackEnabled() -> Bool {
        store.read(key: "claude.cliFallbackEnabled") ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "claude.cliFallbackEnabled")
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let raw: String = store.read(key: "codex.probeMode"),
              let mode = CodexProbeMode(rawValue: raw) else {
            return .rpc
        }
        return mode
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        store.write(value: mode.rawValue, key: "codex.probeMode")
    }

    // MARK: - KimiSettingsRepository

    public func kimiProbeMode() -> KimiProbeMode {
        guard let raw: String = store.read(key: "kimi.probeMode"),
              let mode = KimiProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setKimiProbeMode(_ mode: KimiProbeMode) {
        store.write(value: mode.rawValue, key: "kimi.probeMode")
    }

    public func saveKimiAuthToken(_ token: String) {
        saveCredential(token, forKey: CredentialKey.kimiAuthToken)
    }

    public func getKimiAuthToken() -> String? {
        secureCredentials.get(forKey: CredentialKey.kimiAuthToken)
    }

    public func deleteKimiAuthToken() {
        secureCredentials.delete(forKey: CredentialKey.kimiAuthToken)
    }

    // MARK: - ZaiSettingsRepository

    public func zaiConfigPath() -> String {
        store.read(key: "zai.configPath") ?? ""
    }

    public func setZaiConfigPath(_ path: String) {
        store.write(value: path, key: "zai.configPath")
    }

    public func glmAuthEnvVar() -> String {
        store.read(key: "zai.glmAuthEnvVar") ?? ""
    }

    public func setGlmAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "zai.glmAuthEnvVar")
    }

    // MARK: - CopilotSettingsRepository

    public func copilotProbeMode() -> CopilotProbeMode {
        guard let raw: String = store.read(key: "copilot.probeMode"),
              let mode = CopilotProbeMode(rawValue: raw) else {
            return .billing
        }
        return mode
    }

    public func setCopilotProbeMode(_ mode: CopilotProbeMode) {
        store.write(value: mode.rawValue, key: "copilot.probeMode")
    }

    public func copilotAuthEnvVar() -> String {
        store.read(key: "copilot.authEnvVar") ?? ""
    }

    public func setCopilotAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "copilot.authEnvVar")
    }

    public func copilotMonthlyLimit() -> Int? {
        store.read(key: "copilot.monthlyLimit")
    }

    public func setCopilotMonthlyLimit(_ limit: Int?) {
        store.write(value: limit, key: "copilot.monthlyLimit")
    }

    public func copilotManualUsageValue() -> Double? {
        store.read(key: "copilot.manualUsageValue")
    }

    public func setCopilotManualUsageValue(_ value: Double?) {
        store.write(value: value, key: "copilot.manualUsageValue")
    }

    public func copilotManualUsageIsPercent() -> Bool {
        store.read(key: "copilot.manualUsageIsPercent") ?? false
    }

    public func setCopilotManualUsageIsPercent(_ isPercent: Bool) {
        store.write(value: isPercent, key: "copilot.manualUsageIsPercent")
    }

    public func copilotManualOverrideEnabled() -> Bool {
        store.read(key: "copilot.manualOverrideEnabled") ?? false
    }

    public func setCopilotManualOverrideEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "copilot.manualOverrideEnabled")
    }

    public func copilotApiReturnedEmpty() -> Bool {
        store.read(key: "copilot.apiReturnedEmpty") ?? false
    }

    public func setCopilotApiReturnedEmpty(_ empty: Bool) {
        store.write(value: empty, key: "copilot.apiReturnedEmpty")
    }

    public func copilotLastUsagePeriodMonth() -> Int? {
        store.read(key: "copilot.lastUsagePeriodMonth")
    }

    public func copilotLastUsagePeriodYear() -> Int? {
        store.read(key: "copilot.lastUsagePeriodYear")
    }

    public func setCopilotLastUsagePeriod(month: Int, year: Int) {
        store.write(value: month, key: "copilot.lastUsagePeriodMonth")
        store.write(value: year, key: "copilot.lastUsagePeriodYear")
    }

    // Credentials

    public func saveGithubToken(_ token: String) {
        saveCredential(token, forKey: CredentialKey.githubToken)
    }

    public func getGithubToken() -> String? {
        secureCredentials.get(forKey: CredentialKey.githubToken)
    }

    public func deleteGithubToken() {
        secureCredentials.delete(forKey: CredentialKey.githubToken)
    }

    public func hasGithubToken() -> Bool {
        getGithubToken() != nil
    }

    public func saveGithubUsername(_ username: String) {
        store.write(value: username.isEmpty ? nil : username, key: "copilot.username")
    }

    public func getGithubUsername() -> String? {
        store.read(key: "copilot.username")
    }

    public func deleteGithubUsername() {
        store.write(value: nil, key: "copilot.username")
    }

    // MARK: - AlibabaSettingsRepository

    public func alibabaRegion() -> AlibabaRegion {
        guard let rawValue: String = store.read(key: "alibaba.region") else {
            return .international
        }
        return AlibabaRegion(rawValue: rawValue) ?? .international
    }

    public func setAlibabaRegion(_ region: AlibabaRegion) {
        store.write(value: region.rawValue, key: "alibaba.region")
    }

    public func alibabaCookieSource() -> AlibabaCookieSource {
        guard let rawValue: String = store.read(key: "alibaba.cookieSource") else {
            return .auto
        }
        return AlibabaCookieSource(rawValue: rawValue) ?? .auto
    }

    public func setAlibabaCookieSource(_ source: AlibabaCookieSource) {
        store.write(value: source.rawValue, key: "alibaba.cookieSource")
    }

    public func saveAlibabaManualCookie(_ cookie: String) {
        saveCredential(cookie, forKey: CredentialKey.alibabaManualCookie)
    }

    public func getAlibabaManualCookie() -> String? {
        secureCredentials.get(forKey: CredentialKey.alibabaManualCookie)
    }

    public func saveAlibabaApiKey(_ key: String) {
        saveCredential(key, forKey: CredentialKey.alibabaApiKey)
    }

    public func getAlibabaApiKey() -> String? {
        secureCredentials.get(forKey: CredentialKey.alibabaApiKey)
    }

    public func deleteAlibabaApiKey() {
        secureCredentials.delete(forKey: CredentialKey.alibabaApiKey)
    }

    public func hasAlibabaApiKey() -> Bool {
        secureCredentials.exists(forKey: CredentialKey.alibabaApiKey)
    }

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        store.read(key: "hook.enabled") ?? false
    }

    public func setHookEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "hook.enabled")
    }

    public func hookPort() -> Int {
        let port: Int = store.read(key: "hook.port") ?? Int(HookConstants.defaultPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        store.write(value: port, key: "hook.port")
    }

    // MARK: - MiniMaxSettingsRepository

    public func minimaxRegion() -> MiniMaxRegion {
        guard let raw: String = store.read(key: "minimax.region"),
              let region = MiniMaxRegion(rawValue: raw) else {
            return .china
        }
        return region
    }

    public func setMinimaxRegion(_ region: MiniMaxRegion) {
        store.write(value: region.rawValue, key: "minimax.region")
    }

    public func minimaxAuthEnvVar() -> String {
        store.read(key: "minimax.authEnvVar") ?? ""
    }

    public func setMinimaxAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "minimax.authEnvVar")
    }

    // MiniMax Credentials

    public func saveMinimaxApiKey(_ key: String) {
        saveCredential(key, forKey: CredentialKey.miniMaxApiKey)
    }

    public func getMinimaxApiKey() -> String? {
        secureCredentials.get(forKey: CredentialKey.miniMaxApiKey)
    }

    public func deleteMinimaxApiKey() {
        secureCredentials.delete(forKey: CredentialKey.miniMaxApiKey)
    }

    public func hasMinimaxApiKey() -> Bool {
        getMinimaxApiKey() != nil
    }

    // MARK: - VercelSettingsRepository

    public func vercelAuthEnvVar() -> String {
        store.read(key: "vercel.authEnvVar") ?? ""
    }

    public func setVercelAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "vercel.authEnvVar")
    }

    public func saveVercelApiKey(_ key: String) {
        saveCredential(key, forKey: CredentialKey.vercelApiKey)
    }

    public func getVercelApiKey() -> String? {
        secureCredentials.get(forKey: CredentialKey.vercelApiKey)
    }

    @discardableResult
    public func deleteVercelApiKey() -> Bool {
        secureCredentials.delete(forKey: CredentialKey.vercelApiKey)
    }

    public func hasVercelApiKey() -> Bool {
        secureCredentials.exists(forKey: CredentialKey.vercelApiKey)
    }
}

// MARK: - DeepSeekSettingsRepository

extension JSONSettingsRepository: DeepSeekSettingsRepository {
    public func deepseekAuthEnvVar() -> String {
        store.read(key: "deepseek.authEnvVar") ?? ""
    }

    public func setDeepSeekAuthEnvVar(_ envVar: String) {
        store.write(value: envVar, key: "deepseek.authEnvVar")
    }

    // DeepSeek Credentials

    public func saveDeepSeekApiKey(_ key: String) {
        saveCredential(key, forKey: CredentialKey.deepSeekApiKey)
    }

    public func getDeepSeekApiKey() -> String? {
        secureCredentials.get(forKey: CredentialKey.deepSeekApiKey)
    }

    public func deleteDeepSeekApiKey() {
        secureCredentials.delete(forKey: CredentialKey.deepSeekApiKey)
    }

    public func hasDeepSeekApiKey() -> Bool {
        getDeepSeekApiKey() != nil
    }

}
