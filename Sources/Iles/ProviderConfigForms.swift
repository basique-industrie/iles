import Domain
import Infrastructure
import IslandGeometry
import SwiftUI

/// Per-provider Settings fields (probe mode, keys, Claude hooks).
struct ProviderConfigSection: View {
    @Bindable var runtime: IslandRuntime
    let brand: ProviderBrand
    var expanded = false

    @ViewBuilder
    var body: some View {
        if hasConfiguration {
            SettingsDisclosure(
                title: "Connection",
                subtitle: "Authentication and probe preferences",
                expanded: expanded
            ) {
                providerFields
            }
            .id(brand.id)
        }
    }

    private var hasConfiguration: Bool {
        brand.hasInAppConfiguration
    }

    @ViewBuilder
    private var providerFields: some View {
        switch brand {
        case .claude:
            ClaudeConfigForm(runtime: runtime)
        case .codex:
            CodexConfigForm(runtime: runtime)
        case .kimi:
            KimiConfigForm(runtime: runtime)
        case .copilot:
            CopilotConfigForm(runtime: runtime)
        case .minimax:
            MiniMaxConfigForm(runtime: runtime)
        case .deepseek:
            DeepSeekConfigForm(runtime: runtime)
        case .alibaba:
            AlibabaConfigForm(runtime: runtime)
        case .vercelGateway:
            VercelConfigForm(runtime: runtime)
        case .zai:
            ZaiConfigForm(runtime: runtime)
        default:
            SettingsCaption(text: "This provider uses its local CLI or app session. No extra probe settings.")
        }
    }
}

private struct ClaudeConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var mode = JSONSettingsRepository.shared.claudeProbeMode()
    @State private var fallback = JSONSettingsRepository.shared.claudeCliFallbackEnabled()
    @State private var budgetEnabled = JSONSettingsRepository.shared.claudeApiBudgetEnabled()
    @State private var budget = JSONSettingsRepository.shared.claudeApiBudget() > 0
        ? String(JSONSettingsRepository.shared.claudeApiBudget())
        : ""
    @State private var hasCredentials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Probe mode")
            IslandSegmentBar(
                items: Array(ClaudeProbeMode.allCases),
                selection: $mode,
                title: { $0.displayName },
                symbol: nil
            )
            .onChange(of: mode) { _, value in
                settings.setClaudeProbeMode(value)
                runtime.pinIfInteracting()
                runtime.refreshProvider(ProviderIdentity.claude.rawValue)
            }
            SettingsCaption(text: mode.description)

            if mode == .api {
                CredentialNote(
                    ok: hasCredentials,
                    okText: "OAuth credentials found",
                    failText: "No OAuth credentials. Run claude login."
                )
                SettingsToggleRow(title: "CLI fallback if OAuth is unavailable", isOn: $fallback)
                    .onChange(of: fallback) { _, value in
                        settings.setClaudeCliFallbackEnabled(value)
                        runtime.pinIfInteracting()
                    }
            }

            SettingsToggleRow(title: "API budget warnings", isOn: $budgetEnabled)
                .onChange(of: budgetEnabled) { _, value in
                    settings.setClaudeApiBudgetEnabled(value)
                }
            if budgetEnabled {
                IslandTextField(
                    title: "Monthly budget USD",
                    text: $budget,
                    prompt: "10.00",
                    validationMessage: budgetValidation
                ) {
                    if let value = Double(budget), value > 0 {
                        settings.setClaudeApiBudget(value)
                    }
                }
            }
        }
        .task {
            hasCredentials = await Task.detached {
                ClaudeCredentialLoader().loadCredentials() != nil
            }.value
        }
    }

    private var budgetValidation: String? {
        guard budgetEnabled, !budget.isEmpty else { return nil }
        guard let value = Double(budget), value > 0 else { return "Enter an amount greater than zero." }
        return nil
    }
}

