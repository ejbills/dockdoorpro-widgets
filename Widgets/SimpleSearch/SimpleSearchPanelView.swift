import DockDoorWidgetSDK
import SwiftUI

struct SimpleSearchPanelView: View {
    let widgetId: String
    var model: SimpleSearchModel? = nil
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var activePrefix: String?
    @State private var isStaticLink = false
    @State private var isSubmitting = false
    @State private var isHoveringClear = false
    @State private var isHoveringSearch = false
    @State private var skipNextDetect = false
    @State private var prefixJustRemoved = false
    @State private var scrolledPrefix: String? = nil
    @State private var scrollAccumulator: CGFloat = 0
    @State private var scrollMonitor: Any? = nil
    @State private var clipboardSuggestion: String? = nil
    @ScaledMetric(relativeTo: .title3) private var fieldHeight: CGFloat = 26

    private var engineKeys: [String] {
        visibleEngineKeys(widgetId: widgetId)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeChipColor: Color {
        guard let prefix = activePrefix else { return .blue }
        return engineColor(for: prefix, widgetId: widgetId, isStatic: isStaticLink)
    }

    private var cursorTintColor: Color {
        if let prefix = activePrefix { return engineColor(for: prefix, widgetId: widgetId, isStatic: isStaticLink) }
        if let prefix = scrolledPrefix { return engineColor(for: prefix, widgetId: widgetId) }
        return .accentColor
    }

    private var scrolledIsStatic: Bool {
        guard activePrefix == nil, let sp = scrolledPrefix,
              let template = resolvedShortcuts(widgetId: widgetId)[sp] else { return false }
        return !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
    }

    private var fieldPlaceholder: String {
        if let suggestion = clipboardSuggestion, query.isEmpty {
            return suggestion
        }
        if let prefix = scrolledPrefix, activePrefix == nil {
            let shortcuts = resolvedShortcuts(widgetId: widgetId)
            let template = shortcuts[prefix] ?? ""
            let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
            return isStatic ? "Press Enter to open" : "Type to search…"
        }
        guard activePrefix != nil else { return "Search or URL" }
        return isStaticLink ? "Press Enter to open" : "Type to search…"
    }

    private var fieldBinding: Binding<String> {
        Binding(
            get: { (activePrefix != nil || scrolledPrefix != nil) && query.isEmpty ? "\u{200B}" : query },
            set: { newValue in
                if activePrefix != nil && newValue.isEmpty {
                    let prefix = activePrefix!
                    skipNextDetect = true
                    prefixJustRemoved = true
                    query = prefix + " "
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activePrefix = nil
                        isStaticLink = false
                    }
                } else if scrolledPrefix != nil && activePrefix == nil && newValue.isEmpty {
                    scrollAccumulator = 0
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        scrolledPrefix = nil
                    }
                } else {
                    query = newValue.replacingOccurrences(of: "\u{200B}", with: "")
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            if let prefix = activePrefix {
                Text(engineDisplayName(for: prefix, widgetId: widgetId))
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeChipColor, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.scale.combined(with: .opacity))
            } else if let prefix = scrolledPrefix {
                Text(engineDisplayName(for: prefix, widgetId: widgetId))
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(engineColor(for: prefix, widgetId: widgetId), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.scale.combined(with: .opacity))
            }

            AutoFocusTextField(
                text: fieldBinding,
                placeholder: fieldPlaceholder,
                placeholderIcon: clipboardSuggestion != nil && query.isEmpty ? "clipboard.fill" : nil,
                height: fieldHeight,
                tintColor: cursorTintColor,
                onSubmit: submit,
                onChange: { newValue in
                    if clipboardSuggestion != nil, !query.isEmpty { clipboardSuggestion = nil }
                    if skipNextDetect { skipNextDetect = false; return }
                    guard activePrefix == nil, scrolledPrefix == nil else { return }
                    detectPrefix(in: newValue)
                },
                onTabPress: {
                    if let suggestion = clipboardSuggestion, query.isEmpty {
                        clipboardSuggestion = nil
                        query = suggestion
                        return .handled
                    }
                    guard shortcutsEnabled(widgetId: widgetId),
                          tabConfirmsPrefix(widgetId: widgetId),
                          activePrefix == nil, scrolledPrefix == nil else { return .ignored }
                    let raw = query.replacingOccurrences(of: "\u{200B}", with: "")
                    guard !raw.isEmpty, !raw.contains(" "),
                          resolvedShortcuts(widgetId: widgetId)[raw.lowercased()] != nil else { return .ignored }
                    query = raw + " "
                    detectPrefix(in: raw + " ")
                    return .handled
                },
                onArrow: { step in
                    guard shortcutsEnabled(widgetId: widgetId) else { return .ignored }
                    cycleEngine(by: step)
                    return .handled
                }
            )
            .id("search-field")

            if !query.isEmpty && !isSubmitting {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    query = ""
                    prefixJustRemoved = false
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(isHoveringClear ? Color.white : Color.white.opacity(0.4))
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .onHover { isHoveringClear = $0 }
                .animation(.easeOut(duration: 0.15), value: isHoveringClear)
            }

            Button("Search", systemImage: isSubmitting ? "magnifyingglass.circle.fill" : "magnifyingglass.circle", action: submit)
                .labelStyle(.iconOnly)
                .foregroundStyle(
                    (!(isStaticLink || scrolledIsStatic) && trimmedQuery.isEmpty)
                        ? Color.white.opacity(0.3)
                        : isHoveringSearch ? Color.white : Color.white.opacity(0.6)
                )
                .scaleEffect(isSubmitting ? 1.3 : 1.0)
                .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                .animation(.spring(response: 0.20, dampingFraction: 0.6), value: isSubmitting)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .disabled(!(isStaticLink || scrolledIsStatic) && trimmedQuery.isEmpty)
                .onHover { isHoveringSearch = $0 }
                .animation(.easeOut(duration: 0.15), value: isHoveringSearch)
        }
        .background {
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 320)
        .animation(.easeOut(duration: 0.15), value: isSubmitting)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activePrefix)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scrolledPrefix)
        .onChange(of: scrolledPrefix) { _, newValue in
            // Réécrit vers le modèle pour que l'icône compacte reste synchro après fermeture.
            model?.scrolledPrefix = newValue
        }
        .onAppear {
            if WidgetDefaults.bool(key: "clipboardSuggest", widgetId: widgetId, default: false),
               let clip = NSPasteboard.general.string(forType: .string) {
                let normalized = clip
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !normalized.isEmpty {
                    clipboardSuggestion = normalized
                }
            }
            model?.cancelScrolledReset()  // vraie ouverture (ou clignotement) : annule le reset en attente
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                // Ouvre sur le moteur scrollé au niveau de l'icône (compact), sinon le défaut.
                scrolledPrefix = model?.scrolledPrefix ?? defaultScrolledPrefix(widgetId: widgetId)
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
                guard shortcutsEnabled(widgetId: widgetId) else { return event }
                scrollAccumulator += event.scrollingDeltaY
                let threshold: CGFloat = 20
                if scrollAccumulator > threshold {
                    scrollAccumulator = 0
                    cycleEngine(by: -1)
                } else if scrollAccumulator < -threshold {
                    scrollAccumulator = 0
                    cycleEngine(by: 1)
                }
                return nil
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
            // Fermeture (vraie ou clignotement) : programme le retour au moteur par défaut.
            // Un clignotement rappellera onAppear → cancelScrolledReset avant les 500 ms.
            model?.scheduleScrolledReset()
        }
    }

    private func cycleEngine(by step: Int) {
        guard shortcutsEnabled(widgetId: widgetId) else { return }
        let keys = engineKeys
        guard !keys.isEmpty else { return }
        let current = activePrefix ?? scrolledPrefix ?? keys[0]
        let idx = keys.firstIndex(of: current) ?? 0
        let next = (idx + step + keys.count) % keys.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if activePrefix != nil {
                activePrefix = nil
                isStaticLink = false
            }
            scrolledPrefix = keys[next]
        }
    }

    private func detectPrefix(in text: String) {
        guard shortcutsEnabled(widgetId: widgetId) else { return }
        guard text.hasSuffix(" ") else { return }
        let candidate = String(text.dropLast()).lowercased()
        guard !candidate.isEmpty, !candidate.contains(" ") else { return }
        let shortcuts = resolvedShortcuts(widgetId: widgetId)
        guard let template = shortcuts[candidate] else { return }
        let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
        prefixJustRemoved = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activePrefix = candidate
            isStaticLink = isStatic
            query = ""
        }
    }

    private func submit() {
        if let prefix = activePrefix ?? scrolledPrefix {
            saveLastUsedEngine(prefix, widgetId: widgetId)
        }
        let staticPrefix: String? = {
            if let prefix = activePrefix { return isStaticLink ? prefix : nil }
            return scrolledIsStatic ? scrolledPrefix : nil
        }()
        if let prefix = staticPrefix {
            let shortcuts = resolvedShortcuts(widgetId: widgetId)
            if let urlStr = shortcuts[prefix] {
                let withScheme = urlStr.hasPrefix("http") ? urlStr : "https://\(urlStr)"
                if let url = URL(string: withScheme) { openURL(url) }
            }
            activePrefix = nil
            isStaticLink = false
            dismiss()
            return
        }

        guard !trimmedQuery.isEmpty else { return }

        let effectivePrefix = activePrefix ?? scrolledPrefix
        let fullQuery = effectivePrefix != nil ? "\(effectivePrefix!) \(trimmedQuery)" : trimmedQuery

        withAnimation { isSubmitting = true }

        let skipShortcuts = prefixJustRemoved
        prefixJustRemoved = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if let url = searchURL(for: fullQuery, widgetId: widgetId, skipShortcuts: skipShortcuts) {
                openURL(url)
            }
            query = ""
            activePrefix = nil
            isStaticLink = false
            isSubmitting = false
            dismiss()
        }
    }
}

