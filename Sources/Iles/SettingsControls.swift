import SwiftUI

struct IslandToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(IslandChrome.accent)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var disabled = false
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IslandChrome.text)
            Spacer(minLength: 8)
            IslandToggle(isOn: $isOn)
                .disabled(disabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .opacity(disabled ? 0.55 : 1)
    }
}

struct IslandSegmentBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var title: (Item) -> String
    var symbol: ((Item) -> String)?
    var equalWidth = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                IslandSegmentButton(
                    title: title(item),
                    symbol: symbol?(item),
                    isSelected: item == selection,
                    equalWidth: equalWidth
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = item
                    }
                }
            }
        }
        .fixedSize(horizontal: !equalWidth, vertical: false)
        .padding(2)
        .background(IslandChrome.rowSelected, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(IslandChrome.hairline, lineWidth: 1)
        }
    }
}

private struct IslandSegmentButton: View {
    let title: String
    let symbol: String?
    let isSelected: Bool
    let equalWidth: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? IslandChrome.text : IslandChrome.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: equalWidth ? .infinity : nil)
            .fixedSize(horizontal: !equalWidth, vertical: false)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(IslandChrome.surface)
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(IslandChrome.hairline, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum SettingsButtonProminence: Equatable {
    case primary
    case secondary
    case tertiary
}

struct QuietButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    var prominence: SettingsButtonProminence = .secondary
    var compact: Bool = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var height: CGFloat { compact ? IslandChrome.smallButtonHeight : IslandChrome.buttonHeight }
    private var hPad: CGFloat { compact ? 8 : 10 }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, hPad)
            .frame(minHeight: height)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .buttonStyle(SettingsActionButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var isDestructive: Bool { role == .destructive }

    private var foreground: Color {
        if !isEnabled { return IslandChrome.secondaryText }
        if isDestructive {
            if prominence == .primary { return .white }
            return IslandChrome.error
        }
        switch prominence {
        case .primary: return .white
        case .secondary: return IslandChrome.text
        case .tertiary: return isHovering ? IslandChrome.text : IslandChrome.secondaryText
        }
    }

    private var background: Color {
        if !isEnabled { return prominence == .tertiary ? .clear : IslandChrome.rowSelected }
        if isDestructive, prominence == .primary { return IslandChrome.error }
        switch prominence {
        case .primary: return isHovering ? IslandChrome.accent.opacity(0.9) : IslandChrome.accent
        case .secondary: return isHovering ? IslandChrome.rowSelected : IslandChrome.surface
        case .tertiary: return isHovering ? IslandChrome.rowSelected : Color.clear
        }
    }

    private var border: Color {
        if !isEnabled { return prominence == .tertiary ? .clear : IslandChrome.border }
        switch prominence {
        case .primary: return Color.clear
        case .secondary: return IslandChrome.inputBorder
        case .tertiary: return isHovering ? IslandChrome.border : Color.clear
        }
    }
}

/// Disabled colors are set by QuietButton; avoid PlainButtonStyle's extra fade.
struct SettingsActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
    }
}

struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        // Keep the native continuous track. A stepped SwiftUI slider draws a
        // tick for every point on macOS, turning long ranges into a second line.
        Slider(value: Binding(
            get: { value },
            set: { proposed in
                let rounded = step > 0 ? range.lowerBound + ((proposed - range.lowerBound) / step).rounded() * step : proposed
                value = min(max(rounded, range.lowerBound), range.upperBound)
            }
        ), in: range, onEditingChanged: onEditingChanged)
            .tint(IslandChrome.accent)

    }
}

struct QuietIconButton: View {
    let symbol: String
    var accessibilityName: String? = nil
    var helpText: String? = nil
    var disabled = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovering ? IslandChrome.text : IslandChrome.secondaryText)
                .frame(width: IslandChrome.headerControlSize, height: IslandChrome.headerControlSize)
                .background(
                    isHovering ? IslandChrome.rowSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isHovering ? IslandChrome.border : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityName ?? symbol)
        .help(helpText ?? accessibilityName ?? symbol)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

struct StatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(IslandChrome.secondaryText)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(IslandChrome.fieldFill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(IslandChrome.hairline, lineWidth: 1)
            }
    }
}

struct SettingsMenuLabel: View {
    let symbol: String
    let title: String
    var value: String? = nil
    var compact = false
    var controlHeight: CGFloat? = nil
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandChrome.text)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandChrome.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandChrome.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(IslandChrome.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .frame(maxWidth: .infinity, minHeight: controlHeight ?? IslandChrome.fieldHeight)
        .background(
            isHovering ? IslandChrome.rowSelected : IslandChrome.fieldFill,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isHovering ? IslandChrome.inputBorder : IslandChrome.border,
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct SettingsPopupChrome: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .frame(minHeight: IslandChrome.fieldHeight)
            .background(
                isHovering ? IslandChrome.rowSelected : IslandChrome.fieldFill,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovering ? IslandChrome.inputBorder : IslandChrome.border,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    func settingsPopupChrome() -> some View {
        modifier(SettingsPopupChrome())
    }
}