struct ClaudeHooksSection: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var hooks = JSONSettingsRepository.shared.isHookEnabled()
    @State private var hookStatus = "Off"

    var body: some View {
        SettingsGroup(
            title: "Claude Code Hooks",
            subtitle: "Track live sessions through Claude Code's local hook configuration."
        ) {
            SettingsToggleRow(title: "Track live Claude Code sessions", isOn: $hooks)
                .onChange(of: hooks) { _, value in
                    settings.setHookEnabled(value)
                    NotificationCenter.default.post(name: .hookSettingsChanged, object: nil)
                    runtime.sessionTrackingDidChange()
                    hookStatus = value ? "Installing" : "Turning off"
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        refreshStatus()
                    }
                }
            SettingsStatusLine(title: hookStatus, attention: hookStatus == "Needs attention")
            SettingsCaption(text: "Writes hooks into ~/.claude/settings.json. Other tools are left untouched.")
        }
        .task {
            refreshStatus()
        }
    }

    private func refreshStatus() {
        hookStatus = hooks
            ? (HookInstaller.isInstalled() ? "Installed" : "Needs attention")
            : "Off"
    }
}

private struct CodexConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var mode = JSONSettingsRepository.shared.codexProbeMode()
    @State private var hasCredentials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Probe mode")
            IslandSegmentBar(
                items: Array(CodexProbeMode.allCases),
                selection: $mode,
                title: { $0.displayName },
                symbol: nil
            )
            .onChange(of: mode) { _, value in
                settings.setCodexProbeMode(value)
                runtime.pinIfInteracting()
                runtime.refreshProvider(ProviderIdentity.codex.rawValue)
            }
            SettingsCaption(text: mode.description)
            if mode == .api {
                CredentialNote(
                    ok: hasCredentials,
                    okText: "OAuth credentials found",
                    failText: "No OAuth credentials. Run codex login."
                )
            }
        }
        .task {
            hasCredentials = await Task.detached {
                CodexCredentialLoader().loadCredentials() != nil
            }.value
        }
    }
}

private struct KimiConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var mode = JSONSettingsRepository.shared.kimiProbeMode()
    @State private var token = ""
    @State private var showToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Probe mode")
            IslandSegmentBar(
                items: Array(KimiProbeMode.allCases),
                selection: $mode,
                title: { $0.displayName },
                symbol: nil
            )
            .onChange(of: mode) { _, value in
                settings.setKimiProbeMode(value)
                runtime.pinIfInteracting()
                runtime.refreshProvider(ProviderIdentity.kimi.rawValue)
            }
            SettingsCaption(text: mode.description)
            if mode == .api {
                IslandSecretField(title: "API token", text: $token, reveal: $showToken) {
                    if token.isEmpty {
                        settings.deleteKimiAuthToken()
                    } else {
                        settings.saveKimiAuthToken(token)
                    }
                }
                CredentialNote(
                    ok: !token.isEmpty || settings.getKimiAuthToken() != nil,
                    okText: "Saved API token available",
                    failText: "No saved token; KIMI_AUTH_TOKEN can be used instead."
                )
            }
        }
    }
}

