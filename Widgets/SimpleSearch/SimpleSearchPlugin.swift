import DockDoorWidgetSDK
import SwiftUI

final class SimpleSearchPlugin: WidgetPlugin, DockDoorWidgetProvider, WidgetScrollHandling {
    var id: String { "simple-search" }
    var name: String { "Search" }
    var iconSymbol: String { "magnifyingglass" }
    var widgetDescription: String { "Type a search or URL and open it in your browser." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor private var searchModel: SimpleSearchModel?
    @MainActor private var scrollAccumulator: CGFloat = 0

    func settingsSchema() -> [WidgetSetting] {
        let hidden = hiddenEngines(widgetId: id)

        let rawBuiltins = ["Google (g)", "DuckDuckGo (ddg)", "Bing (bg)", "Yahoo (yh)", "Qwant (qw)", "Kagi (ka)", "Brave (br)", "Ecosia (eco)", "Yandex (yx)", "YouTube (yt)", "Reddit (red)"]
        let builtinOptions = rawBuiltins.map { option -> String in
            guard option.hasSuffix(")"), let open = option.lastIndex(of: "(") else { return option }
            let pfx = String(option[option.index(after: open)..<option.index(before: option.endIndex)]).lowercased()
            return hidden.contains(pfx) ? "⊘ \(option)" : option
        }

        var customOptions: [String] = []
        for row in customEngineRows(widgetId: id) {
            let prefix = (row["prefix"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let url = (row["url"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !prefix.isEmpty, !url.isEmpty else { continue }
            guard !rawBuiltins.contains(where: { $0.contains("(\(prefix))") }) else { continue }
            let clean = url
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
            let host = clean.components(separatedBy: "/").first ?? clean
            let raw = host.components(separatedBy: ".").first ?? host
            let siteName = raw.prefix(1).uppercased() + raw.dropFirst()
            let label = "\(siteName) (\(prefix))"
            customOptions.append(hidden.contains(prefix) ? "⊘ \(label)" : label)
        }

        return [
            // ——— Groupe 1 : moteurs ———
            .picker(
                key: "engine",
                label: "Default Search Engine",
                options: builtinOptions + customOptions,
                defaultValue: "Google (g)"
            ),
            .picker(
                key: "defaultEngineMode",
                label: "Engine When It Opens\n\"Default\" always starts on the one above. \"Last used\" reopens on your previous engine.",
                options: ["Default", "Last used"],
                defaultValue: "Default"
            ),
            .table(
                key: "customEngines",
                label: "Custom Search Engines",
                description: "Use [Input], %s or {searchTerms} in the URL to insert the query. A URL without a placeholder opens as a static link. Color is an optional hex (e.g. FF0000). Changes take effect after restarting the app.",
                columns: [
                    WidgetTableColumn(key: "prefix", title: "Prefix", kind: .text(placeholder: "yt")),
                    WidgetTableColumn(key: "url", title: "URL", kind: .text(placeholder: "youtube.com/results?search_query=[Input]"), width: .expanding),
                    WidgetTableColumn(key: "color", title: "Hex color", kind: .text(placeholder: "FF0000")),
                ],
                defaultRows: []
            ),

            // ——— Groupe 2 : frappe ———
            .picker(
                key: "prefixShortcuts",
                label: "Prefix Shortcuts\nType a prefix (e.g. \"yt cats\") to search a specific engine. Choose how it's confirmed, or turn it off.",
                options: [prefixShortcutsSpace, prefixShortcutsSpaceTab, prefixShortcutsOff],
                defaultValue: prefixShortcutsSpace
            ),
            .textField(
                key: "hiddenEngines",
                label: "Skip Engines\nPrefixes to leave out when scrolling between engines, separated by commas. Leave empty to keep all.",
                placeholder: "yx, yh, bg",
                defaultValue: ""
            ),
            .toggle(
                key: "clipboardSuggest",
                label: "Suggest Clipboard\nWhen opening, show copied text as a hint. Press Tab to use it.",
                defaultValue: false
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        let model = model()
        model.configure(size: size, isVertical: isVertical)

        return AnyView(
            SimpleSearchWidgetView(size: size, isVertical: isVertical, widgetId: id, model: model)
        )
    }

    func performTapAction() {
        Task { @MainActor in
            guard model().slotSpan != .compact else { return }
            model().activate()
        }
    }

    // MARK: - WidgetScrollHandling

    @MainActor
    func handleScroll(delta: CGFloat, isTrackpad: Bool) -> Bool {
        let m = model()
        // Scroll SDK pour les tailles étendues (double/triple) uniquement. Le compact
        // (single) est EXCLU volontairement : le scroll de son icône fermait le panneau.
        // En single, le scroll ne marche que sur le panneau lui-même (son moniteur NSEvent).
        guard shortcutsEnabled(widgetId: id),
              m.isExtended || m.isActive,
              m.text.isEmpty
        else {
            scrollAccumulator = 0
            return false
        }

        scrollAccumulator += delta
        let threshold: CGFloat = isTrackpad ? 3 : 0.5
        if scrollAccumulator >= threshold {
            scrollAccumulator = 0
            m.cycleEngine(by: -1)
        } else if scrollAccumulator <= -threshold {
            scrollAccumulator = 0
            m.cycleEngine(by: 1)
        }
        return true
    }

    @MainActor
    func scrollSessionEnded() {
        scrollAccumulator = 0
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        let model = model()

        if model.slotSpan != .compact {
            return AnyView(InvisibleSearchCaptureView(model: model, dismiss: dismiss))
        }

        return AnyView(SimpleSearchPanelView(widgetId: id, model: model, dismiss: dismiss))
    }

    @MainActor
    private func model() -> SimpleSearchModel {
        if let searchModel {
            return searchModel
        }

        let model = SimpleSearchModel(widgetId: id)
        searchModel = model
        return model
    }
}
