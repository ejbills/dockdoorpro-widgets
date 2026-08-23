import AppKit
import SwiftUI

enum ClipboardDataType {
    case text(String)
    case image(Data)
    case url(URL)
    case fileURL(URL)
}

enum TextSubtype {
    case email, phone, date, code, url, text

    var icon: String {
        switch self {
        case .email: "envelope"
        case .phone: "phone"
        case .date:  "calendar"
        case .code:  "chevron.left.forwardslash.chevron.right"
        case .url:   "globe.americas.fill"
        case .text:  "doc.plaintext"
        }
    }

    var label: String {
        switch self {
        case .email: "Email"
        case .phone: "Phone"
        case .date:  "Date"
        case .code:  "Code"
        case .url:   "Link"
        case .text:  "Text"
        }
    }
}

struct ClipboardItem: Identifiable, Hashable {
    let id: UUID
    let data: ClipboardDataType
    let timestamp: Date
    let source: String
    var isPinned: Bool = false

    let cachedColor: Color?
    let cachedSubtype: TextSubtype?

    init(id: UUID = UUID(), data: ClipboardDataType, timestamp: Date, source: String, isPinned: Bool = false) {
        self.id = id
        self.data = data
        self.timestamp = timestamp
        self.source = source
        self.isPinned = isPinned
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

    private static let regexHex = try! NSRegularExpression(pattern: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$")
    private static let regexRGB = try! NSRegularExpression(pattern: "^rgb\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})\\s*\\)$", options: .caseInsensitive)
    private static let regexHSL = try! NSRegularExpression(pattern: "^hsl\\(\\s*(\\d{1,3})\\s*,\\s*(\\d{1,3})%\\s*,\\s*(\\d{1,3})%\\s*\\)$", options: .caseInsensitive)

    static func detectColor(in text: String) -> Color? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if regexHex.firstMatch(in: trimmed, range: range) != nil {
            var hex = trimmed.dropFirst()
            if hex.count == 3 { hex = Substring(hex.map { "\($0)\($0)" }.joined()) }
            let scanner = Scanner(string: String(hex))
            var rgb: UInt64 = 0
            scanner.scanHexInt64(&rgb)
            return Color(
                red:   Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8)  & 0xFF) / 255,
                blue:  Double( rgb        & 0xFF) / 255
            )
        }

        if regexRGB.firstMatch(in: trimmed, range: range) != nil {
            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count >= 3 {
                return Color(red: Double(nums[0]) / 255, green: Double(nums[1]) / 255, blue: Double(nums[2]) / 255)
            }
        }

        if regexHSL.firstMatch(in: trimmed, range: range) != nil {
            let nums = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if nums.count >= 3 {
                return Color(hue: Double(nums[0]) / 360, saturation: Double(nums[1]) / 100, brightness: Double(nums[2]) / 100)
            }
        }

        return nil
    }

    private static let regexURL   = try! NSRegularExpression(pattern: "^https?://\\S+$", options: .caseInsensitive)
    private static let regexEmail = try! NSRegularExpression(pattern: "^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}$")
    private static let regexPhone = try! NSRegularExpression(pattern: "^[\\+]?[\\d\\s\\-().]{7,}$")
    private static let regexDate  = try! NSRegularExpression(pattern: "^\\d{1,4}[/\\-.]\\d{1,2}[/\\-.]\\d{1,4}$")
    private static let regexCode  = try! NSRegularExpression(pattern: "[{}<>\\[\\];=]|\\bfunc\\b|\\bvar\\b|\\blet\\b|\\bclass\\b|\\bimport\\b|\\breturn\\b|\\bdef\\b|\\bfunction\\b")

    static func detectSubtype(in text: String) -> TextSubtype {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if regexURL.firstMatch(in: trimmed, range: range)   != nil { return .url }
        if regexEmail.firstMatch(in: trimmed, range: range) != nil { return .email }
        if regexPhone.firstMatch(in: trimmed, range: range) != nil { return .phone }
        if regexDate.firstMatch(in: trimmed, range: range)  != nil { return .date }
        if trimmed.count > 3 && regexCode.firstMatch(in: trimmed, range: range) != nil { return .code }

        return .text
    }
}

enum ClipboardFilter: CaseIterable {
    case all, media, data

    var icon: String {
        switch self {
        case .all:   "square.grid.2x2"
        case .media: "photo"
        case .data:  "info.circle"
        }
    }
}

// MARK: - Disk Persistence Storage

