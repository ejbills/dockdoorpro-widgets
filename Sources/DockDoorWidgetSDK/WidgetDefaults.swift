import Foundation

/// Read settings values declared via ``WidgetSetting``.
///
/// The host app stores widget settings under namespaced `UserDefaults`
/// keys: `widget.<widgetId>.<key>`. This helper reads those keys.
///
/// ```swift
/// let showGraph = WidgetDefaults.bool(key: "showGraph", widgetId: id)
/// let interval = WidgetDefaults.string(key: "interval", widgetId: id)
/// ```
public enum WidgetDefaults {
    private static func fullKey(_ key: String, widgetId: String) -> String {
        "widget.\(widgetId).\(key)"
    }

    public static func bool(key: String, widgetId: String, default defaultValue: Bool = false) -> Bool {
        let k = fullKey(key, widgetId: widgetId)
        if UserDefaults.standard.object(forKey: k) != nil {
            return UserDefaults.standard.bool(forKey: k)
        }
        return defaultValue
    }

    public static func string(key: String, widgetId: String, default defaultValue: String = "") -> String {
        let k = fullKey(key, widgetId: widgetId)
        return UserDefaults.standard.string(forKey: k) ?? defaultValue
    }

    public static func double(key: String, widgetId: String, default defaultValue: Double = 0) -> Double {
        let k = fullKey(key, widgetId: widgetId)
        if UserDefaults.standard.object(forKey: k) != nil {
            return UserDefaults.standard.double(forKey: k)
        }
        return defaultValue
    }

    /// Rows saved from a ``WidgetSetting/table(key:label:description:columns:defaultRows:)``
    /// setting. Each row maps column keys to the user's entered values. The host
    /// stores rows as a JSON string under the same namespaced key.
    public static func tableRows(key: String, widgetId: String, default defaultValue: [[String: String]] = []) -> [[String: String]] {
        let k = fullKey(key, widgetId: widgetId)
        guard let raw = UserDefaults.standard.string(forKey: k),
              let data = raw.data(using: .utf8),
              let rows = try? JSONDecoder().decode([[String: String]].self, from: data)
        else {
            return defaultValue
        }
        return rows
    }
}
