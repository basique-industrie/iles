import AppKit
import SwiftUI

/// Shared adaptive colors and spacing for Settings.
enum IslandChrome {
    // MARK: Metrics (Harnais)
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 8
    static let pageInset: CGFloat = 24
    static let stackSpacing: CGFloat = 24
    static let headerControlSize: CGFloat = 28
    static let buttonHeight: CGFloat = 28
    static let smallButtonHeight: CGFloat = 24
    static let fieldHeight: CGFloat = 28
    static let sidebarWidth: CGFloat = 260
    static let pageTop: CGFloat = 16
    static let pageBottom: CGFloat = 32

    // MARK: Adaptive helpers
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNS(light: light, dark: dark))
    }

    static func adaptiveNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func white(_ a: CGFloat) -> NSColor {
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: a)
    }

    // MARK: Harnais tokens
    static var sidebar: Color {
        adaptive(light: rgb(250, 250, 250), dark: rgb(17, 17, 17))
    }

    static var background: Color {
        adaptive(light: rgb(252, 252, 252), dark: rgb(10, 10, 10))
    }

    static var surface: Color {
        adaptive(light: rgb(255, 255, 255), dark: rgb(17, 17, 17))
    }

    static var track: Color {
        adaptive(light: rgb(228, 228, 231), dark: white(0.12))
    }

    static var text: Color {
        adaptive(light: rgb(39, 39, 42), dark: rgb(245, 245, 245))
    }

    static var border: Color {
        adaptive(light: rgb(228, 228, 231), dark: white(0.06))
    }

    static var inputBorder: Color {
        adaptive(light: rgb(212, 212, 216), dark: white(0.08))
    }

    static var accent: Color {
        adaptive(light: rgb(27, 78, 216), dark: rgb(52, 107, 241))
    }

    static var success: Color {
        adaptive(light: rgb(16, 185, 129), dark: rgb(52, 211, 153))
    }

    static var warning: Color {
        adaptive(light: rgb(245, 158, 11), dark: rgb(245, 158, 11))
    }

    static var error: Color {
        adaptive(light: rgb(239, 68, 68), dark: rgb(248, 113, 113))
    }

    static var backgroundNSColor: NSColor {
        adaptiveNS(light: rgb(252, 252, 252), dark: rgb(10, 10, 10))
    }

    static var sidebarNSColor: NSColor {
        adaptiveNS(light: rgb(250, 250, 250), dark: rgb(17, 17, 17))
    }

    static var rowSelected: Color {
        adaptive(light: rgb(244, 244, 245), dark: white(0.04))
    }

    static var rowHover: Color {
        adaptive(light: rgb(250, 250, 250), dark: white(0.03)).opacity(0.25)
    }

    // MARK: Component colors
    static var cardFill: Color {
        adaptive(light: white(0.40), dark: rgb(17, 17, 17, 0.40))
    }

    static var fieldFill: Color {
        adaptive(light: rgb(255, 255, 255), dark: white(0.08))
    }

    static var selectedFill: Color { rowSelected }

    static var hoverFill: Color { rowHover }

    static var hairline: Color {
        adaptive(light: rgb(228, 228, 231, 0.60), dark: white(0.036))
    }

    static var controlBorder: Color { border }
    static var selectionBorder: Color { inputBorder }
    static var insertMark: Color { accent }
    static var sidebarFill: Color { sidebar }
    static var secondaryText: Color {
        adaptive(light: rgb(113, 113, 122), dark: rgb(129, 129, 129))
    }

    static var tertiaryText: Color {
        adaptive(light: rgb(113, 113, 122), dark: rgb(129, 129, 129))
    }

}

struct PageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(IslandChrome.text)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(IslandChrome.secondaryText)
    }
}

struct FieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(IslandChrome.secondaryText)
    }
}

struct SettingsCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(IslandChrome.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MetricPair: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(IslandChrome.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandChrome.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct IslandCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                IslandChrome.surface,
                in: RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous)
                    .strokeBorder(IslandChrome.hairline, lineWidth: 1)
            }

    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title: title)
                if let subtitle {
                    SettingsCaption(text: subtitle)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDisclosure<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @State private var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        expanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        _isExpanded = State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(IslandChrome.text)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(IslandChrome.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandChrome.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsStatusLine: View {
    let title: String
    var detail: String? = nil
    var attention = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(attention ? IslandChrome.warning : IslandChrome.tertiaryText)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(attention ? IslandChrome.warning : IslandChrome.secondaryText)
            if let detail {
                Text("·")
                    .foregroundStyle(IslandChrome.tertiaryText)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IslandChrome.tertiaryText)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }
}
