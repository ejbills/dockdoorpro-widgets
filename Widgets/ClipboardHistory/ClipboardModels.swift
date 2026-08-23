import AppKit
import SwiftUI

// MARK: - Clipboard Data Types

enum ClipboardDataType: Equatable, Sendable {
    case text(String)
    case image(Data)
    case url(URL)
    case fileURL(URL)
}

enum TextSubtype: Sendable {
    case color(Color)
    case url(URL)
    case email
    case phone
    case date
    case code

    var icon: String {
        switch self {
        case .color: return "paintpalette"
        case .url:   return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .date:  return "calendar"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        }
    }

    var label: String {
        switch self {
        case .color: return "Color"
        case .url:   return "URL"
        case .email: return "Email"
        case .phone: return "Phone"
        case .date:  return "Date"
        case .code:  return "Code"
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Sendable {
    case all
    case data
    case media

    var title: String {
        switch self {
        case .all:   return "All"
        case .data:  return "Data"
        case .media: return "Media"
        }
    }

    var icon: String {
        switch self {
        case .all:   return "square.grid.2x2"
        case .data:  return "doc.text"
        case .media: return "photo"
        }
    }
}

// MARK: - Clipboard Item Model

struct ClipboardItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let data: ClipboardDataType
    let timestamp: Date
    let source: String
    var isPinned: Bool
    let originalText: String?

    let cachedColor: Color?
    let cachedSubtype: TextSubtype?

    var isModified: Bool {
        guard let originalText else { return false }
        switch data {
        case .text(let t): return t != originalText
        case .url(let u): return u.absoluteString != originalText
        default: return false
        }
    }

    init(
        id: UUID = UUID(),
        data: ClipboardDataType,
        timestamp: Date,
        source: String,
        isPinned: Bool = false,
        originalText: String? = nil
    ) {
        self.id = id
        self.data = data
        self.timestamp = timestamp
        self.source = source
        self.isPinned = isPinned
        self.originalText = originalText
        if case .text(let t) = data {
            self.cachedColor = Self.detectColor(in: t)
            self.cachedSubtype = Self.detectSubtype(in: t)
        } else {
            self.cachedColor = nil
            self.cachedSubtype = nil
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayText: String {
        switch data {
        case let .text(text):    text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:             ""
        case let .url(url):      url.absoluteString
        case let .fileURL(url):  url.lastPathComponent
        }
    }

    var typeIcon: String {
        cachedSubtype?.icon ?? {
            switch data {
            case .text:    "doc.text"
            case .image:   "photo"
            case .url:     "link"
            case .fileURL: "doc"
            }
        }()
    }

    var typeLabel: String {
        cachedSubtype?.label ?? {
            switch data {
            case .text:              "Text"
            case .image:             "Image"
            case .url:               "Link"
            case let .fileURL(url):  url.pathExtension.uppercased()
            }
        }()
    }

    // MARK: - Regex Matchers & Color Detectors

    private static let regexHex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$")
    }()
    private static let regexRGB: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^rgb\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*\\)$", options: .caseInsensitive)
    }()
    private static let regexHSL: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^hsl\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})%\\s*,\\s*(\\d{1,3})%\\s*\\)$", options: .caseInsensitive)
    }()
    private static let regexEmail: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}$")
    }()
    private static let regexPhone: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^[\\+]?[\\d\\s\\-().]{7,}$")
    }()
    private static let regexDate: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^\\d{1,4}[/\\-.]\\d{1,2}[/\\-.]\\d{1,4}$")
    }()
    private static let regexCode: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "[{}<>\\[\\];=]|\\bfunc\\b|\\bvar\\b|\\blet\\b|\\bclass\\b|\\bimport\\b|\\breturn\\b|\\bdef\\b|\\bfunction\\b")
    }()

    static func detectColor(in text: String) -> Color? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if let regexHex, regexHex.firstMatch(in: trimmed, range: range) != nil {
            var hex = trimmed.dropFirst()
            if hex.count == 3 { hex = Substring(hex.map { "\($0)\($0)" }.joined()) }
            let scanner = Scanner(string: String(hex))
            var rgb: UInt64 = 0
            if scanner.scanHexInt64(&rgb) {
                return Color(
                    red:   Double((rgb >> 16) & 0xFF) / 255,
                    green: Double((rgb >> 8)  & 0xFF) / 255,
                    blue:  Double( rgb        & 0xFF) / 255
                )
            }
        }

        if let regexRGB, regexRGB.firstMatch(in: trimmed, range: range) != nil {
            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count >= 3 {
                let r = min(max(Double(nums[0]), 0), 255) / 255
                let g = min(max(Double(nums[1]), 0), 255) / 255
                let b = min(max(Double(nums[2]), 0), 255) / 255
                return Color(red: r, green: g, blue: b)
            }
        }

        if let regexHSL, regexHSL.firstMatch(in: trimmed, range: range) != nil {
            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count >= 3 {
                let h = min(max(Double(nums[0]), 0), 360) / 360
                let s = min(max(Double(nums[1]), 0), 100) / 100
                let l = min(max(Double(nums[2]), 0), 100) / 100
                return Color(hue: h, saturation: s, brightness: l)
            }
        }

        return nil
    }

    static func detectSubtype(in text: String) -> TextSubtype? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let color = detectColor(in: trimmed) {
            return .color(color)
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
                return .url(url)
            }
        }

        if let regexEmail, regexEmail.firstMatch(in: trimmed, range: range) != nil {
            return .email
        }
        if let regexPhone, regexPhone.firstMatch(in: trimmed, range: range) != nil {
            return .phone
        }
        if let regexDate, regexDate.firstMatch(in: trimmed, range: range) != nil {
            return .date
        }
        if let regexCode, regexCode.firstMatch(in: trimmed, range: range) != nil {
            return .code
        }

        return nil
    }
}
