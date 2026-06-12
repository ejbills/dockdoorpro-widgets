import DockDoorWidgetSDK
import SwiftUI

final class SimpleSearchPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "simple-search" }
    var name: String { "Search" }
    var iconSymbol: String { "magnifyingglass" }
    var widgetDescription: String { "Type a search or URL and open it in your browser." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor private var searchModel: SimpleSearchModel?

    func settingsSchema() -> [WidgetSetting] {
        [
            .picker(
                key: "engine",
                label: "Search Engine",
                options: ["Google", "DuckDuckGo", "Bing", "Yahoo", "Qwant", "Kagi", "Brave", "Ecosia", "Yandex", "YouTube"],
                defaultValue: "Google"
            ),
            .textField(
                key: "customEngineURL",
                label: "Custom Search Engine URL with %s in place of search term",
                placeholder: "https://ask.com/web?q=%s",
                defaultValue: ""
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        let model = model()

        return AnyView(
            SimpleSearchWidgetView(size: size, isVertical: isVertical, widgetId: id, model: model)
        )
    }

    func performTapAction() {
        Task { @MainActor in
            model().activate()
        }
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        let model = model()

        if model.isExtended {
            return AnyView(InvisibleSearchCaptureView(model: model, dismiss: dismiss))
        }

        return AnyView(SimpleSearchPanelView(widgetId: id, dismiss: dismiss))
    }

    @MainActor
    private func model() -> SimpleSearchModel {
        if let searchModel {
            return searchModel
        }

        let model = SimpleSearchModel()
        searchModel = model
        return model
    }
}