private struct CopilotConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var mode = JSONSettingsRepository.shared.copilotProbeMode()
    @State private var envVar = JSONSettingsRepository.shared.copilotAuthEnvVar()
    @State private var token = ""
    @State private var username = JSONSettingsRepository.shared.getGithubUsername() ?? ""
    @State private var monthlyLimit = JSONSettingsRepository.shared.copilotMonthlyLimit().map(String.init) ?? "50"
    @State private var showToken = false
    @State private var manualOverride = JSONSettingsRepository.shared.copilotManualOverrideEnabled()
    @State private var manualUsage = JSONSettingsRepository.shared.copilotManualUsageValue().map { String($0) } ?? ""
    @State private var manualIsPercent = JSONSettingsRepository.shared.copilotManualUsageIsPercent()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Probe mode")
            IslandSegmentBar(
                items: Array(CopilotProbeMode.allCases),
                selection: $mode,
                title: { $0.displayName },
                symbol: nil
            )
            .onChange(of: mode) { _, value in
                settings.setCopilotProbeMode(value)
                runtime.pinIfInteracting()
                runtime.refreshProvider(ProviderIdentity.copilot.rawValue)
            }
            SettingsCaption(text: mode.description)

            IslandTextField(title: "GitHub username", text: $username, prompt: "octocat") {
                settings.saveGithubUsername(username)
            }
            IslandSecretField(title: "GitHub token", text: $token, reveal: $showToken) {
                if token.isEmpty {
                    settings.deleteGithubToken()
                } else {
                    settings.saveGithubToken(token)
                }
            }
            CredentialNote(
                ok: !token.isEmpty || settings.hasGithubToken(),
                okText: "Saved GitHub token available",
                failText: "No saved token; the configured environment variable can be used."
            )
            IslandTextField(title: "Token env var", text: $envVar, prompt: "GITHUB_TOKEN") {
                settings.setCopilotAuthEnvVar(envVar)
            }
            IslandTextField(
                title: "Monthly premium limit",
                text: $monthlyLimit,
                prompt: "50",
                validationMessage: monthlyLimitValidation
            ) {
                if let value = Int(monthlyLimit), value > 0 {
                    settings.setCopilotMonthlyLimit(value)
                }
            }

            SettingsToggleRow(title: "Manual usage override", isOn: $manualOverride)
                .onChange(of: manualOverride) { _, value in
                    settings.setCopilotManualOverrideEnabled(value)
                    runtime.pinIfInteracting()
                    runtime.refreshProvider(ProviderIdentity.copilot.rawValue)
                }

            if manualOverride {
                IslandSegmentBar(
                    items: [true, false],
                    selection: $manualIsPercent,
                    title: { $0 ? "Percent" : "Requests" },
                    symbol: nil
                )
                .onChange(of: manualIsPercent) { _, value in
                    settings.setCopilotManualUsageIsPercent(value)
                    runtime.refreshProvider(ProviderIdentity.copilot.rawValue)
                }
                IslandTextField(
                    title: manualIsPercent ? "Used percent" : "Used requests",
                    text: $manualUsage,
                    prompt: manualIsPercent ? "40" : "20",
                    validationMessage: manualUsageValidation
                ) {
                    if let value = Double(manualUsage), value >= 0,
                       !manualIsPercent || value <= 100 {
                        settings.setCopilotManualUsageValue(value)
                    }
                }
            }
        }
    }

    private var monthlyLimitValidation: String? {
        guard !monthlyLimit.isEmpty else { return nil }
        guard let value = Int(monthlyLimit), value > 0 else { return "Enter a whole number greater than zero." }
        return nil
    }

    private var manualUsageValidation: String? {
        guard manualOverride, !manualUsage.isEmpty else { return nil }
        guard let value = Double(manualUsage), value >= 0 else { return "Enter a non-negative value." }
        if manualIsPercent, value > 100 { return "Percentage cannot exceed 100." }
        return nil
    }
}

private struct MiniMaxConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var region = JSONSettingsRepository.shared.minimaxRegion()
    @State private var envVar = JSONSettingsRepository.shared.minimaxAuthEnvVar()
    @State private var apiKey = ""
    @State private var showKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Region")
            IslandSegmentBar(
                items: Array(MiniMaxRegion.allCases),
                selection: $region,
                title: { $0 == .international ? "International" : "China" },
                symbol: nil
            )
            .onChange(of: region) { _, value in
                settings.setMinimaxRegion(value)
                runtime.pinIfInteracting()
                runtime.refreshProvider(ProviderIdentity.minimax.rawValue)
            }
            IslandSecretField(title: "API key", text: $apiKey, reveal: $showKey) {
                if apiKey.isEmpty {
                    settings.deleteMinimaxApiKey()
                } else {
                    settings.saveMinimaxApiKey(apiKey)
                }
            }
            CredentialNote(
                ok: !apiKey.isEmpty || settings.hasMinimaxApiKey(),
                okText: "Saved API key available",
                failText: "No saved key; the configured environment variable can be used."
            )
            IslandTextField(title: "API key env var", text: $envVar, prompt: "MINIMAX_API_KEY") {
                settings.setMinimaxAuthEnvVar(envVar)
            }
        }
    }
}

