import AppKit
import Domain
import IslandGeometry
import SwiftUI

/// Built-in provider identity: title, accent, icon, and which quota is primary.
enum ProviderBrand: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    static var launchCases: [ProviderBrand] { allCases }

    var identity: ProviderIdentity { ProviderIdentity(rawValue: rawValue) ?? .omp }

    var title: String { identity.displayName }

    var accent: Color {
        switch self {
        case .claude: IslandPalette.claude
        case .codex: IslandPalette.codex
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .antigravity: Color(red: 0.56, green: 0.27, blue: 0.94)
        case .zai: Color(red: 0.13, green: 0.77, blue: 0.75)
        case .copilot: Color(red: 0.39, green: 0.56, blue: 0.92)
        case .ampcode: Color(red: 0.95, green: 0.35, blue: 0.55)
        case .kimi: Color(red: 0.91, green: 0.18, blue: 0.22)
        case .kiro: Color(red: 0.55, green: 0.89, blue: 0.22)
        case .cursor: IslandPalette.cursor
        case .minimax: Color(red: 1, green: 0.72, blue: 0.11)
        case .deepseek: Color(red: 0.29, green: 0.42, blue: 0.82)
        case .vercelGateway: Color(red: 0.88, green: 0.88, blue: 0.88)
        case .alibaba: Color(red: 1, green: 0.42, blue: 0.04)
        case .mistral: Color(red: 0.98, green: 0.45, blue: 0.09)
        case .openCode: Color(red: 0.22, green: 0.84, blue: 0.87)
        case .omp: Color(red: 0.45, green: 0.72, blue: 1)
        case .grok: Color(red: 0.92, green: 0.92, blue: 0.92)
        case .harnais: Color(red: 0.86, green: 0.62, blue: 0.38)
        }
    }

    var iconResource: (name: String, ext: String) {
        switch self {
        case .claude: ("ClaudeIcon", "svg")
        case .codex: ("CodexIcon", "svg")
        case .gemini: ("GeminiIcon", "svg")
        case .antigravity: ("AntigravityIcon", "svg")
        case .zai: ("ZaiIcon", "svg")
        case .copilot: ("CopilotIcon", "svg")
        case .ampcode: ("AmpCodeIcon", "svg")
        case .kimi: ("KimiIcon", "svg")
        case .kiro: ("KiroIcon", "svg")
        case .cursor: ("CursorIcon", "svg")
        case .minimax: ("MiniMaxIcon", "svg")
        case .deepseek: ("DeepSeekIcon", "svg")
        case .vercelGateway: ("VercelIcon", "svg")
        case .alibaba: ("AlibabaIcon", "svg")
        case .mistral: ("MistralIcon", "svg")
        case .openCode: ("OpenCodeIcon", "svg")
        case .omp: ("OmpIcon", "svg")
        case .grok: ("GrokIcon", "svg")
        case .harnais: ("HarnaisIcon", "svg")
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "hexagon"
        case .gemini: "diamond.fill"
        case .antigravity: "atom"
        case .zai: "z.square.fill"
        case .copilot: "airplane"
        case .ampcode: "bolt.fill"
        case .kimi: "moon.fill"
        case .kiro: "hare.fill"
        case .cursor: "cursorarrow"
        case .minimax: "square.grid.2x2.fill"
        case .deepseek: "water.waves"
        case .vercelGateway: "triangle.fill"
        case .alibaba: "cart.fill"
        case .mistral: "wind"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .omp: "iphone"
        case .grok: "theatermasks"
        case .harnais: "point.3.connected.trianglepath.dotted"
        }
    }

    var hasInAppConfiguration: Bool {
        switch self {
        case .claude, .codex, .kimi, .copilot, .minimax, .deepseek,
             .alibaba, .vercelGateway, .zai:
            true
        default:
            false
        }
    }

    var setupInstruction: String {
        switch self {
        case .claude:
            "Install Claude Code and run `claude login`, then choose the API or CLI probe under Connection."
        case .codex:
            "Install the Codex CLI and run `codex login`, then choose the API or RPC probe under Connection."
        case .gemini:
            "Install the Gemini CLI and sign in once. Iles reads its local OAuth credentials."
        case .antigravity:
            "Open Antigravity and sign in, or install and sign in with `agy`; either the running app or its saved credentials is required."
        case .zai:
            "Install Claude Code and configure a Z.ai endpoint and token in its settings, or use the GLM token variable shown under Connection."
        case .copilot:
            "Enter your GitHub username and token under Connection, or provide the configured token environment variable."
        case .ampcode:
            "Install the Amp CLI, sign in, and confirm `amp usage` works in Terminal."
        case .kimi:
            "Install and sign in to the Kimi CLI, or choose API mode under Connection and provide a Kimi token."
        case .kiro:
            "Install `kiro-cli`, sign in, and ensure the command is available in your PATH."
        case .cursor:
            "Open Cursor and sign in once. Iles reads Cursor's local authentication database."
        case .minimax:
            "Provide a MiniMax API key under Connection or through the configured environment variable."
        case .deepseek:
            "Provide a DeepSeek API key under Connection or through the configured environment variable."
        case .vercelGateway:
            "Provide a Vercel AI Gateway API key under Connection or through the configured environment variable."
        case .alibaba:
            "Choose a region and provide either an Alibaba API key or a manual browser cookie under Connection."
        case .mistral:
            "Install Mistral Vibe and complete a session. Iles reads the local Vibe session logs."
        case .openCode:
            "Run `opencode auth login` and choose OpenCode Zen, or install `opencode` to use its local database."
        case .omp:
            "Install Oh My Pi, sign in to at least one provider, and confirm `omp usage --json` works in Terminal."
        case .grok:
            "Install the Grok CLI and sign in so its local OAuth credentials are available."
        case .harnais:
            "Add your accounts in Harnais, then refresh this source in Iles. Iles fetches usage through the Harnais account helper."
        }
    }

    func primaryQuota(in snapshot: UsageSnapshot?) -> UsageQuota? {
        ProviderQuotaPolicy.primaryQuota(providerId: id, in: snapshot)
    }

    func secondaryQuota(in snapshot: UsageSnapshot?) -> UsageQuota? {
        ProviderQuotaPolicy.secondaryQuota(providerId: id, in: snapshot)
    }
}

