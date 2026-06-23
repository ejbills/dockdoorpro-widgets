import AppKit
import DockDoorWidgetSDK
import Foundation
import SwiftUI

final class ToggleDoNotDisturbPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "toggle-do-not-disturb-shortcut" }
    var name: String { "Toggle Do Not Disturb" }
    var iconSymbol: String { "moon.fill" }
    var widgetDescription: String { "Runs the Toggle Do Not Disturb shortcut from the dock." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(ToggleDoNotDisturbView(size: size, isVertical: isVertical))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(ToggleDoNotDisturbPanelView(dismiss: dismiss))
    }

    func performTapAction() {
        ShortcutLauncher.run(name: "toggle do not disturb")
    }
}

enum ShortcutLauncher {
    static func run(name: String) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
