import AppKit
import DockDoorWidgetSDK
import SwiftUI

/// Shared look-up for the speaker glyph, so the dock icon and the panel rows
/// never disagree about what a given volume means.
enum MixerGlyph {
    static func symbol(for volume: Double) -> String {
        switch volume {
        case ..<0.005: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<1.05: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    static func percentLabel(_ volume: Double) -> String {
        "\(Int((volume * 100).rounded()))%"
    }
}

struct AppVolumeMixerView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    var model: AppVolumeMixerModel

    /// How often the audio process list is re-read while the dock icon is on
    /// screen. Apps come and go between sounds, so it has to keep looking.
    private let refreshInterval: TimeInterval = 2

    private var dim: CGFloat { min(size.width, size.height) }

    private var slotSpan: WidgetSlotSpan {
        WidgetSlotSpan.detect(size: size, isVertical: isVertical)
    }

    private var primary: MixerEntry? { model.primaryEntry }

    private var primaryVolume: Double {
        primary.map { model.volume(for: $0) } ?? 1
    }

    private var isAdjusted: Bool {
        primary.map { model.isAdjusted($0) } ?? false
    }

    private var tint: Color {
        if !model.isSupported || model.needsPermission { return .secondary }
        return isAdjusted ? .accentColor : .secondary
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            Group {
                switch slotSpan {
                case .compact: compactLayout
                default: extendedLayout
                }
            }
            .onChange(of: context.date) { _, _ in
                model.tick(minimumInterval: refreshInterval * 0.8)
            }
        }
        .onAppear { model.refresh() }
    }

    private var compactLayout: some View {
        VStack(spacing: 1) {
            speaker(width: dim * (isAdjusted ? WidgetMetrics.sfSymbolScale * 0.9 : WidgetMetrics.sfSymbolScale))
            if isAdjusted {
                Text(MixerGlyph.percentLabel(primaryVolume))
                    .font(.system(size: max(dim * 0.2, 7), weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * WidgetMetrics.spacingScale) {
                    appIcon(side: dim * 0.42)
                    labels(alignment: .center)
                }
            } else {
                HStack(spacing: dim * 0.12) {
                    appIcon(side: dim * WidgetMetrics.contentScale * 0.62)
                    labels(alignment: .leading)
                }
            }
        }
    }

    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: dim * 0.04) {
            Text(primary?.name ?? "No audio")
                .font(.system(size: max(dim * 0.2, 8), weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: dim * 0.06) {
                Image(systemName: MixerGlyph.symbol(for: primaryVolume))
                    .font(.system(size: max(dim * 0.17, 7)))
                    .foregroundStyle(tint)
                Text(primary == nil ? "--" : MixerGlyph.percentLabel(primaryVolume))
                    .font(.system(size: max(dim * 0.18, 7), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private func appIcon(side: CGFloat) -> some View {
        Group {
            if let primary, let icon = AudioProcessCatalog.icon(for: primary) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(primaryVolume < 0.005 ? 0.45 : 1)
            } else {
                speaker(width: side * 0.8)
            }
        }
        .frame(width: side, height: side)
    }

    private func speaker(width: CGFloat) -> some View {
        Image(systemName: MixerGlyph.symbol(for: primaryVolume))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .foregroundStyle(tint)
    }
}