private struct AutoFocusTextField: View {
    let text: Binding<String>
    let placeholder: String
    var placeholderIcon: String? = nil
    let height: CGFloat
    var tintColor: Color = .accentColor
    let onSubmit: () -> Void
    let onChange: (String) -> Void
    var onTabPress: (() -> KeyPress.Result)? = nil
    var onArrow: ((_ step: Int) -> KeyPress.Result)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundStyle(.white)
            .tint(tintColor)
            .onSubmit(onSubmit)
            .focused($isFocused)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onKeyPress(.tab) { onTabPress?() ?? .ignored }
            .onKeyPress(.upArrow) { onArrow?(-1) ?? .ignored }
            .onKeyPress(.downArrow) { onArrow?(1) ?? .ignored }
            .overlay(alignment: .leading) {
                if text.wrappedValue.isEmpty || text.wrappedValue == "\u{200B}" {
                    Group {
                        if let icon = placeholderIcon {
                            Text(" ") + Text(Image(systemName: icon)).baselineOffset(1) + Text(" \(placeholder)")
                        } else {
                            Text(placeholder)
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: text.wrappedValue) { _, newValue in onChange(newValue) }
            .onChange(of: tintColor) { _, newColor in
                Self.applyCursorColor(newColor)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.windows
                        .filter { $0 is NSPanel && $0.isVisible }
                        .forEach { $0.makeKey() }
                    isFocused = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Self.clickToShowCursor()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Self.applyCursorColor(tintColor)
                }
            }
    }

    // Colore le vrai curseur système : insertionPointColor sur le field editor +
    // la vue NSTextInsertionIndicator (macOS 14+) installée par le clic synthétique.
    private static func applyCursorColor(_ color: Color) {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let nsColor = NSColor(color)
        editor.insertionPointColor = nsColor
        var root: NSView = editor
        while let parent = root.superview, !(root is NSTextField) {
            root = parent
        }
        tintIndicators(in: root, color: nsColor)
    }

    private static func tintIndicators(in view: NSView, color: NSColor) {
        if let indicator = view as? NSTextInsertionIndicator {
            indicator.color = color
        }
        for sub in view.subviews {
            tintIndicators(in: sub, color: color)
        }
    }

    // Le curseur système n'est installé par AppKit qu'au premier clic souris dans le
    // champ : on rejoue ce clic via la file d'événements (postEvent, jamais sendEvent —
    // sendEvent bloque la boucle de tracking de mouseDown et freeze le panel).
    private static func clickToShowCursor() {
        guard let window = NSApp.keyWindow,
              let editor = window.firstResponder as? NSTextView else { return }
        let content = editor.string
        guard content.isEmpty || content == "\u{200B}" else { return }

        let rect = editor.convert(editor.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        let now = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: now + 0.001, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        else { return }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
    }
}
