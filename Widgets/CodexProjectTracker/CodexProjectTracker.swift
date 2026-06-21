import AppKit
import DockDoorWidgetSDK
import Foundation
import SwiftUI

final class CodexProjectTrackerPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "codex-project-tracker" }
    var name: String { "Codex Tracker" }
    var iconSymbol: String { "bubble.left.and.text.bubble.right.fill" }
    var widgetDescription: String { "Tracks recent Codex projects and chat activity" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        return AnyView(CodexTrackerCompactView(size: size, isVertical: isVertical))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        return AnyView(CodexTrackerPanelView(dismiss: dismiss))
    }

    func settingsSchema() -> [WidgetSetting] {
        [
            .textField(
                key: "projectsRoot",
                label: "Codex Sessions Folder",
                placeholder: "~/.codex/sessions",
                defaultValue: CodexTrackerStore.defaultProjectsRoot.path
            ),
            .slider(
                key: "recentLimit",
                label: "Recent Session Count",
                range: 3...10,
                step: 1,
                defaultValue: 5
            ),
        ]
    }

    func performTapAction() {
        CodexAppLauncher.openCodex()
    }
}

private struct CodexTrackerCompactView: View {
    let size: CGSize
    let isVertical: Bool
    @State private var snapshot = CodexSnapshot.empty

    private var dim: CGFloat { min(size.width, size.height) }
    private var iconWidth: CGFloat { min(dim * 0.74, 34) }
    private var compactTitleSize: CGFloat { max(10, min(dim * 0.23, 13)) }
    private var titleSize: CGFloat { isVertical ? max(11, min(dim * 0.23, 14)) : max(14, min(dim * 0.30, 17)) }
    private var subtitleSize: CGFloat { isVertical ? max(9, min(dim * 0.18, 11)) : max(10, min(dim * 0.22, 12)) }
    private var isExtended: Bool {
        isVertical ? size.height > size.width * 1.5 : size.width > size.height * 1.5
    }

    var body: some View {
        Group {
            if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
        .task {
            while !Task.isCancelled {
                snapshot = await CodexTrackerStore.snapshot()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 2) {
            CodexAppIconView(size: iconWidth)
            Text("Codex")
                .font(.system(size: compactTitleSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary)
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.12) {
                    CodexAppIconView(size: iconWidth)
                    projectLabels(alignment: .center)
                }
            } else {
                HStack(spacing: dim * 0.12) {
                    CodexAppIconView(size: iconWidth)
                    projectLabels(alignment: .leading)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func projectLabels(alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: alignment, spacing: 0) {
                Text("Codex")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(snapshot.headline)
                    .font(.system(size: subtitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }
            .minimumScaleFactor(0.72)
            .layoutPriority(1)
        }
    }
}

private struct CodexAppIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = CodexAppIconProvider.icon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: max(7, size * 0.22)))
        .overlay {
            RoundedRectangle(cornerRadius: max(7, size * 0.22))
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
}

private enum CodexAppIconProvider {
    static let icon: NSImage? = {
        let fileManager = FileManager.default
        let resourceCandidates = [
            "/Applications/Codex.app/Contents/Resources/icon.icns",
            "/Applications/Codex.app/Contents/Resources/electron.icns",
            "/Applications/Codex.app/Contents/Resources/app.icns",
        ]

        for path in resourceCandidates where fileManager.fileExists(atPath: path) {
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 128, height: 128)
                return image
            }
        }

        let appPath = "/Applications/Codex.app"
        guard fileManager.fileExists(atPath: appPath) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: appPath)
        image.size = NSSize(width: 128, height: 128)
        return image
    }()
}

private struct CodexTrackerPanelView: View {
    let dismiss: () -> Void
    @State private var snapshot = CodexSnapshot.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Codex Tracker", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                StatPill(title: "Projects", value: "\(snapshot.projectCount)")
                StatPill(title: "Recent", value: "\(snapshot.activeCount)")
                StatPill(title: "Sessions", value: "\(snapshot.chatCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.sessions) { session in
                    CodexSessionRow(session: session)
                }
            }

            if let latest = snapshot.latestChat {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Latest Chat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(latest)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .task {
            snapshot = await CodexTrackerStore.snapshot()
        }
    }
}

