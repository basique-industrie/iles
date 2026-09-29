import AppKit
import Infrastructure

/// Two compact islands, drawn at menu-bar scale with a distinct Dev tint.
@MainActor
public enum MenuBarIdentityIcon {
    public static func image(for identity: AppIdentity = .current) -> NSImage {
        let color: NSColor = identity.isDevelopment ? .systemOrange : .black
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 6, height: 14),
                         xRadius: 3, yRadius: 3).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 5, width: 6, height: 8),
                         xRadius: 3, yRadius: 3).fill()
            return true
        }
        image.isTemplate = !identity.isDevelopment
        image.accessibilityDescription = identity.displayName
        return image
    }
}
