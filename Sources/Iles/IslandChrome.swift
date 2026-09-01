import SwiftUI

/// Shared dark chrome for Settings and provider forms.
/// Solid fills only — no system tint, no frosted glass.
enum IslandChrome {
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10
    static let fieldRadius: CGFloat = 8
    static let pageInset: CGFloat = 16
    static let sidebarWidth: CGFloat = 252
    static let stackSpacing: CGFloat = 14
    static let headerControlSize: CGFloat = 28
    static let buttonHeight: CGFloat = 30
    static let contentMaxWidth: CGFloat = 680

    static var cardFill: Color { Color.white.opacity(0.028) }
    static var fieldFill: Color { Color.white.opacity(0.052) }
    static var selectedFill: Color { Color.white.opacity(0.08) }
    static var hoverFill: Color { Color.white.opacity(0.09) }
    static var hairline: Color { Color.white.opacity(0.08) }
    static var controlBorder: Color { Color.white.opacity(0.1) }
    static var selectionBorder: Color { Color.white.opacity(0.16) }
    static var insertMark: Color { Color.white.opacity(0.42) }
    static var sidebarFill: Color { Color.black.opacity(0.32) }
    static var secondaryText: Color { Color.white.opacity(0.68) }
    static var tertiaryText: Color { Color.white.opacity(0.52) }
}

struct PageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(IslandChrome.secondaryText)
    }
}

struct FieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(IslandChrome.secondaryText)
    }
}

struct SettingsCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandChrome.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
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
                IslandChrome.cardFill,
                in: RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous)
                    .strokeBorder(IslandChrome.hairline.opacity(0.72), lineWidth: 1)
            }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(IslandChrome.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
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
                .fill(attention ? Color.orange : Color.white.opacity(0.58))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(attention ? Color.orange.opacity(0.9) : IslandChrome.secondaryText)
            if let detail {
                Text("·")
                    .foregroundStyle(IslandChrome.tertiaryText)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandChrome.tertiaryText)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }
}
