import AppKit
import DockDoorWidgetSDK

@main
struct BundleLoadChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let bundle = Bundle(path: CommandLine.arguments[1])!
        try bundle.loadAndReturnError()
        guard let type = bundle.principalClass as? WidgetPlugin.Type else {
            fatalError("Host cannot resolve principalClass from upstream-built bundle")
        }
        guard let provider = type.init() as? any DockDoorWidgetProvider else {
            fatalError("Plugin does not conform to the host SDK")
        }
        precondition(provider.id == "dot-glass")
        precondition(provider.name == "Dot Glass")
        precondition(provider.settingsSchema().count == 2)
        for (size, vertical) in [(CGSize(width: 64, height: 64),false),(CGSize(width: 128, height: 64),false),(CGSize(width: 64, height: 64),true),(CGSize(width: 64, height: 128),true)] {
            _ = provider.makeBody(size: size, isVertical: vertical)
        }
        precondition(provider.makePanelBody(dismiss: {}) != nil)
        print("Upstream bundle loads through Bundle.principalClass; SDK conformance, settings, panel and four dock layouts constructed")
    }
}
