import Foundation

/// Repository protocol for all app-level settings (display, sync, budget, etc.).
/// Provider-specific settings live in `ProviderSettingsRepository` sub-protocols.
///
/// Both protocols share one backing store (`~/.iles/settings.json`, or
/// `~/.iles-dev/settings.json` for the development app).
public protocol AppSettingsRepository: Sendable {
    // MARK: - Background Sync

    func refreshInterval() -> RefreshInterval
    func setRefreshInterval(_ interval: RefreshInterval)

    // MARK: - Claude API Budget

    func claudeApiBudgetEnabled() -> Bool
    func setClaudeApiBudgetEnabled(_ enabled: Bool)

    func claudeApiBudget() -> Double
    func setClaudeApiBudget(_ amount: Double)

    // MARK: - First-run hint

    func emptyWorkspaceHintDismissed() -> Bool
    func setEmptyWorkspaceHintDismissed(_ dismissed: Bool)

    /// When Harnais is managing Claude/Codex/Cursor accounts, hide those
    /// first-party sources so the island does not double-count the same login.
    func hideBuiltInAIWhenHarnais() -> Bool
    func setHideBuiltInAIWhenHarnais(_ enabled: Bool)
}
