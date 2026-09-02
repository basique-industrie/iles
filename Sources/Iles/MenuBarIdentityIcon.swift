import AppKit
import Infrastructure

/// Menu extra mark. Shipped Iles stays a template symbol; Iles Dev is the same
/// symbol tinted orange, without stretching it into a larger canvas.
@MainActor
public enum MenuBarIdentityIcon {
    public static let symbolName = "circle.hexagonpath.fill"

    public static func applyDevelopmentTintIfNeeded() {
        guard AppIdentity.current.isDevelopment else { return }
        for window in NSApp.windows {
            apply(in: window.contentView)
        }
    }

    private static func apply(in view: NSView?) {
        guard let view else { return }
        if let button = view as? NSStatusBarButton, let current = button.image, current.isTemplate {
            button.image = tinted(current, color: .systemOrange)
        }
        for subview in view.subviews {
            apply(in: subview)
        }
    }

    /// Recolors a template mark at its existing size so the Dev extra matches shipped Iles.
    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let tinted = NSImage(size: size)
        tinted.addRepresentation(rep)
        tinted.isTemplate = false
        return tinted
    }
}
