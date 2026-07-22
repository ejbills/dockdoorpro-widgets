import DockDoorWidgetSDK
import SwiftUI

struct SystemMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    var monitor: SystemMetricsMonitor

    private var dim: CGFloat { min(size.width, size.height) }

    private var showCPU: Bool {
        WidgetDefaults.bool(key: "showCPU", widgetId: widgetId, default: true)
    }

    private var showMemory: Bool {
        WidgetDefaults.bool(key: "showMemory", widgetId: widgetId, default: true)
    }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    private var refreshInterval: TimeInterval {
        switch WidgetDefaults.string(key: "refreshInterval", widgetId: widgetId, default: "1s") {
        case "5s": return 5
        case "2s": return 2
        default: return 1
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            Group {
                if isExtended {
                    extendedLayout
                } else {
                    compactLayout
                }
            }
            .onChange(of: context.date) { _, _ in
                monitor.tick(minimumInterval: refreshInterval * 0.8)
            }
        }
        .onAppear {
            monitor.tick(minimumInterval: 0)
        }
    }

    private var compactLayout: some View {
        Group {
            if showCPU && showMemory {
                ZStack {
                    SegmentedUsageRing(
                        segments: cpuSegments,
                        lineWidth: max(dim * 0.10, 3)
                    )
                    .padding(dim * 0.08)

                    SegmentedUsageRing(
                        segments: memorySegments,
                        lineWidth: max(dim * 0.075, 2.5)
                    )
                    .padding(dim * 0.25)

                    VStack(spacing: 0) {
                        Text(SystemValueFormatter.percent(monitor.cpu.used))
                            .font(.system(size: dim * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                        Text("CPU")
                            .font(.system(size: dim * 0.08, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("M \(SystemValueFormatter.percent(monitor.memory.usedFraction))")
                            .font(.system(size: dim * 0.09, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(SystemMonitorPalette.memoryApp)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            } else if showCPU {
                compactSingleRing(
                    title: "CPU",
                    value: SystemValueFormatter.percent(monitor.cpu.used),
                    segments: cpuSegments
                )
            } else if showMemory {
                compactSingleRing(
                    title: "Memory",
                    value: SystemValueFormatter.percent(monitor.memory.usedFraction),
                    segments: memorySegments
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(dim * 0.08)
    }

    private var extendedLayout: some View {
        Group {
            if showCPU && showMemory && isVertical {
                VStack(spacing: dim * 0.10) {
                    cpuRing
                    memoryRing
                }
            } else if showCPU && showMemory {
                HStack(spacing: dim * 0.16) {
                    cpuRing
                    memoryRing
                }
            } else if showCPU {
                cpuRing
            } else if showMemory {
                memoryRing
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(dim * 0.08)
    }

    private func compactSingleRing(
        title: String,
        value: String,
        segments: [UsageSegment]
    ) -> some View {
        ZStack {
            SegmentedUsageRing(
                segments: segments,
                lineWidth: max(dim * 0.10, 3)
            )
            .padding(dim * 0.08)

            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: dim * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: max(dim * 0.10, 5), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
    }

    private var cpuRing: some View {
        MetricRingView(
            title: "CPU",
            value: SystemValueFormatter.percent(monitor.cpu.used),
            segments: cpuSegments,
            size: dim * 0.72
        )
    }

    private var memoryRing: some View {
        MetricRingView(
            title: "Memory",
            value: SystemValueFormatter.percent(monitor.memory.usedFraction),
            segments: memorySegments,
            size: dim * 0.72
        )
    }

    private var cpuSegments: [UsageSegment] {
        [
            UsageSegment(id: "user", fraction: monitor.cpu.user, color: SystemMonitorPalette.cpuUser),
            UsageSegment(id: "system", fraction: monitor.cpu.system, color: SystemMonitorPalette.cpuSystem),
            UsageSegment(id: "idle", fraction: monitor.cpu.idle, color: SystemMonitorPalette.available),
        ]
    }

    private var memorySegments: [UsageSegment] {
        let total = max(monitor.memory.total, 1)
        return [
            UsageSegment(id: "app", fraction: monitor.memory.app / total, color: SystemMonitorPalette.memoryApp),
            UsageSegment(id: "wired", fraction: monitor.memory.wired / total, color: SystemMonitorPalette.memoryWired),
            UsageSegment(id: "compressed", fraction: monitor.memory.compressed / total, color: SystemMonitorPalette.memoryCompressed),
            UsageSegment(id: "available", fraction: monitor.memory.available / total, color: SystemMonitorPalette.available),
        ]
    }
}
