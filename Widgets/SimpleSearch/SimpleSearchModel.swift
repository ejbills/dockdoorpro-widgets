import DockDoorWidgetSDK
import Observation
import SwiftUI

@Observable
final class SimpleSearchModel {
    var text = ""
    var isActive = false
    var slotSpan: WidgetSlotSpan = .compact

    var isExtended: Bool { slotSpan != .compact }
    var displayText = ""
    var isErasing = false
    var prefixJustRemoved = false
    var scrolledPrefix: String? = nil
    var clipboardSuggestion: String? = nil
    var isHovering: Bool = false
    @ObservationIgnored private var lastRemovedPrefix: String? = nil
    var pendingSubmission: String?
    var activatedAt: Date?

    @ObservationIgnored private var eraseTask: Task<Void, Never>?
    @ObservationIgnored private let keyboardCapture = SimpleSearchKeyboardCapture()
    @ObservationIgnored private let widgetId: String
    // "Last used" gardé EN MÉMOIRE (pas de UserDefaults) : le modèle vit tant que
    // DockDoor Pro tourne, donc le dernier moteur persiste sur toute la session d'usage.
    @ObservationIgnored private var lastUsedEngine: String?

    init(widgetId: String) {
        self.widgetId = widgetId
    }

    func configure(size: CGSize, isVertical: Bool) {
        slotSpan = SimpleSearchLayout.span(size: size, isVertical: isVertical)
    }

    // Moteur sur lequel ouvrir : "Last used" (mémoire) si le réglage l'active, sinon défaut.
    func openingEngine() -> String? {
        let mode = WidgetDefaults.string(key: "defaultEngineMode", widgetId: widgetId, default: "Default")
        if mode == "Last used", let last = lastUsedEngine,
           shortcutsEnabled(widgetId: widgetId), !hiddenEngines(widgetId: widgetId).contains(last) {
            return last
        }
        return defaultScrolledPrefix(widgetId: widgetId)
    }

    func cycleEngine(by step: Int) {
        guard shortcutsEnabled(widgetId: widgetId) else { return }
        cancelScrolledReset()  // toute activité de scroll annule un reset en attente
        let keys = visibleEngineKeys(widgetId: widgetId)
        guard !keys.isEmpty else { return }
        let current = scrolledPrefix ?? keys[0]
        let idx = keys.firstIndex(of: current) ?? 0
        scrolledPrefix = keys[(idx + step + keys.count) % keys.count]
    }

    // Le panneau single lit `scrolledPrefix` à l'ouverture. Quand il se ferme VRAIMENT,
    // on remet le moteur d'ouverture (« Last used » si activé, sinon défaut). Le
    // clignotement du panneau (host) annule ce reset via onAppear, donc seule une vraie
    // fermeture le déclenche.
    @ObservationIgnored private var scrollResetTask: Task<Void, Never>?

    func cancelScrolledReset() {
        scrollResetTask?.cancel()
        scrollResetTask = nil
    }

