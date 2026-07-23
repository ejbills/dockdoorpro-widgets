import DockDoorWidgetSDK
import SwiftUI

struct CodexUsageMonitorView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    @ObservedObject var monitor: CodexUsageMonitor
    @Environment(\.colorScheme) private var appearance

    private var dim: CGFloat { min(size.width, size.height) }
    private var slotSpan: WidgetSlotSpan { WidgetSlotSpan.detect(size: size, isVertical: isVertical) }
    private var theme: CodexThemeColors {
        CodexColorTheme.resolve(widgetId: widgetId).colors(for: appearance)
    }
    private var displayLimit: CodexDisplayLimit {
        CodexDisplayLimit.resolve(title: WidgetDefaults.string(
            key: "displayLimit",
            widgetId: widgetId,
            default: CodexDisplayLimit.weekly.title
        ))
    }
    private var displayMetric: CodexDisplayMetric {
        CodexDisplayMetric.resolve(title: WidgetDefaults.string(
            key: "displayMetric",
            widgetId: widgetId,
            default: CodexDisplayMetric.remaining.title
        ))
    }
    private var showStatus: Bool {
        WidgetDefaults.bool(key: "showStatus", widgetId: widgetId, default: true)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            Group {
                switch slotSpan {
                case .compact: compactLayout
                case .extended: extendedLayout
                case .triple: tripleLayout
                }
            }
            .onChange(of: context.date) { _, _ in monitor.syncConfiguration() }
        }
        .onAppear { monitor.start() }
    }

    private var compactLayout: some View {
        Group {
            if let window = monitor.window(for: displayLimit) {
                ZStack {
                    CodexQuotaRing(
                        progress: progress(window),
                        gradient: ringGradient(window),
                        lineWidth: max(3, dim * 0.10)
                    )
                    .padding(dim * 0.09)
                    Text("\(Int(percent(window).rounded()))%")
                        .font(.system(
                            size: dim * 0.23,
                            weight: .bold,
                            design: .rounded
                        ).monospacedDigit())
                        .foregroundStyle(valueTint(window))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(dim * 0.18)
                }
                .overlay(alignment: .topTrailing) {
                    if showStatus {
                        compactStatusDot
                            .padding(dim * 0.10)
                    }
                }
            } else {
                emptyState(compact: true)
            }
        }
        .padding(dim * 0.06)
    }

    private var extendedLayout: some View {
        Group {
            if let window = monitor.window(for: displayLimit) {
                if isVertical {
                    VStack(spacing: dim * 0.08) {
                        solidPie(window, size: dim * 0.72)
                        metric(window, centered: true)
                    }
                } else {
                    HStack(spacing: dim * 0.12) {
                        solidPie(window, size: dim * 0.72)
                        metric(window, centered: false)
                    }
                }
            } else {
                emptyState(compact: false)
            }
        }
        .padding(dim * 0.09)
    }

    private var tripleLayout: some View {
        Group {
            if let usage = monitor.usage {
                if isVertical {
                    VStack(spacing: dim * 0.10) {
                        if let weekly = usage.weeklyWindow { gauge(weekly, size: dim * 0.66) }
                        limitsStack(usage)
                        if showStatus { serviceBadge }
                    }
                } else {
                    HStack(spacing: dim * 0.12) {
                        if let weekly = usage.weeklyWindow { gauge(weekly, size: dim * 0.68) }
                        limitsStack(usage)
                        if showStatus {
                            Rectangle()
                                .fill(Color.primary.opacity(0.10))
                                .frame(width: 0.5)
                            serviceBadge
                        }
                    }
                }
            } else {
                emptyState(compact: false)
            }
        }
        .padding(dim * 0.09)
    }

    private func gauge(_ window: CodexQuotaWindow, size: CGFloat) -> some View {
        ZStack {
            CodexQuotaRing(
                progress: progress(window),
                gradient: ringGradient(window),
                lineWidth: max(3, size * 0.12)
            )
            VStack(spacing: 0) {
                Text(percent(window), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(valueTint(window))
                Text(displayMetric == .remaining
                    ? CodexLocalization.text("% 剩余", "% LEFT")
                    : CodexLocalization.text("% 已用", "% USED"))
                    .font(.system(size: size * 0.085, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func solidPie(_ window: CodexQuotaWindow, size: CGFloat) -> some View {
        CodexSolidPie(progress: progress(window), colors: theme)
            .frame(width: size, height: size)
    }

    private func metric(_ window: CodexQuotaWindow, centered: Bool) -> some View {
        let metricLabel = displayMetric == .remaining
            ? CodexLocalization.text("剩余", "remaining")
            : CodexLocalization.text("已用", "used")

        return VStack(alignment: centered ? .center : .leading, spacing: dim * 0.035) {
            HStack(spacing: dim * 0.045) {
                Text(displayLimit == .weekly
                    ? CodexLocalization.text("每周", "WEEKLY")
                    : CodexLocalization.text("短周期", "SESSION"))
                    .font(.system(size: dim * 0.13, weight: .bold))
                if showStatus { compactStatusDot }
            }
            Text("\(Int(percent(window).rounded()))% \(metricLabel)")
                .font(.system(size: dim * 0.19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueTint(window))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(window.resetDescription())
                .font(.system(size: dim * 0.085, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            if monitor.isRefreshing {
                Text(CodexLocalization.text("更新中…", "Updating…"))
                    .font(.system(size: dim * 0.075, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
        }
    }

    private func limitsStack(_ usage: CodexUsageSnapshot) -> some View {
        VStack(alignment: isVertical ? .center : .leading, spacing: dim * 0.07) {
            if let weekly = usage.weeklyWindow {
                miniLimit(title: CodexLocalization.text("每周", "Weekly"), window: weekly)
            }
            if let session = usage.sessionWindow {
                miniLimit(title: CodexLocalization.text("短周期", "Session"), window: session)
            }
            if usage.sessionWindow == nil, let reset = usage.resetCreditsAvailable {
                Text(CodexLocalization.text("重置额度 \(reset) 次", "\(reset) quota resets"))
                    .font(.system(size: dim * 0.085, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func miniLimit(title: String, window: CodexQuotaWindow) -> some View {
        VStack(alignment: isVertical ? .center : .leading, spacing: dim * 0.025) {
            HStack(spacing: dim * 0.04) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .fontWeight(.bold)
            }
            .font(.system(size: dim * 0.105, design: .rounded).monospacedDigit())
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(tint(window))
                        .frame(width: proxy.size.width * window.remainingRatio)
                }
            }
            .frame(width: dim * 0.82, height: max(3, dim * 0.045))
        }
    }

    private var serviceBadge: some View {
        let status = monitor.serviceStatus?.overallIndicator ?? .unknown
        let statusColor = status.color(for: appearance)
        return VStack(spacing: dim * 0.045) {
            Circle()
                .fill(statusColor)
                .frame(width: dim * 0.15, height: dim * 0.15)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: statusColor.opacity(0.28), radius: 4)
            Text(CodexLocalization.text("状态", "STATUS"))
                .font(.system(size: dim * 0.07, weight: .bold))
                .foregroundStyle(.secondary)
            Text(status.label)
                .font(.system(size: dim * 0.085, weight: .semibold))
                .lineLimit(1)
        }
        .frame(minWidth: dim * 0.65)
    }

    private var compactStatusDot: some View {
        let indicator = monitor.serviceStatus?.overallIndicator ?? .unknown
        return Circle()
            .fill(indicator.color(for: appearance))
            .frame(width: max(5, dim * 0.07), height: max(5, dim * 0.07))
            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .shadow(
                color: indicator.color(for: appearance).opacity(0.28),
                radius: 2
            )
    }

    private func emptyState(compact: Bool) -> some View {
        VStack(spacing: dim * 0.055) {
            Image(systemName: monitor.usageError == nil ? "terminal.fill" : "person.badge.key.fill")
                .font(.system(size: dim * (compact ? 0.34 : 0.30), weight: .semibold))
                .foregroundStyle(theme.gradient)
            if !compact {
                Text(monitor.usageError == nil
                    ? CodexLocalization.text("正在读取 Codex", "Loading Codex")
                    : CodexLocalization.text("请打开详情", "Open details"))
                    .font(.system(size: dim * 0.10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func percent(_ window: CodexQuotaWindow) -> Double {
        displayMetric == .remaining ? window.remainingPercent : window.usedPercent
    }

    private func progress(_ window: CodexQuotaWindow) -> Double {
        displayMetric == .remaining ? window.remainingRatio : window.usedRatio
    }

    private func tint(_ window: CodexQuotaWindow) -> Color {
        switch window.remainingPercent {
        case ..<10: return CodexPalette.softCritical(for: appearance)
        case ..<25: return CodexPalette.yellow(for: appearance)
        default: return theme.primary
        }
    }

    private func valueTint(_ window: CodexQuotaWindow) -> Color {
        window.remainingPercent < 10 ? CodexPalette.softCritical(for: appearance) : .primary
    }

    private func ringGradient(_ window: CodexQuotaWindow) -> LinearGradient {
        switch window.remainingPercent {
        case ..<10:
            return LinearGradient(
                colors: [
                    CodexPalette.softCritical(for: appearance),
                    CodexPalette.orange(for: appearance).opacity(0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case ..<25:
            return LinearGradient(
                colors: [
                    CodexPalette.yellow(for: appearance),
                    CodexPalette.orange(for: appearance),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return theme.gradient
        }
    }
}

private struct CodexQuotaRing: View {
    let progress: Double
    let gradient: LinearGradient
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct CodexSolidPie: View {
    let progress: Double
    let colors: CodexThemeColors

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.12))
            CodexPieSlice(progress: progress)
                .fill(colors.gradient)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct CodexPieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }
        if clamped >= 0.9999 { return Path(ellipseIn: rect) }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
