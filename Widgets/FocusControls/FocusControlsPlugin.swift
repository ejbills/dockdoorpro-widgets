import AppKit
import DockDoorWidgetSDK
import Foundation
import SwiftUI

final class FocusControlsPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "toggle-do-not-disturb-shortcut" }
    var name: String { "Focus Controls" }
    var iconSymbol: String { "moon.fill" }
    var widgetDescription: String { "Runs the Toggle Do Not Disturb shortcut from the dock." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    func settingsSchema() -> [WidgetSetting] {
        var settings: [WidgetSetting] = []
        for slot in 1...8 {
            settings.append(contentsOf: shortcutSettings(slot))
        }
        return settings
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(FocusControlsView(size: size, isVertical: isVertical))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(FocusControlsPanelView(widgetId: id, dismiss: dismiss))
    }

    func performTapAction() {
        ShortcutLauncher.run(name: "toggle do not disturb")
    }

    private func shortcutSettings(_ slot: Int) -> [WidgetSetting] {
        let presets: [(enabled: Bool, isFocus: Bool, title: String, symbol: String, shortcut: String)] = [
            (true, true, "Reduce Interruptions", "atom", "reduce interruptions"),
            (true, true, "Driving", "car.fill", "driving"),
            (true, true, "Sleep", "bed.double.fill", "sleep"),
            (true, true, "School", "graduationcap.fill", "school"),
            (false, false, "", "", ""),
            (false, false, "", "", ""),
            (false, false, "", "", ""),
            (false, false, "", "", "")
        ]

        let preset = presets[slot - 1]
        return [
            .toggle(key: "shortcut\(slot)Enabled", label: "Enable Shortcut \(slot)", defaultValue: preset.enabled),
            .toggle(key: "shortcut\(slot)IsFocus", label: "Shortcut \(slot) Is Focus", defaultValue: preset.isFocus),
            .textField(key: "shortcut\(slot)Title", label: "Shortcut \(slot) Name", placeholder: "Focus Time", defaultValue: preset.title),
            .textField(key: "shortcut\(slot)Symbol", label: "Shortcut \(slot) SF Symbol", placeholder: "moon.zzz.fill", defaultValue: preset.symbol),
            .textField(key: "shortcut\(slot)Shortcut", label: "Shortcut \(slot) Shortcut Name", placeholder: "focus time", defaultValue: preset.shortcut)
        ]
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
