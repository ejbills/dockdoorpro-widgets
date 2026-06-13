import DockDoorWidgetSDK
import Foundation

func searchURL(for query: String, widgetId: String) -> URL? {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return nil }

    if let url = urlFromPossibleAddress(trimmedQuery) {
        return url
    }

    let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery

    let customURL = WidgetDefaults.string(key: "customEngineURL", widgetId: widgetId)
    if !customURL.isEmpty {
        let raw = customURL.replacingOccurrences(of: "%s", with: encodedQuery)
        return URL(string: raw)
    }

    let engine = WidgetDefaults.string(key: "engine", widgetId: widgetId, default: "Google")

    let rawURL = switch engine {
    case "DuckDuckGo":
        "https://duckduckgo.com/?q=\(encodedQuery)"
    case "Bing":
        "https://www.bing.com/search?q=\(encodedQuery)"
    case "Yahoo":
        "https://search.yahoo.com/search?p=\(encodedQuery)"
    case "Qwant":
        "https://www.qwant.com/?q=\(encodedQuery)"
    case "Kagi":
        "https://kagi.com/search?q=\(encodedQuery)"
    case "Brave":
        "https://search.brave.com/search?q=\(encodedQuery)"
    case "Ecosia":
        "https://www.ecosia.org/search?q=\(encodedQuery)"
    case "Yandex":
        "https://yandex.com/search/?text=\(encodedQuery)"
    case "YouTube":
        "https://www.youtube.com/results?search_query=\(encodedQuery)"
    default:
        "https://www.google.com/search?q=\(encodedQuery)"
    }

    return URL(string: rawURL)
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
