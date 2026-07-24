import DockDoorWidgetSDK
import SwiftUI

enum PomodoroTheme: String, CaseIterable {
    case systemAccent = "System Accent"
    case tomato = "Tomato"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case forest = "Forest"

    var title: String {
        switch self {
        case .systemAccent:
            return PomodoroL10n.text("系统强调色", "System Accent")
        case .tomato:
            return PomodoroL10n.text("番茄红", "Tomato")
        case .sunset:
            return PomodoroL10n.text("日落", "Sunset")
        case .ocean:
            return PomodoroL10n.text("海洋", "Ocean")
        case .forest:
            return PomodoroL10n.text("森林", "Forest")
        }
    }

    static func resolve(title: String) -> PomodoroTheme {
        allCases.first { theme in
            title == theme.rawValue || theme.localizedTitles.contains(title)
        } ?? .tomato
    }

    static func current(widgetId: String) -> PomodoroTheme {
        resolve(
            title: WidgetDefaults.string(
                key: "theme",
                widgetId: widgetId,
                default: PomodoroTheme.tomato.title
            )
        )
    }

    func palette(for colorScheme: ColorScheme) -> PomodoroPalette {
        let dark = colorScheme == .dark
        switch self {
        case .systemAccent:
            return PomodoroPalette(
                primary: dark ? .accentColor.opacity(0.78) : .accentColor,
                secondary: dark
                    ? Color(red: 0.28, green: 0.59, blue: 0.67)
                    : .cyan,
                longBreak: dark
                    ? Color(red: 0.34, green: 0.65, blue: 0.52)
                    : .mint
            )
        case .tomato:
            return PomodoroPalette(
                primary: dark
                    ? Color(red: 0.79, green: 0.36, blue: 0.38)
                    : Color(red: 0.92, green: 0.20, blue: 0.24),
                secondary: dark
                    ? Color(red: 0.79, green: 0.49, blue: 0.30)
                    : Color(red: 0.96, green: 0.42, blue: 0.18),
                longBreak: dark
                    ? Color(red: 0.34, green: 0.65, blue: 0.52)
                    : Color(red: 0.12, green: 0.70, blue: 0.52)
            )
        case .sunset:
            return PomodoroPalette(
                primary: dark
                    ? Color(red: 0.59, green: 0.42, blue: 0.70)
                    : Color(red: 0.67, green: 0.25, blue: 0.80),
                secondary: dark
                    ? Color(red: 0.73, green: 0.37, blue: 0.50)
                    : Color(red: 0.90, green: 0.24, blue: 0.49),
                longBreak: dark
                    ? Color(red: 0.36, green: 0.64, blue: 0.53)
                    : Color(red: 0.12, green: 0.70, blue: 0.52)
            )
        case .ocean:
            return PomodoroPalette(
                primary: dark
                    ? Color(red: 0.24, green: 0.58, blue: 0.72)
                    : Color(red: 0.04, green: 0.48, blue: 0.82),
                secondary: dark
                    ? Color(red: 0.27, green: 0.65, blue: 0.64)
                    : Color(red: 0.04, green: 0.65, blue: 0.63),
                longBreak: dark
                    ? Color(red: 0.34, green: 0.65, blue: 0.52)
                    : Color(red: 0.12, green: 0.70, blue: 0.52)
            )
        case .forest:
            return PomodoroPalette(
                primary: dark
                    ? Color(red: 0.31, green: 0.62, blue: 0.43)
                    : Color(red: 0.13, green: 0.55, blue: 0.30),
                secondary: dark
                    ? Color(red: 0.50, green: 0.64, blue: 0.30)
                    : Color(red: 0.43, green: 0.64, blue: 0.18),
                longBreak: dark
                    ? Color(red: 0.29, green: 0.62, blue: 0.57)
                    : Color(red: 0.08, green: 0.65, blue: 0.58)
            )
        }
    }

    private var localizedTitles: [String] {
        switch self {
        case .systemAccent: return ["系统强调色", "System Accent"]
        case .tomato: return ["番茄红", "Tomato"]
        case .sunset: return ["日落", "Sunset"]
        case .ocean: return ["海洋", "Ocean"]
        case .forest: return ["森林", "Forest"]
        }
    }
}

struct PomodoroPalette {
    let primary: Color
    let secondary: Color
    let longBreak: Color

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func phaseColor(_ phase: PomodoroPhase) -> Color {
        switch phase {
        case .focus:
            return primary
        case .shortBreak:
            return secondary
        case .longBreak:
            return longBreak
        }
    }
}

enum PomodoroL10n {
    static var isChinese: Bool {
        let identifier = Locale.preferredLanguages.first
            ?? Locale.current.identifier
        return identifier.lowercased().hasPrefix("zh")
    }

    static var locale: Locale {
        Locale(identifier: isChinese ? "zh_CN" : "en_US")
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}
