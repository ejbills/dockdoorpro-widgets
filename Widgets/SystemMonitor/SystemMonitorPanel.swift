import DockDoorWidgetSDK
import SwiftUI

struct SystemMonitorPanel: View {
    let dismiss: () -> Void
    let widgetId: String
    var monitor: SystemMetricsMonitor

    @State private var appeared = false

    private var refreshInterval: TimeInterval {
        switch WidgetDefaults.string(key: "refreshInterval", widgetId: widgetId, default: "1s") {
        case "5s": return 5
        case "2s": return 2
        default: return 1
        }
    }

    private var processLimit: Int {
        Int(WidgetDefaults.string(key: "processCount", widgetId: widgetId, default: "8")) ?? 8
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            panelContent
                .onChange(of: context.date) { _, _ in
                    monitor.tick(minimumInterval: refreshInterval * 0.8)
                }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            monitor.tick(minimumInterval: 0)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 340, height: 0)
            header
            SystemGlassDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overview
                    history
                    cpuDetails
                    memoryDetails
                    processSection(
                        title: "Top CPU Processes",
                        symbol: "cpu",
                        processes: Array(monitor.topCPUProcesses.prefix(processLimit)),
                        value: { SystemValueFormatter.processPercent($0.value) },
                        color: SystemMonitorPalette.cpuUser
                    )
                    processSection(
                        title: "Top Memory Processes",
                        symbol: "memorychip",
                        processes: Array(monitor.topMemoryProcesses.prefix(processLimit)),
                        value: { SystemValueFormatter.bytes($0.value) },
                        color: SystemMonitorPalette.memoryCompressed
                    )
                }
                .padding(14)
            }
        }
        .background(panelBackground)
        .overlay(panelBorder)
        .shadow(color: SystemMonitorPalette.cpuUser.opacity(0.12), radius: 20, x: -4)
        .shadow(color: SystemMonitorPalette.memoryCompressed.opacity(0.10), radius: 20, x: 4)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SystemMonitorPalette.cpuUser, SystemMonitorPalette.memoryCompressed],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("CPU & Memory")
                .font(.system(size: 14, weight: .semibold))

            Spacer()
            SystemLivePulseDot(color: SystemMonitorPalette.cpuUser)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var overview: some View {
        HStack(spacing: 0) {
            panelMetricRing(
                title: "CPU",
                value: SystemValueFormatter.percent(monitor.cpu.used),
                segments: cpuSegments
            )

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5, height: 96)

            panelMetricRing(
                title: "Memory",
                value: SystemValueFormatter.percent(monitor.memory.usedFraction),
                segments: memorySegments
            )
        }
        .background(
            ZStack {
                SystemGlassCard()

                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [SystemMonitorPalette.cpuUser.opacity(0.11), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [Color.clear, SystemMonitorPalette.memoryCompressed.opacity(0.11)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        )
    }

    private func panelMetricRing(title: String, value: String, segments: [UsageSegment]) -> some View {
        MetricRingView(title: title, value: value, segments: segments, size: 88)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("60-second History")

            HStack(spacing: 8) {
                historyCard(
                    title: "CPU",
                    value: SystemValueFormatter.percent(monitor.cpu.used),
                    data: monitor.cpuHistory,
                    color: SystemMonitorPalette.cpuUser,
                    reflectionFromTrailing: false
                )
                historyCard(
                    title: "Memory",
                    value: SystemValueFormatter.percent(monitor.memory.usedFraction),
                    data: monitor.memoryHistory,
                    color: SystemMonitorPalette.memoryCompressed,
                    reflectionFromTrailing: true
                )
            }
        }
    }

    private func historyCard(
        title: String,
        value: String,
        data: [Double],
        color: Color,
        reflectionFromTrailing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            SystemHistoryChart(data: data, color: color)
                .frame(height: 48)
        }
        .padding(9)
        .background(
            ZStack {
                SystemGlassCard()
                LinearGradient(
                    colors: reflectionFromTrailing
                        ? [Color.clear, color.opacity(0.10)]
                        : [color.opacity(0.10), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        )
    }

    private var cpuDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("CPU Details")

            VStack(spacing: 0) {
                detailRow("User", value: SystemValueFormatter.percent(monitor.cpu.user), color: SystemMonitorPalette.cpuUser)
                divider
                detailRow("System", value: SystemValueFormatter.percent(monitor.cpu.system), color: SystemMonitorPalette.cpuSystem)
                divider
                detailRow("Idle", value: SystemValueFormatter.percent(monitor.cpu.idle), color: SystemMonitorPalette.available)
                divider
                detailRow(
                    "Load Average",
                    value: monitor.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: "  ")
                )
                divider
                detailRow("Frequency", value: SystemValueFormatter.frequency(monitor.cpuFrequencyMHz))
                divider
                detailRow("Uptime", value: SystemValueFormatter.uptime(monitor.uptime))
                divider
                statusDetailRow(
                    "Temperature",
                    value: SystemValueFormatter.temperature(monitor.cpuTemperature),
                    valueColor: temperatureColor
                )
            }
            .background(SystemGlassCard())
        }
    }

    private var memoryDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("Memory Details")

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Used")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(SystemValueFormatter.bytes(monitor.memory.used)) / \(SystemValueFormatter.bytes(monitor.memory.total))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .font(.system(size: 12))

                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        memoryBarPart(
                            color: SystemMonitorPalette.memoryApp,
                            width: geometry.size.width * fraction(monitor.memory.app)
                        )
                        memoryBarPart(
                            color: SystemMonitorPalette.memoryWired,
                            width: geometry.size.width * fraction(monitor.memory.wired)
                        )
                        memoryBarPart(
                            color: SystemMonitorPalette.memoryCompressed,
                            width: geometry.size.width * fraction(monitor.memory.compressed)
                        )
                        memoryBarPart(
                            color: SystemMonitorPalette.available,
                            width: geometry.size.width * fraction(monitor.memory.available)
                        )
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)

                memoryLegendRow("App Memory", value: monitor.memory.app, color: SystemMonitorPalette.memoryApp)
                memoryLegendRow("Wired", value: monitor.memory.wired, color: SystemMonitorPalette.memoryWired)
                memoryLegendRow("Compressed", value: monitor.memory.compressed, color: SystemMonitorPalette.memoryCompressed)
                memoryLegendRow("Available", value: monitor.memory.available, color: SystemMonitorPalette.available)
                memoryLegendRow("Swap Used", value: monitor.memory.swapUsed, color: .purple)

                HStack {
                    Text("Pressure")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monitor.memory.pressure.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pressureColor)
                }
            }
            .padding(11)
            .background(SystemGlassCard())
        }
    }

    private func processSection(
        title: String,
        symbol: String,
        processes: [ProcessMetric],
        value: @escaping (ProcessMetric) -> String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel(title)

            if processes.isEmpty {
                Text("Collecting process samples…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(12)
                    .background(SystemGlassCard())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        ProcessUsageRow(
                            process: process,
                            symbol: symbol,
                            formattedValue: value(process),
                            color: color,
                            requestTermination: { force in
                                monitor.requestTermination(of: process, force: force)
                            }
                        )
                        if index != processes.count - 1 {
                            divider.padding(.leading, 30)
                        }
                    }
                }
                .background(SystemGlassCard())
            }
        }
    }

    private func detailRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack(spacing: 7) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
    }

    private func statusDetailRow(_ label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
    }

    private func memoryLegendRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(SystemValueFormatter.bytes(value))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    private func memoryBarPart(color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0))
    }

    private func fraction(_ value: Double) -> CGFloat {
        guard monitor.memory.total > 0 else { return 0 }
        return CGFloat(min(max(value / monitor.memory.total, 0), 1))
    }

    private var pressureColor: Color {
        switch monitor.memory.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var temperatureColor: Color {
        guard let temperature = monitor.cpuTemperature else { return .secondary }
        if temperature >= 90 { return .red }
        if temperature >= 70 { return .orange }
        return .green
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.4)
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

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            SystemMonitorPalette.cpuUser.opacity(0.07),
                            Color.clear,
                            SystemMonitorPalette.memoryCompressed.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var panelBorder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.05), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct ProcessUsageRow: View {
    let process: ProcessMetric
    let symbol: String
    let formattedValue: String
    let color: Color
    let requestTermination: (Bool) -> ProcessTerminationResult

    @State private var hovering = false
    @State private var showingTerminationConfirmation = false
    @State private var terminationResult: ProcessTerminationResult?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if hovering {
                HStack(spacing: 4) {
                    Text(terminationResult?.displayText ?? "PID \(process.pid)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(terminationResult == nil ? color : terminationResultColor)

                    if process.canTerminate {
                        Button {
                            showingTerminationConfirmation = true
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Terminate \(process.name) (PID \(process.pid))")
                        .accessibilityLabel("Terminate \(process.name)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill((terminationResult == nil ? color : terminationResultColor).opacity(0.12))
                )
            } else {
                Text(formattedValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("PID: \(process.pid)")
        .confirmationDialog(
            "Terminate \(process.name)?",
            isPresented: $showingTerminationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Terminate", role: .destructive) {
                terminationResult = requestTermination(false)
            }
            Button("Force Quit", role: .destructive) {
                terminationResult = requestTermination(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PID \(process.pid). Terminate requests a normal quit; Force Quit ends it immediately.")
        }
    }

    private var terminationResultColor: Color {
        switch terminationResult {
        case .requested: return .orange
        case .forceRequested: return .red
        case .blocked, .permissionDenied, .processChanged, .notRunning, .failed: return .red
        case nil: return color
        }
    }
}
