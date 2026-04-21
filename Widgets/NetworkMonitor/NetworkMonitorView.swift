import DockDoorWidgetSDK
import SwiftUI


struct NetworkMonitorView: View {
    let size:       CGSize
    let isVertical: Bool
    let pluginId:   String

    @ObservedObject private var monitor = NetworkSpeedMonitor.shared

    private var speedUnit:   String { WidgetDefaults.string(key: "speedUnit",  widgetId: pluginId, default: "Auto") }
    private var showHistory: Bool   { WidgetDefaults.bool(key: "showHistory",  widgetId: pluginId) }
    private var showLabels:  Bool   { WidgetDefaults.bool(key: "showLabels",   widgetId: pluginId) }

    private var colors: NetworkColors { NetworkColors.resolve(pluginId: pluginId) }
    private var dlColor: Color { colors.download }
    private var ulColor: Color { colors.upload   }

    private var dim: CGFloat { min(size.width, size.height) }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width  * 1.5
            : size.width  > size.height * 1.5
    }

    private var dl: (value: String, unit: String) { monitor.formattedSpeed(monitor.downloadSpeed, unit: speedUnit) }
    private var ul: (value: String, unit: String) { monitor.formattedSpeed(monitor.uploadSpeed,   unit: speedUnit) }
    private var combined: (value: String, unit: String) { monitor.formattedSpeed(monitor.downloadSpeed + monitor.uploadSpeed, unit: speedUnit) }

    private var combinedColor: Color { Color(hue: 0.58, saturation: 0.6, brightness: 0.9) }

    @State private var selectedIfaces: Set<String> = []

    var body: some View {
        Group {
            if isExtended { extendedLayout } else { compactLayout }
        }
        .onAppear {
            let saved = UserDefaults.standard.string(forKey: "\(pluginId).selectedInterfaces") ?? ""
            selectedIfaces = saved.isEmpty ? [] : Set(saved.split(separator: ",").map(String.init))
            monitor.selectedInterfaces = selectedIfaces
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
                VStack(spacing: dim * 0.05) {
                    speedRow(arrow: "arrow.down", formatted: dl, color: dlColor, label: "Download")
                    if showHistory {
                        Sparkline(data: monitor.downloadHistory, color: dlColor)
                            .frame(height: dim * 0.15)
                            .padding(.horizontal, dim * 0.04)
                    }
                    Capsule()
                        .fill(Color.primary.opacity(0.25))
                        .frame(height: 1.5)
                        .padding(.horizontal, dim * 0.02)
                    speedRow(arrow: "arrow.up", formatted: ul, color: ulColor, label: "Upload")
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
                            Sparkline(data: monitor.uploadHistory,   color: ulColor)
                        }
                        .frame(height: dim * 0.18)
                        .padding(.horizontal, dim * 0.04)
                    }
                }
                .padding(dim * 0.1)
            }
        }
    }


    private func ifaceDropdown(compact: Bool) -> some View {
        Menu {
            Button {
                toggleInterface("")
            } label: {
                HStack {
                    Text("All Interfaces")
                    if selectedIfaces.isEmpty { Image(systemName: "checkmark") }
                }
            }

            Divider()

            ForEach(monitor.availableInterfaces, id: \.self) { name in
                Button {
                    toggleInterface(name)
                } label: {
                    HStack {
                        Text(name)
                        if let ip = monitor.interfaceIPs[name] {
                            Text("· \(ip)").foregroundStyle(.secondary)
                        }
                        if selectedIfaces.contains(name) { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: dim * 0.11, weight: .semibold))
                    .foregroundStyle(dlColor)
                Text(selectedIfaces.isEmpty
                    ? "All Interfaces"
                    : selectedIfaces.count == 1
                        ? selectedIfaces.first!
                        : "\(selectedIfaces.count) Interfaces"
                )
                .font(.system(size: dim * 0.12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: dim * 0.09, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, dim * 0.08)
            .padding(.vertical, dim * 0.05)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: dim * 0.08))
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: compact ? 160 : .infinity)
    }

    private func toggleInterface(_ name: String) {
        if name.isEmpty {
            selectedIfaces = []
        } else if selectedIfaces.contains(name) {
            selectedIfaces.remove(name)
        } else {
            selectedIfaces.insert(name)
        }
        monitor.selectedInterfaces = selectedIfaces
        UserDefaults.standard.set(selectedIfaces.joined(separator: ","), forKey: "\(pluginId).selectedInterfaces")
    }

    private func speedRow(arrow: String, formatted: (value: String, unit: String), color: Color, label: String) -> some View {
        HStack(spacing: dim * 0.08) {
            Image(systemName: arrow)
                .font(.system(size: dim * WidgetMetrics.sfSymbolScale * 0.95, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: dim * 0.22, alignment: .center)

            Text(formatted.value)
                .font(.system(size: dim * 0.24, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(formatted.unit)
                .font(.system(size: dim * 0.14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showLabels {
                Text(label)
                    .font(.system(size: dim * 0.13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
    let data:  [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w    = geo.size.width
            let h    = geo.size.height
            let peak = (data.max() ?? 0) > 0 ? data.max()! : 1.0
            let pts  = points(w: w, h: h, peak: peak)

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