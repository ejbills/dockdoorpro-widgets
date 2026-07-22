import AppKit
import SwiftUI

enum SystemMonitorPalette {
    static let cpuUser = adaptive(
        light: NSColor(red: 0.05, green: 0.52, blue: 0.98, alpha: 1),
        dark: NSColor(red: 0.25, green: 0.49, blue: 0.69, alpha: 1)
    )
    static let cpuSystem = adaptive(
        light: NSColor(red: 1.00, green: 0.24, blue: 0.30, alpha: 1),
        dark: NSColor(red: 0.76, green: 0.32, blue: 0.35, alpha: 1)
    )
    static let memoryApp = cpuUser
    static let memoryWired = adaptive(
        light: NSColor(red: 1.00, green: 0.51, blue: 0.12, alpha: 1),
        dark: NSColor(red: 0.73, green: 0.43, blue: 0.22, alpha: 1)
    )
    static let memoryCompressed = adaptive(
        light: NSColor(red: 1.00, green: 0.16, blue: 0.35, alpha: 1),
        dark: NSColor(red: 0.76, green: 0.29, blue: 0.43, alpha: 1)
    )
    static let memorySwap = adaptive(
        light: NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),
        dark: NSColor(red: 0.59, green: 0.40, blue: 0.66, alpha: 1)
    )
    static let destructive = adaptive(
        light: NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1),
        dark: NSColor(red: 0.74, green: 0.34, blue: 0.32, alpha: 1)
    )
    static let statusNormal = adaptive(
        light: NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        dark: NSColor(red: 0.31, green: 0.62, blue: 0.40, alpha: 1)
    )
    static let statusWarning = adaptive(
        light: NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
        dark: NSColor(red: 0.74, green: 0.48, blue: 0.25, alpha: 1)
    )
    static let available = Color.primary.opacity(0.16)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct UsageSegment: Identifiable {
    let id: String
    let fraction: Double
    let color: Color
}

struct SegmentedUsageRing: View {
    let segments: [UsageSegment]
    let lineWidth: CGFloat
    var rounded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            ForEach(positionedSegments) { item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(
                        item.segment.color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: rounded ? .round : .butt
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var positionedSegments: [PositionedSegment] {
        var cursor = 0.0
        return segments.compactMap { segment in
            let amount = min(max(segment.fraction, 0), 1 - cursor)
            guard amount > 0 else { return nil }
            let item = PositionedSegment(
                segment: segment,
                start: cursor,
                end: cursor + amount
            )
            cursor += amount
            return item
        }
    }

    private struct PositionedSegment: Identifiable {
        let segment: UsageSegment
        let start: Double
        let end: Double
        var id: String { segment.id }
    }
}

struct MetricRingView: View {
    let title: String
    let value: String
    let segments: [UsageSegment]
    let size: CGFloat
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: max(size * 0.07, 2)) {
            ZStack {
                SegmentedUsageRing(
                    segments: segments,
                    lineWidth: max(size * 0.13, 3)
                )
                .padding(size * 0.09)

                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: size * 0.24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: size * 0.09, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: size, height: size)

            Text(title)
                .font(.system(size: max(size * 0.13, 8), weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct SystemHistoryChart: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            ZStack {
                fillPath(points, size: geometry.size)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.55), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath(points)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
        }
        .clipped()
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let step = size.width / CGFloat(data.count - 1)
        return data.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(min(max(value, 0), 1)) * size.height * 0.92
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func fillPath(_ points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

struct SystemGlassCard: View {
    var cornerRadius: CGFloat = 9

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.primary.opacity(0.05))
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

struct SystemGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

struct SystemLivePulseDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.8 : 1)
                .opacity(pulsing ? 0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

enum SystemValueFormatter {
    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--" }
        let gib = value / 1_073_741_824
        if gib >= 10 { return String(format: "%.1f GB", gib) }
        if gib >= 1 { return String(format: "%.2f GB", gib) }
        let mib = value / 1_048_576
        if mib >= 10 { return String(format: "%.0f MB", mib) }
        return String(format: "%.1f MB", mib)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    static func processPercent(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f%%", value) }
        return String(format: "%.1f%%", value)
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    static func frequency(_ megahertz: Double?) -> String {
        guard let megahertz, megahertz.isFinite, megahertz > 0 else { return "--" }
        return String(format: "%.0f MHz", megahertz)
    }

    static func temperature(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite, celsius > 0 else { return "--" }
        return String(format: "%.0f°C", celsius)
    }
}
