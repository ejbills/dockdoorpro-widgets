import AppKit
import DockDoorWidgetSDK
import SwiftUI

final class FolderStackPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "folder-stack" }
    var name: String { "Folder Stack" }
    var iconSymbol: String { "folder.fill" }
    var widgetDescription: String { "Pin a folder and stack its files like the native Downloads stack" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private lazy var store = FolderStore(widgetId: id)
    private let anchor = WidgetAnchor()
    private lazy var fanController = FanWindowController(store: store, anchor: anchor)

    func settingsSchema() -> [WidgetSetting] {
        [
            .textField(
                key: "folderPath",
                label: "Folder",
                placeholder: "~/Downloads",
                defaultValue: ""
            ),
            .picker(
                key: "displayStyle",
                label: "Display As",
                options: FolderDisplayStyle.settingOptions,
                defaultValue: "Stack"
            ),
            .picker(
                key: "fileClickAction",
                label: "When Clicking a File",
                options: ["Open & Reveal on right-click", "Open", "Reveal in Finder"],
                defaultValue: "Open & Reveal on right-click"
            ),
            // Caps the vertical stack. The grid scrolls and ignores this.
            .slider(key: "maxItems", label: "Files Shown in Stack", range: 6...20, step: 1, defaultValue: 10),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(FolderStackView(size: size, isVertical: isVertical, store: store, anchor: anchor))
    }

    func performTapAction() {
        Task { @MainActor in fanController.toggle() }
    }
}