private struct PersistedItemDTO: Codable {
    let id: UUID
    let type: String // "text", "image", "url", "fileURL"
    let textValue: String?
    let urlString: String?
    let imageFilename: String?
    let timestamp: Date
    let source: String
    let isPinned: Bool
}

final class ClipboardStorage: @unchecked Sendable {
    static let shared = ClipboardStorage()

    private let fileManager = FileManager.default
    private let baseDir: URL
    private let imagesDir: URL
    private let indexFile: URL
    private let queue = DispatchQueue(label: "net.dockdoor.clipboard.storage", qos: .utility)

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDir = appSupport.appendingPathComponent("DockDoorPro/Clipboard", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("Images", isDirectory: true)
        indexFile = baseDir.appendingPathComponent("history.json")

        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func load() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: indexFile.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexFile)
            let dtos = try JSONDecoder().decode([PersistedItemDTO].self, from: data)
            return dtos.compactMap { dto -> ClipboardItem? in
                let dataType: ClipboardDataType
                switch dto.type {
                case "text":
                    guard let text = dto.textValue else { return nil }
                    dataType = .text(text)
                case "url":
                    guard let urlStr = dto.urlString, let url = URL(string: urlStr) else { return nil }
                    dataType = .url(url)
                case "fileURL":
                    guard let urlStr = dto.urlString, let url = URL(string: urlStr) else { return nil }
                    dataType = .fileURL(url)
                case "image":
                    guard let imgFile = dto.imageFilename else { return nil }
                    let imgURL = imagesDir.appendingPathComponent(imgFile)
                    guard let imgData = try? Data(contentsOf: imgURL) else { return nil }
                    dataType = .image(imgData)
                default:
                    return nil
                }
                return ClipboardItem(
                    id: dto.id,
                    data: dataType,
                    timestamp: dto.timestamp,
                    source: dto.source,
                    isPinned: dto.isPinned
                )
            }
        } catch {
            return []
        }
    }

    func save(items: [ClipboardItem]) {
        let snapshot = items
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.fileManager.createDirectory(at: self.imagesDir, withIntermediateDirectories: true)

                var activeImageFilenames = Set<String>()
                var dtos: [PersistedItemDTO] = []

                for item in snapshot {
                    switch item.data {
                    case .text(let text):
                        dtos.append(PersistedItemDTO(
                            id: item.id,
                            type: "text",
                            textValue: text,
                            urlString: nil,
                            imageFilename: nil,
                            timestamp: item.timestamp,
                            source: item.source,
                            isPinned: item.isPinned
                        ))
                    case .url(let url):
                        dtos.append(PersistedItemDTO(
                            id: item.id,
                            type: "url",
                            textValue: nil,
                            urlString: url.absoluteString,
                            imageFilename: nil,
                            timestamp: item.timestamp,
                            source: item.source,
                            isPinned: item.isPinned
                        ))
                    case .fileURL(let url):
                        dtos.append(PersistedItemDTO(
                            id: item.id,
                            type: "fileURL",
                            textValue: nil,
                            urlString: url.absoluteString,
                            imageFilename: nil,
                            timestamp: item.timestamp,
                            source: item.source,
                            isPinned: item.isPinned
                        ))
                    case .image(let data):
                        let filename = "\(item.id.uuidString).dat"
                        activeImageFilenames.insert(filename)
                        let fileURL = self.imagesDir.appendingPathComponent(filename)
                        if !self.fileManager.fileExists(atPath: fileURL.path) {
                            try? data.write(to: fileURL, options: .atomic)
                        }
                        dtos.append(PersistedItemDTO(
                            id: item.id,
                            type: "image",
                            textValue: nil,
                            urlString: nil,
                            imageFilename: filename,
                            timestamp: item.timestamp,
                            source: item.source,
                            isPinned: item.isPinned
                        ))
                    }
                }

                let encoded = try JSONEncoder().encode(dtos)
                try encoded.write(to: self.indexFile, options: .atomic)

                // Cleanup deleted image files
                if let files = try? self.fileManager.contentsOfDirectory(atPath: self.imagesDir.path) {
                    for file in files where !activeImageFilenames.contains(file) {
                        try? self.fileManager.removeItem(at: self.imagesDir.appendingPathComponent(file))
                    }
                }
            } catch {
                // Log silently
            }
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.indexFile)
            try? self.fileManager.removeItem(at: self.imagesDir)
            try? self.fileManager.createDirectory(at: self.imagesDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Observable Manager State

@Observable
final class ClipboardManagerState {
    var clipboardItems: [ClipboardItem] = []
    var isPersistenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPersistenceEnabled, forKey: "ClipboardHistory_persistRestarts")
            if isPersistenceEnabled {
                ClipboardStorage.shared.save(items: clipboardItems)
            }
        }
    }

    var maxHistoryCount: Int = 100
    private var isInternalCopy = false
    private var lastChangeCount: Int = 0

    var pinnedItems: [ClipboardItem] { clipboardItems.filter { $0.isPinned } }
    var unpinnedItems: [ClipboardItem] { clipboardItems.filter { !$0.isPinned } }

    init() {
        let persistedPreference = UserDefaults.standard.object(forKey: "ClipboardHistory_persistRestarts")
        let shouldPersist = (persistedPreference as? Bool) ?? true
        self.isPersistenceEnabled = shouldPersist

        if shouldPersist {
            let loaded = ClipboardStorage.shared.load()
            self.clipboardItems = loaded
        }
    }

    func togglePersistence() {
        isPersistenceEnabled.toggle()
    }

    func filteredItems(_ filter: ClipboardFilter) -> [ClipboardItem] {
        switch filter {
        case .all:   clipboardItems
        case .media: clipboardItems.filter {
            if case .image = $0.data { return true }
            if case .fileURL = $0.data { return true }
            return false
        }
        case .data:  clipboardItems.filter {
            if case .text = $0.data { return true }
            if case .url = $0.data { return true }
            return false
        }
        }
    }

    func loadCurrentClipboard() {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        if let data = detectClipboardData(from: pasteboard) {
            let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            addClipboardItem(data: data, source: source)
        }
    }

    func refresh() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        if isInternalCopy {
            lastChangeCount = changeCount
            isInternalCopy = false
            return
        }

        lastChangeCount = changeCount
        if let data = detectClipboardData(from: pasteboard) {
            let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            addClipboardItem(data: data, source: source)
        }
    }

    func copyItemToClipboard(_ item: ClipboardItem) {
        isInternalCopy = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.data {
        case let .text(text):       pasteboard.setString(text, forType: .string)
        case let .image(imageData): pasteboard.setData(imageData, forType: .tiff)
        case let .url(url):         pasteboard.setString(url.absoluteString, forType: .string)
        case let .fileURL(url):     pasteboard.writeObjects([url as NSURL])
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[idx].isPinned.toggle()
        if isPersistenceEnabled {
            ClipboardStorage.shared.save(items: clipboardItems)
        }
    }

    func removeItem(_ item: ClipboardItem) {
        clipboardItems.removeAll { $0.id == item.id }
        if isPersistenceEnabled {
            ClipboardStorage.shared.save(items: clipboardItems)
        }
    }

    func clearAllItems() {
        clipboardItems.removeAll { !$0.isPinned }
        if isPersistenceEnabled {
            ClipboardStorage.shared.save(items: clipboardItems)
        }
    }

    private func detectClipboardData(from pasteboard: NSPasteboard) -> ClipboardDataType? {
        // Privacy / Password Protection: Skip concealed or transient password types
        let concealedTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
            NSPasteboard.PasteboardType("com.agilebits.onepassword"),
            NSPasteboard.PasteboardType("de.stefanimhoff.stefan.KeePassXC")
        ]
        if let types = pasteboard.types {
            for cType in concealedTypes where types.contains(cType) {
                return nil
            }
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = fileURLs.first {
            return .fileURL(fileURL)
        }
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return .image(imageData)
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            if let url = URL(string: string), url.scheme != nil, url.host != nil {
                return .url(url)
            }
            return .text(string)
        }
        return nil
    }

    private func addClipboardItem(data: ClipboardDataType, source: String) {
        clipboardItems.removeAll { item in
            guard !item.isPinned else { return false }
            switch (data, item.data) {
            case let (.text(a), .text(b)):       return a == b
            case let (.url(a), .url(b)):         return a.absoluteString == b.absoluteString
            case let (.fileURL(a), .fileURL(b)): return a.path == b.path
            case let (.image(a), .image(b)):     return a == b
            default: return false
            }
        }

        let insertIdx = pinnedItems.count
        clipboardItems.insert(ClipboardItem(data: data, timestamp: Date(), source: source), at: insertIdx)

        let unpinned = clipboardItems.filter { !$0.isPinned }
        if unpinned.count > maxHistoryCount {
            if let last = unpinned.last {
                clipboardItems.removeAll { $0.id == last.id }
            }
        }

        if isPersistenceEnabled {
            ClipboardStorage.shared.save(items: clipboardItems)
        }
    }
}
