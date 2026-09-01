import AppKit
import SwiftUI

/// Right-edge macOS island.
///
/// One continuous S at each end: an inset curve at the bezel flowing into a
/// rounded outer corner. Each half follows a quintic Bézier that targets zero
/// curvature at the straight edges and central inflection, then renders through
/// a subpixel-accurate cubic approximation supported by SwiftUI's `Path`.
public struct IslandShape: Shape {
    public var mirrored: Bool

    public init(mirrored: Bool = false) {
        self.mirrored = mirrored
    }

    public func path(in rect: CGRect) -> Path {
        let rightEdgePath = rightEdgePath(in: rect)
        guard mirrored else { return rightEdgePath }
        return rightEdgePath.applying(
            CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0)
                .scaledBy(x: -1, y: 1)
        )
    }

    private func rightEdgePath(in rect: CGRect) -> Path {
        let j = IslandMetrics.joinDepth
        let outer = IslandMetrics.outerRadius
        let step = IslandMetrics.curveStep
        let doubleStep = step * 2
        var path = Path()

        let topInflection = CGPoint(x: rect.maxX - outer, y: rect.minY + outer)
        let topEnd = CGPoint(x: rect.minX, y: rect.minY + j)
        let bottomStart = CGPoint(x: rect.minX, y: rect.maxY - j)
        let bottomInflection = CGPoint(x: rect.maxX - outer, y: rect.maxY - outer)

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))

        addQuinticCurve(
            to: &path,
            points: [
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + step),
                CGPoint(x: rect.maxX, y: rect.minY + doubleStep),
                CGPoint(x: topInflection.x + doubleStep, y: topInflection.y),
                CGPoint(x: topInflection.x + step, y: topInflection.y),
                topInflection,
            ]
        )
        addQuinticCurve(
            to: &path,
            points: [
                topInflection,
                CGPoint(x: topInflection.x - step, y: topInflection.y),
                CGPoint(x: topInflection.x - doubleStep, y: topInflection.y),
                CGPoint(x: rect.minX, y: topEnd.y - doubleStep),
                CGPoint(x: rect.minX, y: topEnd.y - step),
                topEnd,
            ]
        )

        path.addLine(to: bottomStart)

        addQuinticCurve(
            to: &path,
            points: [
                bottomStart,
                CGPoint(x: rect.minX, y: bottomStart.y + step),
                CGPoint(x: rect.minX, y: bottomStart.y + doubleStep),
                CGPoint(x: bottomInflection.x - doubleStep, y: bottomInflection.y),
                CGPoint(x: bottomInflection.x - step, y: bottomInflection.y),
                bottomInflection,
            ]
        )
        addQuinticCurve(
            to: &path,
            points: [
                bottomInflection,
                CGPoint(x: bottomInflection.x + step, y: bottomInflection.y),
                CGPoint(x: bottomInflection.x + doubleStep, y: bottomInflection.y),
                CGPoint(x: rect.maxX, y: rect.maxY - doubleStep),
                CGPoint(x: rect.maxX, y: rect.maxY - step),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// Core Graphics supports cubic curves, so approximate the quintic with
    /// short cubic Hermite segments while preserving its positions and tangents.
    private func addQuinticCurve(to path: inout Path, points: [CGPoint]) {
        precondition(points.count == 6)
        let subdivisions = 3
        let delta = 1 / CGFloat(subdivisions)

        for index in 1...subdivisions {
            let startT = CGFloat(index - 1) * delta
            let endT = CGFloat(index) * delta
            let start = quinticPoint(at: startT, points: points)
            let end = quinticPoint(at: endT, points: points)
            let startDerivative = quinticDerivative(at: startT, points: points)
            let endDerivative = quinticDerivative(at: endT, points: points)
            let scale = delta / 3

            path.addCurve(
                to: end,
                control1: CGPoint(
                    x: start.x + startDerivative.x * scale,
                    y: start.y + startDerivative.y * scale
                ),
                control2: CGPoint(
                    x: end.x - endDerivative.x * scale,
                    y: end.y - endDerivative.y * scale
                )
            )
        }
    }

    private func quinticPoint(at t: CGFloat, points: [CGPoint]) -> CGPoint {
        let u = 1 - t
        let weights = [
            u * u * u * u * u,
            5 * u * u * u * u * t,
            10 * u * u * u * t * t,
            10 * u * u * t * t * t,
            5 * u * t * t * t * t,
            t * t * t * t * t,
        ]
        return CGPoint(
            x: zip(points, weights).reduce(0) { $0 + $1.0.x * $1.1 },
            y: zip(points, weights).reduce(0) { $0 + $1.0.y * $1.1 }
        )
    }

    private func quinticDerivative(at t: CGFloat, points: [CGPoint]) -> CGPoint {
        let u = 1 - t
        let weights = [
            u * u * u * u,
            4 * u * u * u * t,
            6 * u * u * t * t,
            4 * u * t * t * t,
            t * t * t * t,
        ]
        let differences = zip(points.dropFirst(), points).map { next, previous in
            CGPoint(x: next.x - previous.x, y: next.y - previous.y)
        }
        return CGPoint(
            x: 5 * zip(differences, weights).reduce(0) { $0 + $1.0.x * $1.1 },
            y: 5 * zip(differences, weights).reduce(0) { $0 + $1.0.y * $1.1 }
        )
    }
}

/// Rounded card with a triangular pointer on the trailing edge.
public struct PopoverBubbleShape: Shape {
    public var cornerRadius: CGFloat = 14
    public var pointerSize: CGSize = CGSize(width: 7, height: 12)
    public var pointerY: CGFloat = 40
    public var pointerOnTrailingEdge: Bool = true

    public init(
        cornerRadius: CGFloat = 14,
        pointerSize: CGSize = CGSize(width: 7, height: 12),
        pointerY: CGFloat = 40,
        pointerOnTrailingEdge: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.pointerSize = pointerSize
        self.pointerY = pointerY
        self.pointerOnTrailingEdge = pointerOnTrailingEdge
    }

    public func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: pointerOnTrailingEdge ? rect.minX : rect.minX + pointerSize.width,
            y: rect.minY,
            width: rect.width - pointerSize.width,
            height: rect.height
        )
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)

        let clampedY = min(max(pointerY, cornerRadius + 10), body.height - cornerRadius - 10)
        var pointer = Path()
        let baseX = pointerOnTrailingEdge ? body.maxX - 0.5 : body.minX + 0.5
        let tipX = pointerOnTrailingEdge ? rect.maxX : rect.minX
        pointer.move(to: CGPoint(x: baseX, y: clampedY - pointerSize.height / 2))
        pointer.addLine(to: CGPoint(x: tipX, y: clampedY))
        pointer.addLine(to: CGPoint(x: baseX, y: clampedY + pointerSize.height / 2))
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
    }
}

