import AppKit
import DockDoorWidgetSDK
import QuickLookThumbnailing
import SwiftUI

// MARK: - Display style

/// How the folder presents its files when activated.
///
/// - ``stack``: the native vertical Downloads stack (icons rising from the dock).
/// - ``grid``: a scrollable grid of every file in the folder.
enum FolderDisplayStyle: String, CaseIterable {
    case stack
    case grid

    /// Maps a settings picker value (e.g. "Stack", "Grid") to a style.
    init(setting: String) {
        self = FolderDisplayStyle(rawValue: setting.lowercased()) ?? .stack
    }

    /// Picker option labels exposed in the widget settings.
    static var settingOptions: [String] { ["Stack", "Grid"] }
}

// MARK: - File click action

/// What happens when the user clicks a file in the stack.
enum FileClickAction {
    /// Open with the default app; reveal in Finder when right-clicked or a modifier is held.
    case openRevealOnModifier
    /// Always open with the default app.
    case open
    /// Always reveal the file in Finder.
    case revealInFinder

    init(setting: String) {
        switch setting {
        case "Open": self = .open
        case "Reveal in Finder": self = .revealInFinder
        default: self = .openRevealOnModifier
        }
    }
}

// MARK: - Thumbnails

/// Caches file icons and QuickLook thumbnails (real previews for images, PDFs,
/// videos, etc.). Icons are returned instantly; thumbnails resolve async.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let thumbnails = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()

    /// Generic type icon, available synchronously. Used as a placeholder.
    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(image, forKey: key)
        return image
    }

    func cachedThumbnail(for url: URL) -> NSImage? {
        thumbnails.object(forKey: url.path as NSString)
    }

    /// Generates the best QuickLook representation (a true preview when one
    /// exists, otherwise the type icon) and calls `completion` on the main queue.
    func thumbnail(for url: URL, pixelSize: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = url.path as NSString
        if let cached = thumbnails.object(forKey: key) {
            completion(cached)
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixelSize, height: pixelSize),
            scale: 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else { return }
            let image = representation.nsImage
            self?.thumbnails.setObject(image, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
    }
}

/// Shows a file's QuickLook thumbnail, falling back to its type icon while the
/// preview generates (or if none exists).
struct FileThumbnail: View {
    let url: URL
    var pixelSize: CGFloat = 128

    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: resolved)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .onAppear(perform: load)
            .onChange(of: url) { _, _ in
                image = nil
                load()
            }
    }

    private var resolved: NSImage {
        image ?? ThumbnailCache.shared.cachedThumbnail(for: url) ?? ThumbnailCache.shared.icon(for: url)
    }

    private func load() {
        if let cached = ThumbnailCache.shared.cachedThumbnail(for: url) {
            image = cached
            return
        }
        ThumbnailCache.shared.thumbnail(for: url, pixelSize: pixelSize) { generated in
            image = generated
        }
    }
}

// MARK: - Widget anchor

/// Tracks the widget's live position on screen so the floating stack window can
/// anchor to it and follow when the dock (and therefore the widget) moves.
final class WidgetAnchor {
    private(set) var screenFrame: CGRect?
    private var lastNotifiedFrame: CGRect?

    /// Invoked on the main thread whenever the widget's screen frame changes.
    var onChange: ((CGRect) -> Void)?

    /// Set by the tracker view; forces an immediate re-measurement of the
    /// widget's frame. Used to follow the widget during dock animations that
    /// don't post window move/resize notifications.
    var refresh: (() -> Void)?

    /// Records the latest frame and only fires ``onChange`` when it has actually
    /// moved. The follow loop polls every display refresh, but the widget sits
    /// still the vast majority of the time, so this skips the expensive window
    /// repositioning on every idle tick.
    func update(_ frame: CGRect) {
        screenFrame = frame
        if let last = lastNotifiedFrame, Self.isApproximatelyEqual(last, frame) {
            return
        }
        lastNotifiedFrame = frame
        onChange?(frame)
    }

    private static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }
}

// MARK: - File entry

