import AppKit
import Infrastructure

/// Menu extra mark. Shipped Iles stays a template symbol; Iles Dev is the same
/// symbol tinted orange, without stretching it into a larger canvas.
@MainActor
public enum MenuBarIdentityIcon {
    public static let symbolName = "circle.hexagonpath.fill"

    public static func image(for identity: AppIdentity = .current) -> NSImage {
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: identity.displayName)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let sized = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let configured = symbol.withSymbolConfiguration(sized) ?? symbol
        guard identity.isDevelopment else {
            let image = (configured.copy() as? NSImage) ?? configured
            image.isTemplate = true
            return image
        }
        return tinted(configured, color: .systemOrange)
    }

    /// Recolors a template mark at its existing size so the Dev extra matches shipped Iles.
    static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
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
