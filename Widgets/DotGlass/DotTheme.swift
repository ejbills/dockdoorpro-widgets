import SwiftUI
import DockDoorWidgetSDK

enum DotTheme: String, CaseIterable {
    case arctic = "Arctic", aurora = "Aurora", orchid = "Orchid"
    case ember = "Ember", rose = "Rose", solar = "Solar"

    static var current: DotTheme { DotTheme(rawValue: WidgetDefaults.string(key: "theme", widgetId: "dot-glass", default: "Arctic")) ?? .arctic }

    var colors: [Color] {
        switch self {
        case .arctic: return [.init(red: 0.18, green: 0.78, blue: 1), .init(red: 0.2, green: 0.34, blue: 0.95), .init(red: 0.72, green: 0.95, blue: 1)]
        case .aurora: return [.init(red: 0.16, green: 0.94, blue: 0.67), .init(red: 0.05, green: 0.48, blue: 0.62), .init(red: 0.7, green: 1, blue: 0.73)]
        case .orchid: return [.init(red: 0.68, green: 0.37, blue: 1), .init(red: 0.32, green: 0.2, blue: 0.81), .init(red: 0.96, green: 0.65, blue: 1)]
        case .ember: return [.init(red: 1, green: 0.43, blue: 0.17), .init(red: 0.78, green: 0.12, blue: 0.23), .init(red: 1, green: 0.83, blue: 0.44)]
        case .rose: return [.init(red: 1, green: 0.38, blue: 0.66), .init(red: 0.65, green: 0.18, blue: 0.48), .init(red: 1, green: 0.8, blue: 0.89)]
        case .solar: return [.init(red: 0.98, green: 0.8, blue: 0.2), .init(red: 0.8, green: 0.46, blue: 0.08), .init(red: 1, green: 0.98, blue: 0.67)]
        }
    }

    // Opaque, deep colors keep white message text legible over any glass backdrop.
    var messageColor: Color {
        switch self {
        case .arctic: return Color(red: 0.12, green: 0.34, blue: 0.53)
        case .aurora: return Color(red: 0.08, green: 0.36, blue: 0.29)
        case .orchid: return Color(red: 0.35, green: 0.22, blue: 0.53)
        case .ember: return Color(red: 0.49, green: 0.24, blue: 0.14)
        case .rose: return Color(red: 0.47, green: 0.21, blue: 0.34)
        case .solar: return Color(red: 0.40, green: 0.31, blue: 0.10)
        }
    }

}


/// Shared by real messages and the clearly labeled onboarding examples.
struct DotBubbleSurface: ViewModifier {
    let isMine: Bool
    @Environment(\.dotTheme) private var selectedTheme
    @Environment(\.dotGlassOpacity) private var glassOpacity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var themeName: String { selectedTheme.rawValue }
    private var theme: DotTheme { DotTheme(rawValue: themeName) ?? .arctic }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        let tint = isMine ? Color(red: 0.24, green: 0.25, blue: 0.28) : theme.messageColor
        let opacity = min(1, max(0.2, glassOpacity))
        content
            .foregroundStyle(.white.opacity(0.96))
            .background {
                if reduceTransparency {
                    shape.fill(tint)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(tint.opacity(isMine ? 0.36 : 0.54)) }
                        .overlay {
                            shape.fill(LinearGradient(colors: [theme.colors[2].opacity(0.12), .clear],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .opacity(opacity)
                }
            }
            .overlay(shape.strokeBorder(theme.colors[2].opacity((isMine ? 0.17 : 0.28) * opacity), lineWidth: 0.7))
    }
}

private struct DotThemeKey: EnvironmentKey {
    static let defaultValue = DotTheme.arctic
}

extension EnvironmentValues {
    var dotTheme: DotTheme {
        get { self[DotThemeKey.self] }
        set { self[DotThemeKey.self] = newValue }
    }

    var dotGlassOpacity: Double {
        get { self[DotGlassOpacityKey.self] }
        set { self[DotGlassOpacityKey.self] = newValue }
    }
}

private struct DotGlassOpacityKey: EnvironmentKey {
    static let defaultValue = 0.68
}
