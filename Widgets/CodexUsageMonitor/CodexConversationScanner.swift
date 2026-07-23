import Foundation

struct CodexConversationSnapshot: Sendable {
    let conversations: [CodexRecentConversation]
    let projectCount: Int
    let activeCount: Int
    let updatedAt: Date
}

struct CodexRecentConversation: Identifiable, Sendable {
    let id: String
    let title: String?
    let projectName: String
    let projectPath: String
    let createdAt: Date?
    let modifiedAt: Date
    let isActive: Bool
    let isArchived: Bool

    var relativeActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modifiedAt, relativeTo: Date())
    }

    var codexDeepLink: URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
}

struct CodexConversationScanner: Sendable {
    private static let maximumCandidateCount = 120
    private static let maximumPrefixBytes = 1024 * 1024
    private static let maximumHistoryBytes = 2 * 1024 * 1024
    private static let activeWindow: TimeInterval = 30 * 60

    func scan(limit: Int = 8) async -> CodexConversationSnapshot {
        await Task.detached(priority: .utility) {
            Self.buildSnapshot(limit: limit)
        }.value
    }

    private static func buildSnapshot(limit: Int) -> CodexConversationSnapshot {
        let resolvedLimit = max(3, min(12, limit))
        let now = Date()
        let historyTitles = historyTitlesBySessionID()
        var conversations: [CodexRecentConversation] = []

        for file in sessionFiles().prefix(maximumCandidateCount) {
            guard !Task.isCancelled else { break }
            guard let metadata = sessionMetadataAndTitle(from: file.url),
                  !metadata.isSubagent
            else { continue }

            let projectURL = URL(fileURLWithPath: metadata.cwd).standardizedFileURL
            let projectName = projectURL.lastPathComponent.isEmpty
                ? projectURL.path
                : projectURL.lastPathComponent
            let id = metadata.id ?? file.url.deletingPathExtension().lastPathComponent
            let title = metadata.title ?? historyTitles[id]

            conversations.append(CodexRecentConversation(
                id: id,
                title: title,
                projectName: projectName,
                projectPath: projectURL.path,
                createdAt: metadata.createdAt,
                modifiedAt: file.modifiedAt,
                isActive: now.timeIntervalSince(file.modifiedAt) < activeWindow,
                isArchived: file.isArchived
            ))

            if conversations.count >= resolvedLimit {
                break
            }
        }

        return CodexConversationSnapshot(
            conversations: conversations,
            projectCount: Set(conversations.map(\.projectPath)).count,
            activeCount: conversations.filter(\.isActive).count,
            updatedAt: now
        )
    }

    private static func sessionFiles() -> [ConversationFile] {
        let home = codexHome()
        let roots = [
            (home.appendingPathComponent("sessions", isDirectory: true), false),
            (home.appendingPathComponent("archived_sessions", isDirectory: true), true),
        ]
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey,
        ]
        var files: [ConversationFile] = []

        for (root, isArchived) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl",
                      let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else { continue }

                files.append(ConversationFile(
                    url: fileURL,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    isArchived: isArchived
                ))
            }
        }

        return files.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.url.path < rhs.url.path
        }
    }

    private static func sessionMetadataAndTitle(
        from url: URL
    ) -> ConversationMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maximumPrefixBytes),
              let prefix = String(data: data, encoding: .utf8)
        else { return nil }

        var sessionID: String?
        var cwd: String?
        var createdAt: Date?
        var isSubagent = false
        var title: String?

        for line in prefix.split(separator: "\n").prefix(120) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { continue }

            if type == "session_meta" {
                sessionID = payload["id"] as? String
                    ?? payload["session_id"] as? String
                cwd = payload["cwd"] as? String
                createdAt = parseDate(
                    payload["timestamp"] as? String
                        ?? object["timestamp"] as? String
                )
                isSubagent = sourceIsSubagent(payload["source"])
                continue
            }

            if type == "event_msg",
               payload["type"] as? String == "user_message",
               title == nil
            {
                title = normalizedTitle(
                    payload["message"] as? String
                        ?? payload["text"] as? String
                )
            }

            if cwd != nil, title != nil {
                break
            }
        }

        guard let cwd, !cwd.isEmpty else { return nil }
        return ConversationMetadata(
            id: sessionID,
            cwd: cwd,
            createdAt: createdAt,
            title: title,
            isSubagent: isSubagent
        )
    }

    private static func historyTitlesBySessionID() -> [String: String] {
        let url = codexHome().appendingPathComponent("history.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(fileSize, UInt64(maximumHistoryBytes))
        try? handle.seek(toOffset: fileSize - readSize)

        guard let data = try? handle.read(upToCount: Int(readSize)),
              let text = String(data: data, encoding: .utf8)
        else { return [:] }

        var titles: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let sessionID = object["session_id"] as? String,
                  let title = normalizedTitle(object["text"] as? String)
            else { continue }
            titles[sessionID] = title
        }
        return titles
    }

    private static func sourceIsSubagent(_ source: Any?) -> Bool {
        if let source = source as? String {
            return source.lowercased() == "subagent"
        }
        if let source = source as? [String: Any] {
            return source["subagent"] != nil
        }
        return false
    }

    private static func normalizedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let title = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return title.count > 120 ? String(title.prefix(120)) + "…" : title
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func codexHome() -> URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty
        {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
}

private struct ConversationFile {
    let url: URL
    let modifiedAt: Date
    let isArchived: Bool
}

private struct ConversationMetadata {
    let id: String?
    let cwd: String
    let createdAt: Date?
    let title: String?
    let isSubagent: Bool
}
