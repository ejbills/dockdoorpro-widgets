import SwiftUI

/// Official, account-level Codex activity returned by the OpenAI account usage API.
///
/// This view is intentionally self-contained so it can be embedded in any
/// panel page without relying on panel-private card or divider types.
struct CodexOfficialActivityView: View {
    let snapshot: CodexAccountInsightsSnapshot?
    let primary: Color
    let secondary: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var trendMode: TrendMode = .daily
    @State private var hoveredHeatmapDay: HeatmapDay?

    var body: some View {
        VStack(spacing: 12) {
            if let snapshot, let usage = snapshot.officialUsage {
                summaryGrid(usage)
                heatmapCard(usage)
                trendCard(usage)
                sourceFooter(snapshot)
            } else {
                unavailableCard
            }
        }
    }

    private func summaryGrid(_ usage: CodexOfficialAccountUsage) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            summaryTile(
                icon: "sum",
                title: CodexLocalization.text("累计 Token", "Lifetime tokens"),
                value: compactNumber(usage.lifetimeTokens),
                detail: CodexLocalization.text("官方账号累计", "Official account total")
            )
            summaryTile(
                icon: "chart.bar.fill",
                title: CodexLocalization.text("单日峰值", "Peak daily"),
                value: compactNumber(usage.peakDailyTokens),
                detail: CodexLocalization.text("历史最高用量", "Highest daily usage")
            )
            summaryTile(
                icon: "flame.fill",
                title: CodexLocalization.text("当前连续", "Current streak"),
                value: dayCount(usage.currentStreakDays),
                detail: String(
                    format: CodexLocalization.text("最长 %@",
                                                   "Longest %@"),
                    dayCount(usage.longestStreakDays)
                )
            )
            summaryTile(
                icon: "timer",
                title: CodexLocalization.text("最长任务", "Longest task"),
                value: duration(usage.longestRunningTurnSeconds),
                detail: CodexLocalization.text("单次运行时长", "Single turn duration")
            )
        }
    }

    private func summaryTile(
        icon: String,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary)
                .frame(width: 25, height: 25)
                .background(primary.opacity(colorScheme == .dark ? 0.15 : 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(cardBackground)
    }

    private func heatmapCard(_ usage: CodexOfficialAccountUsage) -> some View {
        let days = heatmapDays(from: usage.dailyUsageBuckets)
        let peak = max(days.map(\.tokens).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(
                    CodexLocalization.text("近一年活跃度", "Last year activity"),
                    systemImage: "calendar"
                )
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(CodexLocalization.text("少", "Less"))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                heatLegend
                Text(CodexLocalization.text("多", "More"))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { proxy in
                let gap: CGFloat = 1.25
                let cell = max(2.5, (proxy.size.width - gap * 52) / 53)

                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<53, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = days[column * 7 + row]
                                RoundedRectangle(cornerRadius: max(0.8, cell * 0.22))
                                    .fill(heatColor(for: day, peak: peak))
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        if hovering {
                                            hoveredHeatmapDay = day
                                        } else if hoveredHeatmapDay?.id == day.id {
                                            hoveredHeatmapDay = nil
                                        }
                                    }
                                    .help(heatmapTooltip(day))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomLeading) {
                    if let day = hoveredHeatmapDay {
                        Text(heatmapTooltip(day))
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tooltipBackground)
                                    .shadow(
                                        color: .black.opacity(colorScheme == .dark ? 0.35 : 0.14),
                                        radius: 5,
                                        y: 2
                                    )
                            )
                            .padding(3)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.easeOut(duration: 0.12), value: hoveredHeatmapDay?.id)
            }
            .frame(height: 46)

            HStack {
                Text(monthRange(days))
                Spacer()
                Text(
                    CodexLocalization.text(
                        "悬停查看每日 Token",
                        "Hover for daily tokens"
                    )
                )
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(cardBackground)
    }

    private var heatLegend: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(primary.opacity(0.16 + Double(level) * 0.18))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func trendCard(_ usage: CodexOfficialAccountUsage) -> some View {
        let points = trendPoints(from: usage.dailyUsageBuckets, mode: trendMode)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(CodexLocalization.text("使用趋势", "Usage trend"))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $trendMode) {
                    ForEach(TrendMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 174)
                .controlSize(.small)
            }

            CompactTrendChart(
                points: points,
                style: trendMode == .cumulative ? .line : .bars,
                mode: trendMode,
                primary: primary,
                secondary: secondary
            )
            .id(trendMode)
            .frame(height: 78)

            HStack {
                Text(points.first?.label ?? "—")
                Spacer()
                if let latest = points.last {
                    Text(compactNumber(latest.value))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                Spacer()
                Text(points.last?.label ?? "—")
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(cardBackground)
    }

    private func sourceFooter(_ snapshot: CodexAccountInsightsSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(primary)
            Text(CodexLocalization.text("官方数据 · OpenAI 账户用量 API",
                                        "Official data · OpenAI Account Usage API"))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(relativeDate(snapshot.fetchedAt))
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }

    private var unavailableCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(primary)
            Text(CodexLocalization.text("暂无官方活动数据", "Official activity is unavailable"))
                .font(.system(size: 13, weight: .bold))
            Text(
                CodexLocalization.text(
                    "刷新后将通过 OAuth API 只读获取账号聚合统计。",
                    "Refresh to load aggregate account statistics read-only through the OAuth API."
                )
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        CodexGlassCard(cornerRadius: 13)
    }

    private var tooltipBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.18)
            : Color.white.opacity(0.96)
    }

    private func heatColor(for day: HeatmapDay, peak: Int64) -> Color {
        guard !day.isFuture else {
            return Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.018)
        }
        guard day.tokens > 0 else {
            return Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.065)
        }
        let normalized = log10(Double(day.tokens) + 1) / log10(Double(peak) + 1)
        let opacity = 0.24 + 0.70 * normalized
        return primary.opacity(opacity)
    }

    private func heatmapDays(
        from buckets: [CodexOfficialDailyUsageBucket]
    ) -> [HeatmapDay] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = CodexLocalization.locale
        calendar.timeZone = .current

        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // ISO week starts on Monday. Convert Sunday=1 ... Saturday=7 to
        // Monday-based zero offset.
        let mondayOffset = (weekday + 5) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -52, to: currentWeekStart) ?? currentWeekStart

        let parsedBuckets = buckets.reduce(into: [Date: Int64]()) { result, bucket in
            guard let day = Self.serverDate(bucket.startDate, calendar: calendar) else {
                return
            }
            result[day, default: 0] += max(0, bucket.tokens)
        }

        return (0..<(53 * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return HeatmapDay(
                date: date,
                tokens: parsedBuckets[date] ?? 0,
                isFuture: date > today
            )
        }
    }

    private func trendPoints(
        from buckets: [CodexOfficialDailyUsageBucket],
        mode: TrendMode
    ) -> [TrendPoint] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = CodexLocalization.locale
        calendar.timeZone = .current

        let daily = buckets.compactMap { bucket -> (Date, Int64)? in
            guard let date = Self.serverDate(bucket.startDate, calendar: calendar) else {
                return nil
            }
            return (date, max(0, bucket.tokens))
        }
        .sorted { $0.0 < $1.0 }

        switch mode {
        case .daily:
            return daily.suffix(30).map {
                TrendPoint(date: $0.0, value: $0.1, label: shortDate($0.0))
            }

        case .weekly:
            let grouped = Dictionary(grouping: daily) {
                calendar.dateInterval(of: .weekOfYear, for: $0.0)?.start ?? $0.0
            }
            return grouped.keys.sorted().suffix(26).map { week in
                TrendPoint(
                    date: week,
                    value: grouped[week, default: []].reduce(0) { $0 + $1.1 },
                    label: shortDate(week)
                )
            }

        case .cumulative:
            var running: Int64 = 0
            let grouped = Dictionary(grouping: daily) {
                calendar.dateInterval(of: .weekOfYear, for: $0.0)?.start ?? $0.0
            }
            return grouped.keys.sorted().suffix(53).map { week in
                running += grouped[week, default: []].reduce(0) { $0 + $1.1 }
                return TrendPoint(date: week, value: running, label: shortDate(week))
            }
        }
    }

    private func heatmapTooltip(_ day: HeatmapDay) -> String {
        let tokens = day.isFuture ? "—" : compactNumber(day.tokens)
        return "\(longDate(day.date)) · \(tokens) tokens"
    }

    private func monthRange(_ days: [HeatmapDay]) -> String {
        guard let first = days.first(where: { !$0.isFuture }),
              let last = days.last(where: { !$0.isFuture })
        else {
            return "—"
        }
        return "\(monthDate(first.date)) – \(monthDate(last.date))"
    }

    private func compactNumber(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return compactNumber(value)
    }

    private func compactNumber(_ value: Int64) -> String {
        let absolute = abs(Double(value))
        let divisor: Double
        let suffix: String
        switch absolute {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return value.formatted(.number.locale(CodexLocalization.locale))
        }

        let scaledValue = Double(value) / divisor
        let number = scaledValue.formatted(
            .number
                .locale(CodexLocalization.locale)
                .precision(.fractionLength(absolute / divisor >= 100 ? 0 : 1))
        )
        return number + suffix
    }

    private func dayCount(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return CodexLocalization.text("\(value) 天", "\(value)d")
    }

    private func duration(_ seconds: Int64?) -> String {
        guard let seconds else { return "—" }
        if seconds >= 3_600 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return CodexLocalization.text("\(hours)时 \(minutes)分", "\(hours)h \(minutes)m")
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            return CodexLocalization.text("\(minutes) 分", "\(minutes)m")
        }
        return CodexLocalization.text("\(seconds) 秒", "\(seconds)s")
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = CodexLocalization.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(CodexLocalization.locale)
                .month(.defaultDigits)
                .day(.defaultDigits)
        )
    }

    private func monthDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(CodexLocalization.locale)
                .year(.twoDigits)
                .month(.abbreviated)
        )
    }

    private func longDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(CodexLocalization.locale)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    private static func serverDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }
}

