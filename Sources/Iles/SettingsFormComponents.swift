import SwiftUI

struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(IslandChrome.hairline)
            .frame(height: 1)
    }
}

struct SettingsPage<Content: View>: View {
    var maxWidth: CGFloat
    var alignment: Alignment
    @ViewBuilder var content: () -> Content

    init(
        maxWidth: CGFloat = IslandChrome.contentMaxWidth,
        alignment: Alignment = .topLeading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IslandChrome.stackSpacing) {
                content()
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(IslandChrome.pageInset)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .scrollIndicators(.hidden)
    }
}

struct CredentialNote: View {
    let ok: Bool
    let okText: String
    let failText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(Color.white.opacity(ok ? 0.55 : 0.2))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            SettingsCaption(text: ok ? okText : failText)
        }
    }
}

enum SettingsNoticeStyle {
    case information
    case warning

    var symbol: String {
        switch self {
        case .information: "info.circle"
        case .warning: "exclamationmark.triangle"
        }
    }

    var foreground: Color {
        switch self {
        case .information: IslandChrome.secondaryText
        case .warning: Color.orange.opacity(0.9)
        }
    }
}

struct SettingsNotice: View {
    let text: String
    var style: SettingsNoticeStyle = .information

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(style.foreground)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            IslandChrome.fieldFill,
            in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
        }
    }
}

struct IslandTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String
    var validationMessage: String? = nil
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .islandFieldChrome()
                .focused($isFocused)
                .onSubmit(commitIfNeeded)
                .onChange(of: text) { old, new in
                    if old != new { isDirty = true }
                }
                .onChange(of: isFocused) { old, new in
                    if old, !new { commitIfNeeded() }
                }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
    }

    private func commitIfNeeded() {
        guard isDirty else { return }
        onCommit()
        isDirty = false
    }
}

struct IslandSecretField: View {
    let title: String
    @Binding var text: String
    @Binding var reveal: Bool
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            HStack(spacing: 8) {
                Group {
                    if reveal {
                        TextField(title, text: $text)
                    } else {
                        SecureField(title, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused($isFocused)
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IslandChrome.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Hide secret" : "Show secret")
                .help(reveal ? "Hide secret" : "Show secret")
            }
            .islandFieldChrome()
            .onSubmit(commitIfNeeded)
            .onChange(of: text) { old, new in
                if old != new { isDirty = true }
            }
            .onChange(of: isFocused) { old, new in
                if old, !new { commitIfNeeded() }
            }
        }
    }

    private func commitIfNeeded() {
        guard isDirty else { return }
        onCommit()
        isDirty = false
    }
}

private extension View {
    func islandFieldChrome() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                IslandChrome.fieldFill,
                in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
    }
}
