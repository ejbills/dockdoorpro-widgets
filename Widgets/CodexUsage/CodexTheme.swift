import DockDoorWidgetSDK
import SwiftUI

/// Palette for the usage ring and panel. The host owns the value: it is
/// declared as a `.picker` setting and read back through `WidgetDefaults`.
enum CodexTheme: String, CaseIterable {
    case astra = "Astra", luna = "Luna", sol = "Sol", terra = "Terra", rainbow = "Rainbow"

    static func current(widgetId: String) -> CodexTheme {
        CodexTheme(
            rawValue: WidgetDefaults.string(
                key: "modelTheme",
                widgetId: widgetId,
                default: CodexTheme.luna.rawValue
            )
        ) ?? .luna
    }

    var accent: Color { colors[1] }
    var colors: [Color] {
        switch self {
        case .astra: return [Color(red: 0.38, green: 0.16, blue: 0.85), Color(red: 0.76, green: 0.48, blue: 1), Color(red: 0.98, green: 0.72, blue: 1)]
        case .luna: return [Color(red: 0.20, green: 0.36, blue: 0.90), Color(red: 0.40, green: 0.77, blue: 1), Color(red: 0.80, green: 0.91, blue: 1)]
        case .sol: return [Color(red: 0.85, green: 0.25, blue: 0.10), Color(red: 1, green: 0.61, blue: 0.20), Color(red: 1, green: 0.88, blue: 0.49)]
        case .terra: return [Color(red: 0.62, green: 0.36, blue: 0.19), Color(red: 0.30, green: 0.77, blue: 0.52), Color(red: 0.78, green: 0.87, blue: 0.56)]
        case .rainbow: return [.pink, .orange, .yellow, .green, .cyan, .purple, .pink]
        }
    }
    var base: Color {
        switch self {
        case .astra: return Color(red: 0.055, green: 0.025, blue: 0.12)
        case .luna: return Color(red: 0.025, green: 0.055, blue: 0.12)
        case .sol: return Color(red: 0.13, green: 0.055, blue: 0.025)
        case .terra: return Color(red: 0.065, green: 0.08, blue: 0.045)
        case .rainbow: return Color(red: 0.07, green: 0.055, blue: 0.10)
        }
    }
}

struct CodexThemeBackground: View {
    let theme: CodexTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // Light appearance keeps the host's own panel chrome and only
            // takes a tint, so semantic text colors stay readable.
            if isDark {
                theme.base.opacity(reduceTransparency ? 1 : 0.94)
            } else {
                theme.accent.opacity(reduceTransparency ? 0.16 : 0.10)
            }
            RadialGradient(colors: [theme.accent.opacity(isDark ? 0.20 : 0.12), .clear], center: .topTrailing,
                           startRadius: 10, endRadius: 360)
            // Static points keep the main surface quiet; only the ring animates.
            if theme == .astra && isDark {
                Canvas { context, size in
                    for index in 0..<32 {
                        let x = CGFloat((index * 73 + 13) % 347) / 347 * size.width
                        let y = CGFloat((index * 97 + 7) % 641) / 641 * size.height
                        let radius: CGFloat = index.isMultiple(of: 5) ? 1 : 0.5
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                                     with: .color(.white.opacity(index.isMultiple(of: 5) ? 0.20 : 0.10)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
