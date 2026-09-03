import AppKit
import Infrastructure

/// Menu extra mark. Shipped Iles stays a template symbol; Iles Dev is the same
/// symbol tinted orange, without stretching it into a larger canvas.
///
/// SwiftUI `MenuBarExtra` ignores `foregroundStyle` and will restore a template
/// image after launch, so the color is applied on the `NSStatusBarButton` and
/// reapplied when that image changes.
@MainActor
public enum MenuBarIdentityIcon {
    public static let symbolName = "circle.hexagonpath.fill"

    private static var monitor: Monitor?

    public static func applyDevelopmentTintIfNeeded() {
        guard AppIdentity.current.isDevelopment else { return }
        if monitor == nil {
            monitor = Monitor()
            monitor?.start()
        }
        monitor?.apply()
    }

    /// Recolors a template mark at its existing size so the Dev extra matches shipped Iles.
    fileprivate static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
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

@MainActor
private final class Monitor {
    private var observations: [NSKeyValueObservation] = []
    private var observedButtons = Set<ObjectIdentifier>()
    private var tintedImages: [ObjectIdentifier: NSImage] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var retry: Task<Void, Never>?

    func start() {
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.apply()
                }
            }
        )
        retry = Task { @MainActor [weak self] in
            for delay in [0, 50, 150, 400, 800, 1600, 3000] as [UInt64] {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                self?.apply()
            }
        }
    }

    func apply() {
        for button in statusBarButtons() {
            tint(button)
            observe(button)
        }
    }

    private func tint(_ button: NSStatusBarButton) {
        button.contentTintColor = .systemOrange
        guard let current = button.image else { return }
        let id = ObjectIdentifier(button)
        if let existing = tintedImages[id], current === existing {
            return
        }
        let tinted = MenuBarIdentityIcon.tinted(current, color: .systemOrange)
        tintedImages[id] = tinted
        button.image = tinted
    }

    private func observe(_ button: NSStatusBarButton) {
        let id = ObjectIdentifier(button)
        guard !observedButtons.contains(id) else { return }
        observedButtons.insert(id)
        observations.append(button.observe(\.image, options: [.new]) { [weak self] button, _ in
            Task { @MainActor in
                self?.tint(button)
            }
        })
    }

    private func statusBarButtons() -> [NSStatusBarButton] {
        var found: [NSStatusBarButton] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ button: NSStatusBarButton?) {
            guard let button else { return }
            let id = ObjectIdentifier(button)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            found.append(button)
        }

        for item in statusItems() {
            add(item.button)
        }
        for window in NSApp.windows {
            walk(window.contentView, add: add)
            walk(window.contentView?.superview, add: add)
        }
        return found
    }

    private func walk(_ view: NSView?, add: (NSStatusBarButton?) -> Void) {
        guard let view else { return }
        add(view as? NSStatusBarButton)
        for subview in view.subviews {
            walk(subview, add: add)
        }
    }

    /// `NSStatusBar` does not publish its items. The getter exists on macOS and
    /// is how this process finds its own `MenuBarExtra` button.
    private func statusItems() -> [NSStatusItem] {
        let bar = NSStatusBar.system
        let selector = NSSelectorFromString("items")
        guard bar.responds(to: selector) else { return [] }
        guard let object = bar.perform(selector)?.takeUnretainedValue() else { return [] }
        return (object as? [NSStatusItem]) ?? []
    }
}
