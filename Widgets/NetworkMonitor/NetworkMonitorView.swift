import DockDoorWidgetSDK
import SwiftUI

struct NetworkMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let pluginId: String
    var monitor: NetworkSpeedMonitor

    private var speedUnit: String { WidgetDefaults.string(key: "speedUnit", widgetId: pluginId, default: "Auto") }
    private var showHistory: Bool { WidgetDefaults.bool(key: "showHistory", widgetId: pluginId) }
    private var showLabels: Bool { WidgetDefaults.bool(key: "showLabels", widgetId: pluginId) }

    private var colors: NetworkColors { NetworkColors.resolve(pluginId: pluginId) }
    private var dlColor: Color { colors.download }
    private var ulColor: Color { colors.upload }

    private var dim: CGFloat { min(size.width, size.height) }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    private var dl: (value: String, unit: String) { monitor.formattedSpeed(monitor.downloadSpeed, unit: speedUnit) }
    private var ul: (value: String, unit: String) { monitor.formattedSpeed(monitor.uploadSpeed, unit: speedUnit) }
    private var combined: (value: String, unit: String) { monitor.formattedSpeed(monitor.downloadSpeed + monitor.uploadSpeed, unit: speedUnit) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Group {
                if isExtended { extendedLayout } else { compactLayout }
            }
            .onChange(of: context.date) { _, _ in
                monitor.tick()
            }
        }
        .onAppear {
            let saved = UserDefaults.standard.string(forKey: "\(pluginId).selectedInterfaces") ?? ""
            let ifaces: Set<String> = saved.isEmpty ? [] : Set(saved.split(separator: ",").map(String.init))
            monitor.selectedInterfaces = ifaces
            monitor.tick()
        }
    }

    private var compactLayout: some View {
        VStack(spacing: dim * 0.08) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: dim * WidgetMetrics.sfSymbolScale * 0.55, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [dlColor, ulColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: dim * 0.02) {
                Text(combined.value)
                    .font(.system(size: dim * 0.34, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(combined.unit)
                    .font(.system(size: dim * 0.15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showHistory {
                let combinedHistory = zip(monitor.downloadHistory, monitor.uploadHistory).map(+)
                Sparkline(data: combinedHistory, color: dlColor)
                    .frame(height: dim * 0.12)
                    .padding(.horizontal, dim * 0.04)
            }
        }
        .padding(dim * 0.12)
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.08) {
                    speedColumn(arrow: "arrow.down", formatted: dl, color: dlColor, label: "Download")
                    if showHistory {
                        Sparkline(data: monitor.downloadHistory, color: dlColor)
                            .frame(height: dim * 0.15)
                            .padding(.horizontal, dim * 0.04)
                    }
                    Capsule()
                        .fill(Color.primary.opacity(0.25))
                        .frame(height: 1.5)
                        .padding(.horizontal, dim * 0.1)
                    speedColumn(arrow: "arrow.up", formatted: ul, color: ulColor, label: "Upload")
                    if showHistory {
                        Sparkline(data: monitor.uploadHistory, color: ulColor)
                            .frame(height: dim * 0.15)
                            .padding(.horizontal, dim * 0.04)
                    }
                }
                .padding(dim * 0.1)
            } else {
                VStack(spacing: dim * 0.05) {
                    HStack(alignment: .center, spacing: 0) {
                        speedColumn(arrow: "arrow.down", formatted: dl, color: dlColor, label: "Download")
                        Capsule()
                            .fill(Color.primary.opacity(0.25))
                            .frame(width: 1.5, height: dim * 0.55)
                            .padding(.horizontal, dim * 0.06)
                        speedColumn(arrow: "arrow.up", formatted: ul, color: ulColor, label: "Upload")
                    }

                    if showHistory {
                        HStack(spacing: dim * 0.06) {
                            Sparkline(data: monitor.downloadHistory, color: dlColor)
                            Sparkline(data: monitor.uploadHistory, color: ulColor)
                        }
                        .frame(height: dim * 0.18)
                        .padding(.horizontal, dim * 0.04)
                    }
                }
                .padding(dim * 0.1)
            }
        }
    }

    private func speedColumn(arrow: String, formatted: (value: String, unit: String), color: Color, label: String) -> some View {
        VStack(spacing: dim * 0.06) {
            HStack(spacing: 4) {
                Image(systemName: arrow)
                    .font(.system(size: dim * 0.18, weight: .bold))
                    .foregroundStyle(color)
                if showLabels {
                    Text(label)
                        .font(.system(size: dim * 0.13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(formatted.value)
                .font(.system(size: dim * 0.29, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(formatted.unit)
                .font(.system(size: dim * 0.14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}


struct Sparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let peak = (data.max() ?? 0) > 0 ? data.max()! : 1.0
            let pts = points(w: w, h: h, peak: peak)

            ZStack {
                fillPath(pts: pts, w: w, h: h)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.35), color.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ))
                linePath(pts: pts)
                    .stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
        .clipped()
    }

    private func points(w: CGFloat, h: CGFloat, peak: Double) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let step = w / CGFloat(data.count - 1)
        return data.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v / peak) * h * 0.92)
        }
    }

    private func linePath(pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
    }

    private func fillPath(pts: [CGPoint], w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: h))
            p.addLine(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: h))
            p.closeSubpath()
        }
    }
}
