import AppKit
import DockDoorWidgetSDK
import SwiftUI
import UniformTypeIdentifiers

struct FolderStackView: View {
    let size: CGSize
    let isVertical: Bool
    var store: FolderStore
    var anchor: WidgetAnchor

    @State private var isDropTargeted = false

    private var dim: CGFloat { min(size.width, size.height) }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    var body: some View {
        Group {
            if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
        .padding(8)
        .background(AnchorTracker(anchor: anchor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: dim * 0.18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: dim * 0.18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { store.refresh() }
    }

    /// Moves dropped files/folders into the pinned folder.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async { store.moveIntoFolder(url) }
            }
        }
        return handled
    }

    // MARK: - Compact (single slot)

    private var compactLayout: some View {
        stackedPreview(size: dim * WidgetMetrics.contentScale)
    }

    // MARK: - Extended (double slot)

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * WidgetMetrics.spacingScale) {
                    stackedPreview(size: dim * 0.6)
                    labels(alignment: .center)
                }
            } else {
                HStack(spacing: dim * 0.1) {
                    stackedPreview(size: dim * 0.65)
                    labels(alignment: .leading)
                }
            }
        }
    }

    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(store.folderName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(itemCountLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private var itemCountLabel: String {
        let count = store.entries.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    // MARK: - Preview

    /// Shows the most-recent file's icon, falling back to a folder icon when the
    /// folder is empty. No backing card so the icon reads cleanly.
    private func stackedPreview(size: CGFloat) -> some View {
        Group {
            if let top = store.topEntry {
                FileThumbnail(url: top.url, pixelSize: 256)
            } else {
                Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: size * 0.03, y: size * 0.02)
    }
}
