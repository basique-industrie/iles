import AppKit
import SwiftUI

/// Keeps SwiftUI and AppKit layer rasterization aligned when a window moves
/// between displays with different backing scales.
@MainActor
final class ScaleAwareHostingView<Content: View>: NSHostingView<Content> {
    private var scaleSyncTask: Task<Void, Never>?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        synchronizeBackingScale()
    }

    private func synchronizeBackingScale() {
        guard let scale = window?.backingScaleFactor else { return }
        apply(scale: scale, to: layer)
        needsLayout = true
        needsDisplay = true

        // SwiftUI may replace render layers shortly after the AppKit callback.
        // Resynchronize a few subsequent frames, rather than recursively walking
        // the entire Settings layer tree on every layout and slider movement.
        scaleSyncTask?.cancel()
        scaleSyncTask = Task { @MainActor [weak self] in
            await Task.yield()
            for delay in [0, 16, 80] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled,
                      let self,
                      self.window?.backingScaleFactor == scale
                else { return }
                self.apply(scale: scale, to: self.layer)
                self.layer?.setNeedsDisplay()
            }
        }
    }

    private func apply(scale: CGFloat, to layer: CALayer?) {
        guard let layer else { return }
        layer.contentsScale = scale
        layer.rasterizationScale = scale
        layer.sublayers?.forEach { apply(scale: scale, to: $0) }
    }
}
