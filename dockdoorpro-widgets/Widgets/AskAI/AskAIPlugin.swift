import DockDoorWidgetSDK
import SwiftUI

final class AskAIPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "ask-ai" }
    var name: String { "Ask" }
    var iconSymbol: String { "siri.gen2" }
    var widgetDescription: String { "Ask a question from your dock and get a streamed, on-device answer from Apple's Foundation Models. Tap the widget to copy the answer." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    // One model for the plugin's lifetime so the dock slot and the hover panel
    // share the same question, answer and generation state.
    @MainActor private var model: AskModel?

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(AskDockView(model: currentModel(), size: size, isVertical: isVertical))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(AskPanelView(model: currentModel(), dismiss: dismiss))
    }

    /// Tapping the widget copies the current answer to the clipboard.
    func performTapAction() {
        Task { @MainActor in
            currentModel().copyAnswerToClipboard()
        }
    }

    @MainActor
    private func currentModel() -> AskModel {
        if let model {
            return model
        }
        let model = AskModel()
        self.model = model
        return model
    }
}