private struct DeepSeekConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var envVar = JSONSettingsRepository.shared.deepseekAuthEnvVar()
    @State private var apiKey = ""
    @State private var showKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IslandSecretField(title: "API key", text: $apiKey, reveal: $showKey) {
                if apiKey.isEmpty {
                    settings.deleteDeepSeekApiKey()
                } else {
                    settings.saveDeepSeekApiKey(apiKey)
                }
            }
            CredentialNote(
                ok: !apiKey.isEmpty || settings.hasDeepSeekApiKey(),
                okText: "Saved API key available",
                failText: "No saved key; the configured environment variable can be used."
            )
            IslandTextField(title: "API key env var", text: $envVar, prompt: "DEEPSEEK_API_KEY") {
                settings.setDeepSeekAuthEnvVar(envVar)
            }
        }
    }
}

private struct AlibabaConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var region = JSONSettingsRepository.shared.alibabaRegion()
    @State private var cookie = JSONSettingsRepository.shared.getAlibabaManualCookie() ?? ""
    @State private var apiKey = ""
    @State private var showCookie = false
    @State private var showKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "Region")
            IslandSegmentBar(
                items: Array(AlibabaRegion.allCases),
                selection: $region,
                title: { $0.displayName },
                symbol: nil
            )
            .onChange(of: region) { _, value in
                settings.setAlibabaRegion(value)
                runtime.refreshProvider(ProviderIdentity.alibaba.rawValue)
            }

            IslandSecretField(title: "Cookie", text: $cookie, reveal: $showCookie) {
                if cookie.isEmpty {
                    settings.deleteAlibabaManualCookie()
                } else {
                    settings.saveAlibabaManualCookie(cookie)
                }
            }
            CredentialNote(
                ok: !cookie.isEmpty || settings.getAlibabaManualCookie() != nil,
                okText: "Saved browser cookie available",
                failText: "No manual browser cookie saved."
            )
            IslandSecretField(title: "API key", text: $apiKey, reveal: $showKey) {
                if apiKey.isEmpty {
                    settings.deleteAlibabaApiKey()
                } else {
                    settings.saveAlibabaApiKey(apiKey)
                }
            }
            CredentialNote(
                ok: !apiKey.isEmpty || settings.hasAlibabaApiKey(),
                okText: "Saved API key available",
                failText: "No API key saved."
            )
        }
    }
}

private struct VercelConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var envVar = JSONSettingsRepository.shared.vercelAuthEnvVar()
    @State private var apiKey = ""
    @State private var showKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IslandSecretField(title: "AI Gateway API key", text: $apiKey, reveal: $showKey) {
                if apiKey.isEmpty {
                    _ = settings.deleteVercelApiKey()
                } else {
                    settings.saveVercelApiKey(apiKey)
                }
            }
            CredentialNote(
                ok: !apiKey.isEmpty || settings.hasVercelApiKey(),
                okText: "Saved AI Gateway key available",
                failText: "No saved key; the configured environment variable can be used."
            )
            IslandTextField(title: "API key env var", text: $envVar, prompt: "AI_GATEWAY_API_KEY") {
                settings.setVercelAuthEnvVar(envVar)
            }
        }
    }
}

private struct ZaiConfigForm: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @State private var configPath = JSONSettingsRepository.shared.zaiConfigPath()
    @State private var envVar = JSONSettingsRepository.shared.glmAuthEnvVar()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IslandTextField(title: "settings.json path", text: $configPath, prompt: "~/.claude/settings.json") {
                settings.setZaiConfigPath(configPath)
            }
            IslandTextField(title: "GLM token env var", text: $envVar, prompt: "GLM_AUTH_TOKEN") {
                settings.setGlmAuthEnvVar(envVar)
            }
            SettingsCaption(text: "Looks up the token in settings.json first, then the environment variable.")
        }
    }
}
