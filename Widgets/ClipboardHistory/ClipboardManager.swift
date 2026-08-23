import AppKit
import SwiftUI
import os

// MARK: - Clipboard Manager State

@Observable
final class ClipboardManagerState: @unchecked Sendable {
    var clipboardItems: [ClipboardItem] = []
    var maxHistoryCount: Int = 100
    var isPersistenceEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isPersistenceEnabled, forKey: "ClipboardHistory_persist")
            if isPersistenceEnabled {
                storage.save(items: clipboardItems)
            } else {
                storage.clearAll()
            }
        }
    }

    private let storage: any ClipboardStorageProtocol
    private var lastChangeCount: Int = 0
    private var isInternalCopy = false

    var pinnedItems: [ClipboardItem] { clipboardItems.filter { $0.isPinned } }
    var unpinnedItems: [ClipboardItem] { clipboardItems.filter { !$0.isPinned } }

    init(storage: (any ClipboardStorageProtocol)? = nil) {
        let defaultStorage = storage ?? ClipboardStorage.shared
        self.storage = defaultStorage

        let shouldPersist = UserDefaults.standard.object(forKey: "ClipboardHistory_persist") as? Bool ?? true
        self.isPersistenceEnabled = shouldPersist

        if shouldPersist {
            self.clipboardItems = defaultStorage.load()
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
        lastChangeCount = pasteboard.changeCount
    }

    func updateItemText(_ item: ClipboardItem, newText: String) -> ClipboardItem? {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return nil }
        let currentPinned = clipboardItems[idx].isPinned

        let rootOriginalText: String?
        if let existingOrig = clipboardItems[idx].originalText {
            rootOriginalText = existingOrig
        } else {
            switch clipboardItems[idx].data {
            case .text(let t): rootOriginalText = t
            case .url(let u): rootOriginalText = u.absoluteString
            default: rootOriginalText = nil
            }
        }

        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedData: ClipboardDataType
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")),
           let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            updatedData = .url(url)
        } else {
            updatedData = .text(newText)
        }

        let finalOriginalText = (rootOriginalText == newText) ? nil : rootOriginalText

        let updatedItem = ClipboardItem(
            id: item.id,
            data: updatedData,
            timestamp: Date(),
            source: item.source,
            isPinned: currentPinned,
            originalText: finalOriginalText
        )
        clipboardItems[idx] = updatedItem
        if isPersistenceEnabled {
            storage.save(items: clipboardItems)
        }
        return updatedItem
    }

    func restoreItemToOriginal(_ item: ClipboardItem) -> ClipboardItem? {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == item.id }),
              let origText = clipboardItems[idx].originalText else { return nil }
        let currentPinned = clipboardItems[idx].isPinned
        let trimmed = origText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedData: ClipboardDataType
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")),
           let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            updatedData = .url(url)
        } else {
            updatedData = .text(origText)
        }

        let updatedItem = ClipboardItem(
            id: item.id,
            data: updatedData,
            timestamp: Date(),
            source: item.source,
            isPinned: currentPinned,
            originalText: nil
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

    // MARK: - Private Pasteboard Detection & Ingestion

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

    private func areDataEqual(_ a: ClipboardDataType, _ b: ClipboardDataType) -> Bool {
        switch (a, b) {
        case let (.text(t1), .text(t2)): return t1 == t2
        case let (.url(u1), .url(u2)): return u1.absoluteString == u2.absoluteString
        case let (.fileURL(f1), .fileURL(f2)): return f1.path == f2.path
        case let (.image(d1), .image(d2)): return d1.count == d2.count && d1 == d2
        default: return false
        }
    }

    private func addClipboardItem(data: ClipboardDataType, source: String) {
        // If content already matches an existing pinned item, keep it pinned and update timestamp
        if let pinnedIdx = clipboardItems.firstIndex(where: { item in
            guard item.isPinned else { return false }
            return areDataEqual(data, item.data)
        }) {
            let existing = clipboardItems[pinnedIdx]
            clipboardItems[pinnedIdx] = ClipboardItem(
                id: existing.id,
                data: existing.data,
                timestamp: Date(),
                source: source,
                isPinned: true,
                originalText: existing.originalText
            )
            if isPersistenceEnabled {
                storage.save(items: clipboardItems)
            }
            return
        }

        // Remove existing unpinned duplicate
        clipboardItems.removeAll { item in
            guard !item.isPinned else { return false }
            return areDataEqual(data, item.data)
        }

        let insertIdx = pinnedItems.count
        clipboardItems.insert(ClipboardItem(data: data, timestamp: Date(), source: source, isPinned: false), at: insertIdx)

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