public enum IslandPalette {
    public static let surface = Color.black
    public static let track = Color(red: 63 / 255, green: 63 / 255, blue: 61 / 255)
    public static let iconWell = Color(red: 53 / 255, green: 54 / 255, blue: 49 / 255)
    public static let label = Color(red: 125 / 255, green: 131 / 255, blue: 131 / 255)
    public static let popover = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    public static let popoverNSColor = NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
    public static let claude = Color(red: 1, green: 77 / 255, blue: 0)
    public static let codex = Color(red: 46 / 255, green: 229 / 255, blue: 118 / 255)
    public static let cursor = Color(red: 212 / 255, green: 1, blue: 0)
}

public enum IslandMetrics {
    public static let width: CGFloat = 48
    public static let outerRadius: CGFloat = 24
    /// Control-point spacing for the continuous S profile. This is deliberately
    /// separate from the visible outer radius: it tunes curvature, not bounds.
    public static let curveStep: CGFloat = 7
    public static let joinDepth: CGFloat = 48
    public static let topPadding: CGFloat = 32
    public static let topGap: CGFloat = 8
    public static let ringSize: CGFloat = 24
    public static let ringStroke: CGFloat = 3
    public static let accentStroke: CGFloat = 2.5
    public static let dualRingInnerSize: CGFloat = 16
    public static let dualRingInnerStroke: CGFloat = 2
    public static let dualRingInnerAccentStroke: CGFloat = 2
    public static let clusterMiddleSize: CGFloat = 16
    public static let clusterInnerSize: CGFloat = 8
    /// Trio rings use the same visual weight as a single progress ring.
    public static let clusterRingStroke: CGFloat = ringStroke
    public static let clusterAccentStroke: CGFloat = accentStroke
    public static let markSize: CGFloat = 10
    public static let ringLabelSpacing: CGFloat = 4
    public static let ringLabelHeight: CGFloat = 12
    public static let itemSpacing: CGFloat = 12
    public static let itemHeight: CGFloat = 44
    public static let providerWindowWidth: CGFloat = 268
    public static let providerWindowHeight: CGFloat = 176
    public static let providerWindowGap: CGFloat = 8
    /// Pointer width reserved on the trailing edge of the hover card.
    public static let providerWindowPointerWidth: CGFloat = 7
    /// Extra height inset so the body sits inside the bubble, not the pointer.
    public static let providerWindowBodyInset: CGFloat = 6

