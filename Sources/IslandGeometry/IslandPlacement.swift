import Foundation

/// Vertical slot of the island on the right screen edge.
///
/// `topGap` is the space under the menu bar. Command-drag changes it;
/// the island stays glued to the trailing edge.
public enum IslandPlacement: Sendable {
    public static let bottomGap: CGFloat = 16

    public static func clampedTopGap(
        _ gap: CGFloat,
        islandHeight: CGFloat,
        visibleHeight: CGFloat
    ) -> CGFloat {
        let minGap = IslandMetrics.topGap
        let maxGap = max(minGap, visibleHeight - islandHeight - bottomGap)
        return min(max(gap, minGap), maxGap)
    }

    /// Mouse up (positive AppKit delta) moves the island up, so the top gap shrinks.
    public static func topGap(
        movingFrom startGap: CGFloat,
        mouseDeltaY: CGFloat,
        islandHeight: CGFloat,
        visibleHeight: CGFloat
    ) -> CGFloat {
        clampedTopGap(
            startGap - mouseDeltaY,
            islandHeight: islandHeight,
            visibleHeight: visibleHeight
        )
    }

    public static func originY(
        topGap: CGFloat,
        islandHeight: CGFloat,
        visibleMaxY: CGFloat
    ) -> CGFloat {
        visibleMaxY - islandHeight - topGap
    }
}
