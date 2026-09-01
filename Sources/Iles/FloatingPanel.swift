import AppKit

/// Borderless status-bar panel used for the island and the hover card.
/// Stays above normal windows and joins every Space.
final class FloatingPanel: NSPanel {
    init(size: NSSize, animates: Bool = false) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = animates ? .utilityWindow : .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
