import Foundation

/// How many dock slots the widget's content area currently spans.
///
/// The host never tells a widget its slot count directly — widgets infer it
/// from the aspect ratio of the `size` passed to `makeBody(size:isVertical:)`.
/// Use ``detect(size:isVertical:)`` instead of hand-rolled ratio checks.
///
/// A widget only ever receives a `.triple` size if it opts in by declaring
/// `"maxSlotSpan": 3` in its `widget.json`. Widgets that don't opt in can
/// ignore the `.triple` case entirely.
///
/// ```swift
/// switch WidgetSlotSpan.detect(size: size, isVertical: isVertical) {
/// case .compact:  compactLayout()
/// case .extended: extendedLayout()
/// case .triple:   tripleLayout()
/// }
/// ```
/// - Important: This type is `@frozen` and `detect` is emitted into the
///   widget binary, so bundles built against a newer SDK still load on host
///   versions that predate it. Keep it dependency-free: it must not call
///   other (non-inlinable) SDK symbols.
@frozen
public enum WidgetSlotSpan: Sendable {
    /// Single slot — icon centered, optional small label below.
    case compact
    /// Double slot — icon plus labels, stacked along the dock axis.
    case extended
    /// Triple slot — opt-in via `"maxSlotSpan": 3` in `widget.json`.
    case triple

    /// Classifies a content area by its aspect ratio along the dock axis.
    ///
    /// Thresholds match the documented layout convention: ratios above 1.5
    /// are extended, above 2.5 triple.
    @_alwaysEmitIntoClient
    public static func detect(size: CGSize, isVertical: Bool) -> WidgetSlotSpan {
        guard size.width > 0, size.height > 0 else { return .compact }
        let ratio = isVertical ? size.height / size.width
                               : size.width / size.height
        if ratio > 2.5 { return .triple }
        if ratio > 1.5 { return .extended }
        return .compact
    }
}
