import AppKit
import DockDoorWidgetSDK
import SwiftUI

struct CodexUsageMonitorPanel: View {
    let widgetId: String
    @ObservedObject var monitor: CodexUsageMonitor
    @Environment(\.colorScheme) private var appearance

    #if CODEX_USAGE_TESTING
    @State private var page: CodexPanelPage = {
        switch UserDefaults.standard.string(forKey: "codexUsage.testing.page") {
        case "status": return .status
        case "settings": return .settings
        default: return .overview
        }
    }()
    #else
    @State private var page: CodexPanelPage = .overview
    #endif
    @State private var displayLimit = CodexDisplayLimit.weekly
    @State private var displayMetric = CodexDisplayMetric.remaining
    @State private var colorTheme = CodexColorTheme.codex
    @State private var quotaUsageSource = CodexQuotaUsageSource.automatic
    @State private var refreshInterval = CodexRefreshInterval.fiveMinutes
    @State private var showStatus = true
    @State private var showExtraModelQuotas = true
    @State private var hoveredUsageDayID: String?
    @State private var hoveredUsageLocation: CGPoint?
    @State private var usageTooltipSize = CGSize(width: 126, height: 80)
    #if CODEX_USAGE_TESTING
    @State private var hoveredHeaderPage: CodexPanelPage? = {
        switch UserDefaults.standard.string(forKey: "codexUsage.testing.hoveredHeaderPage") {
        case "overview": return .overview
        case "status": return .status
        case "settings": return .settings
        default: return nil
        }
    }()
    #else
    @State private var hoveredHeaderPage: CodexPanelPage?
    #endif
    #if CODEX_USAGE_TESTING
    @State private var appeared = true
    #else
    @State private var appeared = false
    #endif

