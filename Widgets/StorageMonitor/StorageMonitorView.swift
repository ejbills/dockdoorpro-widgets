import DockDoorWidgetSDK
import SwiftUI

struct StorageMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String

    @State private var volume: VolumeInfo?

    // MARK: - Settings

    private var showPercentage: Bool {
        WidgetDefaults.bool(key: "showPercentage", widgetId: widgetId)
    }

    private var warningThreshold: Double {
        WidgetDefaults.double(key: "warningThreshold", widgetId: widgetId, default: 75) / 100
    }

    private var useRoundedCap: Bool {
        WidgetDefaults.string(key: "ringStyle", widgetId: widgetId, default: "Rounded") == "Rounded"
    }

    private var dim: CGFloat { min(size.width, size.height) }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    private var usedFraction: Double {
        volume?.usedFraction ?? 0
    }

    private var ringColor: Color {
        if usedFraction > 0.9 { return .red }
        if usedFraction > warningThreshold { return .orange }
        return .blue
    }

    private var freeLabel: String {
        if showPercentage {
            return "\(Int(((volume?.freeFraction ?? 0) * 100).rounded()))%"
        }
        return volume?.freeLabel.replacingOccurrences(of: " free", with: "") ?? "--"
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
        .task { await refreshPeriodically() }
    }

    // MARK: - Compact

    private var compactLayout: some View {
        ZStack {
            usageRing(size: dim * WidgetMetrics.contentScale)

            Text(freeLabel)
                .font(.system(size: dim * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
    }

    // MARK: - Extended

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * WidgetMetrics.spacingScale) {
                    usageRing(size: dim * 0.6)
                    VStack(spacing: 1) {
                        Text(freeLabel)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("Free")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            } else {
                HStack(spacing: dim * 0.1) {
                    usageRing(size: dim * 0.65)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(freeLabel)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("Free of \(volume?.totalLabel ?? "--")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
            }
        }
    }

    // MARK: - Ring

    private func usageRing(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: size * 0.22)

            Circle()
                .trim(from: 0, to: 1 - usedFraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: size * 0.22, lineCap: useRoundedCap ? .round : .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(4)
        .frame(width: size, height: size)
    }

    // MARK: - Data

    private func refresh() {
        volume = StorageVolumeSnapshot.rootVolume()
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
