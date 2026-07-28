import SwiftUI

/// Detailed, local-only usage analytics derived from Codex session logs.
///
/// The view owns its card styling so it can be embedded without depending on
/// panel-private implementation details.
struct CodexLocalInsightsView: View {
    let snapshot: CodexRecentUsageSnapshot
    let primary: Color
    let secondary: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var period: Period = .sevenDays
    @State private var hoveredMetric: String?
    @State private var hoveredModel: String?

    var body: some View {
        VStack(spacing: 12) {
            periodHeader
            summaryCard
            tokenCompositionCard
            topModelsCard
            pricingFooter
        }
    }

    private var periodHeader: some View {
        HStack(spacing: 10) {
            Label(
                CodexLocalization.text("本机用量洞察", "Local usage insights"),
                systemImage: "internaldrive"
            )
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Picker("", selection: $period) {
                ForEach(Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 132)
            .help(
                CodexLocalization.text(
                    "切换本机日志统计周期",
                    "Change the local log aggregation period"
                )
            )
        }
        .animation(.easeOut(duration: 0.16), value: period)
    }

    private var summaryCard: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            summaryMetric(
                id: "tokens",
                icon: "sum",
                title: CodexLocalization.text("总 Token", "Total tokens"),
                value: compactNumber(summary.totalTokens),
                help: CodexLocalization.text(
                    "当前周期的输入与输出 Token 总量",
                    "Total input and output tokens in this period"
                )
            )
            summaryMetric(
                id: "cost",
                icon: "dollarsign.circle",
                title: CodexLocalization.text("等价费用", "API equivalent"),
                value: currency(summary.estimatedCostUSD),
                help: CodexLocalization.text(
                    "依据 API 价格目录计算的等价费用，不是订阅账单",
                    "API-equivalent estimate from the pricing catalog, not a subscription bill"
                )
            )
            summaryMetric(
                id: "requests",
                icon: "arrow.up.arrow.down",
                title: CodexLocalization.text("请求", "Requests"),
                value: compactNumber(summary.requestCount),
                help: CodexLocalization.text(
                    "从本机会话日志识别到的模型请求数",
                    "Model requests identified in local session logs"
                )
            )
            summaryMetric(
                id: "activeDays",
                icon: "calendar.badge.checkmark",
                title: CodexLocalization.text("活跃日", "Active days"),
                value: "\(summary.activeDays) / \(max(summary.dayCount, period.dayCount))",
                help: CodexLocalization.text(
                    "统计周期内至少产生过 Token 的天数",
                    "Days with at least one recorded token in this period"
                )
            )
            summaryMetric(
                id: "peak",
                icon: "chart.bar.fill",
                title: CodexLocalization.text("单日峰值", "Peak day"),
                value: compactNumber(summary.peakDayTokens),
                detail: formattedDay(summary.peakDayKey),
                help: CodexLocalization.text(
                    "当前周期内 Token 使用最多的一天",
                    "Highest-token day in the selected period"
                )
            )
            summaryMetric(
                id: "comparison",
                icon: comparisonIcon,
                title: CodexLocalization.text("环比", "Change"),
                value: comparisonText,
                detail: comparisonDetail,
                valueColor: comparisonColor,
                help: comparisonHelp
            )
        }
        .padding(10)
        .background(cardBackground)
    }

    private func summaryMetric(
        id: String,
        icon: String,
        title: String,
        value: String,
        detail: String? = nil,
        valueColor: Color? = nil,
        help: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(primary)
                .frame(width: 23, height: 23)
                .background(primary.opacity(colorScheme == .dark ? 0.15 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(valueColor ?? Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    hoveredMetric == id
                        ? primary.opacity(colorScheme == .dark ? 0.10 : 0.065)
                        : Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.018)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .scaleEffect(hoveredMetric == id ? 1.012 : 1)
        .animation(.easeOut(duration: 0.13), value: hoveredMetric == id)
        .onHover { hovering in
            hoveredMetric = hovering ? id : (hoveredMetric == id ? nil : hoveredMetric)
        }
        .help(help)
    }

    private var tokenCompositionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    CodexLocalization.text("Token 构成", "Token composition"),
                    systemImage: "chart.bar.doc.horizontal"
                )
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(compactNumber(summary.totalTokens))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            compositionBar
                .frame(height: 10)
                .help(compositionHelp)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(compositionItems) { item in
                    compositionMetric(item)
                }
                compositionMetric(
                    CompositionItem(
                        id: "priority",
                        title: "Fast/Priority",
                        value: summary.priorityTokens,
                        color: fastColor
                    )
                )
            }

            HStack(spacing: 8) {
                ratioPill(
                    icon: "bolt.horizontal.circle",
                    title: CodexLocalization.text("Cache 命中", "Cache hit"),
                    value: percent(summary.cacheHitPercent)
                )
                ratioPill(
                    icon: "hare",
                    title: CodexLocalization.text("Fast 占比", "Fast share"),
                    value: percent(fastShare)
                )
            }
        }
        .padding(11)
        .background(cardBackground)
    }

    @ViewBuilder
    private var compositionBar: some View {
        let items = compositionItems.filter { $0.value > 0 }
        let total = max(1, items.reduce(0) { $0 + $1.value })

        GeometryReader { proxy in
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.075))
            } else {
                let spacing = CGFloat(max(0, items.count - 1)) * 2
                let usableWidth = max(0, proxy.size.width - spacing)

                HStack(spacing: 2) {
                    ForEach(items) { item in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.color)
                            .frame(
                                width: max(
                                    2,
                                    usableWidth * CGFloat(item.value) / CGFloat(total)
                                )
                            )
                            .help(
                                "\(item.title): \(compactNumber(item.value)) · "
                                    + percent(Double(item.value) / Double(total) * 100)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.20), value: period)
    }

    private func compositionMetric(_ item: CompositionItem) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.color)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(compactNumber(item.value))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(item.title): \(item.value.formatted(.number.locale(CodexLocalization.locale)))")
    }

    private func ratioPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(primary)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03))
        )
    }

    private var topModelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(
                    CodexLocalization.text("常用模型", "Top models"),
                    systemImage: "cpu"
                )
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(CodexLocalization.text("近 30 日", "Last 30 days"))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)

            if snapshot.topModels.isEmpty {
                Text(CodexLocalization.text("暂无模型用量", "No model usage yet"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(snapshot.topModels.prefix(3).enumerated()), id: \.element.id) {
                    index,
                    model in
                    if index > 0 {
                        Divider()
                            .opacity(colorScheme == .dark ? 0.22 : 0.32)
                            .padding(.leading, 17)
                    }
                    modelRow(model, rank: index)
                }
            }
        }
        .padding(11)
        .background(cardBackground)
    }

    private func modelRow(_ model: CodexModelUsageSummary, rank: Int) -> some View {
        let share = modelShare(model)
        let isHovered = hoveredModel == model.id

        return HStack(spacing: 8) {
            Circle()
                .fill(rank == 0 ? primary : (rank == 1 ? secondary : tertiaryAccent))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.model)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.065))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [primary, secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(2, proxy.size.width * CGFloat(share / 100)))
                    }
                }
                .frame(height: 3)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(compactNumber(model.tokens))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text(currency(model.estimatedCostUSD))
                    Text(percent(share))
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? primary.opacity(colorScheme == .dark ? 0.09 : 0.055) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .scaleEffect(isHovered ? 1.008 : 1)
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .onHover { hovering in
            hoveredModel = hovering ? model.id : (hoveredModel == model.id ? nil : hoveredModel)
        }
        .help(
            "\(model.model)\n"
                + CodexLocalization.text("Token：", "Tokens: ")
                + model.tokens.formatted(.number.locale(CodexLocalization.locale))
                + "\n"
                + CodexLocalization.text("API 等价费用：", "API-equivalent cost: ")
                + currency(model.estimatedCostUSD)
        )
    }

    private var pricingFooter: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(primary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    CodexLocalization.text(
                        "API 等价估算，不是订阅账单",
                        "API-equivalent estimate, not a subscription bill"
                    )
                )
                .fontWeight(.semibold)

                Text(
                    CodexLocalization.text("价格来源：", "Pricing source: ")
                        + (snapshot.pricingSource
                            ?? CodexLocalization.text("内置价表", "Built-in pricing"))
                )
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
        .help(
            CodexLocalization.text(
                "费用根据本地 Token 记录和价格目录估算，可能与实际产品权益不同。",
                "Cost is estimated from local token records and the pricing catalog; product entitlements may differ."
            )
        )
    }

    private var summary: CodexUsagePeriodSummary {
        period == .sevenDays
            ? snapshot.last7DaysSummary
            : snapshot.last30DaysSummary
    }

    private var compositionItems: [CompositionItem] {
        [
            CompositionItem(
                id: "input",
                title: CodexLocalization.text("输入", "Input"),
                value: summary.uncachedInputTokens,
                color: primary
            ),
            CompositionItem(
                id: "cacheRead",
                title: "Cache Read",
                value: summary.cachedInputTokens,
                color: secondary
            ),
            CompositionItem(
                id: "cacheWrite",
                title: "Cache Write",
                value: summary.cacheWriteInputTokens,
                color: cacheWriteColor
            ),
            CompositionItem(
                id: "visibleOutput",
                title: CodexLocalization.text("可见输出", "Visible output"),
                value: summary.visibleOutputTokens,
                color: outputColor
            ),
            CompositionItem(
                id: "reasoning",
                title: CodexLocalization.text("推理", "Reasoning"),
                value: summary.reasoningOutputTokens,
                color: reasoningColor
            ),
        ]
    }

    private var fastShare: Double? {
        guard summary.totalTokens > 0 else { return nil }
        return min(
            100,
            max(0, Double(summary.priorityTokens) / Double(summary.totalTokens) * 100)
        )
    }

    private var comparisonValue: Double? {
        period == .sevenDays ? snapshot.comparison.sevenDayChangePercent : nil
    }

    private var comparisonText: String {
        guard let comparisonValue else {
            return CodexLocalization.text("—", "—")
        }
        return String(format: "%@%.0f%%", comparisonValue >= 0 ? "+" : "", comparisonValue)
    }

    private var comparisonDetail: String? {
        period == .sevenDays
            ? CodexLocalization.text("较前 7 日", "vs prior 7d")
            : CodexLocalization.text("暂无基准", "No baseline")
    }

    private var comparisonIcon: String {
        guard let comparisonValue else { return "minus" }
        if comparisonValue > 0 { return "arrow.up.right" }
        if comparisonValue < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var comparisonColor: Color? {
        guard let comparisonValue else { return nil }
        if comparisonValue > 0 { return CodexPalette.orange(for: colorScheme) }
        if comparisonValue < 0 { return CodexPalette.green(for: colorScheme) }
        return nil
    }

    private var comparisonHelp: String {
        if period == .sevenDays {
            return CodexLocalization.text(
                "最近 7 日 Token 总量相对之前 7 日的变化",
                "Change in total tokens versus the preceding seven days"
            )
        }
        return CodexLocalization.text(
            "当前本机扫描范围为 30 日，尚无前一个 30 日周期作为基准",
            "The current local scan covers 30 days, so a prior 30-day baseline is unavailable"
        )
    }

    private var compositionHelp: String {
        CodexLocalization.text(
            "输入、Cache Read、Cache Write、可见输出和推理 Token 的构成；Fast 为独立服务层标签。",
            "Composition of input, cache read, cache write, visible output, and reasoning tokens. Fast is a separate service-tier label."
        )
    }

    private func modelShare(_ model: CodexModelUsageSummary) -> Double {
        let total = snapshot.last30DaysSummary.totalTokens
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(model.tokens) / Double(total) * 100))
    }

    private var cardBackground: some View {
        CodexGlassCard(cornerRadius: 13)
    }

    private var cacheWriteColor: Color {
        colorScheme == .dark
            ? Color(red: 0.74, green: 0.53, blue: 0.29)
            : Color(red: 0.91, green: 0.57, blue: 0.14)
    }

    private var outputColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.68, blue: 0.47)
            : Color(red: 0.18, green: 0.70, blue: 0.38)
    }

    private var reasoningColor: Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.47, blue: 0.73)
            : Color(red: 0.62, green: 0.31, blue: 0.77)
    }

    private var fastColor: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.38, blue: 0.55)
            : Color(red: 0.88, green: 0.21, blue: 0.54)
    }

    private var tertiaryAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.46, green: 0.63, blue: 0.74)
            : Color(red: 0.32, green: 0.58, blue: 0.75)
    }

    private func compactNumber(_ value: Int) -> String {
        let number = Double(max(0, value))
        if number >= 1_000_000_000 {
            return compact(number / 1_000_000_000, suffix: "B")
        }
        if number >= 1_000_000 {
            return compact(number / 1_000_000, suffix: "M")
        }
        if number >= 1_000 {
            return compact(number / 1_000, suffix: "K")
        }
        return value.formatted(.number.locale(CodexLocalization.locale))
    }

    private func compact(_ value: Double, suffix: String) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return String(format: "%.\(digits)f%@", value, suffix)
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 100 {
            return String(format: "$%.0f", value)
        }
        if value >= 10 {
            return String(format: "$%.1f", value)
        }
        return String(format: "$%.2f", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    private func formattedDay(_ dayKey: String?) -> String? {
        guard let dayKey else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let formatter = DateFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.dateFormat = CodexLocalization.isChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }

    private enum Period: String, CaseIterable, Identifiable {
        case sevenDays
        case thirtyDays

        var id: String { rawValue }
        var dayCount: Int { self == .sevenDays ? 7 : 30 }
        var title: String {
            switch self {
            case .sevenDays:
                return CodexLocalization.text("7 日", "7 days")
            case .thirtyDays:
                return CodexLocalization.text("30 日", "30 days")
            }
        }
    }

    private struct CompositionItem: Identifiable {
        let id: String
        let title: String
        let value: Int
        let color: Color
    }
}
