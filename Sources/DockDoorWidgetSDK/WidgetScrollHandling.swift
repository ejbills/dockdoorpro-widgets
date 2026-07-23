import CoreGraphics
import Foundation

/// Opt-in scroll handling for marketplace widgets.
///
/// Conform your plugin to this protocol **in addition to**
/// ``DockDoorWidgetProvider`` to receive scroll events while the pointer is
/// over your widget. Do not add this conformance to a separate object — the
/// host checks the provider instance itself.
///
/// Scroll delivery follows the same rule as the built-in Now Playing volume
/// scroll: your handler is only active while your widget is the **only widget
/// in its stack**. Stacks with multiple widgets use scroll to page between
/// them, so your handler is never called there.
///
/// ```swift
/// final class MyPlugin: WidgetPlugin, DockDoorWidgetProvider, WidgetScrollHandling {
///     func handleScroll(delta: CGFloat, isTrackpad: Bool) -> Bool {
///         guard abs(delta) > 0.5 else { return true }
///         cycleSelection(forward: delta > 0)
///         return true
///     }
/// }
/// ```
public protocol WidgetScrollHandling: AnyObject {
    /// Called on the main thread for each scroll increment while hovered.
    ///
    /// - Parameters:
    ///   - delta: Normalized scroll amount along the dock's expansion axis.
    ///     Positive scrolls away from the dock edge. Momentum-phase events are
    ///     filtered out by the host; you only see direct input.
    ///   - isTrackpad: `true` for fluid trackpad gestures, `false` for a
    ///     stepped mouse wheel (deltas arrive in larger discrete jumps).
    /// - Returns: `true` to consume the event, `false` to let the dock handle
    ///   it (file tray open/close gesture).
    @MainActor func handleScroll(delta: CGFloat, isTrackpad: Bool) -> Bool

    /// Called on the main thread when the scroll session ends (the pointer
    /// leaves your widget). Commit any in-progress selection here. Default
    /// implementation does nothing.
    @MainActor func scrollSessionEnded()
}

public extension WidgetScrollHandling {
    @MainActor func scrollSessionEnded() {}
}