    private let panelWidth: CGFloat = 360
    private let panelContentWidth: CGFloat = 332
    private var theme: CodexThemeColors { colorTheme.colors(for: appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .zIndex(20)
            CodexGlassDivider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .overview: overviewPage
                    case .status: statusPage
                    case .settings: settingsPage
                    }
                }
                .frame(width: panelContentWidth, alignment: .topLeading)
                .padding(14)
            }
            .frame(
                width: panelWidth,
                height: page == .status ? 520 : 490,
                alignment: .topLeading
            )
            .scrollIndicators(.hidden)
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(panelBackground)
        .overlay(panelBorder)
        .shadow(color: theme.primary.opacity(0.16), radius: 22, x: -5)
        .shadow(color: theme.secondary.opacity(0.10), radius: 22, x: 5)
        .shadow(color: .black.opacity(0.30), radius: 14, y: 6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            #if !CODEX_USAGE_TESTING
            hoveredHeaderPage = nil
            #endif
            loadSettings()
            monitor.start()
            withAnimation(.easeOut(duration: 0.18)) {
                appeared = true
            }
        }
        .onDisappear {
            #if !CODEX_USAGE_TESTING
            hoveredHeaderPage = nil
            #endif
        }
        .onChange(of: monitor.settingsRevision) { _, _ in
            loadSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: headerSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.gradient)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if monitor.isRefreshing {
                ProgressView().controlSize(.mini)
            } else if showStatus || page == .status {
                CodexPulseDot(
                    color: monitor.serviceStatus?.overallIndicator.color(for: appearance) ?? theme.primary
                )
            }

            headerButton(
                symbol: "chart.pie.fill",
                target: .overview,
                help: CodexLocalization.text("额度与 Token 使用", "Quota and Token usage")
            )
            headerButton(
                symbol: "waveform.path.ecg",
                target: .status,
                help: CodexLocalization.text("ChatGPT / Codex 服务状态", "ChatGPT / Codex service status")
            )
            headerButton(
                symbol: "gearshape.fill",
                target: .settings,
                help: CodexLocalization.text("组件设置", "Widget settings")
            )
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

    private func headerButton(
        symbol: String,
        target: CodexPanelPage,
        help: String
    ) -> some View {
        let isSelected = page == target
        let isHovered = hoveredHeaderPage == target
        let tipAlignment: Alignment = target == .settings ? .bottomTrailing : .bottom

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { page = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(
                    theme.primary.opacity(isSelected ? 0.18 : (isHovered ? 0.10 : 0)),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            theme.primary.opacity(isHovered ? 0.34 : (isSelected ? 0.16 : 0)),
                            lineWidth: 0.6
                        )
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected || isHovered ? theme.primary : .secondary)
        .scaleEffect(isHovered ? 1.12 : 1)
        .offset(y: isHovered ? -1 : 0)
        .shadow(color: theme.primary.opacity(isHovered ? 0.24 : 0), radius: 6, y: 2)
        .overlay(alignment: tipAlignment) {
            if isHovered {
                CodexHeaderTabTip(text: help, accent: theme.primary)
                    .offset(y: 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.90, anchor: .top)))
            }
        }
        .zIndex(isHovered ? 30 : 0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                if hovering {
                    hoveredHeaderPage = target
                } else if hoveredHeaderPage == target {
                    hoveredHeaderPage = nil
                }
            }
        }
        .accessibilityLabel(help)
        .accessibilityHint(isSelected
            ? CodexLocalization.text("当前页面", "Current page")
            : CodexLocalization.text("切换到此页面", "Switch to this page"))
    }

    private var headerSymbol: String {
        switch page {
        case .overview: return "terminal.fill"
        case .status: return "waveform.path.ecg"
        case .settings: return "gearshape.fill"
        }
    }

    private var headerTitle: String {
        switch page {
        case .overview: return "Codex"
        case .status: return CodexLocalization.text("OpenAI 状态", "OpenAI Status")
        case .settings: return CodexLocalization.text("Codex 设置", "Codex Settings")
        }
    }

    private var headerSubtitle: String {
        switch page {
        case .overview:
            return monitor.usage?.accountEmail ?? CodexLocalization.text("额度监控", "Quota monitor")
        case .status:
            if CodexLocalization.isChinese {
                return monitor.serviceStatus?.overallIndicator.label ?? "ChatGPT 与 Codex"
            }
            return monitor.serviceStatus?.description ?? "ChatGPT and Codex"
        case .settings:
            return "DockDoor Pro Widget"
        }
    }

    @ViewBuilder
    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let usage = monitor.usage {
                accountRow(usage)
                if let weekly = usage.weeklyWindow {
                    quotaHero(weekly)
                }
                if let session = usage.sessionWindow {
                    quotaCard(
                        session,
                        title: CodexLocalization.text("短周期额度", "Session quota"),
                        symbol: "timer"
                    )
                }
                if let recentUsage = monitor.recentUsage {
                    recentTokenUsageCard(recentUsage)
                } else if monitor.tokenUsageError == nil {
                    recentTokenUsageLoadingCard
                }
                resetAndCredits(usage)
                if showExtraModelQuotas, !usage.extraWindows.isEmpty {
                    extraLimits(usage.extraWindows)
                }
                overviewFooter(usage)
            } else if let error = monitor.usageError {
                errorCard(error)
            } else {
                loadingCard
            }
        }
    }

    private func accountRow(_ usage: CodexUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(theme.primary.opacity(0.14))
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(usage.accountEmail ?? CodexLocalization.text("Codex 账户", "Codex account"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(CodexLocalization.text(
                    "\(usage.displayPlan) · \(usage.fetchedAt.codexRelativeText)更新",
                    "\(usage.displayPlan) · updated \(usage.fetchedAt.codexRelativeText)"
                ))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showStatus { statusCapsule }
        }
        .padding(10)
        .background(CodexGlassCard())
    }

    private var statusCapsule: some View {
        let indicator = monitor.serviceStatus?.overallIndicator ?? .unknown
        let statusColor = indicator.color(for: appearance)
        return HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(indicator.label)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.10), in: Capsule())
    }

    private func quotaHero(_ window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CodexLocalization.text("每周", "Weekly"))
                        .font(.system(size: 17, weight: .bold))
                    Text(window.resetDescription())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(window.remainingPercent, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 29, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(quotaTint(window))
                    Text(CodexLocalization.text("% 剩余", "% remaining"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            segmentedProgress(window)

            HStack {
                Label(
                    CodexLocalization.text(
                        "已用 \(Int(window.usedPercent.rounded()))%",
                        "\(Int(window.usedPercent.rounded()))% used"
                    ),
                    systemImage: "chart.bar.fill"
                )
                Spacer()
                if let resetAt = window.resetAt {
                    Text(resetAt.codexShortTime)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            ZStack {
                CodexGlassCard(cornerRadius: 12)
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [theme.primary.opacity(0.12), theme.secondary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
    }

    private func segmentedProgress(_ window: CodexQuotaWindow) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(theme.primary)
                    .frame(width: proxy.size.width * window.usedRatio)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                            .frame(width: 2)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 9)
    }

    private func quotaCard(
        _ window: CodexQuotaWindow,
        title: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(CodexLocalization.text(
                    "\(Int(window.remainingPercent.rounded()))% 剩余",
                    "\(Int(window.remainingPercent.rounded()))% remaining"
                ))
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(quotaTint(window))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(quotaTint(window))
                        .frame(width: proxy.size.width * window.remainingRatio)
                }
            }
            .frame(height: 6)
            Text(window.resetDescription())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(CodexGlassCard())
    }

    private func recentTokenUsageCard(_ snapshot: CodexRecentUsageSnapshot) -> some View {
        let chartDays = snapshot.chartDays
        let chartValues = chartDays.map {
            $0.estimatedCostUSD ?? Double($0.totalTokens) / 1_000_000
        }
        let peak = max(chartValues.max() ?? 0, 0.001)
        let hoveredDay = chartDays.first { $0.id == hoveredUsageDayID }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                codexSectionLabel(CodexLocalization.text("最近 TOKEN 使用", "RECENT TOKEN USAGE"))
                Spacer()
                Text(CodexLocalization.text("API 等价估算", "API-equivalent estimate"))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            HStack(spacing: 0) {
                recentMetric(
                    title: CodexLocalization.text("今日", "Today"),
                    cost: snapshot.todayEstimatedCostUSD,
                    tokens: snapshot.todayTokens
                )
                Spacer(minLength: 18)
                recentMetric(
                    title: CodexLocalization.text("近 30 天", "Last 30 days"),
                    cost: snapshot.last30DaysEstimatedCostUSD,
                    tokens: snapshot.last30DaysTokens
                )
            }

            GeometryReader { chartProxy in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(chartDays.enumerated()), id: \.element.id) { index, day in
                            let value = chartValues[index]
                            let isHovered = hoveredUsageDayID == day.id
                            VStack(spacing: 3) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.primary.opacity(
                                        isHovered ? 1 : (index >= chartDays.count - 2 ? 0.88 : 0.52)
                                    ))
                                    .frame(height: max(3, CGFloat(value / peak) * 72))
                                Text(chartDayLabel(day.dayKey))
                                    .font(.system(
                                        size: 7.5,
                                        weight: isHovered ? .semibold : .medium,
                                        design: .rounded
                                    ))
                                    .foregroundStyle(
                                        isHovered ? theme.primary : Color.secondary.opacity(0.72)
                                    )
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(height: 92, alignment: .bottom)
                    .padding(.top, 10)

                    if let hoveredDay, let hoveredUsageLocation {
                        let origin = usageTooltipOrigin(
                            pointer: hoveredUsageLocation,
                            tooltipSize: usageTooltipSize,
                            chartSize: chartProxy.size
                        )
                        usageDayTooltip(hoveredDay)
                            .background {
                                GeometryReader { tooltipProxy in
                                    Color.clear.preference(
                                        key: CodexUsageTooltipSizePreferenceKey.self,
                                        value: tooltipProxy.size
                                    )
                                }
                            }
                            .offset(x: origin.x, y: origin.y)
                            .transition(.opacity)
                    } else {
                        Text(snapshot.chartDays.compactMap(\.estimatedCostUSD).max().map {
                            "$\(Int($0.rounded()))"
                        } ?? formatTokenCount(snapshot.chartDays.map(\.totalTokens).max() ?? 0))
                            .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        updateHoveredUsageDay(
                            at: location,
                            chartWidth: chartProxy.size.width,
                            chartDays: chartDays
                        )
                    case .ended:
                        hoveredUsageDayID = nil
                        hoveredUsageLocation = nil
                    }
                }
                .onPreferenceChange(CodexUsageTooltipSizePreferenceKey.self) { size in
                    guard size.width > 0, size.height > 0 else { return }
                    usageTooltipSize = size
                }
            }
            .frame(height: 102)

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.primary)
                Text(CodexLocalization.text(
                    "最常用模型：\(snapshot.mostUsedModel ?? "未知")",
                    "Most used model: \(snapshot.mostUsedModel ?? "Unknown")"
                ))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(CodexLocalization.text(
                    "\(snapshot.pricingSource ?? "内置价表") · 长上下文 / Fast / Cache 已计入",
                    "\(snapshot.pricingSource ?? "Built-in pricing") · Long context / Fast / Cache included"
                ))
                Text(CodexLocalization.text(
                    "API 等价估算，不是订阅账单",
                    "API-equivalent estimate, not a subscription bill"
                ))
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            ZStack {
                CodexGlassCard(cornerRadius: 11)
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [theme.primary.opacity(0.06), theme.secondary.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
    }

    private func recentMetric(
        title: String,
        cost: Double?,
        tokens: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(cost.map(formatUSD) ?? "—")
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            Text("\(formatTokenCount(tokens)) API tokens")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func usageDayTooltip(_ day: CodexTokenUsageDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chartDayTooltipTitle(day.dayKey))
                .font(.system(size: 8.5, weight: .semibold))
            Text("\(day.totalTokens.formatted()) API tokens")
                .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
            Text(CodexLocalization.text(
                "输入 \(formatTokenCount(day.inputTokens)) · 输出 \(formatTokenCount(day.outputTokens))",
                "Input \(formatTokenCount(day.inputTokens)) · Output \(formatTokenCount(day.outputTokens))"
            ))
                .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            if day.cachedInputTokens > 0 || day.cacheWriteInputTokens > 0 {
                Text(CodexLocalization.text(
                    "Cache 读 \(formatTokenCount(day.cachedInputTokens)) · 写 \(formatTokenCount(day.cacheWriteInputTokens))",
                    "Cache read \(formatTokenCount(day.cachedInputTokens)) · write \(formatTokenCount(day.cacheWriteInputTokens))"
                ))
                    .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if day.priorityTokens > 0 {
                Text("Fast/Priority \(formatTokenCount(day.priorityTokens))")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.secondary)
            }
            Text(day.estimatedCostUSD.map(formatUSD)
                ?? CodexLocalization.text("费用未知", "Cost unavailable"))
                .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .allowsHitTesting(false)
    }

    private func updateHoveredUsageDay(
        at location: CGPoint,
        chartWidth: CGFloat,
        chartDays: [CodexTokenUsageDay]
    ) {
        guard !chartDays.isEmpty, chartWidth > 0 else {
            hoveredUsageDayID = nil
            hoveredUsageLocation = nil
            return
        }

        let spacing: CGFloat = 4
        let totalSpacing = spacing * CGFloat(max(0, chartDays.count - 1))
        let barWidth = max(1, (chartWidth - totalSpacing) / CGFloat(chartDays.count))
        let step = barWidth + spacing
        let rawIndex = Int(max(0, location.x) / step)
        let index = min(chartDays.count - 1, max(0, rawIndex))

        hoveredUsageDayID = chartDays[index].id
        hoveredUsageLocation = location
    }

    private func usageTooltipOrigin(
        pointer: CGPoint,
        tooltipSize: CGSize,
        chartSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 2
        let gap: CGFloat = 8
        let width = max(tooltipSize.width, 1)
        let height = max(tooltipSize.height, 1)

        let preferredRightX = pointer.x + gap
        let x: CGFloat
        if preferredRightX + width <= chartSize.width - margin {
            x = preferredRightX
        } else {
            x = max(margin, pointer.x - gap - width)
        }

        let preferredAboveY = pointer.y - gap - height
        let maxY = max(margin, chartSize.height - height - margin)
        let y = preferredAboveY >= margin
            ? min(preferredAboveY, maxY)
            : min(maxY, pointer.y + gap)

        return CGPoint(x: x, y: max(margin, y))
    }

    private func chartDayLabel(_ dayKey: String) -> String {
        guard let date = parseChartDay(dayKey) else { return String(dayKey.suffix(5)) }
        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func chartDayTooltipTitle(_ dayKey: String) -> String {
        guard let date = parseChartDay(dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d EEE")
        return formatter.string(from: date)
    }

    private func parseChartDay(_ dayKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }

    private var recentTokenUsageLoadingCard: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.mini)
            VStack(alignment: .leading, spacing: 2) {
                Text(CodexLocalization.text(
                    "正在统计最近 Token 使用",
                    "Calculating recent Token usage"
                ))
                    .font(.system(size: 10, weight: .semibold))
                Text(CodexLocalization.text(
                    "首次扫描可能需要几秒，之后只读取新增会话记录。",
                    "The initial scan may take a few seconds; later scans read only new session records."
                ))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(CodexGlassCard())
    }

    private func resetAndCredits(_ usage: CodexUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            codexSectionLabel(CodexLocalization.text("额度补充", "QUOTA EXTRAS"))
            HStack(spacing: 10) {
                metricTile(
                    title: CodexLocalization.text("重置额度", "Quota resets"),
                    value: usage.resetCreditsAvailable.map {
                        CodexLocalization.text("\($0) 次可用", "\($0) available")
                    } ?? CodexLocalization.text("暂无数据", "Unavailable"),
                    symbol: "arrow.counterclockwise.circle.fill",
                    color: theme.primary,
                    trailingDetail: usage.resetCreditsExpiresAt.flatMap(resetCreditRemainingDescription)
                )
                metricTile(
                    title: "Credits",
                    value: usage.creditsBalance.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—",
                    symbol: "creditcard.fill",
                    color: theme.secondary
                )
            }
        }
    }

    private func metricTile(
        title: String,
        value: String,
        symbol: String,
        color: Color,
        trailingDetail: String? = nil
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let trailingDetail {
                        Image(systemName: "clock")
                            .font(.system(size: 8, weight: .semibold))
                        Text(trailingDetail)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(CodexGlassCard())
    }

    private func extraLimits(_ windows: [CodexQuotaWindow]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            codexSectionLabel(CodexLocalization.text("额外模型额度", "EXTRA MODEL QUOTAS"))
            VStack(spacing: 0) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    HStack(spacing: 8) {
                        Circle().fill(theme.secondary).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(window.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Text(window.resetDescription())
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    if index < windows.count - 1 { CodexGlassDivider() }
                }
            }
            .background(CodexGlassCard())
        }
    }

    private func overviewFooter(_ usage: CodexUsageSnapshot) -> some View {
        HStack(spacing: 12) {
            Label(usage.fetchedAt.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                open("https://chatgpt.com/codex/settings/usage")
            } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
            .buttonStyle(.plain)
            .modifier(CodexFooterActionHover(
                testingID: "dashboard",
                help: CodexLocalization.text("打开 Codex 用量仪表盘", "Open Codex usage dashboard"),
                accent: theme.primary,
                restingColor: .secondary,
                tipAlignment: .top
            ))
            Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .disabled(monitor.isRefreshing)
                .modifier(CodexFooterActionHover(
                    testingID: "refresh",
                    help: monitor.isRefreshing
                        ? CodexLocalization.text("正在刷新额度与状态", "Refreshing quota and status")
                        : CodexLocalization.text("立即刷新额度与状态", "Refresh quota and status now"),
                    accent: theme.primary,
                    restingColor: .secondary,
                    tipAlignment: .topTrailing
                ))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let status = monitor.serviceStatus {
                overallStatusCard(status)
                if let chatGPT = status.chatGPT { statusGroupCard(chatGPT, symbol: "bubble.left.and.bubble.right.fill") }
                if let codex = status.codex { statusGroupCard(codex, symbol: "terminal.fill") }
                statusFooter(status)
            } else if let error = monitor.statusError {
                errorCard(error)
            } else {
                loadingCard
            }
        }
    }

    private func overallStatusCard(_ status: OpenAIStatusSnapshot) -> some View {
        let statusColor = status.overallIndicator.color(for: appearance)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14))
                Circle().fill(statusColor).frame(width: 11, height: 11)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(CodexLocalization.isChinese
                    ? status.overallIndicator.label
                    : (status.description ?? status.overallIndicator.label))
                    .font(.system(size: 12, weight: .semibold))
                Text(status.updatedAt.map {
                    CodexLocalization.text(
                        "官方状态 · \($0.codexRelativeText)更新",
                        "Official status · updated \($0.codexRelativeText)"
                    )
                } ?? CodexLocalization.text("OpenAI 官方状态", "Official OpenAI status"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.overallIndicator.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(statusColor)
        }
        .padding(12)
        .background(statusColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(statusColor.opacity(0.16), lineWidth: 0.5)
        )
    }

    private func statusGroupCard(
        _ group: OpenAIStatusGroup,
        symbol: String
    ) -> some View {
        let groupColor = group.indicator.color(for: appearance)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primary)
                    .frame(width: 18)
                Text(group.name)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Circle().fill(groupColor).frame(width: 8, height: 8)
                Text(group.indicator.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)

            CodexGlassDivider()

            ForEach(Array(group.components.enumerated()), id: \.element.id) { index, component in
                let componentColor = component.indicator.color(for: appearance)
                HStack(spacing: 9) {
                    Circle().fill(componentColor).frame(width: 7, height: 7)
                    Text(component.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(component.indicator.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                if index < group.components.count - 1 { CodexGlassDivider().padding(.leading, 28) }
            }
        }
        .background(CodexGlassCard(cornerRadius: 10))
    }

    private func statusFooter(_ status: OpenAIStatusSnapshot) -> some View {
        HStack {
            Text(CodexLocalization.text(
                "获取于 \(status.fetchedAt.formatted(date: .omitted, time: .shortened))",
                "Fetched at \(status.fetchedAt.formatted(date: .omitted, time: .shortened))"
            ))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
            Button { open("https://status.openai.com") } label: {
                Label(
                    CodexLocalization.text("打开状态页", "Open status page"),
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .modifier(CodexFooterActionHover(
                testingID: "status",
                help: CodexLocalization.text("打开 OpenAI 官方状态页", "Open official OpenAI status page"),
                accent: theme.primary,
                restingColor: theme.primary,
                tipAlignment: .topTrailing
            ))
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection(CodexLocalization.text("DOCK 展示", "DOCK DISPLAY")) {
                settingPicker(CodexLocalization.text("主额度", "Primary quota"), selection: $displayLimit) {
                    ForEach(CodexDisplayLimit.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: displayLimit) { _, value in
                    monitor.writeSetting(value.title, key: "displayLimit")
                }
                CodexGlassDivider()
                settingPicker(CodexLocalization.text("数值", "Value"), selection: $displayMetric) {
                    ForEach(CodexDisplayMetric.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: displayMetric) { _, value in
                    monitor.writeSetting(value.title, key: "displayMetric")
                }
                CodexGlassDivider()
                settingPicker(CodexLocalization.text("主题", "Theme"), selection: $colorTheme) {
                    ForEach(CodexColorTheme.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: colorTheme) { _, value in
                    monitor.writeSetting(value.title, key: "colorTheme")
                }
                CodexGlassDivider()
                HStack {
                    Text(CodexLocalization.text("显示服务状态", "Show service status"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $showStatus)
                        .labelsHidden()
                        .toggleStyle(CodexAccentSwitchStyle(accent: theme.primary))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onChange(of: showStatus) { _, value in
                    monitor.writeSetting(value, key: "showStatus")
                }
                CodexGlassDivider()
                HStack {
                    Text(CodexLocalization.text(
                        "显示额外模型额度",
                        "Show extra model quotas"
                    ))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $showExtraModelQuotas)
                        .labelsHidden()
                        .toggleStyle(CodexAccentSwitchStyle(accent: theme.primary))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onChange(of: showExtraModelQuotas) { _, value in
                    monitor.writeSetting(value, key: "showExtraModelQuotas")
                }
            }

            settingsSection(CodexLocalization.text("连接", "CONNECTION")) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(CodexLocalization.text("额度来源", "Quota usage source"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(resolvedQuotaSourceLabel)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $quotaUsageSource) {
                            ForEach(CodexQuotaUsageSource.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    Text(CodexLocalization.text(
                        "只控制短周期和每周额度的获取；本地 Token 与费用统计独立运行。",
                        "Controls session and weekly quota fetching only. Local Token and cost statistics run independently."
                    ))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onChange(of: quotaUsageSource) { _, value in
                    monitor.writeSetting(value.title, key: "quotaUsageSource")
                }
            }

            settingsSection(CodexLocalization.text("刷新", "REFRESH")) {
                settingPicker(CodexLocalization.text("频率", "Interval"), selection: $refreshInterval) {
                    ForEach(CodexRefreshInterval.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: refreshInterval) { _, value in
                    monitor.writeSetting(value.title, key: "refreshInterval")
                }
                CodexGlassDivider()
                Button { monitor.refresh() } label: {
                    settingActionRow(
                        CodexLocalization.text("立即刷新", "Refresh now"),
                        symbol: "arrow.clockwise",
                        trailing: monitor.isRefreshing
                            ? CodexLocalization.text("更新中…", "Updating…")
                            : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(monitor.isRefreshing)
            }

            settingsSection(CodexLocalization.text("账户与链接", "ACCOUNT & LINKS")) {
                Button { open("https://chatgpt.com/codex/settings/usage") } label: {
                    settingActionRow(
                        CodexLocalization.text("Codex 用量仪表盘", "Codex usage dashboard"),
                        symbol: "gauge.with.dots.needle.67percent"
                    )
                }
                .buttonStyle(.plain)
                CodexGlassDivider()
                Button { open("https://status.openai.com") } label: {
                    settingActionRow(
                        CodexLocalization.text("OpenAI 状态页", "OpenAI status page"),
                        symbol: "waveform.path.ecg"
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 7) {
                codexSectionLabel(CodexLocalization.text("登录与隐私", "LOGIN & PRIVACY"))
                Label {
                    Text(CodexLocalization.text(
                        "额度通过 OAuth API 读取；本地统计只读取会话中的 token_count、模型和服务等级字段，不读取或缓存提示词，缓存不包含访问 Token。",
                        "Quota is read through the OAuth API. Local statistics read only token_count, model, and service-tier fields, never prompts; caches contain no access tokens."
                    ))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(theme.primary)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(10)
                .background(CodexGlassCard())
            }

            Text(CodexLocalization.text(
                "状态数据来自 status.openai.com；额度接口与字段兼容逻辑参考 CodexBar（MIT）。",
                "Status data comes from status.openai.com. Quota API and compatibility logic reference CodexBar (MIT)."
            ))
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            codexSectionLabel(title)
            VStack(spacing: 0) { content() }
                .background(CodexGlassCard())
        }
    }

    private func settingPicker<Selection: Hashable, Content: View>(
        _ label: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .medium))
            Spacer()
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func settingActionRow(
        _ label: String,
        symbol: String,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.primary)
                .frame(width: 16)
            Text(label).font(.system(size: 11, weight: .medium))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func codexSectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.45)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CodexPalette.yellow(for: appearance))
            Text(CodexLocalization.text("无法读取 Codex 额度", "Unable to read Codex quota"))
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(CodexLocalization.text("重新加载", "Reload")) { monitor.refresh() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(CodexGlassCard(cornerRadius: 12))
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(CodexLocalization.text("正在读取 Codex 数据…", "Loading Codex data…"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(CodexGlassCard(cornerRadius: 12))
    }

    private func quotaTint(_ window: CodexQuotaWindow) -> Color {
        switch window.remainingPercent {
        case ..<10: return CodexPalette.softCritical(for: appearance)
        case ..<25: return CodexPalette.yellow(for: appearance)
        default: return theme.primary
        }
    }

    private func formatUSD(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func resetCreditRemainingDescription(_ expiresAt: Date) -> String? {
        let seconds = Int(expiresAt.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "\(days)d \(hours)h" }
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    private func formatTokenCount(_ value: Int) -> String {
        let number = Double(value)
        switch value {
        case 1_000_000_000...:
            return String(format: number >= 10_000_000_000 ? "%.0fB" : "%.1fB", number / 1_000_000_000)
        case 1_000_000...:
            return String(format: number >= 100_000_000 ? "%.0fM" : "%.1fM", number / 1_000_000)
        case 1_000...:
            return String(format: number >= 100_000 ? "%.0fK" : "%.1fK", number / 1_000)
        default:
            return value.formatted()
        }
    }

    private func loadSettings() {
        displayLimit = CodexDisplayLimit.resolve(title: WidgetDefaults.string(
            key: "displayLimit",
            widgetId: widgetId,
            default: CodexDisplayLimit.weekly.title
        ))
        displayMetric = CodexDisplayMetric.resolve(title: WidgetDefaults.string(
            key: "displayMetric",
            widgetId: widgetId,
            default: CodexDisplayMetric.remaining.title
        ))
        colorTheme = CodexColorTheme.resolve(widgetId: widgetId)
        quotaUsageSource = CodexQuotaUsageSource.resolve(title: WidgetDefaults.string(
            key: "quotaUsageSource",
            widgetId: widgetId,
            default: CodexQuotaUsageSource.automatic.title
        ))
        refreshInterval = CodexRefreshInterval.resolve(title: WidgetDefaults.string(
            key: "refreshInterval",
            widgetId: widgetId,
            default: CodexRefreshInterval.fiveMinutes.title
        ))
        showStatus = WidgetDefaults.bool(key: "showStatus", widgetId: widgetId, default: true)
        showExtraModelQuotas = WidgetDefaults.bool(
            key: "showExtraModelQuotas",
            widgetId: widgetId,
            default: true
        )
    }

    private var resolvedQuotaSourceLabel: String {
        if quotaUsageSource == .automatic {
            return monitor.resolvedQuotaUsageSource?.sourceLabel
                ?? CodexLocalization.text("检测中", "Detecting")
        }
        return quotaUsageSource.sourceLabel
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [theme.primary.opacity(0.08), Color.clear, theme.secondary.opacity(0.05)],
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

private enum CodexPanelPage {
    case overview
    case status
    case settings
}

private struct CodexUsageTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct CodexHeaderTabTip: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CodexFooterActionHover: ViewModifier {
    let testingID: String
    let help: String
    let accent: Color
    let restingColor: Color
    let tipAlignment: Alignment

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var visuallyHovered: Bool {
        #if CODEX_USAGE_TESTING
        isHovered || UserDefaults.standard.string(
            forKey: "codexUsage.testing.hoveredFooterAction"
        ) == testingID
        #else
        isHovered
        #endif
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 5)
            .frame(height: 22)
            .foregroundStyle(visuallyHovered && isEnabled ? accent : restingColor)
            .background(
                accent.opacity(visuallyHovered && isEnabled ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        accent.opacity(visuallyHovered && isEnabled ? 0.34 : 0),
                        lineWidth: 0.6
                    )
            }
            .scaleEffect(visuallyHovered && isEnabled ? 1.10 : 1)
            .offset(y: visuallyHovered && isEnabled ? -1 : 0)
            .shadow(
                color: accent.opacity(visuallyHovered && isEnabled ? 0.24 : 0),
                radius: 6,
                y: 2
            )
            .overlay(alignment: tipAlignment) {
                if visuallyHovered && isEnabled {
                    CodexHeaderTabTip(text: help, accent: accent)
                        .offset(y: -30)
                        .transition(.opacity.combined(with: .scale(scale: 0.90, anchor: .bottom)))
                }
            }
            .zIndex(visuallyHovered ? 30 : 0)
            .onHover { hovering in
                let nextHovered = isEnabled && hovering
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    isHovered = nextHovered
                }
            }
            .accessibilityLabel(help)
    }
}

private struct CodexAccentSwitchStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(configuration.isOn ? accent : Color.primary.opacity(0.16))
                .frame(width: 44, height: 24)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityValue(configuration.isOn
            ? CodexLocalization.text("已开启", "On")
            : CodexLocalization.text("已关闭", "Off"))
    }
}

private struct CodexGlassCard: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.primary.opacity(0.05))
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

private struct CodexGlassDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

private struct CodexPulseDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.8 : 1)
                .opacity(pulsing ? 0 : 0.6)
            Circle().fill(color).frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
