import SwiftUI

/// Small, deterministic stars follow the filled arc rather than the empty track.
struct AstraRingSparkles: View {
    let progress: Double
    let ringSize: CGFloat
    let lineWidth: CGFloat
    /// Frame to draw in: the ring's full frame, so the overlay never spills
    /// past what the host will clip. `ringSize` stays the orbit diameter.
    let canvasSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    // White stars vanish against a light panel; take the palette instead.
    private var starColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.45, green: 0.16, blue: 0.80)
    }

    // The dock ring is on screen for as long as the dock is, so it runs at a
    // lower rate and skips the blurred halos, which are the expensive part.
    private var isCompact: Bool { ringSize < 45 }
    private var frameInterval: Double { isCompact ? 1.0 / 12.0 : 1.0 / 18.0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval,
                                paused: reduceMotion || !isVisible)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                drawStars(context: &context, size: size, time: time, color: starColor)
            }
        }
        // Matches RippleRings in the host: composite the animated canvas into a
        // single Metal-backed texture instead of recompositing it per frame.
        .drawingGroup()
        .frame(width: canvasSize, height: canvasSize)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize, time: Double, color: Color) {
        let count = isCompact ? 5 : 12
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = ringSize / 2
        for index in 0..<count {
            let seed = Double(index) * 2.39996
            let pulse = (sin(time * (1.3 + Double(index % 3) * 0.25) + seed) + 1) / 2
            let position = (Double(index) + 0.5 + 0.18 * sin(time * 0.35 + seed)) / Double(count)
            let angle = position * progress * .pi * 2 - .pi / 2
            let orbit: CGFloat = radius + CGFloat(sin(seed)) * lineWidth * 0.22
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * orbit,
                                y: center.y + CGFloat(sin(angle)) * orbit)
            let arm: CGFloat = max(1.1, lineWidth * 0.38) * CGFloat(0.65 + pulse * 0.65)
            if !isCompact {
                var halo = context
                halo.addFilter(.blur(radius: max(1.4, lineWidth * 0.5)))
                halo.fill(Path(ellipseIn: CGRect(x: point.x - arm * 2, y: point.y - arm * 2,
                                                 width: arm * 4, height: arm * 4)),
                          with: .color(Color(red: 0.84, green: 0.57, blue: 1).opacity(0.25 + pulse * 0.4)))
            }
            var star = Path()
            let inner = arm * 0.22
            star.move(to: CGPoint(x: point.x, y: point.y - arm))
            star.addLine(to: CGPoint(x: point.x + inner, y: point.y - inner))
            star.addLine(to: CGPoint(x: point.x + arm, y: point.y))
            star.addLine(to: CGPoint(x: point.x + inner, y: point.y + inner))
            star.addLine(to: CGPoint(x: point.x, y: point.y + arm))
            star.addLine(to: CGPoint(x: point.x - inner, y: point.y + inner))
            star.addLine(to: CGPoint(x: point.x - arm, y: point.y))
            star.addLine(to: CGPoint(x: point.x - inner, y: point.y - inner))
            star.closeSubpath()
            context.fill(star, with: .color(color.opacity(0.35 + pulse * 0.65)))
        }
    }
}
