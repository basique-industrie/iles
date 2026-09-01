import SwiftUI

struct IslandToggle: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? Color.white.opacity(0.48) : Color.white.opacity(0.1))
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .brightness(isHovering && isEnabled ? 0.08 : 0)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            IslandToggle(isOn: $isOn)
                .disabled(disabled)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 2)
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
        .padding(3)
        .background(Color.black.opacity(0.35), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
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
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? Color.white : IslandChrome.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: equalWidth ? .infinity : nil)
            .fixedSize(horizontal: !equalWidth, vertical: false)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(IslandChrome.selectedFill)
                }
            }
            .contentShape(Capsule())
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
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: IslandChrome.buttonHeight)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var foreground: Color {
        if role == .destructive { return isHovering ? Color.red.opacity(0.95) : Color.red.opacity(0.72) }
        switch prominence {
        case .primary: return .white
        case .secondary: return isHovering ? .white : IslandChrome.secondaryText
        case .tertiary: return isHovering ? .white : IslandChrome.tertiaryText
        }
    }

    private var background: Color {
        if isHovering { return Color.white.opacity(prominence == .primary ? 0.18 : 0.08) }
        switch prominence {
        case .primary: return Color.white.opacity(0.13)
        case .secondary: return Color.clear
        case .tertiary: return Color.clear
        }
    }

    private var border: Color {
        switch prominence {
        case .primary: return Color.white.opacity(isHovering ? 0.28 : 0.2)
        case .secondary: return isHovering ? IslandChrome.controlBorder : Color.clear
        case .tertiary: return isHovering ? IslandChrome.controlBorder : Color.clear
        }
    }
}

struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var isEditing = false

    var body: some View {
        GeometryReader { proxy in
            let thumbSize: CGFloat = 16
            let travel = max(proxy.size.width - thumbSize, 1)
            let thumbCenter = thumbSize / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(IslandChrome.controlBorder)
                    .frame(height: 5)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.48))
                    .frame(width: max(thumbCenter, 5), height: 5)
                Circle()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .position(x: thumbCenter, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isEditing {
                            isEditing = true
                            onEditingChanged(true)
                        }
                        setFraction((gesture.location.x - thumbSize / 2) / travel)
                    }
                    .onEnded { _ in
                        guard isEditing else { return }
                        isEditing = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 20)
        .onDisappear {
            guard isEditing else { return }
            isEditing = false
            onEditingChanged(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Top spacing")
        .accessibilityValue("\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            onEditingChanged(true)
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private func setFraction(_ fraction: CGFloat) {
        let clamped = min(max(Double(fraction), 0), 1)
        setValue(range.lowerBound + clamped * (range.upperBound - range.lowerBound))
    }

    private func setValue(_ proposed: Double) {
        let stepped = range.lowerBound
            + ((proposed - range.lowerBound) / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Color.white : IslandChrome.secondaryText)
                .frame(width: IslandChrome.headerControlSize, height: IslandChrome.headerControlSize)
                .background(
                    isHovering ? IslandChrome.hoverFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                        .strokeBorder(isHovering ? IslandChrome.controlBorder : Color.clear, lineWidth: 1)
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(IslandChrome.secondaryText)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(IslandChrome.fieldFill, in: Capsule(style: .continuous))
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
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .background(IslandChrome.selectedFill, in: Circle())
            Text(title)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandChrome.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .foregroundStyle(isHovering ? Color.white : IslandChrome.secondaryText)
                .frame(width: compact ? 19 : 22, height: compact ? 19 : 22)
                .background(Color.white.opacity(isHovering ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, compact ? 6 : 9)
        .frame(maxWidth: .infinity, minHeight: controlHeight ?? (compact ? 30 : 36))
        .background(
            Color.white.opacity(isHovering ? 0.11 : (compact ? 0.075 : 0.06)),
            in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                .strokeBorder(
                    isHovering || compact ? IslandChrome.selectionBorder : IslandChrome.controlBorder,
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct SettingsPopupChrome: ViewModifier {
    let compact: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .frame(minHeight: compact ? 30 : 36)
            .background(
                Color.white.opacity(isHovering ? 0.11 : 0.08),
                in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.white.opacity(0.24) : IslandChrome.selectionBorder,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    func settingsPopupChrome(compact: Bool = false) -> some View {
        modifier(SettingsPopupChrome(compact: compact))
    }
}