    public static var leadingInset: CGFloat { (width - ringSize) / 2 }

    public static var ringCenterOffset: CGFloat {
        let contentHeight = ringSize + ringLabelSpacing + ringLabelHeight
        return (itemHeight - contentHeight) / 2 + ringSize / 2
    }

    public static func height(forProviderCount count: Int) -> CGFloat {
        let n = max(count, 0)
        guard n > 0 else { return joinDepth * 2 }
        let content = topPadding * 2 + itemHeight * CGFloat(n) + itemSpacing * CGFloat(n - 1)
        return max(content, joinDepth * 2)
    }

    /// Largest provider count whose island still fits `maxHeight`.
    public static func maxProviderCount(forHeight maxHeight: CGFloat) -> Int {
        let usable = maxHeight - topPadding * 2
        guard usable >= itemHeight else { return 0 }
        return max(0, Int(floor((usable + itemSpacing) / (itemHeight + itemSpacing))))
    }

    public static func ringCenterY(index: Int) -> CGFloat {
        topPadding + CGFloat(index) * (itemHeight + itemSpacing) + ringCenterOffset
    }

    /// Catches metric drift that would clip rings or un-center them.
    public static func assertLayoutInvariants() {
        precondition(leadingInset * 2 + ringSize == width, "rings must be centered in island width")
        precondition(outerRadius == width / 2, "outer radius must follow the island width")
        precondition(joinDepth == outerRadius * 2, "S-join must follow the outer radius scale")
        precondition(curveStep > 0 && curveStep * 2 < outerRadius, "curve controls must fit inside the outer radius")
        precondition(ringSize > markSize, "provider mark must fit inside the ring")
        precondition(accentStroke <= ringStroke, "progress stroke must fit over the ring track")
        let dualRingCenterlineGap = (
            (ringSize - ringStroke) - (dualRingInnerSize - dualRingInnerStroke)
        ) / 2
        let dualRingVisibleGap = dualRingCenterlineGap - (ringStroke + dualRingInnerStroke) / 2
        precondition(dualRingVisibleGap >= 1, "dual-ring strokes must remain visually separate")
        precondition(
            dualRingInnerSize - dualRingInnerStroke * 2 >= markSize + 2,
            "dual-ring center mark needs optical clearance"
        )
        let clusterSizes = [ringSize, clusterMiddleSize, clusterInnerSize]
        for pair in zip(clusterSizes, clusterSizes.dropFirst()) {
            let visibleGap = (pair.0 - pair.1) / 2 - clusterRingStroke
            precondition(visibleGap >= 1, "trio-ring strokes must remain visually separate")
        }
        precondition(clusterRingStroke == ringStroke, "trio and single rings must share track weight")
        precondition(clusterAccentStroke == accentStroke, "trio and single rings must share progress weight")
        precondition(
            ringSize + ringLabelSpacing + ringLabelHeight <= itemHeight,
            "ring and label must fit inside each item"
        )
        precondition(height(forProviderCount: 3) == topPadding * 2 + itemHeight * 3 + itemSpacing * 2)
        precondition(maxProviderCount(forHeight: height(forProviderCount: 3)) == 3)
    }
}
