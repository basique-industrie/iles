import Domain
import SwiftUI

struct IslandPlacementBadge: View {
  let edge: IslandEdge
  let mode: IslandPlacementMode
  let isVisible: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
        .frame(width: 18, height: 23)
      Capsule(style: .continuous)
        .fill(isVisible ? IslandChrome.text : IslandChrome.tertiaryText)
        .frame(width: 4, height: 13)
        .offset(x: edge == .leading ? -9 : 9)
      Image(systemName: edge == .leading ? "arrow.left" : "arrow.right")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(IslandChrome.tertiaryText)
        .offset(x: edge == .leading ? 3 : -3)
    }
    .frame(width: 30, height: 32)
    .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .opacity(isVisible ? 1 : 0.58)
    .help("\(edgeName) · \(modeName) placement")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(edgeName), \(modeName) placement")
  }

  private var edgeName: String { edge == .leading ? "Left edge" : "Right edge" }
  private var modeName: String { mode == .automatic ? "Automatic" : "Manual" }
}

struct WorkspaceUndo {
  let id = UUID()
  let message: String
  let action: WorkspaceUndoAction
}

enum WorkspaceUndoAction {
  case removal(ComplicationRemoval)
  case islandRemoval(IslandRemoval)
  case order(islandID: UUID, ids: [UUID])
}

struct RowActionGlyph: View {
  let symbol: String
  @State private var isHovering = false

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(isHovering ? IslandChrome.text : IslandChrome.secondaryText)
      .frame(width: 28, height: 28)
      .background(
        isHovering ? IslandChrome.hoverFill : Color.clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .onHover { isHovering = $0 }
      .animation(.easeOut(duration: 0.12), value: isHovering)
  }
}

private struct DestructiveSwipeActionModifier: ViewModifier {
  let accessibilityName: String
  let isEnabled: Bool
  let showsSeparator: Bool
  let actionWidth: CGFloat
  let actionHeight: CGFloat
  let action: () -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(action: action) {
          Image(systemName: "trash")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: actionWidth, height: actionHeight)
            .contentShape(Rectangle())
            .background(IslandChrome.error)
            .overlay(alignment: .bottom) {
              if showsSeparator {
                Rectangle()
                  .fill(IslandChrome.hairline)
                  .frame(height: 1)
              }
            }
        }
        .buttonStyle(.plain)
        .tint(.clear)
        .accessibilityLabel(accessibilityName)
        .help(accessibilityName)
      }
    } else {
      content
    }
  }
}

extension View {
  func destructiveSwipeAction(
    accessibilityName: String,
    isEnabled: Bool = true,
    showsSeparator: Bool = false,
    actionWidth: CGFloat = 84,
    actionHeight: CGFloat,
    action: @escaping () -> Void
  ) -> some View {
    modifier(
      DestructiveSwipeActionModifier(
        accessibilityName: accessibilityName,
        isEnabled: isEnabled,
        showsSeparator: showsSeparator,
        actionWidth: actionWidth,
        actionHeight: actionHeight,
        action: action
      ))
  }
}

struct ComplicationDropDelegate: DropDelegate {
  let targetID: UUID
  let draggedID: UUID?
  let setTargeted: (Bool) -> Void
  let move: (UUID, UUID) -> Void
  let finish: () -> Void

  func validateDrop(info: DropInfo) -> Bool { draggedID != nil }

  func dropEntered(info: DropInfo) {
    guard let draggedID, draggedID != targetID else { return }
    setTargeted(true)
    move(draggedID, targetID)
  }

  func dropExited(info: DropInfo) { setTargeted(false) }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    setTargeted(false)
    guard draggedID != nil else { return false }
    finish()
    return true
  }
}
