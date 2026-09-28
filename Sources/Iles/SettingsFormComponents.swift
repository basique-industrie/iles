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
            .padding(.horizontal, IslandChrome.pageInset)
            .padding(.vertical, IslandChrome.pageInset)
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
                .fill(ok ? IslandChrome.success : IslandChrome.error)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            SettingsCaption(text: ok ? okText : failText)
        }
    }
}

enum SettingsNoticeStyle {
    case information
    case warning
    case error
    case success

    var symbol: String {
        switch self {
        case .information: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        case .success: "checkmark.circle"
        }
    }

    var foreground: Color {
        switch self {
        case .information: IslandChrome.secondaryText
        case .warning: IslandChrome.warning
        case .error: IslandChrome.error
        case .success: IslandChrome.success
        }
    }
}

struct SettingsNotice: View {
    let text: String
    var style: SettingsNoticeStyle = .information

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(style.foreground)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            IslandChrome.fieldFill,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(IslandChrome.border, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: title)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandChrome.text)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandChrome.error)
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
        VStack(alignment: .leading, spacing: 4) {
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandChrome.text)
                .focused($isFocused)
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
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
            .frame(minHeight: IslandChrome.fieldHeight)
            .background(
                IslandChrome.fieldFill,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(IslandChrome.border, lineWidth: 1)
            }
    }
}

struct SettingsPageHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                PageTitle(title: title)
                if let subtitle { SettingsCaption(text: subtitle) }
            }
            Spacer(minLength: 12)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsPageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actions = { EmptyView() }
    }
}
