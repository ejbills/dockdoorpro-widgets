import AppKit
import DockDoorWidgetSDK
import SwiftUI

struct StorageMonitorPanelView: View {
    let widgetId: String
    let dismiss: () -> Void

    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if volumes.isEmpty {
                Text("No volumes found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume, onRefresh: { refresh() })
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .task { await refreshPeriodically() }
    }

    private func refresh() {
        volumes = StorageVolumeSnapshot.mountedVolumes()
    }

    private func refreshPeriodically() async {
        refresh()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            refresh()
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let onRefresh: () -> Void

    @State private var isHovering = false
    @State private var isEjecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: volume.kind.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(volume.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                Text(volume.freeLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)

                if isHovering {
                    actionButtons
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(volume.color.opacity(0.15))

                    Capsule()
                        .fill(volume.color)
                        .frame(width: geo.size.width * volume.usedFraction)
                }
            }
            .frame(height: 4)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Text("\(volume.usedLabel) of \(volume.totalLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: openInFinder) {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")

            if volume.canEject {
                Button(action: eject) {
                    Image(systemName: "eject")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isEjecting)
                .opacity(isEjecting ? 0.4 : 1)
                .help("Eject")
            }
        }
        .foregroundStyle(.secondary)
    }

    @MainActor
    private func openInFinder() {
        NSWorkspace.shared.open(volume.url)
    }

    @MainActor
    private func eject() {
        guard !isEjecting else { return }
        isEjecting = true
        errorMessage = nil

        let url = volume.url
        Task {
            let failed = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                    return false
                } catch {
                    return true
                }
            }.value

            isEjecting = false

            if failed {
                errorMessage = "Volume is busy"
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                errorMessage = nil
            } else {
                onRefresh()
            }
        }
    }
}

private extension VolumeInfo {
    var color: Color {
        if usedFraction > 0.9 { return .red }
        if usedFraction > 0.75 { return .orange }
        return .blue
    }
}
