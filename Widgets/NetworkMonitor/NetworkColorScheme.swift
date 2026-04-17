import DockDoorWidgetSDK
import SwiftUI


enum NetworkColorScheme: String, CaseIterable {
    case blueRed    = "Blue / Red"
    case tealPurple = "Teal / Purple"
    case custom     = "Custom"
}

enum NamedColor: String, CaseIterable {
    case blue   = "Blue"
    case red    = "Red"
    case orange = "Orange"
    case green  = "Green"
    case teal   = "Teal"
    case cyan   = "Cyan"
    case purple = "Purple"
    case pink   = "Pink"
    case yellow = "Yellow"
    case white  = "White"

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .red:    return .red
        case .orange: return .orange
        case .green:  return .green
        case .teal:   return Color(red: 0.18, green: 0.80, blue: 0.75)
        case .cyan:   return .cyan
        case .purple: return .purple
        case .pink:   return .pink
        case .yellow: return .yellow
        case .white:  return Color.primary.opacity(0.85)
        }
    }
}


struct NetworkColors {
    let download: Color
    let upload: Color

    static func resolve(pluginId: String) -> NetworkColors {
        guard WidgetDefaults.bool(key: "colorCode", widgetId: pluginId) else {
            return NetworkColors(download: .secondary, upload: .secondary)
        }

        let scheme = NetworkColorScheme(
            rawValue: WidgetDefaults.string(key: "colorScheme", widgetId: pluginId, default: NetworkColorScheme.blueRed.rawValue)
        ) ?? .blueRed

        switch scheme {
        case .blueRed:
            return NetworkColors(download: .blue, upload: .red)

        case .tealPurple:
            let teal = Color(red: 0.18, green: 0.80, blue: 0.75)
            return NetworkColors(download: teal, upload: .purple)

        case .custom:
            let dl = NamedColor(rawValue: WidgetDefaults.string(key: "customDLColor", widgetId: pluginId, default: "Blue"))?.color ?? .blue
            let ul = NamedColor(rawValue: WidgetDefaults.string(key: "customULColor", widgetId: pluginId, default: "Orange"))?.color ?? .orange
            return NetworkColors(download: dl, upload: ul)
        }
    }
}
