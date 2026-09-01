import Foundation

/// Repository protocol for all app-level settings (display, sync, budget, etc.).
/// Provider-specific settings live in `ProviderSettingsRepository` sub-protocols.
///
/// Both protocols share one backing store (`~/.iles/settings.json`).
public protocol AppSettingsRepository: Sendable {
    // MARK: - Background Sync

    func refreshInterval() -> RefreshInterval
    func setRefreshInterval(_ interval: RefreshInterval)

    // MARK: - Claude API Budget

    func claudeApiBudgetEnabled() -> Bool
    func setClaudeApiBudgetEnabled(_ enabled: Bool)

    func claudeApiBudget() -> Double
    func setClaudeApiBudget(_ amount: Double)

}
