import DockDoorWidgetSDK
import Foundation
import SwiftUI

func searchURL(for query: String, widgetId: String, skipShortcuts: Bool = false) -> URL? {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return nil }

    if let url = urlFromPossibleAddress(trimmedQuery) {
        return url
    }

    if !skipShortcuts,
       shortcutsEnabled(widgetId: widgetId),
       let url = urlFromShortcut(trimmedQuery, widgetId: widgetId) {
        return url
    }

    let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery
    let rawEngine = WidgetDefaults.string(key: "engine", widgetId: widgetId, default: "Google (g)")
    let engine = rawEngine.hasPrefix("⊘ ") ? String(rawEngine.dropFirst(2)) : rawEngine

    if engine.hasSuffix(")"), let openParen = engine.lastIndex(of: "(") {
        let prefix = String(engine[engine.index(after: openParen)..<engine.index(before: engine.endIndex)])
        if !builtinShortcuts.keys.contains(prefix) {
            let shortcuts = resolvedShortcuts(widgetId: widgetId)
            if let template = shortcuts[prefix] {
                let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
                if isStatic { return URL(string: template.hasPrefix("http") ? template : "https://\(template)") }
                let url = template
                    .replacingOccurrences(of: "%s", with: encodedQuery)
                    .replacingOccurrences(of: "[Input]", with: encodedQuery)
                    .replacingOccurrences(of: "{searchTerms}", with: encodedQuery)
                return URL(string: url.hasPrefix("http") ? url : "https://\(url)")
            }
        }
    }

    let rawURL = switch engine {
    case "DuckDuckGo (ddg)": "https://duckduckgo.com/?q=\(encodedQuery)"
    case "Bing (bg)":        "https://www.bing.com/search?q=\(encodedQuery)"
    case "Yahoo (yh)":       "https://search.yahoo.com/search?p=\(encodedQuery)"
    case "Qwant (qw)":       "https://www.qwant.com/?q=\(encodedQuery)"
    case "Kagi (ka)":        "https://kagi.com/search?q=\(encodedQuery)"
    case "Brave (br)":       "https://search.brave.com/search?q=\(encodedQuery)"
    case "Ecosia (eco)":     "https://www.ecosia.org/search?q=\(encodedQuery)"
    case "Yandex (yx)":      "https://yandex.com/search/?text=\(encodedQuery)"
    case "YouTube (yt)":     "https://www.youtube.com/results?search_query=\(encodedQuery)"
    case "Reddit (red)":     "https://www.reddit.com/search/?q=\(encodedQuery)"
    default:                 "https://www.google.com/search?q=\(encodedQuery)"
    }

    return URL(string: rawURL)
}

private let builtinShortcuts: [String: String] = [
    "g":    "https://www.google.com/search?q=[Input]",
    "ddg":  "https://duckduckgo.com/?q=[Input]",
    "bg":   "https://www.bing.com/search?q=[Input]",
    "yh":   "https://search.yahoo.com/search?p=[Input]",
    "qw":   "https://www.qwant.com/?q=[Input]",
    "ka":   "https://kagi.com/search?q=[Input]",
    "br":   "https://search.brave.com/search?q=[Input]",
    "eco":  "https://www.ecosia.org/search?q=[Input]",
    "yx":   "https://yandex.com/search/?text=[Input]",
    "yt":   "https://www.youtube.com/results?search_query=[Input]",
    "red":  "https://www.reddit.com/search/?q=[Input]",
]

let builtinDisplayNames: [String: String] = [
    "g": "Google", "ddg": "DuckDuckGo", "bg": "Bing",
    "yh": "Yahoo", "qw": "Qwant", "ka": "Kagi",
    "br": "Brave", "eco": "Ecosia", "yx": "Yandex",
    "yt": "YouTube", "red": "Reddit"
]

private let builtinColors: [String: String] = [
    "g":   "4285F4",  // Google blue
    "ddg": "DE5833",  // DuckDuckGo orange
    "bg":  "0078D4",  // Bing blue
    "yh":  "6001D2",  // Yahoo purple
    "qw":  "5C40CC",  // Qwant indigo
    "ka":  "E8701A",  // Kagi amber
    "br":  "FB542B",  // Brave orange
    "eco": "1EAB35",  // Ecosia green
    "yx":  "FC3F1D",  // Yandex red
    "yt":  "FF0000",  // YouTube red
    "red": "FF4500",  // Reddit orange-red
]