/// A single file (or sub-folder) shown in the stack.
struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let modificationDate: Date

    var name: String { url.lastPathComponent }

    /// Cached type icon, used as the drag image. Routed through ``ThumbnailCache``
    /// so repeated SwiftUI updates don't hit Icon Services for every visible row.
    var icon: NSImage { ThumbnailCache.shared.icon(for: url) }

    static func == (lhs: FileEntry, rhs: FileEntry) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - Store

/// Reads the pinned folder (configured via the widget's settings) and exposes
/// its contents, most-recent first, plus the file open/reveal actions.
@Observable
final class FolderStore {
    private let widgetId: String

    var entries: [FileEntry] = []

    init(widgetId: String) {
        self.widgetId = widgetId
    }

    /// The pinned folder. Resolved from the `folderPath` text-field setting,
    /// expanding a leading `~`, and defaulting to `~/Downloads`.
    var folderURL: URL {
        let raw = WidgetDefaults.string(key: "folderPath", widgetId: widgetId, default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return Self.defaultDownloadsFolder() }
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    var folderName: String { folderURL.lastPathComponent }

    var displayStyle: FolderDisplayStyle {
        FolderDisplayStyle(setting: WidgetDefaults.string(key: "displayStyle", widgetId: widgetId, default: "Stack"))
    }

    var clickAction: FileClickAction {
        FileClickAction(setting: WidgetDefaults.string(key: "fileClickAction", widgetId: widgetId, default: "Open & Reveal on right-click"))
    }

    var maxItems: Int {
        Int(WidgetDefaults.double(key: "maxItems", widgetId: widgetId, default: 10))
    }

    /// The single most-recent entry, used for the dock-slot preview.
    var topEntry: FileEntry? { entries.first }

    /// Entries trimmed to the configured maximum for the stack presentation.
    var stackedEntries: [FileEntry] {
        Array(entries.prefix(max(1, maxItems)))
    }

    // MARK: Folder resolution

    private static func defaultDownloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: Reading

    /// Scans the pinned folder on a background queue and publishes the result on
    /// the main thread. Keeping the enumeration off the main thread avoids a UI
    /// hitch for large folders (e.g. a busy Downloads). `completion` runs on the
    /// main thread once `entries` has been updated.
    func refresh(completion: (() -> Void)? = nil) {
        let url = folderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = Self.scan(url)
            DispatchQueue.main.async {
                self.entries = scanned
                completion?()
            }
        }
    }

    private static func scan(_ folderURL: URL) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let mapped: [FileEntry] = items.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            let modDate = values?.contentModificationDate ?? .distantPast
            let isDir = values?.isDirectory ?? false
            return FileEntry(url: url, isDirectory: isDir, modificationDate: modDate)
        }

        return mapped.sorted { $0.modificationDate > $1.modificationDate }
    }

    // MARK: Actions

    func handleClick(_ entry: FileEntry, revealOverride: Bool) {
        switch clickAction {
        case .open:
            open(entry)
        case .revealInFinder:
            reveal(entry)
        case .openRevealOnModifier:
            revealOverride ? reveal(entry) : open(entry)
        }
    }

    func open(_ entry: FileEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    func reveal(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// Opens the pinned folder itself in Finder.
    func openFolder() {
        NSWorkspace.shared.open(folderURL)
    }

    // MARK: Drop-in (move files into the pinned folder)

    /// Moves a dropped file/folder into the pinned folder, resolving name
    /// collisions. No-op if the item already lives in the folder.
    @discardableResult
    func moveIntoFolder(_ source: URL) -> Bool {
        let fm = FileManager.default
        let folder = folderURL

        // Already inside the folder — nothing to do.
        if source.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return false
        }

        let destination = uniqueDestination(for: source.lastPathComponent, in: folder)
        do {
            try fm.moveItem(at: source, to: destination)
        } catch {
            // Cross-volume or permission issues: fall back to a copy.
            guard (try? fm.copyItem(at: source, to: destination)) != nil else { return false }
        }
        refresh()
        return true
    }

    private func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            index += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
