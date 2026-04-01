import DockDoorWidgetSDK
import SwiftUI

struct StorageMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String

    @State private var totalGB: Double = 0
    @State private var freeGB: Double = 0

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
        guard totalGB > 0 else { return 0 }
        return (totalGB - freeGB) / totalGB
    }

    private var ringColor: Color {
        if usedFraction > 0.9 { return .red }
        if usedFraction > warningThreshold { return .orange }
        return .blue
    }

    private var freeLabel: String {
        if showPercentage {
            return "\(Int((1 - usedFraction) * 100))%"
        }
        if freeGB >= 100 {
            return "\(Int(freeGB)) GB"
        }
        return String(format: "%.1f GB", freeGB)
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
        .onAppear { refresh() }
    }

    // MARK: - Compact

    private var compactLayout: some View {
        VStack(spacing: 1) {
            usageRing(size: dim * WidgetMetrics.contentScale * 0.75)

            Text(freeLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
                        Text("Free of \(Int(totalGB)) GB")
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
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else { return }
        if let total = attrs[.systemSize] as? Int64 {
            totalGB = Double(total) / 1_073_741_824
        }
        if let free = attrs[.systemFreeSize] as? Int64 {
            freeGB = Double(free) / 1_073_741_824
        }
    }
}