func engineDisplayName(for prefix: String, widgetId: String) -> String {
    if let name = builtinDisplayNames[prefix] { return name }
    guard let template = resolvedShortcuts(widgetId: widgetId)[prefix] else { return prefix }
    let clean = template
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "www.", with: "")
    let host = clean.components(separatedBy: "/").first ?? clean
    let name = host.components(separatedBy: ".").first ?? host
    return name.prefix(1).uppercased() + name.dropFirst()
}

func resolvedShortcuts(widgetId: String) -> [String: String] {
    var shortcuts = builtinShortcuts
    for row in customEngineRows(widgetId: widgetId) {
        let prefix = (row["prefix"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let url = (row["url"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, !url.isEmpty else { continue }
        shortcuts[prefix] = url
    }
    return shortcuts
}

/// Custom engines as table rows (columns: prefix, url, color).
/// Falls back to migrating the legacy `custom_1…20` text fields until the user
/// edits the table, so existing setups keep working after the SDK update.
func customEngineRows(widgetId: String) -> [[String: String]] {
    WidgetDefaults.tableRows(key: "customEngines", widgetId: widgetId, default: legacyCustomRows(widgetId: widgetId))
}

func legacyCustomRows(widgetId: String) -> [[String: String]] {
    var rows: [[String: String]] = []
    for i in 1...20 {
        let v = WidgetDefaults.string(key: "custom_\(i)", widgetId: widgetId).trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, let parsed = parseCustomEngine(v), !parsed.url.isEmpty else { continue }
        var row = ["prefix": parsed.prefix, "url": parsed.url]
        if let hex = parsed.hexColor { row["color"] = hex }
        rows.append(row)
    }
    return rows
}

/// Normalize a hex string from the color column (`#f00`, `f00`, `FF0000` → `FF0000`).
func normalizedHex(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s = String(s.dropFirst()) }
    guard hexIsValid(s) else { return nil }
    if s.count == 3 { s = s.flatMap { [String($0), String($0)] }.joined() }
    return s.uppercased()
}

func parseCustomEngine(_ raw: String) -> (prefix: String, url: String, hexColor: String?)? {
    let v = raw.trimmingCharacters(in: .whitespaces)
    guard !v.isEmpty, let firstComma = v.firstIndex(of: ",") else { return nil }
    let prefix = String(v[..<firstComma]).trimmingCharacters(in: .whitespaces).lowercased()
    let rest = String(v[v.index(after: firstComma)...]).trimmingCharacters(in: .whitespaces)
    guard !prefix.isEmpty, !rest.isEmpty else { return nil }

    if let lastComma = rest.lastIndex(of: ",") {
        let candidate = String(rest[rest.index(after: lastComma)...]).trimmingCharacters(in: .whitespaces)
        let hexStr = candidate.hasPrefix("#") ? String(candidate.dropFirst()) : candidate
        if hexIsValid(hexStr) {
            let url = String(rest[..<lastComma]).trimmingCharacters(in: .whitespaces)
            if !url.isEmpty {
                let expanded = hexStr.count == 3
                    ? hexStr.flatMap { [String($0), String($0)] }.joined()
                    : hexStr
                return (prefix, url, expanded.uppercased())
            }
        }
    }
    return (prefix, rest, nil)
}

private func hexIsValid(_ s: String) -> Bool {
    (s.count == 3 || s.count == 6) && s.allSatisfy { "0123456789ABCDEFabcdef".contains($0) }
}

func engineColor(for prefix: String, widgetId: String, isStatic: Bool = false) -> Color {
    for row in customEngineRows(widgetId: widgetId) {
        let rowPrefix = (row["prefix"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard rowPrefix == prefix else { continue }
        if let raw = row["color"], let hex = normalizedHex(raw), let color = Color(hex: hex) { return color }
        break
    }
    if let hex = builtinColors[prefix], let color = Color(hex: hex) { return color }
    return isStatic ? .green : .blue
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private func urlFromShortcut(_ query: String, widgetId: String) -> URL? {
    let shortcuts = resolvedShortcuts(widgetId: widgetId)

    if let spaceIdx = query.firstIndex(of: " ") {
        let prefix = String(query[..<spaceIdx]).lowercased()
        let term = String(query[query.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, !prefix.contains(" "), let template = shortcuts[prefix] else { return nil }
        let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
        if isStatic { return URL(string: template.hasPrefix("http") ? template : "https://\(template)") }
        guard !term.isEmpty else { return nil }
        let encoded = term.replacingOccurrences(of: " ", with: "+")
        let url = template
            .replacingOccurrences(of: "%s", with: encoded)
            .replacingOccurrences(of: "[Input]", with: encoded)
            .replacingOccurrences(of: "{searchTerms}", with: encoded)
        return URL(string: url.hasPrefix("http") ? url : "https://\(url)")
    }

    let prefix = query.lowercased()
    guard !prefix.isEmpty, !prefix.contains(" "), let template = shortcuts[prefix] else { return nil }
    let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
    guard isStatic else { return nil }
    return URL(string: template.hasPrefix("http") ? template : "https://\(template)")
}

// Réglage fusionné "Prefix Shortcuts" (menu 3 choix), remplace les 2 anciens toggles.
// Migre automatiquement depuis les clés bool `shortcutsEnabled` + `tabConfirmsPrefix`
// tant que l'utilisateur n'a pas touché au nouveau menu.
let prefixShortcutsOff = "Off"
let prefixShortcutsSpace = "Space to confirm"
let prefixShortcutsSpaceTab = "Space or Tab to confirm"

func prefixShortcutsMode(widgetId: String) -> String {
    let stored = WidgetDefaults.string(key: "prefixShortcuts", widgetId: widgetId, default: "")
    if !stored.isEmpty { return stored }
    guard WidgetDefaults.bool(key: "shortcutsEnabled", widgetId: widgetId, default: true) else { return prefixShortcutsOff }
    return WidgetDefaults.bool(key: "tabConfirmsPrefix", widgetId: widgetId, default: false)
        ? prefixShortcutsSpaceTab : prefixShortcutsSpace
}

func shortcutsEnabled(widgetId: String) -> Bool {
    prefixShortcutsMode(widgetId: widgetId) != prefixShortcutsOff
}

func tabConfirmsPrefix(widgetId: String) -> Bool {
    prefixShortcutsMode(widgetId: widgetId) == prefixShortcutsSpaceTab
}

// Lit le presse-papier si le réglage est actif : texte court normalisé sur une ligne.
// Utilisé par le panneau ET l'inline pour la suggestion « Suggest Clipboard ».
func readClipboardSuggestion(widgetId: String) -> String? {
    guard WidgetDefaults.bool(key: "clipboardSuggest", widgetId: widgetId, default: false),
          let clip = NSPasteboard.general.string(forType: .string) else { return nil }
    let normalized = clip
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    return normalized.isEmpty ? nil : normalized
}

func hiddenEngines(widgetId: String) -> Set<String> {
    let raw = WidgetDefaults.string(key: "hiddenEngines", widgetId: widgetId, default: "")
    return Set(raw.components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty })
}

func visibleEngineKeys(widgetId: String) -> [String] {
    let hidden = hiddenEngines(widgetId: widgetId)
    return Array(resolvedShortcuts(widgetId: widgetId).keys)
        .filter { !hidden.contains($0) }
        .sorted()
}

func defaultScrolledPrefix(widgetId: String) -> String? {
    guard shortcutsEnabled(widgetId: widgetId) else { return nil }
    let hidden = hiddenEngines(widgetId: widgetId)
    let mode = WidgetDefaults.string(key: "defaultEngineMode", widgetId: widgetId, default: "None")
    switch mode {
    case "Last used":
        let last = UserDefaults.standard.string(forKey: "simple-search.\(widgetId).lastUsedEngine")
        return last.flatMap { hidden.contains($0) ? nil : $0 }
    default:
        let engineStr = WidgetDefaults.string(key: "engine", widgetId: widgetId, default: "Google (g)")
        let prefix = prefixFromOption(engineStr)
        return prefix.flatMap { hidden.contains($0) ? nil : $0 }
    }
}

func saveLastUsedEngine(_ prefix: String, widgetId: String) {
    let mode = WidgetDefaults.string(key: "defaultEngineMode", widgetId: widgetId, default: "None")
    guard mode == "Last used" else { return }
    UserDefaults.standard.set(prefix, forKey: "simple-search.\(widgetId).lastUsedEngine")
}

private func prefixFromOption(_ option: String) -> String? {
    guard option.hasSuffix(")"), let openParen = option.lastIndex(of: "(") else { return nil }
    let prefix = String(option[option.index(after: openParen)..<option.index(before: option.endIndex)]).lowercased()
    return prefix.isEmpty ? nil : prefix
}

private func urlFromPossibleAddress(_ string: String) -> URL? {
    if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("ftp://") {
        return URL(string: string)
    }

    let parts = string.split(separator: ".")
    guard parts.count >= 2, let topLevelDomain = parts.last else { return nil }

    let hasValidTopLevelDomain = topLevelDomain.count >= 2
        && topLevelDomain.count <= 6
        && topLevelDomain.allSatisfy(\.isLetter)

    guard hasValidTopLevelDomain, !string.contains(" ") else { return nil }

    return URL(string: "https://\(string)")
}