private struct CodexSessionRow: View {
    let session: CodexSession
    @State private var isHovering = false

    var body: some View {
        Button {
            CodexAppLauncher.openSession(session)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.isActive ? "circle.fill" : "circle")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(session.isActive ? .green : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(session.title ?? session.relativeActivity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(session.relativeActivity)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(isHovering ? 0.9 : 0.0))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(.white.opacity(isHovering ? 0.10 : 0.0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open in Codex")
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CodexSnapshot {
    var projectCount: Int
    var activeCount: Int
    var chatCount: Int
    var headline: String
    var latestChat: String?
    var projects: [CodexProject]
    var sessions: [CodexSession]

    static let empty = CodexSnapshot(
        projectCount: 0,
        activeCount: 0,
        chatCount: 0,
        headline: "Loading",
        latestChat: nil,
        projects: [],
        sessions: []
    )
}

private struct CodexProject: Identifiable {
    let id: String
    let name: String
    let url: URL
    let modified: Date
    let isActive: Bool

    var relativeActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modified, relativeTo: Date())
    }
}

private struct CodexSession: Identifiable {
    let id: String
    let url: URL
    let projectName: String
    let projectURL: URL
    let modified: Date
    let title: String?
    let isActive: Bool

    var relativeActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modified, relativeTo: Date())
    }

    var codexDeepLink: URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
}

private enum CodexAppLauncher {
    private static let codexAppURL = URL(fileURLWithPath: "/Applications/Codex.app")

    static func openSession(_ session: CodexSession) {
        if let deepLink = session.codexDeepLink {
            NSWorkspace.shared.open(deepLink)
        } else {
            openCodex()
        }
    }

    static func openCodex() {
        if FileManager.default.fileExists(atPath: codexAppURL.path) {
            NSWorkspace.shared.open(codexAppURL)
        } else {
            NSWorkspace.shared.open(CodexTrackerStore.defaultProjectsRoot)
        }
    }
}

private enum CodexTrackerStore {
    static let defaultProjectsRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/sessions")

    private static let codexHome = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex")

    static func snapshot() async -> CodexSnapshot {
        await Task.detached(priority: .utility) {
            buildSnapshot()
        }.value
    }

    private static func buildSnapshot() -> CodexSnapshot {
        let sessionsRoot = configuredProjectsRoot()
        let sessionFiles = sessionFiles(in: sessionsRoot)
        let records = sessionFiles.prefix(500).compactMap { file -> CodexSessionRecord? in
            guard let metadata = sessionMetadata(from: file.url) else { return nil }
            return CodexSessionRecord(file: file, metadata: metadata)
        }
        let sessions = recentSessions(from: records)
        let projects = recentProjects(from: records)
        let latestChat = latestHistoryPrompt()
        let activeCount = sessions.filter(\.isActive).count
        let headline = sessions.first?.projectName ?? projects.first?.name ?? "No sessions"

        return CodexSnapshot(
            projectCount: projects.count,
            activeCount: activeCount,
            chatCount: sessionFiles.count,
            headline: headline,
            latestChat: latestChat,
            projects: projects,
            sessions: sessions
        )
    }

