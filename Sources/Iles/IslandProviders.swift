import Domain
import Foundation
import Infrastructure

/// Builds the built-in provider set. Extensions are attached after first paint.
enum IslandProviders {
    @MainActor
    static func makeAll(demo: Bool, settings: JSONSettingsRepository) -> [any AIProvider] {
        if demo {
            return demoProviders(settings: settings)
        }
        return liveProviders(settings: settings)
    }

    @MainActor
    private static func liveProviders(settings: JSONSettingsRepository) -> [any AIProvider] {
        [
            ClaudeProvider(
                cliProbe: ClaudeUsageProbe(),
                apiProbe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settings,
                dailyUsageAnalyzer: ClaudeDailyUsageAnalyzer()
            ),
            CodexProvider(
                rpcProbe: CodexUsageProbe(),
                apiProbe: CodexAPIUsageProbe(),
                settingsRepository: settings
            ),
            GeminiProvider(probe: GeminiUsageProbe(), settingsRepository: settings),
            AntigravityProvider(probe: AntigravityUsageProbe(), settingsRepository: settings),
            ZaiProvider(
                probe: ZaiUsageProbe(settingsRepository: settings),
                settingsRepository: settings
            ),
            CopilotProvider(
                billingProbe: CopilotUsageProbe(settingsRepository: settings),
                internalProbe: CopilotInternalAPIProbe(settingsRepository: settings),
                settingsRepository: settings
            ),
            AmpCodeProvider(probe: AmpCodeUsageProbe(), settingsRepository: settings),
            KimiProvider(
                cliProbe: KimiCLIUsageProbe(),
                apiProbe: KimiUsageProbe(),
                settingsRepository: settings
            ),
            KiroProvider(probe: KiroUsageProbe(), settingsRepository: settings),
            CursorProvider(probe: CursorUsageProbe(), settingsRepository: settings),
            MiniMaxProvider(
                probe: MiniMaxUsageProbe(settingsRepository: settings),
                settingsRepository: settings
            ),
            DeepSeekProvider(
                probe: DeepSeekUsageProbe(settingsRepository: settings),
                settingsRepository: settings
            ),
            VercelProvider(
                probe: VercelUsageProbe(settingsRepository: settings),
                settingsRepository: settings
            ),
            AlibabaProvider(
                probe: AlibabaUsageProbe(settingsRepository: settings, cookieProvider: AlibabaBrowserCookieProvider()),
                settingsRepository: settings
            ),
            MistralProvider(
                probe: MistralUsageProbe(),
                settingsRepository: settings
            ),
            OpenCodeProvider(
                probe: OpenCodeAPIUsageProbe(fallback: OpenCodeUsageProbe()),
                settingsRepository: settings
            ),
            OmpProvider(
                probe: OmpUsageProbe(),
                settingsRepository: settings
            ),
            GrokProvider(
                probe: GrokUsageProbe(),
                settingsRepository: settings
            ),
        ]
    }

    @MainActor
    private static func demoProviders(settings: JSONSettingsRepository) -> [any AIProvider] {
        [
            ClaudeProvider(
                cliProbe: DemoUsageProbe.claude,
                settingsRepository: settings
            ),
            CodexProvider(
                rpcProbe: DemoUsageProbe.codex,
                settingsRepository: settings
            ),
            GeminiProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.gemini.rawValue, remaining: 64), settingsRepository: settings),
            AntigravityProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.antigravity.rawValue, remaining: 41), settingsRepository: settings),
            ZaiProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.zai.rawValue, remaining: 88), settingsRepository: settings),
            CopilotProvider(billingProbe: DemoUsageProbe.generic(id: ProviderIdentity.copilot.rawValue, remaining: 55), settingsRepository: settings),
            AmpCodeProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.ampcode.rawValue, remaining: 33), settingsRepository: settings),
            KimiProvider(cliProbe: DemoUsageProbe.generic(id: ProviderIdentity.kimi.rawValue, remaining: 77), settingsRepository: settings),
            KiroProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.kiro.rawValue, remaining: 60), settingsRepository: settings),
            CursorProvider(probe: DemoUsageProbe.cursor, settingsRepository: settings),
            MiniMaxProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.minimax.rawValue, remaining: 45), settingsRepository: settings),
            DeepSeekProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.deepseek.rawValue, remaining: 82), settingsRepository: settings),
            VercelProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.vercelGateway.rawValue, remaining: 51), settingsRepository: settings),
            AlibabaProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.alibaba.rawValue, remaining: 39), settingsRepository: settings),
            MistralProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.mistral.rawValue, remaining: 73), settingsRepository: settings),
            OpenCodeProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.openCode.rawValue, remaining: 58), settingsRepository: settings),
            OmpProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.omp.rawValue, remaining: 66), settingsRepository: settings),
            GrokProvider(probe: DemoUsageProbe.generic(id: ProviderIdentity.grok.rawValue, remaining: 29), settingsRepository: settings),
        ]
    }
}