    func scheduleScrolledReset() {
        scrollResetTask?.cancel()
        scrollResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.scrolledPrefix = self.openingEngine()  // respecte « Last used »
        }
    }

    func activate() {
        eraseTask?.cancel()
        isErasing = false
        isActive = true
        prefixJustRemoved = false
        scrolledPrefix = openingEngine()
        clipboardSuggestion = readClipboardSuggestion(widgetId: widgetId)
        text = ""
        displayText = ""
        activatedAt = .now
        keyboardCapture.start(
            initialText: "",
            onChange: { [weak self] query in
                self?.updateQuery(query)
            },
            onSubmit: { [weak self] in
                self?.submit()
            },
            onCancel: { [weak self] in
                self?.reset()
            },
            chipRemoveCheck: { [weak self] prefix in
                guard let self, !self.prefixJustRemoved else { return false }
                return resolvedShortcuts(widgetId: self.widgetId)[prefix.lowercased()] != nil
            },
            onChipRemove: { [weak self] removedPrefix in
                self?.lastRemovedPrefix = removedPrefix
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self?.prefixJustRemoved = true
                }
            },
            onEmptyBackspace: { [weak self] in
                guard let self, self.scrolledPrefix != nil else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.scrolledPrefix = nil
                }
                return true
            },
            tabPrefixCheck: { [weak self] prefix in
                guard let self else { return false }
                guard shortcutsEnabled(widgetId: self.widgetId) else { return false }
                guard tabConfirmsPrefix(widgetId: self.widgetId) else { return false }
                guard !self.prefixJustRemoved, self.scrolledPrefix == nil else { return false }
                return resolvedShortcuts(widgetId: self.widgetId)[prefix] != nil
            },
            onTabWhenEmpty: { [weak self] in
                // Champ vide + suggestion presse-papier → Tab l'accepte.
                guard let self, let suggestion = self.clipboardSuggestion else { return nil }
                self.clipboardSuggestion = nil
                return suggestion
            },
            onArrow: { [weak self] step in
                // Flèches ↑/↓ (champ vide) : cycle de moteur, comme le panneau.
                guard let self, shortcutsEnabled(widgetId: self.widgetId) else { return false }
                self.cycleEngine(by: step)
                return true
            }
        )
    }

    func updateQuery(_ query: String) {
        if !query.isEmpty { clipboardSuggestion = nil }
        if prefixJustRemoved {
            if query.isEmpty {
                prefixJustRemoved = false
                lastRemovedPrefix = nil
            } else if query.hasSuffix(" ") {
                let candidate = String(query.dropLast()).lowercased()
                if !candidate.isEmpty && !candidate.contains(" ") &&
                   candidate != lastRemovedPrefix &&
                   resolvedShortcuts(widgetId: widgetId)[candidate] != nil {
                    prefixJustRemoved = false
                    lastRemovedPrefix = nil
                }
            }
        }
        text = query
        displayText = query
    }

    func reset() {
        eraseTask?.cancel()
        keyboardCapture.stop()
        isActive = false
        isErasing = false
        prefixJustRemoved = false
        lastRemovedPrefix = nil
        scrolledPrefix = nil
        clipboardSuggestion = nil
        isHovering = false
        text = ""
        displayText = ""
        activatedAt = nil
    }

    func recordLastUsedEngine(_ prefix: String?) {
        guard let prefix, !prefix.isEmpty else { return }
        lastUsedEngine = prefix  // en mémoire uniquement
    }

    func clearPendingSubmission() {
        pendingSubmission = nil
        prefixJustRemoved = false
    }

    func startErasing(visibleText: String, completion: @escaping () -> Void) {
        eraseTask?.cancel()

        guard !visibleText.isEmpty else {
            completion()
            return
        }

        isErasing = true
        displayText = visibleText
        let characters = Array(visibleText)

        eraseTask = Task { @MainActor in
            for index in stride(from: characters.count - 1, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(5))
                guard !Task.isCancelled else { return }
                displayText = String(characters.prefix(index))
            }

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            isErasing = false
            completion()
        }
    }

    func submit() {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine the engine used and build the effective query
        let typedPrefix: String? = {
            guard scrolledPrefix == nil, !prefixJustRemoved, let spaceIdx = rawText.firstIndex(of: " ") else { return nil }
            let candidate = String(rawText[..<spaceIdx]).lowercased()
            return resolvedShortcuts(widgetId: widgetId)[candidate] != nil ? candidate : nil
        }()

        let usedEngine = typedPrefix ?? scrolledPrefix

        let scrolledIsStatic: Bool = {
            guard typedPrefix == nil, let sp = scrolledPrefix,
                  let template = resolvedShortcuts(widgetId: widgetId)[sp] else { return false }
            return !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
        }()

        // Prepend scrolledPrefix if the user typed no prefix of their own
        let effectiveText: String
        if let sp = scrolledPrefix, typedPrefix == nil, !rawText.isEmpty {
            effectiveText = "\(sp) \(rawText)"
        } else if scrolledIsStatic, let sp = scrolledPrefix {
            effectiveText = sp
        } else {
            effectiveText = rawText
        }

        guard !effectiveText.isEmpty else { return }

        recordLastUsedEngine(usedEngine)

        pendingSubmission = effectiveText
        text = ""
        displayText = ""
        keyboardCapture.stop()

        startErasing(visibleText: rawText.isEmpty ? effectiveText : rawText) {
            self.reset()
        }
    }
}
