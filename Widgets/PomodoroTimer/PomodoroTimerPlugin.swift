import DockDoorWidgetSDK
import SwiftUI

final class PomodoroTimerPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "pomodoro-timer" }
    var name: String {
        PomodoroL10n.text("番茄时钟", "Pomodoro Timer")
    }
    var iconSymbol: String { "timer" }
    var widgetDescription: String {
        PomodoroL10n.text(
            "带休息循环、每日目标与进度记忆的专注计时器。",
            "Focus timer with break cycles, daily goals, and persistent progress."
        )
    }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private lazy var timerModel = PomodoroTimerModel(widgetId: id)

    func settingsSchema() -> [WidgetSetting] {
        normalizeStoredTheme()
        return [
            .slider(
                key: "focusMinutes",
                label: PomodoroL10n.text("专注时长（分钟）", "Focus Duration (minutes)"),
                range: 15...60,
                step: 5,
                defaultValue: 25
            ),
            .slider(
                key: "shortBreakMinutes",
                label: PomodoroL10n.text("短休息（分钟）", "Short Break (minutes)"),
                range: 3...15,
                step: 1,
                defaultValue: 5
            ),
            .slider(
                key: "longBreakMinutes",
                label: PomodoroL10n.text("长休息（分钟）", "Long Break (minutes)"),
                range: 10...30,
                step: 5,
                defaultValue: 15
            ),
            .picker(
                key: "sessionsPerRound",
                label: PomodoroL10n.text("长休息前的专注次数", "Focus Sessions Before Long Break"),
                options: ["2", "3", "4", "5"],
                defaultValue: "4"
            ),
            .slider(
                key: "dailyGoal",
                label: PomodoroL10n.text("每日专注目标", "Daily Focus Goal"),
                range: 1...12,
                step: 1,
                defaultValue: 8
            ),
            .toggle(
                key: "autoStartBreaks",
                label: PomodoroL10n.text("自动开始休息", "Auto-start Breaks"),
                defaultValue: false
            ),
            .toggle(
                key: "autoStartFocus",
                label: PomodoroL10n.text("自动开始专注", "Auto-start Focus Sessions"),
                defaultValue: false
            ),
            .toggle(
                key: "playSound",
                label: PomodoroL10n.text("阶段结束时播放提示音", "Play Sound When a Session Ends"),
                defaultValue: true
            ),
            .picker(
                key: "theme",
                label: PomodoroL10n.text("主题颜色", "Color Theme"),
                options: PomodoroTheme.allCases.map(\.title),
                defaultValue: PomodoroTheme.tomato.title
            ),
        ]
    }

    private func normalizeStoredTheme() {
        let key = "widget.\(id).theme"
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: key) else { return }
        let normalized = PomodoroTheme.resolve(title: value).title
        if value != normalized {
            defaults.set(normalized, forKey: key)
        }
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(
            PomodoroDockView(
                size: size,
                isVertical: isVertical,
                widgetId: id,
                model: timerModel
            )
        )
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(
            PomodoroPanelView(
                widgetId: id,
                model: timerModel,
                dismiss: dismiss
            )
        )
    }

    func performTapAction() {
        DispatchQueue.main.async { [weak self] in
            self?.timerModel.toggleTimer()
        }
    }
}
