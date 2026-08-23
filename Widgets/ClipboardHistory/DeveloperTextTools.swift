import Foundation

// MARK: - Developer & Text Formatting Tools

enum DeveloperTextTools {
    static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
              let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    static func beautifyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return formatted
    }

    static func minifyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let compactData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              let formatted = String(data: compactData, encoding: .utf8) else {
            return nil
        }
        return formatted
    }

    static func isBase64(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count % 4 == 0,
              let data = Data(base64Encoded: trimmed),
              let str = String(data: data, encoding: .utf8), !str.isEmpty else {
            return false
        }
        return true
    }

    static func decodeBase64(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func encodeBase64(_ text: String) -> String {
        return Data(text.utf8).base64EncodedString()
    }

    static func isURLEncoded(_ text: String) -> Bool {
        return text.contains("%") && (text.removingPercentEncoding != text)
    }

    static func decodeURL(_ text: String) -> String? {
        return text.removingPercentEncoding
    }

    static func encodeURL(_ text: String) -> String? {
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }

    static func cleanPlainText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "“", with: "\"")
                       .replacingOccurrences(of: "”", with: "\"")
                       .replacingOccurrences(of: "‘", with: "'")
                       .replacingOccurrences(of: "’", with: "'")
        let lines = result.components(separatedBy: .newlines)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func toCamelCase(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let first = words.first?.lowercased() else { return text }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return first + rest.joined()
    }

    static func toSnakeCase(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.map { $0.lowercased() }.joined(separator: "_")
    }

    static func toKebabCase(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.map { $0.lowercased() }.joined(separator: "-")
    }

    static func toUpperCase(_ text: String) -> String {
        return text.uppercased()
    }

    static func toLowerCase(_ text: String) -> String {
        return text.lowercased()
    }
}
