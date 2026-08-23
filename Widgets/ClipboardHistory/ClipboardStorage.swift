import Foundation
import os

// MARK: - Clipboard Storage Protocol

protocol ClipboardStorageProtocol: Sendable {
    func load() -> [ClipboardItem]
    func save(items: [ClipboardItem])
    func clearAll()
}

// MARK: - Persisted Item DTO

struct PersistedItemDTO: Codable {
    let id: UUID
    let type: String
    let textValue: String?
    let urlString: String?
    let imageFilename: String?
    let timestamp: Date
    let source: String
    let isPinned: Bool
    let originalText: String?
}

// MARK: - Storage Implementation

final class ClipboardStorage: ClipboardStorageProtocol, @unchecked Sendable {
    static let shared = ClipboardStorage()

    private let logger = Logger(subsystem: "net.dockdoor.clipboard", category: "Storage")
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
                    isPinned: dto.isPinned,
                    originalText: dto.originalText
                )
            }
        } catch {
            logger.error("Failed to decode history.json: \(error.localizedDescription)")
            let backupFile = baseDir.appendingPathComponent("history.json.corrupted")
            try? fileManager.moveItem(at: indexFile, to: backupFile)
            return []
        }
    }

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
                        isPinned: item.isPinned,
                        originalText: item.originalText
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
                        isPinned: item.isPinned,
                        originalText: item.originalText
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
                        isPinned: item.isPinned,
                        originalText: item.originalText
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
                        isPinned: item.isPinned,
                        originalText: nil
                    ))
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dtos)
            try data.write(to: indexFile, options: .atomic)

            // Garbage collect unreferenced cached image files
            if let files = try? fileManager.contentsOfDirectory(atPath: imagesDir.path) {
                for file in files where !activeImageFilenames.contains(file) {
                    try? fileManager.removeItem(at: imagesDir.appendingPathComponent(file))
                }
            }
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingWorkItem?.cancel()
            try? self.fileManager.removeItem(at: self.indexFile)
            if let files = try? self.fileManager.contentsOfDirectory(atPath: self.imagesDir.path) {
                for file in files {
                    try? self.fileManager.removeItem(at: self.imagesDir.appendingPathComponent(file))
                }
            }
        }
    }
}
