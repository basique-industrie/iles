/// Stable provider identifiers and display names.
///
/// Probes, settings, alerts, and the island all key off these values.
/// Do not repeat `"claude"` / `"Codex"` string literals elsewhere.
public enum ProviderIdentity: String, Sendable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case antigravity
    case zai
    case copilot
    case ampcode
    case kimi
    case kiro
    case cursor
    case minimax
    case deepseek
    case vercelGateway = "vercel-gateway"
    case alibaba
    case mistral
    case openCode = "opencode-go"
    case omp
    case grok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        case .zai: "Z.ai"
        case .copilot: "Copilot"
        case .ampcode: "Amp"
        case .kimi: "Kimi"
        case .kiro: "Kiro"
        case .cursor: "Cursor"
        case .minimax: "MiniMax"
        case .deepseek: "DeepSeek"
        case .vercelGateway: "Vercel"
        case .alibaba: "Alibaba"
        case .mistral: "Mistral"
        case .openCode: "OpenCode"
        case .omp: "Oh My Pi"
        case .grok: "Grok"
        }
    }
}
