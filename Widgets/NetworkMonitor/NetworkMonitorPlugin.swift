import DockDoorWidgetSDK
import SwiftUI


final class NetworkMonitorPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id:                    String { "network-monitor" }
    var name:                  String { "Network Monitor" }
    var iconSymbol:            String { "network" }
    var widgetDescription:     String { "Live download & upload speeds. Hover for full details." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    func settingsSchema() -> [WidgetSetting] {
        let colorNames = NamedColor.allCases.map(\.rawValue)
        return [
            .picker(
                key: "speedUnit",
                label: "Speed Unit",
                options: ["Auto", "KB/s", "MB/s"],
                defaultValue: "Auto"
            ),

            .toggle(
                key: "colorCode",
                label: "Color-Code Speeds",
                defaultValue: true
            ),
            .picker(
                key: "colorScheme",
                label: "Color Scheme",
                options: NetworkColorScheme.allCases.map(\.rawValue),
                defaultValue: NetworkColorScheme.blueRed.rawValue
            ),
            .picker(
                key: "customDLColor",
                label: "  ↳ Download Color (Custom only)",
                options: colorNames,
                defaultValue: "Blue"
            ),
            .picker(
                key: "customULColor",
                label: "  ↳ Upload Color (Custom only)",
                options: colorNames,
                defaultValue: "Orange"
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(NetworkMonitorView(size: size, isVertical: isVertical, pluginId: id))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(NetworkMonitorPanel(dismiss: dismiss, pluginId: id))
    }
}