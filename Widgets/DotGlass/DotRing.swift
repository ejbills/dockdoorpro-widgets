import SwiftUI

/// A calm gradient orb that flows only while the Dot is speaking.
struct DotRing: View {
    @Environment(\.dotTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    let phase: DotPhase
    var diameter: CGFloat = 104

    private var speechActive: Bool { phase == .speaking && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30,
                                paused: reduceMotion || !visible || !speechActive)) { timeline in
            let time = speechActive ? timeline.date.timeIntervalSinceReferenceDate : 0
            let breath = speechActive ? sin(time * 1.45) : 0
            let flow = speechActive ? CGFloat(time * 1.2) : 0
            let amplitude = speechActive ? diameter * CGFloat(0.014 + 0.004 * breath) : 0
            let pulse = speechActive ? 0.025 + 0.018 * breath : 0
            let colors = theme.colors
            ZStack {
                FluidOrbShape(phase: flow, amplitude: amplitude * 1.45)
                    .stroke(AngularGradient(colors: [colors[0], colors[2], colors[1], colors[0]],
                                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: diameter * 0.24, lineCap: .round))
                    .padding(diameter * 0.18)
                    .blur(radius: diameter * 0.085)
                    .scaleEffect(1.08 + pulse * 1.4)
                    .opacity(speechActive ? 0.78 : 0.36)

                FluidOrbShape(phase: flow, amplitude: amplitude)
                    .stroke(AngularGradient(colors: [colors[2], colors[0], colors[1], colors[0], colors[2]],
                                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: diameter * 0.17, lineCap: .round))
                    .padding(diameter * 0.18)
                    .rotationEffect(.degrees(speechActive ? time.truncatingRemainder(dividingBy: 30) * 9 : 0))
                    .shadow(color: colors[0].opacity(speechActive ? 0.55 : 0.24),
                            radius: diameter * (speechActive ? 0.105 : 0.065))

            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: speechActive)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot, \(phase.rawValue)")
    }
}

/// Small harmonic deformations keep the orb fluid without a sharp or jittery edge.
private struct FluidOrbShape: Shape {
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, amplitude) }
        set { phase = newValue.first; amplitude = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) * 0.5
        let steps = 144
        var path = Path()
        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2
            let wave = sin(angle * 3 + phase) * 0.52
                + sin(angle * 5 - phase * 0.7) * 0.28
                + sin(angle * 2 + phase * 0.43) * 0.20
            let radius = baseRadius + amplitude * wave
            let point = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
