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
    case harnais

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
        case .harnais: "Harnais"
        }
    }

    /// Claude, Codex, and Cursor accounts published through Harnais.
    public static let harnaisUpstream: [ProviderIdentity] = [.claude, .codex, .cursor]

    public static let harnaisUpstreamIDs: Set<String> = Set(harnaisUpstream.map(\.rawValue))

    /// Maps a Harnais window onto the upstream provider it belongs to.
    public static func mappedFromHarnais(
        providerId: String,
        group: String? = nil,
        label: String? = nil
    ) -> ProviderIdentity? {
        if let identity = ProviderIdentity(rawValue: providerId),
           harnaisUpstream.contains(identity) {
            return identity
        }
        for candidate in [group, label].compactMap({ $0 }) {
            if let identity = parseHarnaisLabel(candidate) {
                return identity
            }
        }
        return nil
    }

    private static func parseHarnaisLabel(_ text: String) -> ProviderIdentity? {
        var remainder = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = remainder.lastIndex(of: ":") {
            remainder = String(remainder[remainder.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let head = remainder
            .split(whereSeparator: { $0 == "·" || $0.isWhitespace })
            .first
            .map { String($0).lowercased() } ?? ""
        for identity in harnaisUpstream {
            if head == identity.rawValue || head == identity.displayName.lowercased() {
                return identity
            }
        }
        return nil
    }
}
