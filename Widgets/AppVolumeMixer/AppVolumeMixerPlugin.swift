import DockDoorWidgetSDK
import SwiftUI

final class AppVolumeMixerPlugin: WidgetPlugin, DockDoorWidgetProvider, WidgetScrollHandling {
    var id: String { "app-volume-mixer" }
    var name: String { "Volume Mixer" }
    var iconSymbol: String { "slider.vertical.3" }
    var widgetDescription: String { "Per-app volume control from the dock. Turn any app down, mute it, or boost it past 100%." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor private lazy var model = AppVolumeMixerModel(widgetId: id)

    func settingsSchema() -> [WidgetSetting] {
        [
            .toggle(
                key: "allowBoost",
                label: "Allow Boost Above 100%",
                defaultValue: false
            ),
            .toggle(
                key: "showOnlyPlaying",
                label: "Panel Shows Only Apps Playing Now",
                defaultValue: false
            ),
            .slider(
                key: "scrollStep",
                label: "Scroll Step (%)",
                range: 1 ... 10,
                step: 1,
                defaultValue: 4
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(
            AppVolumeMixerView(
                size: size,
                isVertical: isVertical,
                widgetId: id,
                model: model
            )
        )
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(
            AppVolumeMixerPanel(
                dismiss: dismiss,
                widgetId: id,
                model: model
            )
        )
    }

    // MARK: - Scroll

    @MainActor
    func handleScroll(delta: CGFloat, isTrackpad: Bool) -> Bool {
        guard abs(delta) > 0.5, let entry = model.primaryEntry, !entry.isBypassed else { return false }
        let step = WidgetDefaults.double(key: "scrollStep", widgetId: id, default: 4) / 100
        // Wheel notches arrive as larger discrete jumps than a trackpad's
        // stream of small ones, so one notch is one step either way.
        let magnitude = isTrackpad ? min(abs(delta) / 10, 1) : 1
        let direction: Double = delta > 0 ? 1 : -1
        model.setVolume(model.volume(for: entry) + direction * step * magnitude, for: entry)
        return true
    }
}
