import DockDoorWidgetSDK
import SwiftUI

final class SystemMonitorPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "system-monitor-cpu-memory" }
    var name: String { "CPU & Memory" }
    var iconSymbol: String { "gauge.with.dots.needle.67percent" }
    var widgetDescription: String { "Live CPU and memory rings. Hover for temperature, frequency, history, and top processes." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let monitor = SystemMetricsMonitor()

    func settingsSchema() -> [WidgetSetting] {
        [
            .toggle(
                key: "showCPU",
                label: "Show CPU in Dock",
                defaultValue: true
            ),
            .toggle(
                key: "showMemory",
                label: "Show Memory in Dock",
                defaultValue: true
            ),
            .picker(
                key: "refreshInterval",
                label: "Refresh Interval",
                options: ["1s", "2s", "5s"],
                defaultValue: "1s"
            ),
            .picker(
                key: "processCount",
                label: "Processes in Panel",
                options: ["5", "8", "12"],
                defaultValue: "8"
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(
            SystemMonitorView(
                size: size,
                isVertical: isVertical,
                widgetId: id,
                monitor: monitor
            )
        )
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(
            SystemMonitorPanel(
                dismiss: dismiss,
                widgetId: id,
                monitor: monitor
            )
        )
    }
}
