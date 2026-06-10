import SwiftUI
import AppKit
import DockDoorWidgetSDK

// MARK: - Plugin

final class SimpleSearchPlugin: WidgetPlugin, DockDoorWidgetProvider {

    var id: String         { "simple-search" }
    var name: String       { "Search" }
    var iconSymbol: String { "magnifyingglass" }
    var widgetDescription: String { "Type to search → Enter → opens in your browser." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let bridge = SearchBridge()

    func performTapAction() {}

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        let extended = isVertical
            ? size.height > size.width  * 1.5
            : size.width  > size.height * 1.5
        bridge.isExtended = extended
        return AnyView(SimpleSearchWidgetView(size: size, isVertical: isVertical, bridge: bridge))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        if bridge.isExtended {
            // Mode double → panel invisible, texte affiché inline
            return AnyView(InvisiblePanelView(bridge: bridge, dismiss: dismiss))
        } else {
            // Mode simple → panel visible
            return AnyView(SimpleSearchPanelView(dismiss: dismiss))
        }
    }

    func settingsSchema() -> [WidgetSetting] {
        [.picker(key: "engine", label: "Search engine",
                 options: ["Google", "DuckDuckGo", "Bing"],
                 defaultValue: "Google")]
    }
}

// MARK: - Shared state

private enum UISettings {
    static var fieldWidth: CGFloat = 200
}

@Observable
private final class SearchBridge {
    var text: String = ""
    var isActive: Bool = false
    var isExtended: Bool = false
    var displayText: String = "" // texte affiché pendant l'effacement
    var isErasing: Bool = false

    func startErasing(visibleText: String, completion: @escaping () -> Void) {
        guard !visibleText.isEmpty else { completion(); return }
        isErasing = true
        displayText = visibleText // on part du texte visible uniquement
        let chars = Array(visibleText)
        let delay = 0.005 // 5ms par caractère
        func eraseNext(_ index: Int) {
            guard index >= 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.isErasing = false
                    completion()
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(chars.count - index)) {
                self.displayText = String(chars.prefix(index))
                eraseNext(index - 1)
            }
        }
        eraseNext(chars.count - 1)
    }
}

// MARK: - Search helper

private func isLikelyURL(_ string: String) -> Bool {
    // URL complète avec scheme
    if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("ftp://") {
        return URL(string: string) != nil
    }
    // Domaine sans scheme : ex. google.com, sub.domain.co.uk
    let parts = string.components(separatedBy: ".")
    guard parts.count >= 2 else { return false }
    let tld = parts.last ?? ""
    // TLD valide (2-6 lettres, pas de espaces)
    let validTLD = tld.count >= 2 && tld.count <= 6 && tld.allSatisfy({ $0.isLetter })
    let noSpaces = !string.contains(" ")
    return validTLD && noSpaces
}

private func openSearch(_ query: String) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }

    // Détection URL
    if isLikelyURL(q) {
        var urlString = q
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") && !urlString.hasPrefix("ftp://") {
            urlString = "https://\(urlString)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }
    }

    // Recherche classique
    let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    let engine = WidgetDefaults.string(key: "engine", widgetId: "simple-search", default: "Google")
    let raw: String
    switch engine {
    case "DuckDuckGo": raw = "https://duckduckgo.com/?q=\(enc)"
    case "Bing":       raw = "https://www.bing.com/search?q=\(enc)"
    default:           raw = "https://www.google.com/search?q=\(enc)"
    }
    if let url = URL(string: raw) { NSWorkspace.shared.open(url) }
}

// MARK: - Panel invisible (mode double)

private struct InvisiblePanelView: View {
    let bridge: SearchBridge
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        InvisibleTextField(
            text: $query,
            onSubmit: {
                openSearch(query)
                query = ""
                bridge.text = ""
                // Calcule le suffixe visible dans le widget au moment du submit
                let font = NSFont.systemFont(ofSize: 15)
                let widgetWidth = UISettings.fieldWidth
                let visible = visibleSuffix(of: bridge.displayText, font: font, width: widgetWidth)
                bridge.startErasing(visibleText: visible) {
                    bridge.isActive = false
                    dismiss()
                }
            },
            onEscape: {
                query = ""
                bridge.text = ""
                bridge.isActive = false
                dismiss()
            }
        )
        .frame(width: 0, height: 0)
        .opacity(0)
        .onChange(of: query) { _, new in
            bridge.text = new
            bridge.displayText = new
        }
        .onAppear  {
            bridge.isActive = true
            bridge.text = ""
            bridge.displayText = ""
        }
        .onDisappear {
            bridge.isActive = false
            bridge.text = ""
            bridge.displayText = ""
        }
    }
}

