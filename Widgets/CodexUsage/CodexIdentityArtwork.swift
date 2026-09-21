import SwiftUI
import DockDoorWidgetSDK
import Foundation

/// Read-only model artwork shared with the personal 6.0 design.
struct CodexIdentityArtwork: View {
    let identity: CodexTheme
    let isEmphasized: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var animated: Bool { WidgetDefaults.bool(key: "animateArtwork", widgetId: codexUsageWidgetId, default: true) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0,
                                paused: reduceMotion || !animated || !isVisible)) { timeline in
            let time = reduceMotion || !animated ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let base = identity == .astra ? Color(red: 0.065, green: 0.01, blue: 0.18) : identity.base
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [base, identity.colors[0].opacity(0.58), base]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                let center = CGPoint(x: size.width * 0.79, y: size.height * 0.30)
                let radius = min(size.height * 0.25, 16)
                let pulse = 0.78 + 0.16 * sin(time * 1.1)
                glow(&context, at: center, radius: size.height * 0.95,
                     color: identity.accent.opacity((isEmphasized ? 0.55 : 0.35)))
                switch identity {
                case .astra:
                    glow(&context, at: CGPoint(x: size.width * 0.34, y: size.height * 0.68),
                         radius: size.width * 0.65, color: .purple.opacity(0.7))
                    stars(&context, size: size, time: time, count: 28, tint: Color(red: 0.95, green: 0.73, blue: 1))
                    let flare = star(at: center, radius: radius * 0.48)
                    var bloom = context
                    bloom.addFilter(.blur(radius: 4))
                    bloom.fill(flare, with: .color(.pink.opacity(pulse)))
                    context.fill(flare, with: .color(.white.opacity(pulse)))
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * 1.8, y: center.y - radius * 0.65,
                                                         width: radius * 3.6, height: radius * 1.3)),
                                   with: .color(.purple.opacity(0.35)), lineWidth: 0.6)
                case .luna:
                    stars(&context, size: size, time: time, count: 13, tint: .cyan)
                    orbit(&context, center: center, radius: radius, tint: .cyan)
                    let moon = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: moon), with: .linearGradient(
                        Gradient(colors: [.white, Color(red: 0.48, green: 0.79, blue: 1)]),
                        startPoint: CGPoint(x: moon.minX, y: moon.minY), endPoint: CGPoint(x: moon.maxX, y: moon.maxY)))
                    context.fill(Path(ellipseIn: moon.offsetBy(dx: radius * 0.65, dy: -radius * 0.30)),
                                 with: .color(Color(red: 0.025, green: 0.07, blue: 0.18)))
                case .sol:
                    orbit(&context, center: center, radius: radius * 1.15, tint: .orange)
                    for ray in 0..<16 {
                        let angle = Double(ray) * .pi / 8 + time * 0.035
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + CGFloat(Foundation.cos(angle)) * radius * 1.2, y: center.y + CGFloat(Foundation.sin(angle)) * radius * 1.2))
                        path.addLine(to: CGPoint(x: center.x + CGFloat(Foundation.cos(angle)) * radius * 1.75, y: center.y + CGFloat(Foundation.sin(angle)) * radius * 1.75))
                        context.stroke(path, with: .color(.yellow.opacity(0.6)), lineWidth: ray.isMultiple(of: 2) ? 1.4 : 0.7)
                    }
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .radialGradient(Gradient(colors: [.white, .yellow, .orange]), center: center, startRadius: 0, endRadius: radius * 1.2))
                case .terra:
                    orbit(&context, center: center, radius: radius, tint: Color(red: 0.71, green: 0.53, blue: 0.26))
                    let planet = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(planet, with: .linearGradient(Gradient(colors: [.mint, Color(red: 0.03, green: 0.28, blue: 0.19), .black]),
                                                             startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                                                             endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
                    var terrain = context
                    terrain.clip(to: planet)
                    for band in 0..<5 {
                        let y = center.y - radius + CGFloat(band) * radius * 0.5
                        var contour = Path()
                        contour.move(to: CGPoint(x: center.x - radius, y: y))
                        contour.addCurve(to: CGPoint(x: center.x + radius, y: y + radius * 0.4),
                                         control1: CGPoint(x: center.x - radius * 0.4, y: y - radius * 0.6),
                                         control2: CGPoint(x: center.x + radius * 0.2, y: y + radius))
                        terrain.stroke(contour, with: .color(Color(red: 0.82, green: 0.91, blue: 0.51).opacity(0.78)), lineWidth: 1.5)
                    }
                    context.stroke(planet, with: .color(.mint.opacity(0.8)), lineWidth: 0.8)
                case .rainbow:
                    for (index, color) in identity.colors.enumerated() {
                        var ribbon = Path()
                        let y = CGFloat(index) * 5 + 3
                        ribbon.move(to: CGPoint(x: -10, y: y + 10))
                        ribbon.addCurve(to: CGPoint(x: size.width + 10, y: y),
                                        control1: CGPoint(x: size.width * 0.35, y: -14 + 4 * sin(time * 0.5)),
                                        control2: CGPoint(x: size.width * 0.60, y: size.height + 14))
                        context.stroke(ribbon, with: .color(color.opacity(0.55)), lineWidth: 6)
                    }
                    stars(&context, size: size, time: time, count: 10, tint: .white)
                }
                // Keep text contrast independent of how bright the artwork gets.
                context.fill(Path(rect), with: .linearGradient(Gradient(stops: [
                    .init(color: .clear, location: 0.35), .init(color: .black.opacity(0.40), location: 1)
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ context: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [color, .clear]), center: center, startRadius: 0, endRadius: radius))
    }

    private func orbit(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color) {
        for index in 0..<4 {
            let r = radius * (1.7 + CGFloat(index) * 0.65)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                           with: .color(tint.opacity(0.26 - Double(index) * 0.045)), lineWidth: 0.7)
        }
    }

    private func stars(_ context: inout GraphicsContext, size: CGSize, time: Double, count: Int, tint: Color) {
        for index in 0..<count {
            let x = CGFloat((index * 37 + 11) % 101) / 101 * size.width
            let y = CGFloat((index * 23 + 9) % 83) / 83 * size.height
            let twinkle = 0.55 + 0.45 * sin(time * (1.0 + Double(index % 3) * 0.3) + Double(index))
            let radius: CGFloat = index.isMultiple(of: 5) ? 1.8 : 0.65
            let center = CGPoint(x: x, y: y)
            let shape = index.isMultiple(of: 5) ? star(at: center, radius: radius)
                : Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius))
            if index.isMultiple(of: 5) {
                var glow = context
                glow.addFilter(.blur(radius: 2.5))
                glow.fill(shape, with: .color(tint.opacity(twinkle)))
            }
            context.fill(shape, with: .color(.white.opacity(0.30 + 0.65 * twinkle)))
        }
    }

    private func star(at center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4 - .pi / 2
            let r = index.isMultiple(of: 2) ? radius * 2 : radius * 0.38
            let point = CGPoint(x: center.x + CGFloat(Foundation.cos(angle)) * r, y: center.y + CGFloat(Foundation.sin(angle)) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
