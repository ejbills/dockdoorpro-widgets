import DockDoorWidgetSDK
import SwiftUI

struct PomodoroDockView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String

    @ObservedObject var model: PomodoroTimerModel
    @Environment(\.colorScheme) private var colorScheme

    private var dim: CGFloat { min(size.width, size.height) }

    private var slotSpan: WidgetSlotSpan {
        WidgetSlotSpan.detect(size: size, isVertical: isVertical)
    }

    private var palette: PomodoroPalette {
        PomodoroTheme.current(widgetId: widgetId).palette(for: colorScheme)
    }

    private var phaseColor: Color {
        palette.phaseColor(model.phase)
    }

    var body: some View {
        Group {
            switch slotSpan {
            case .compact:
                compactLayout
            case .extended:
                extendedLayout
            case .triple:
                tripleLayout
            }
        }
        .padding(dim * 0.07)
        .animation(.easeInOut(duration: 0.28), value: model.remainingFraction)
        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: model.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.phase.title), \(model.displayTime), \(model.statusText)"
        )
    }

    private var compactLayout: some View {
        countdownRing(size: dim * 0.77, compact: true)
            .scaleEffect(model.completionPulse.isMultiple(of: 2) ? 1 : 1.035)
            .animation(
                .spring(response: 0.32, dampingFraction: 0.62),
                value: model.completionPulse
            )
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.055) {
                    countdownRing(size: dim * 0.58, compact: false)
                    statusSummary(alignment: .center, compact: true)
                }
            } else {
                HStack(spacing: dim * 0.10) {
                    countdownRing(size: dim * 0.65, compact: false)
                    statusSummary(alignment: .leading, compact: false)
                }
            }
        }
    }

    private var tripleLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.07) {
                    countdownRing(size: dim * 0.62, compact: false)
                    statusSummary(alignment: .center, compact: false)
                    dailyGoalView(horizontal: false)
                }
            } else {
                HStack(spacing: dim * 0.12) {
                    countdownRing(size: dim * 0.67, compact: false)
                    statusSummary(alignment: .leading, compact: false)
                    dailyGoalView(horizontal: true)
                        .frame(maxWidth: dim * 0.95)
                }
            }
        }
    }

    private func countdownRing(size ringSize: CGFloat, compact: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(phaseColor.opacity(0.14), lineWidth: ringSize * 0.105)

            Circle()
                .trim(from: 0, to: max(0.001, model.remainingFraction))
                .stroke(
                    AngularGradient(
                        colors: [phaseColor, palette.secondary, phaseColor],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: ringSize * 0.105,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: phaseColor.opacity(0.22), radius: ringSize * 0.045)

            if compact {
                VStack(spacing: -1) {
                    Text(model.compactValue)
                        .font(.system(
                            size: ringSize * 0.30,
                            weight: .bold,
                            design: .rounded
                        ).monospacedDigit())
                        .minimumScaleFactor(0.62)
                    Text(model.compactUnit)
                        .font(.system(
                            size: max(7.5, ringSize * 0.13),
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(.secondary)
                        .kerning(0.2)
                }
            } else {
                Image(systemName: model.phase.symbol)
                    .font(.system(size: ringSize * 0.25, weight: .semibold))
                    .foregroundStyle(phaseColor)
            }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(statusColor)
                .frame(width: ringSize * 0.13, height: ringSize * 0.13)
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 0.6)
                }
                .shadow(color: statusColor.opacity(0.28), radius: 2)
                .offset(x: ringSize * 0.015, y: -ringSize * 0.015)
        }
        .frame(width: ringSize, height: ringSize)
    }

    private func statusSummary(
        alignment: HorizontalAlignment,
        compact: Bool
    ) -> some View {
        VStack(alignment: alignment, spacing: compact ? 0 : 1) {
            Text(model.phase.compactTitle)
                .font(.system(
                    size: dim * (compact ? 0.105 : 0.12),
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(phaseColor)
                .lineLimit(1)

            Text(model.displayTime)
                .font(.system(
                    size: dim * (compact ? 0.16 : 0.20),
                    weight: .bold,
                    design: .rounded
                ).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if !compact {
                HStack(spacing: 3) {
                    Image(systemName: model.isRunning ? "play.fill" : (model.isPaused ? "pause.fill" : "circle"))
                        .font(.system(size: max(7, dim * 0.09), weight: .bold))
                    Text(model.statusText)
                        .lineLimit(1)
                }
                .font(.system(
                    size: max(8, dim * 0.11),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func dailyGoalView(horizontal: Bool) -> some View {
        VStack(
            alignment: horizontal ? .leading : .center,
            spacing: dim * 0.035
        ) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(palette.secondary)
                Text("\(model.completedToday)/\(model.dailyGoal)")
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .font(.system(size: dim * 0.105, weight: .semibold))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(phaseColor.opacity(0.13))
                    Capsule()
                        .fill(palette.gradient)
                        .frame(width: proxy.size.width * model.dailyProgress)
                }
            }
            .frame(height: max(3, dim * 0.045))

            Text(PomodoroL10n.text("今日目标", "TODAY"))
                .font(.system(size: dim * 0.07, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.25)
        }
    }

    private var statusColor: Color {
        switch model.runState {
        case .running:
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.66, blue: 0.42)
                : .green
        case .paused:
            return colorScheme == .dark
                ? Color(red: 0.78, green: 0.50, blue: 0.28)
                : .orange
        case .idle: return Color.secondary.opacity(0.7)
        }
    }
}
