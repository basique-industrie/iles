import SwiftUI

/// Mounted only during a refresh; the ring stays idle between requests.
struct RingLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let lineWidth: CGFloat
    let inset: CGFloat

    var body: some View {
        Group {
            if reduceMotion {
                arc.rotationEffect(.degrees(-90))
            } else {
                RotatingLoadingArc { arc }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var arc: some View {
        Circle()
            .inset(by: inset)
            .trim(from: 0.05, to: 0.8)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: color.opacity(0.04), location: 0),
                        .init(color: color.opacity(0.3), location: 0.3),
                        .init(color: color, location: 0.8)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
    }
}

private struct RotatingLoadingArc<Content: View>: View {
    @State private var rotating = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .rotationEffect(.degrees(rotating ? 270 : -90))
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}
