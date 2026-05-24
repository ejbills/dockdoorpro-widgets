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
                label: "Codex Projects Folder",
                placeholder: "~/Library/Mobile Documents/com~apple~CloudDocs/Codex Projects",
                defaultValue: CodexTrackerStore.defaultProjectsRoot.path
            ),
            .slider(
                key: "recentLimit",
                label: "Recent Project Count",
                range: 3...10,
                step: 1,
                defaultValue: 5
            ),
        ]
    }

    func performTapAction() {
        NSWorkspace.shared.open(CodexTrackerStore.defaultProjectsRoot)
    }
}

private struct CodexTrackerCompactView: View {
    let size: CGSize
    let isVertical: Bool
    @State private var snapshot = CodexTrackerStore.snapshot()

    private var dim: CGFloat { min(size.width, size.height) }
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
                snapshot = CodexTrackerStore.snapshot()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 1) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: dim * 0.34, weight: .semibold))
            Text("Codex")
                .font(.system(size: dim * 0.2, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.primary)
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.12) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: dim * 0.34, weight: .semibold))
                    projectLabels(alignment: .center)
                }
            } else {
                HStack(spacing: dim * 0.12) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: dim * 0.36, weight: .semibold))
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
                    .font(.system(size: 11, weight: .bold))
                Text(snapshot.headline)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct CodexTrackerPanelView: View {
    let dismiss: () -> Void
    @State private var snapshot = CodexTrackerStore.snapshot()

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
                StatPill(title: "Active", value: "\(snapshot.activeCount)")
                StatPill(title: "Chats", value: "\(snapshot.chatCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Projects")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.projects) { project in
                    HStack(spacing: 8) {
                        Image(systemName: project.isActive ? "circle.fill" : "circle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(project.isActive ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(project.relativeActivity)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.open(project.url)
                    }
                }
            }

            if let latest = snapshot.latestChat {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Latest Chat")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(latest)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .task {
            snapshot = CodexTrackerStore.snapshot()
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9, weight: .medium))
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

private enum CodexTrackerStore {
    static let defaultProjectsRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Codex Projects")

    static func snapshot() -> CodexSnapshot {
        let projectsRoot = configuredProjectsRoot()
        let projects = recentProjects(in: projectsRoot)
        let chats = recentChatTitles()
        let activeCount = projects.filter(\.isActive).count
        let headline = projects.first?.name ?? "No projects"

        return CodexSnapshot(
            projectCount: projects.count,
            activeCount: activeCount,
            chatCount: chats.count,
            headline: headline,
            latestChat: chats.first,
            projects: projects
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

    private static func recentProjects(in root: URL) -> [CodexProject] {
        let limit = max(3, min(10, Int(WidgetDefaults.double(
            key: "recentLimit",
            widgetId: "codex-project-tracker",
            default: 5
        ))))

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url -> CodexProject? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let modified = values?.contentModificationDate ?? .distantPast
            return CodexProject(
                id: url.path,
                name: url.lastPathComponent,
                url: url,
                modified: modified,
                isActive: Date().timeIntervalSince(modified) < 60 * 60 * 24 * 7
            )
        }
        .sorted { $0.modified > $1.modified }
        .prefix(limit)
        .map { $0 }
    }

    private static func recentChatTitles() -> [String] {
        let memoryRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/memories/MEMORY.md")

        guard let text = try? String(contentsOf: memoryRoot, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("- ") else { return nil }
                let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
            .suffix(8)
            .reversed()
    }
}
