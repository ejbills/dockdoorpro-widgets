import Foundation

/// Declarative setting definition.
///
/// Instead of providing a SwiftUI settings view, marketplace widgets
/// declare their settings as data. The host app renders these using
/// its native settings UI, ensuring a consistent look.
///
/// Use ``WidgetDefaults`` to read the current value at runtime.
///
/// ```swift
/// func settingsSchema() -> [WidgetSetting] {
///     [
///         .toggle(key: "showGraph", label: "Show Graph", defaultValue: true),
///         .picker(key: "interval", label: "Update Interval",
///                 options: ["1s", "5s", "30s"], defaultValue: "5s"),
///     ]
/// }
/// ```
public enum WidgetSetting: Sendable {
    case toggle(key: String, label: String, defaultValue: Bool)
    case picker(key: String, label: String, options: [String], defaultValue: String)
    case slider(key: String, label: String, range: ClosedRange<Double>, step: Double = 1, defaultValue: Double)
    case textField(key: String, label: String, placeholder: String, defaultValue: String)
    case table(key: String, label: String, description: String = "", columns: [WidgetTableColumn], defaultRows: [[String: String]] = [])
}

/// One column of a ``WidgetSetting/table(key:label:description:columns:defaultRows:)`` setting.
///
/// Each row the user adds is a `[columnKey: value]` dictionary; read the saved
/// rows at runtime with ``WidgetDefaults/tableRows(key:widgetId:default:)``.
///
/// ```swift
/// .table(
///     key: "customEngines",
///     label: "Custom Search Engines",
///     description: "Use {searchTerms} in the URL to insert the query.",
///     columns: [
///         WidgetTableColumn(key: "type", title: "Type", kind: .picker(options: ["Query", "Static"])),
///         WidgetTableColumn(key: "prefix", title: "Prefix", kind: .text(placeholder: "yt")),
///         WidgetTableColumn(key: "url", title: "URL", kind: .text(placeholder: "https://…"), width: .expanding),
///     ]
/// )
/// ```
public struct WidgetTableColumn: Sendable {
    /// The control rendered for this column in each row.
    public enum Kind: Sendable {
        /// Free-form text field with a placeholder.
        case text(placeholder: String = "")
        /// Menu picker limited to the given options. The first option is the
        /// default for new rows.
        case picker(options: [String])
    }

    /// Relative width of the column.
    public enum Width: Sendable {
        /// Sized to fit alongside other columns.
        case standard
        /// Takes the remaining horizontal space (e.g. a URL column).
        case expanding
    }

    public let key: String
    public let title: String
    public let kind: Kind
    public let width: Width

    public init(key: String, title: String, kind: Kind, width: Width = .standard) {
        self.key = key
        self.title = title
        self.kind = kind
        self.width = width
    }
}
