import AppKit
import Domain
import Infrastructure
import IslandGeometry
import SwiftUI

enum EmptyWorkspaceHintMetrics {
    static let width: CGFloat = 196
    static let height: CGFloat = 36
    static let gap: CGFloat = 8
}

/// One-shot first-run callout beside the empty-workspace plus.
enum EmptyWorkspaceHint {
    static var isVisible: Bool {
        !JSONSettingsRepository.shared.emptyWorkspaceHintDismissed()
    }

    static func dismiss() {
        guard isVisible else { return }
        JSONSettingsRepository.shared.setEmptyWorkspaceHintDismissed(true)
        NotificationCenter.default.post(name: .emptyWorkspaceHintDidChange, object: nil)
    }

    static func frame(relativeTo plus: NSRect, edge: IslandEdge) -> NSRect {
        let size = NSSize(width: EmptyWorkspaceHintMetrics.width, height: EmptyWorkspaceHintMetrics.height)
        let x: CGFloat = switch edge {
        case .trailing: plus.minX - EmptyWorkspaceHintMetrics.gap - size.width
        case .leading: plus.maxX + EmptyWorkspaceHintMetrics.gap
        }
        return NSRect(
            x: x,
            y: plus.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct EmptyWorkspaceHintView: View {
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Text("Click to add an island.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandChrome.tertiaryText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(width: EmptyWorkspaceHintMetrics.width, height: EmptyWorkspaceHintMetrics.height)
        .background {
            Capsule(style: .continuous)
                .fill(IslandPalette.surface)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Click to add an island")
    }
}