    private static func configuredProjectsRoot() -> URL {
        let path = WidgetDefaults.string(
            key: "projectsRoot",
            widgetId: "codex-project-tracker",
            default: defaultProjectsRoot.path
        )

        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    private static func recentLimit() -> Int {
        max(3, min(10, Int(WidgetDefaults.double(
            key: "recentLimit",
            widgetId: "codex-project-tracker",
            default: 5
        ))))
    }

    private static func recentProjects(from sessions: [CodexSessionRecord]) -> [CodexProject] {
        var projectsByPath: [String: CodexProject] = [:]

        for session in sessions {
            let projectURL = URL(fileURLWithPath: session.metadata.cwd).standardizedFileURL
            let path = projectURL.path
            let modified = session.metadata.timestamp ?? session.file.modified
            let existing = projectsByPath[path]

            if existing == nil || modified > existing!.modified {
                projectsByPath[path] = CodexProject(
                    id: path,
                    name: projectURL.lastPathComponent.isEmpty ? path : projectURL.lastPathComponent,
                    url: projectURL,
                    modified: modified,
                    isActive: Date().timeIntervalSince(modified) < 60 * 60 * 24 * 7
                )
            }
        }

        return projectsByPath.values
            .sorted { $0.modified > $1.modified }
            .prefix(recentLimit())
            .map { $0 }
    }

    private static func recentSessions(from sessionRecords: [CodexSessionRecord]) -> [CodexSession] {
        var sessions: [CodexSession] = []

        for record in sessionRecords {
            let projectURL = URL(fileURLWithPath: record.metadata.cwd).standardizedFileURL
            let modified = record.metadata.timestamp ?? record.file.modified
            let projectName = projectURL.lastPathComponent.isEmpty ? projectURL.path : projectURL.lastPathComponent

            sessions.append(CodexSession(
                id: record.metadata.id ?? record.file.url.path,
                url: record.file.url,
                projectName: projectName,
                projectURL: projectURL,
                modified: modified,
                title: sessionTitle(from: record.file.url),
                isActive: Date().timeIntervalSince(modified) < 60 * 60 * 24 * 7
            ))

            if sessions.count >= recentLimit() {
                break
            }
        }

        return sessions
    }

    private static func sessionFiles(in root: URL) -> [CodexSessionFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item -> CodexSessionFile? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return CodexSessionFile(url: url, modified: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }
    }

    private static func sessionMetadata(from url: URL) -> CodexSessionMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 64 * 1024),
              let prefix = String(data: data, encoding: .utf8)
        else { return nil }

        let decoder = JSONDecoder()

        for line in prefix.split(separator: "\n").prefix(20) {
            guard let lineData = String(line).data(using: .utf8),
                  let envelope = try? decoder.decode(CodexSessionEnvelope.self, from: lineData),
                  envelope.type == "session_meta",
                  let cwd = envelope.payload.cwd,
                  !cwd.isEmpty
            else { continue }

            return CodexSessionMetadata(
                id: envelope.payload.id,
                cwd: cwd,
                timestamp: parseCodexDate(envelope.payload.timestamp ?? envelope.timestamp)
            )
        }

        return nil
    }

    private static func sessionTitle(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 256 * 1024),
              let prefix = String(data: data, encoding: .utf8)
        else { return nil }

        let decoder = JSONDecoder()

        for line in prefix.split(separator: "\n").prefix(80) {
            guard let lineData = String(line).data(using: .utf8),
                  let envelope = try? decoder.decode(CodexEventEnvelope.self, from: lineData),
                  envelope.type == "event_msg",
                  envelope.payload.type == "user_message"
            else { continue }

            let title = (envelope.payload.message ?? envelope.payload.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            if !title.isEmpty {
                return title.count > 96 ? String(title.prefix(96)) + "..." : title
            }
        }

        return nil
    }

    private static func latestHistoryPrompt() -> String? {
        let historyURL = codexHome.appendingPathComponent("history.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: historyURL) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = min(fileSize, 256 * 1024)
        try? handle.seek(toOffset: fileSize - readSize)

        guard let data = try? handle.read(upToCount: Int(readSize)),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let decoder = JSONDecoder()

        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(CodexHistoryEntry.self, from: data)
            else { continue }

            let prompt = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                return prompt.count > 160 ? String(prompt.prefix(160)) + "..." : prompt
            }
        }

        return nil
    }

    private static func parseCodexDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

private struct CodexSessionFile {
    let url: URL
    let modified: Date
}

private struct CodexSessionRecord {
    let file: CodexSessionFile
    let metadata: CodexSessionMetadata
}

private struct CodexSessionMetadata {
    let id: String?
    let cwd: String
    let timestamp: Date?
}

private struct CodexSessionEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let id: String?
        let timestamp: String?
        let cwd: String?
    }
}

private struct CodexEventEnvelope: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String?
        let message: String?
        let text: String?
    }
}

private struct CodexHistoryEntry: Decodable {
    let text: String
}