// MARK: - NSTextField invisible

private struct InvisibleTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alphaValue = 0.01
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeKey()
            field.window?.makeFirstResponder(field)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            field.window?.makeKey()
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InvisibleTextField
        init(_ p: InvisibleTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            if sel == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            return false
        }
    }
}

// MARK: - Panel visible (mode simple)

private struct SimpleSearchPanelView: View {
    let dismiss: () -> Void
    @State private var query = ""
    @State private var isSubmitting = false

    var body: some View {
        HStack(spacing: 8) {
            AutoFocusTextField(
                text: $query,
                placeholder: "Search…",
                onSubmit: { submit() },
                onEscape: { dismiss() }
            )
            .frame(height: 22)

            if !query.isEmpty && !isSubmitting {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Button { submit() } label: {
                Image(systemName: isSubmitting ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .foregroundStyle(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .tertiary : .primary)
                    .scaleEffect(isSubmitting ? 1.3 : 1.0)
                    .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSubmitting)
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(6)
        .frame(width: 320)
        .animation(.easeOut(duration: 0.15), value: isSubmitting)
    }

    private func submit() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation { isSubmitting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            openSearch(query)
            query = ""
            isSubmitting = false
            dismiss()
        }
    }
}

// MARK: - AutoFocusTextField (panel visible)

private struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 15)
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeKey()
            field.window?.makeFirstResponder(field)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            field.window?.makeKey()
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusTextField
        init(_ p: AutoFocusTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            if sel == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            return false
        }
    }
}

// MARK: - Widget View

private struct SimpleSearchWidgetView: View {
    let size: CGSize
    let isVertical: Bool
    let bridge: SearchBridge

    private var dim: CGFloat { min(size.width, size.height) }
    private var isExtended: Bool {
        isVertical
            ? size.height > size.width  * 1.5
            : size.width  > size.height * 1.5
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
                .contentShape(Rectangle())

            if isExtended || bridge.isActive {
                fieldDisplayView
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
            } else {
                iconView
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: bridge.isActive)
    }

    private var iconView: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: dim * 0.38, weight: .medium))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }

    private var fieldDisplayView: some View {
        let fontSize: CGFloat = min(dim * 0.34, 15)
        // Stocker la largeur disponible pour le calcul du suffixe visible
        UISettings.fieldWidth = size.width - 8 * 2 - (fontSize * 0.9 + 5)
        return HStack(spacing: 5) {
            if !bridge.isActive && !bridge.isErasing {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: fontSize * 0.9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            TextWithCursor(
                text: bridge.isErasing ? bridge.displayText : bridge.text,
                fontSize: fontSize,
                showCursor: bridge.isActive && !bridge.isErasing
            )
            .frame(maxWidth: (bridge.isActive || bridge.isErasing) ? .infinity : nil, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: (bridge.isActive || bridge.isErasing) ? .leading : .center)
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.15), value: bridge.isActive)
        .animation(.easeOut(duration: 0.15), value: bridge.isErasing)
    }
}

// MARK: - Helper suffix visible

private func visibleSuffix(of text: String, font: NSFont, width: CGFloat) -> String {
    guard !text.isEmpty else { return text }
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    var start = text.startIndex
    while start < text.endIndex {
        let sub = String(text[start...])
        if (sub as NSString).size(withAttributes: attrs).width <= width { return sub }
        start = text.index(after: start)
    }
    return String(text.last ?? Character(" "))
}

// MARK: - TextWithCursor

private struct TextWithCursor: View {
    let text: String
    let fontSize: CGFloat
    let showCursor: Bool
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 0) {
            if showCursor && text.isEmpty {
                cursor
            }
            if !text.isEmpty {
                GeometryReader { geo in
                    let font = NSFont.systemFont(ofSize: fontSize)
                    let visible = visibleSuffix(of: text, font: font, width: geo.size.width)
                    HStack(spacing: 0) {
                        Text(visible)
                            .font(.system(size: fontSize, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize()
                        if showCursor { cursor }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(height: fontSize * 1.4)
            } else if !showCursor {
                Text("Type")
                    .font(.system(size: fontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var cursor: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 1.5, height: fontSize * 1.1)
            .opacity(cursorOn ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    cursorOn.toggle()
                }
            }
    }
}
