import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.ejbills.DockDoorPro", category: "ClipboardWidget")

enum ClipboardDataType {
    case text(String)
    case image(Data)
    case url(URL)
    case fileURL(URL)
}

enum TextSubtype: Sendable {
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

struct ClipboardItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let data: ClipboardDataType
    let timestamp: Date
    let source: String
    var isPinned: Bool

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

    // Cached NSRegularExpression patterns
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

    static func detectSubtype(in text: String) -> TextSubtype {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")),
           let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return .url
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let regexEmail, regexEmail.firstMatch(in: trimmed, range: range) != nil { return .email }
        if let regexPhone, regexPhone.firstMatch(in: trimmed, range: range) != nil { return .phone }
        if let regexDate, regexDate.firstMatch(in: trimmed, range: range) != nil { return .date }
        if trimmed.count > 3, let regexCode, regexCode.firstMatch(in: trimmed, range: range) != nil { return .code }

        return .text
    }
}

enum ClipboardFilter: CaseIterable, Sendable {
    case all, media, data

    var icon: String {
        switch self {
        case .all:   "square.grid.2x2"
        case .media: "photo"
        case .data:  "info.circle"
        }
    }
}

// MARK: - Disk Persistence Protocol & Actor

protocol ClipboardStorageProtocol: Sendable {
    func load() -> [ClipboardItem]
    func save(items: [ClipboardItem])
    func clearAll()
}

private struct PersistedItemDTO: Codable {
    let id: UUID
    let type: String
    let textValue: String?
    let urlString: String?
    let imageFilename: String?
    let timestamp: Date
    let source: String
    let isPinned: Bool
}

final class ClipboardStorage: ClipboardStorageProtocol, @unchecked Sendable {
    static let shared = ClipboardStorage()

    private let fileManager = FileManager.default
    private let baseDir: URL
    private let imagesDir: URL
    private let indexFile: URL
    private let queue = DispatchQueue(label: "net.dockdoor.clipboard.storage", qos: .utility)
    private var pendingWorkItem: DispatchWorkItem?

    // Max 15MB per cached image file to prevent memory exhaustion DoS
    private let maxImageByteSize = 15 * 1024 * 1024

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
            guard !data.isEmpty else { return [] }
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
                    guard let attributes = try? fileManager.attributesOfItem(atPath: imgURL.path),
                          let fileSize = attributes[.size] as? Int,
                          fileSize <= maxImageByteSize,
                          let imgData = try? Data(contentsOf: imgURL) else { return nil }
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
            logger.error("Failed to decode history.json: \(error.localizedDescription)")
            // Backup corrupted file
            let backupFile = baseDir.appendingPathComponent("history.json.corrupted")
            try? fileManager.moveItem(at: indexFile, to: backupFile)
            return []
        }
    }

    // FIX #3 & PERF #1: Debounced background atomic save
    func save(items: [ClipboardItem]) {
        let snapshot = items
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.performSave(items: snapshot)
            }
            self.pendingWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }

    private func performSave(items: [ClipboardItem]) {
        do {
            try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)

            var activeImageFilenames = Set<String>()
            var dtos: [PersistedItemDTO] = []
            dtos.reserveCapacity(items.count)

            for item in items {
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
                    guard data.count <= maxImageByteSize else { continue }
                    let filename = "\(item.id.uuidString).dat"
                    activeImageFilenames.insert(filename)
                    let fileURL = imagesDir.appendingPathComponent(filename)
                    if !fileManager.fileExists(atPath: fileURL.path) {
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
            try encoded.write(to: indexFile, options: .atomic)

            // Cleanup deleted image files
            if let files = try? fileManager.contentsOfDirectory(atPath: imagesDir.path) {
                for file in files where !activeImageFilenames.contains(file) {
                    try? fileManager.removeItem(at: imagesDir.appendingPathComponent(file))
                }
            }
        } catch {
            logger.error("Failed to save clipboard history to disk: \(error.localizedDescription)")
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingWorkItem?.cancel()
            try? self.fileManager.removeItem(at: self.indexFile)
            try? self.fileManager.removeItem(at: self.imagesDir)
            try? self.fileManager.createDirectory(at: self.imagesDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Observable Manager State

@Observable
final class ClipboardManagerState: @unchecked Sendable {
    var clipboardItems: [ClipboardItem] = []
    var isPersistenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPersistenceEnabled, forKey: "ClipboardHistory_persistRestarts")
            if isPersistenceEnabled {
                storage.save(items: clipboardItems)
            }
        }
    }

    var maxHistoryCount: Int = 100
    private var isInternalCopy = false
    private var lastChangeCount: Int = 0
    private let storage: ClipboardStorageProtocol

    var pinnedItems: [ClipboardItem] { clipboardItems.filter { $0.isPinned } }
    var unpinnedItems: [ClipboardItem] { clipboardItems.filter { !$0.isPinned } }

    init(storage: ClipboardStorageProtocol = ClipboardStorage.shared) {
        self.storage = storage
        let persistedPreference = UserDefaults.standard.object(forKey: "ClipboardHistory_persistRestarts")
        let shouldPersist = (persistedPreference as? Bool) ?? true
        self.isPersistenceEnabled = shouldPersist

        if shouldPersist {
            self.clipboardItems = storage.load()
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

    func updateItemText(_ item: ClipboardItem, newText: String) -> ClipboardItem? {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return nil }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedData: ClipboardDataType
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")),
           let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            updatedData = .url(url)
        } else {
            updatedData = .text(newText)
        }

        let updatedItem = ClipboardItem(
            id: item.id,
            data: updatedData,
            timestamp: Date(),
            source: item.source,
            isPinned: item.isPinned
        )
        clipboardItems[idx] = updatedItem
        if isPersistenceEnabled {
            storage.save(items: clipboardItems)
        }
        return updatedItem
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[idx].isPinned.toggle()
        if isPersistenceEnabled {
            storage.save(items: clipboardItems)
        }
    }

    func removeItem(_ item: ClipboardItem) {
        clipboardItems.removeAll { $0.id == item.id }
        if isPersistenceEnabled {
            storage.save(items: clipboardItems)
        }
    }

    func clearAllItems() {
        clipboardItems.removeAll { !$0.isPinned }
        if isPersistenceEnabled {
            storage.save(items: clipboardItems)
        }
    }

    private func detectClipboardData(from pasteboard: NSPasteboard) -> ClipboardDataType? {
        // Privacy & Security: Filter out password managers and concealed/transient types
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
            storage.save(items: clipboardItems)
        }
    }
}
