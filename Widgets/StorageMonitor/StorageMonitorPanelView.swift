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
                    volumeRow(volume)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .task { await refreshPeriodically() }
    }

    private func volumeRow(_ volume: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(volume.freeLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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

            Text("\(volume.usedLabel) of \(volume.totalLabel)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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

private extension VolumeInfo {
    var color: Color {
        if usedFraction > 0.9 { return .red }
        if usedFraction > 0.75 { return .orange }
        return .blue
    }
}