private extension CodexOfficialActivityView {
    struct HeatmapDay: Identifiable, Equatable {
        let date: Date
        let tokens: Int64
        let isFuture: Bool

        var id: Date { date }
    }

    struct TrendPoint: Identifiable {
        let date: Date
        let value: Int64
        let label: String

        var id: Date { date }
    }

    enum TrendMode: String, CaseIterable, Identifiable {
        case daily
        case weekly
        case cumulative

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: return CodexLocalization.text("每日", "Daily")
            case .weekly: return CodexLocalization.text("每周", "Weekly")
            case .cumulative: return CodexLocalization.text("累计", "Cumulative")
            }
        }

        var tooltipMetric: String {
            switch self {
            case .daily:
                return CodexLocalization.text("当日 Token", "Daily tokens")
            case .weekly:
                return CodexLocalization.text("当周 Token", "Weekly tokens")
            case .cumulative:
                return CodexLocalization.text("累计 Token", "Cumulative tokens")
            }
        }
    }
}

private struct CodexOfficialTrendTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct CompactTrendChart: View {
    enum Style: Equatable {
        case bars
        case line
    }

    let points: [CodexOfficialActivityView.TrendPoint]
    let style: Style
    let mode: CodexOfficialActivityView.TrendMode
    let primary: Color
    let secondary: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?
    @State private var hoveredLocation: CGPoint?
    @State private var tooltipSize = CGSize(width: 118, height: 46)

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(points.map(\.value).max() ?? 0, 1)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Divider().opacity(0.18)
                    Spacer()
                    Divider().opacity(0.13)
                    Spacer()
                    Divider().opacity(0.18)
                }

                if points.isEmpty {
                    Text("—")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if style == .bars {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            let isHovered = hoveredIndex == index
                            let hasHoveredPoint = hoveredIndex != nil
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [primary.opacity(0.72), secondary.opacity(0.92)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: point.value > 0 ? 2 : 1,
                                    maxHeight: max(
                                        point.value > 0 ? 2 : 1,
                                        proxy.size.height * CGFloat(Double(point.value) / Double(maximum))
                                    )
                                )
                                .opacity(isHovered || !hasHoveredPoint ? 1 : 0.20)
                                .overlay {
                                    if isHovered {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(
                                                Color.white.opacity(
                                                    colorScheme == .dark ? 0.42 : 0.72
                                                ),
                                                lineWidth: 0.8
                                            )
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    linePath(in: proxy.size, maximum: maximum)
                        .stroke(
                            LinearGradient(
                                colors: [primary, secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )

                    areaPath(in: proxy.size, maximum: maximum)
                        .fill(
                            LinearGradient(
                                colors: [primary.opacity(0.20), secondary.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    if let hoveredIndex, points.indices.contains(hoveredIndex) {
                        let location = chartPoint(
                            index: hoveredIndex,
                            value: points[hoveredIndex].value,
                            in: proxy.size,
                            maximum: maximum
                        )
                        Rectangle()
                            .fill(primary.opacity(colorScheme == .dark ? 0.32 : 0.24))
                            .frame(width: 0.7, height: proxy.size.height)
                            .offset(x: location.x)
                        Circle()
                            .fill(primary)
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                            }
                            .shadow(color: primary.opacity(0.32), radius: 4)
                            .offset(x: location.x - 3.5, y: location.y - 3.5)
                    }
                }

                if let hoveredIndex,
                   points.indices.contains(hoveredIndex),
                   let pointer = hoveredLocation {
                    let origin = tooltipOrigin(
                        pointer: pointer,
                        tooltipSize: tooltipSize,
                        chartSize: proxy.size
                    )
                    trendTooltip(points[hoveredIndex])
                        .background {
                            GeometryReader { tooltipProxy in
                                Color.clear.preference(
                                    key: CodexOfficialTrendTooltipSizePreferenceKey.self,
                                    value: tooltipProxy.size
                                )
                            }
                        }
                        .offset(x: origin.x, y: origin.y)
                        .transition(.opacity)
                        .zIndex(4)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    updateHover(at: location, chartSize: proxy.size)
                case .ended:
                    hoveredIndex = nil
                    hoveredLocation = nil
                }
            }
            .onPreferenceChange(CodexOfficialTrendTooltipSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                tooltipSize = size
            }
            .animation(.easeOut(duration: 0.14), value: hoveredIndex)
        }
    }

    private func trendTooltip(
        _ point: CodexOfficialActivityView.TrendPoint
    ) -> some View {
        let formattedValue = point.value.formatted(
            .number.locale(CodexLocalization.locale)
        )

        return VStack(alignment: .leading, spacing: 3) {
            Text(tooltipDate(point.date))
                .font(.system(size: 8.5, weight: .semibold))
            Text("\(mode.tooltipMetric) · \(formattedValue)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(trendTooltipBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(primary.opacity(0.26), lineWidth: 0.6)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.32 : 0.15),
            radius: 5,
            y: 2
        )
        .allowsHitTesting(false)
    }

    private var trendTooltipBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.17, blue: 0.21)
            : Color(red: 0.87, green: 0.93, blue: 0.97)
    }

    private func tooltipDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(CodexLocalization.locale)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    private func updateHover(at location: CGPoint, chartSize: CGSize) {
        guard !points.isEmpty, chartSize.width > 0 else {
            hoveredIndex = nil
            hoveredLocation = nil
            return
        }

        let clampedX = min(max(location.x, 0), chartSize.width)
        let index: Int
        if style == .bars {
            let step = chartSize.width / CGFloat(points.count)
            index = min(
                points.count - 1,
                max(0, Int(clampedX / max(step, 1)))
            )
        } else {
            let ratio = clampedX / chartSize.width
            index = min(
                points.count - 1,
                max(0, Int((ratio * CGFloat(max(points.count - 1, 0))).rounded()))
            )
        }

        hoveredIndex = index
        hoveredLocation = location
    }

    private func tooltipOrigin(
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

    private func linePath(in size: CGSize, maximum: Int64) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let location = chartPoint(index: index, value: point.value, in: size, maximum: maximum)
                if index == 0 {
                    path.move(to: location)
                } else {
                    path.addLine(to: location)
                }
            }
        }
    }

    private func areaPath(in size: CGSize, maximum: Int64) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, point) in points.enumerated() {
                path.addLine(
                    to: chartPoint(index: index, value: point.value, in: size, maximum: maximum)
                )
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private func chartPoint(
        index: Int,
        value: Int64,
        in size: CGSize,
        maximum: Int64
    ) -> CGPoint {
        let denominator = max(points.count - 1, 1)
        let x = size.width * CGFloat(index) / CGFloat(denominator)
        let ratio = CGFloat(Double(value) / Double(maximum))
        return CGPoint(x: x, y: max(1, size.height * (1 - ratio)))
    }
}
