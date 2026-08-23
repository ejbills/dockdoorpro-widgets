import DockDoorWidgetSDK
import SwiftUI
import AppKit

@objc(ClipboardPlugin)
final class ClipboardPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "clipboard-history" }
    var name: String { "Clipboard" }
    var iconSymbol: String { "list.bullet.clipboard" }
    var widgetDescription: String { "Clipboard history with preview" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let manager = ClipboardManagerState()

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(ClipboardWidgetView(size: size, isVertical: isVertical, manager: manager))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        let ctx = PanelWindowContext()
        let guardedDismiss: () -> Void = {
            ctx.cancelScheduledClose()
            let workItem = DispatchWorkItem {
                let mouse = NSEvent.mouseLocation
                if let frame = ctx.window?.frame, frame.contains(mouse) { return }
                dismiss()
            }
            ctx.pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
        }
        return AnyView(
            ClipboardPanelView(
                manager: manager,
                dismiss: dismiss,
                guardedDismiss: guardedDismiss,
                context: ctx
            )
        )
    }
}

final class PanelWindowContext: @unchecked Sendable {
    weak var window: NSWindow?
    var pendingWorkItem: DispatchWorkItem?

    func cancelScheduledClose() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
