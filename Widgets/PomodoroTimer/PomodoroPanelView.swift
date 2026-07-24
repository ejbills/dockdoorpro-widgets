import SwiftUI

struct PomodoroPanelView: View {
    let widgetId: String
    @ObservedObject var model: PomodoroTimerModel
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: PomodoroPalette {
        PomodoroTheme.current(widgetId: widgetId).palette(for: colorScheme)
    }

    private var phaseColor: Color {
        palette.phaseColor(model.phase)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                phaseSelector
                timerCard
                controls
                todayCard
                footerHint
            }
            .padding(16)
        }
        .frame(width: 340)
        .background(panelBackground)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.phase)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.gradient)
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: phaseColor.opacity(0.22), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(PomodoroL10n.text("番茄时钟", "Pomodoro Timer"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(model.statusText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(palette.secondary)
                Text("\(model.completedToday)/\(model.dailyGoal)")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(phaseColor.opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(phaseColor.opacity(0.16), lineWidth: 0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.055), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var phaseSelector: some View {
        HStack(spacing: 6) {
            ForEach(PomodoroPhase.allCases) { phase in
                Button {
                    model.selectPhase(phase)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: phase.symbol)
                            .font(.system(size: 9, weight: .semibold))
                        Text(phase.title)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PomodoroModeButtonStyle(
                        selected: model.phase == phase,
                        accent: palette.phaseColor(phase)
                    )
                )
                .accessibilityHint(PomodoroL10n.text(
                    "切换并重置为此阶段",
                    "Switch and reset to this phase"
                ))
            }
        }
    }

    private var timerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 11)

                Circle()
                    .trim(from: 0, to: max(0.001, model.remainingFraction))
                    .stroke(
                        AngularGradient(
                            colors: [phaseColor, palette.secondary, phaseColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phaseColor.opacity(0.20), radius: 7)

                VStack(spacing: 3) {
                    Image(systemName: model.phase.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(phaseColor)
                    Text(model.displayTime)
                        .font(.system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        ).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(model.phase.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
            }
            .frame(width: 154, height: 154)
            .scaleEffect(model.completionPulse.isMultiple(of: 2) ? 1 : 1.025)
            .animation(
                .spring(response: 0.30, dampingFraction: 0.60),
                value: model.completionPulse
            )

            roundProgress

            HStack(spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text(PomodoroL10n.text(
                    "接下来：\(model.nextPhase.title)",
                    "Up next: \(model.nextPhase.title)"
                ))
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(
            LinearGradient(
                colors: [
                    phaseColor.opacity(colorScheme == .dark ? 0.12 : 0.08),
                    palette.secondary.opacity(colorScheme == .dark ? 0.07 : 0.045),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(phaseColor.opacity(0.16), lineWidth: 0.7)
        }
    }

    private var roundProgress: some View {
        HStack(spacing: 7) {
            ForEach(0..<model.sessionsPerRound, id: \.self) { index in
                let completed = model.phase == .longBreak
                    || index < model.cycleFocusCount
                let current = model.phase == .focus
                    && index == min(
                        model.cycleFocusCount,
                        model.sessionsPerRound - 1
                    )

                Circle()
                    .fill(completed ? phaseColor : Color.primary.opacity(0.10))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if current {
                            Circle()
                                .strokeBorder(phaseColor, lineWidth: 1.5)
                                .padding(-3)
                        }
                    }
                    .shadow(
                        color: completed ? phaseColor.opacity(0.24) : .clear,
                        radius: 2
                    )
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(PomodoroL10n.text(
            "本轮已完成 \(model.cycleFocusCount) 次专注",
            "\(model.cycleFocusCount) focus sessions completed this round"
        ))
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Button {
                model.reset()
            } label: {
                Label(
                    PomodoroL10n.text("重置", "Reset"),
                    systemImage: "arrow.counterclockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PomodoroActionButtonStyle(accent: phaseColor))

            Button {
                model.toggleTimer()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PomodoroActionButtonStyle(
                    accent: phaseColor,
                    prominent: true
                )
            )
            .keyboardShortcut(.space, modifiers: [])

            Button {
                model.skip()
            } label: {
                Label(
                    PomodoroL10n.text("跳过", "Skip"),
                    systemImage: "forward.end.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PomodoroActionButtonStyle(accent: palette.secondary))
        }
    }

    private var todayCard: some View {
        VStack(spacing: 9) {
            HStack {
                Label(
                    PomodoroL10n.text("今日专注", "Today's Focus"),
                    systemImage: "chart.bar.fill"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(PomodoroL10n.text(
                    "\(model.completedToday) / \(model.dailyGoal) 个番茄",
                    "\(model.completedToday) of \(model.dailyGoal) sessions"
                ))
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(phaseColor.opacity(0.12))

                    Capsule()
                        .fill(palette.gradient)
                        .frame(width: proxy.size.width * model.dailyProgress)
                        .shadow(color: phaseColor.opacity(0.18), radius: 3)
                }
            }
            .frame(height: 7)

            HStack {
                Text(todayMotivation)
                Spacer()
                Text("\(Int((model.dailyProgress * 100).rounded()))%")
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
    }

    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.click.2")
            Text(PomodoroL10n.text(
                "单击 Dock 小组件可快速开始或暂停",
                "Click the Dock widget to start or pause"
            ))
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
    }

    private var primaryActionTitle: String {
        switch model.runState {
        case .running:
            return PomodoroL10n.text("暂停", "Pause")
        case .paused:
            return PomodoroL10n.text("继续", "Resume")
        case .idle:
            return PomodoroL10n.text("开始", "Start")
        }
    }

    private var primaryActionSymbol: String {
        model.isRunning ? "pause.fill" : "play.fill"
    }

    private var todayMotivation: String {
        if model.completedToday >= model.dailyGoal {
            return PomodoroL10n.text("今日目标已完成，做得好！", "Goal complete — nicely done!")
        }
        if model.completedToday == 0 {
            return PomodoroL10n.text("从第一个番茄开始", "Start with one focused session")
        }
        return PomodoroL10n.text("保持节奏，继续前进", "Keep the rhythm going")
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    phaseColor.opacity(colorScheme == .dark ? 0.07 : 0.045),
                    .clear,
                    palette.secondary.opacity(colorScheme == .dark ? 0.045 : 0.025),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct PomodoroModeButtonStyle: ButtonStyle {
    let selected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        PomodoroModeButtonBody(
            configuration: configuration,
            selected: selected,
            accent: accent
        )
    }
}

private struct PomodoroModeButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let accent: Color

    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(selected || hovered ? accent : Color.secondary)
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(
                accent.opacity(selected ? 0.14 : (hovered ? 0.08 : 0)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        accent.opacity(selected ? 0.22 : (hovered ? 0.14 : 0)),
                        lineWidth: 0.7
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : (hovered ? 1.015 : 1))
            .animation(.easeOut(duration: 0.14), value: hovered)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

private struct PomodoroActionButtonStyle: ButtonStyle {
    let accent: Color
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PomodoroActionButtonBody(
            configuration: configuration,
            accent: accent,
            prominent: prominent
        )
    }
}

private struct PomodoroActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let accent: Color
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(prominent ? Color.white : accent)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                prominent
                    ? AnyShapeStyle(accent.opacity(configuration.isPressed ? 0.78 : 0.94))
                    : AnyShapeStyle(accent.opacity(hovered ? 0.13 : 0.07)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        (prominent ? Color.white : accent)
                            .opacity(hovered ? 0.24 : 0.12),
                        lineWidth: 0.7
                    )
            }
            .shadow(
                color: accent.opacity(prominent && hovered ? 0.22 : 0),
                radius: 6,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (hovered ? 1.025 : 1))
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.14), value: hovered)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}
