import AppKit
import DockDoorWidgetSDK
import SwiftUI

final class ThingsTodayPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "things-today" }
    var name: String { "Things Today" }
    var iconSymbol: String { "checklist" }
    var widgetDescription: String { "Shows Today's Things 3 tasks with Upcoming and Deadlines in the panel" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let store = ThingsStore()

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(ThingsTodayView(size: size, isVertical: isVertical, store: store))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(ThingsTodayPanel(dismiss: dismiss, store: store))
    }

    func performTapAction() {
        guard let url = URL(string: "things:///today") else { return }
        NSWorkspace.shared.open(url)
    }
}