/// One accent policy for island graphics, previews, and detail views. Source
/// domains keep distinct but restrained identities while selection chrome stays
/// neutral throughout Settings.
enum ComplicationSourceStyle {
    static func accent(
        sourceID: String,
        descriptor: ComplicationSourceDescriptor?,
        metricIDs: [String] = []
    ) -> Color {
        if let brand = HarnaisGlance.resolvedBrand(
            sourceID: sourceID,
            metricIDs: metricIDs,
            descriptor: descriptor
        ) {
            return brand.accent
        }
        if sourceID == "system.clock" || sourceID.hasPrefix("calendar.") {
            return Color(red: 0.45, green: 0.66, blue: 1)
        }
        if sourceID == "system.battery" || sourceID.hasPrefix("system.mac") {
            return Color(red: 0.40, green: 0.82, blue: 0.64)
        }
        if sourceID.hasPrefix("session.") {
            return Color(red: 0.74, green: 0.50, blue: 1)
        }
        if sourceID.hasPrefix("productivity.") {
            return Color(red: 0.40, green: 0.82, blue: 0.78)
        }
        if sourceID.hasPrefix("developer.") {
            return Color(red: 0.95, green: 0.63, blue: 0.32)
        }
        if sourceID.hasPrefix("services.") {
            return Color(red: 0.94, green: 0.46, blue: 0.58)
        }
        if descriptor?.kind == .extensionSource {
            return Color(red: 0.45, green: 0.72, blue: 1)
        }
        return Color.white.opacity(0.82)
    }
}

struct ProviderMark: View {
    let brand: ProviderBrand
    var size: CGFloat = 26
    var zoomsOnHover = false
    var tint: NSColor = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VectorTemplateMark(resource: brand.iconResource, tint: tint)
            .frame(width: size, height: size)
            .scaleEffect(zoomsOnHover && isHovering && !reduceMotion ? 1.08 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { hovering in
                guard zoomsOnHover else { return }
                isHovering = hovering
            }
    }
}

/// Draws bundled SVG resources through AppKit's vector image representation.
/// `Image(_:bundle:)` does not resolve arbitrary SwiftPM SVG resources reliably,
/// while `Image(nsImage:)` may cache a rasterized SwiftUI representation when a
/// window crosses displays. NSImageView redraws the SVG at the active backing scale.
struct VectorTemplateMark: NSViewRepresentable {
    let resource: (name: String, ext: String)
    var tint: NSColor = .white

    func makeNSView(context: Context) -> VectorMarkContainerView {
        let view = VectorMarkContainerView()
        view.tint = tint
        view.image = VectorMarkCache.image(named: resource.name, extension: resource.ext)
        return view
    }

    func updateNSView(_ view: VectorMarkContainerView, context: Context) {
        view.tint = tint
        view.image = VectorMarkCache.image(named: resource.name, extension: resource.ext)
        view.needsDisplay = true
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: VectorMarkContainerView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? proposal.height ?? 1
        let height = proposal.height ?? proposal.width ?? 1
        return CGSize(width: width, height: height)
    }
}

final class VectorMarkContainerView: NSView {
    private let imageView = NSImageView()

    var tint: NSColor {
        get { imageView.contentTintColor ?? .white }
        set { imageView.contentTintColor = newValue }
    }

    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 1) }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.contentTintColor = .white
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshBackingScale()
    }

    private func refreshBackingScale() {
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
        }
        imageView.needsDisplay = true
        needsDisplay = true
    }
}

/// SPM's generated `Bundle.module` looks for `Iles_IlesCore.bundle` next to
/// the `.app`. Development `swift run` finds it beside the executable. A
/// packaged app also keeps a copy under `Contents/Resources`.
enum IlesResourceBundle {
    static let bundle: Bundle = resolve(applicationBundle: .main, moduleBundle: .module)

    /// Packaged apps keep `Iles_IlesCore.bundle` under `Contents/Resources`.
    /// SPM's `Bundle.module` looks next to the `.app`, which codesign rejects.
    static func resolve(applicationBundle: Bundle, moduleBundle: @autoclosure () -> Bundle) -> Bundle {
        let candidates = [
            applicationBundle.bundleURL.appendingPathComponent("Iles_IlesCore.bundle"),
            applicationBundle.resourceURL?.appendingPathComponent("Iles_IlesCore.bundle"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return moduleBundle()
    }
}

@MainActor
private enum VectorMarkCache {
    private static var images: [String: NSImage] = [:]

    static func image(named name: String, extension ext: String) -> NSImage? {
        let key = "\(name).\(ext)"
        if let image = images[key] { return image }
        guard let url = IlesResourceBundle.bundle.url(forResource: name, withExtension: ext),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        images[key] = image
        return image
    }
}
