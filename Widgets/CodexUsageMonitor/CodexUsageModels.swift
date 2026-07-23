import Foundation
import SwiftUI

enum CodexLocalization {
    static var isChinese: Bool {
        let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        return identifier.lowercased().hasPrefix("zh")
    }

    static var locale: Locale {
        Locale(identifier: isChinese ? "zh_CN" : "en_US")
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}

enum CodexQuotaUsageSource: String, CaseIterable, Identifiable {
    case automatic
    case oauth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return CodexLocalization.text("自动", "Automatic")
        case .oauth: return "OAuth API"
        }
    }

    var sourceLabel: String {
        switch self {
        case .automatic: return "auto"
        case .oauth: return "oauth"
        }
    }

    static func resolve(title: String) -> CodexQuotaUsageSource {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .automatic
    }

    private var localizedTitles: [String] {
        switch self {
        case .automatic: return ["自动", "Automatic"]
        case .oauth: return ["OAuth API"]
        }
    }
}

struct CodexQuotaFetchResult {
    let snapshot: CodexUsageSnapshot
    let resolvedSource: CodexQuotaUsageSource
}

enum CodexPalette {
    static let teal = Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
    static let cyan = Color(red: 82 / 255, green: 197 / 255, blue: 211 / 255)
    static let indigo = Color(red: 115 / 255, green: 107 / 255, blue: 212 / 255)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let yellow = Color(red: 0.96, green: 0.77, blue: 0.13)
    static let red = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let softCritical = Color(red: 0.93, green: 0.31, blue: 0.38)

    static func green(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.32, green: 0.66, blue: 0.41) : green
    }

    static func yellow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.64, blue: 0.27) : yellow
    }

    static func red(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.76, green: 0.40, blue: 0.36) : red
    }

    static func softCritical(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.76, green: 0.43, blue: 0.49) : softCritical
    }

    static func orange(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.78, green: 0.50, blue: 0.28) : .orange
    }

    static var quotaGradient: LinearGradient {
        LinearGradient(colors: [teal, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum CodexColorTheme: String, CaseIterable, Identifiable {
    case systemAccent
    case codex
    case ocean
    case purple
    case blueMagenta
    case mint
    case sunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemAccent: return CodexLocalization.text("系统强调色", "System Accent")
        case .codex: return CodexLocalization.text("Codex 青", "Codex Teal")
        case .ocean: return "Ocean"
        case .purple: return CodexLocalization.text("紫罗兰", "Violet")
        case .blueMagenta: return CodexLocalization.text("蓝洋红", "Blue Magenta")
        case .mint: return CodexLocalization.text("薄荷", "Mint")
        case .sunset: return CodexLocalization.text("日落", "Sunset")
        }
    }

    private var localizedTitles: [String] {
        switch self {
        case .systemAccent: return ["系统强调色", "System Accent"]
        case .codex: return ["Codex 青", "Codex Teal"]
        case .ocean: return ["Ocean"]
        case .purple: return ["紫罗兰", "Violet"]
        case .blueMagenta: return ["蓝洋红", "Blue Magenta"]
        case .mint: return ["薄荷", "Mint"]
        case .sunset: return ["日落", "Sunset"]
        }
    }

    func colors(for colorScheme: ColorScheme) -> CodexThemeColors {
        if colorScheme == .dark {
            return darkColors
        }

        switch self {
        case .systemAccent:
            return CodexThemeColors(
                primary: .accentColor,
                secondary: .accentColor.opacity(0.48)
            )
        case .codex:
            return CodexThemeColors(
                primary: Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255),
                secondary: Color(red: 115 / 255, green: 107 / 255, blue: 212 / 255)
            )
        case .ocean:
            return CodexThemeColors(
                primary: Color(red: 0.10, green: 0.72, blue: 0.94),
                secondary: Color(red: 0.18, green: 0.36, blue: 0.98)
            )
        case .purple:
            return CodexThemeColors(
                primary: Color(red: 0.56, green: 0.35, blue: 0.96),
                secondary: Color(red: 0.76, green: 0.32, blue: 0.92)
            )
        case .blueMagenta:
            return CodexThemeColors(
                primary: Color(red: 0.10, green: 0.53, blue: 0.98),
                secondary: Color(red: 0.86, green: 0.17, blue: 0.91)
            )
        case .mint:
            return CodexThemeColors(
                primary: Color(red: 0.16, green: 0.76, blue: 0.61),
                secondary: Color(red: 0.10, green: 0.70, blue: 0.86)
            )
        case .sunset:
            return CodexThemeColors(
                primary: Color(red: 0.98, green: 0.47, blue: 0.20),
                secondary: Color(red: 0.96, green: 0.25, blue: 0.51)
            )
        }
    }

    private var darkColors: CodexThemeColors {
        switch self {
        case .systemAccent:
            return CodexThemeColors(
                primary: .accentColor.opacity(0.78),
                secondary: .accentColor.opacity(0.38)
            )
        case .codex:
            return CodexThemeColors(
                primary: Color(red: 0.29, green: 0.59, blue: 0.63),
                secondary: Color(red: 0.45, green: 0.43, blue: 0.68)
            )
        case .ocean:
            return CodexThemeColors(
                primary: Color(red: 0.22, green: 0.58, blue: 0.70),
                secondary: Color(red: 0.30, green: 0.43, blue: 0.71)
            )
        case .purple:
            return CodexThemeColors(
                primary: Color(red: 0.50, green: 0.40, blue: 0.71),
                secondary: Color(red: 0.63, green: 0.38, blue: 0.68)
            )
        case .blueMagenta:
            return CodexThemeColors(
                primary: Color(red: 0.27, green: 0.51, blue: 0.77),
                secondary: Color(red: 0.66, green: 0.36, blue: 0.67)
            )
        case .mint:
            return CodexThemeColors(
                primary: Color(red: 0.29, green: 0.63, blue: 0.55),
                secondary: Color(red: 0.27, green: 0.58, blue: 0.66)
            )
        case .sunset:
            return CodexThemeColors(
                primary: Color(red: 0.78, green: 0.48, blue: 0.28),
                secondary: Color(red: 0.74, green: 0.37, blue: 0.48)
            )
        }
    }

    static func resolve(widgetId: String) -> CodexColorTheme {
        let title = UserDefaults.standard.string(
            forKey: "widget.\(widgetId).colorTheme"
        ) ?? CodexColorTheme.codex.title
        return allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .codex
    }
}

struct CodexThemeColors {
    let primary: Color
    let secondary: Color

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct CodexQuotaWindow: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetAt: Date?
    let durationSeconds: Int

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var usedRatio: Double { max(0, min(1, usedPercent / 100)) }
    var remainingRatio: Double { max(0, min(1, remainingPercent / 100)) }

    func resetDescription(now: Date = Date()) -> String {
        guard let resetAt else {
            return CodexLocalization.text("暂无重置时间", "Reset time unavailable")
        }
        let seconds = max(0, resetAt.timeIntervalSince(now))
        if seconds < 60 { return CodexLocalization.text("即将重置", "Resetting soon") }
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if days > 0 {
            return CodexLocalization.text(
                "\(days)天 \(hours)小时后重置",
                "Resets in \(days)d \(hours)h"
            )
        }
        if hours > 0 {
            return CodexLocalization.text(
                "\(hours)小时 \(minutes)分钟后重置",
                "Resets in \(hours)h \(minutes)m"
            )
        }
        return CodexLocalization.text("\(minutes)分钟后重置", "Resets in \(minutes)m")
    }
}

struct CodexTokenUsageDay: Codable, Equatable, Identifiable {
    let dayKey: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let priorityTokens: Int
    let estimatedCostUSD: Double?

    var id: String { dayKey }
    var totalTokens: Int { inputTokens + outputTokens }
}

struct CodexRecentUsageSnapshot: Codable, Equatable {
    let todayTokens: Int
    let todayEstimatedCostUSD: Double?
    let last30DaysTokens: Int
    let last30DaysEstimatedCostUSD: Double?
    let daily: [CodexTokenUsageDay]
    let mostUsedModel: String?
    let pricingSource: String?
    let updatedAt: Date

    var chartDays: [CodexTokenUsageDay] {
        Array(daily.suffix(8))
    }
}

struct CodexUsageSnapshot: Codable, Equatable {
    let accountEmail: String?
    let plan: String?
    let sessionWindow: CodexQuotaWindow?
    let weeklyWindow: CodexQuotaWindow?
    let extraWindows: [CodexQuotaWindow]
    let creditsBalance: Double?
    let resetCreditsAvailable: Int?
    let resetCreditsExpiresAt: Date?
    let fetchedAt: Date

    var displayPlan: String {
        guard let plan, !plan.isEmpty else { return "Codex" }
        switch plan.lowercased() {
        case "pro", "prolite", "pro_lite": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return plan.capitalized
        }
    }
}

enum OpenAIServiceIndicator: String, Codable, Equatable {
    case operational
    case degraded
    case partialOutage
    case majorOutage
    case maintenance
    case unknown

    init(status: String) {
        switch status {
        case "operational": self = .operational
        case "degraded_performance": self = .degraded
        case "partial_outage": self = .partialOutage
        case "major_outage", "full_outage": self = .majorOutage
        case "under_maintenance": self = .maintenance
        default: self = .unknown
        }
    }

    init(overallIndicator: String) {
        switch overallIndicator {
        case "none": self = .operational
        case "minor": self = .degraded
        case "major": self = .partialOutage
        case "critical": self = .majorOutage
        case "maintenance": self = .maintenance
        default: self = .unknown
        }
    }

    var rank: Int {
        switch self {
        case .operational: return 0
        case .maintenance, .unknown: return 1
        case .degraded: return 2
        case .partialOutage: return 3
        case .majorOutage: return 4
        }
    }

    var label: String {
        switch self {
        case .operational: return CodexLocalization.text("正常运行", "Operational")
        case .degraded: return CodexLocalization.text("性能下降", "Degraded")
        case .partialOutage: return CodexLocalization.text("部分中断", "Partial outage")
        case .majorOutage: return CodexLocalization.text("服务中断", "Major outage")
        case .maintenance: return CodexLocalization.text("维护中", "Maintenance")
        case .unknown: return CodexLocalization.text("状态未知", "Unknown")
        }
    }

    func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .operational: return CodexPalette.green(for: colorScheme)
        case .maintenance, .degraded: return CodexPalette.yellow(for: colorScheme)
        case .partialOutage, .majorOutage: return CodexPalette.red(for: colorScheme)
        case .unknown: return .secondary
        }
    }
}

struct OpenAIStatusComponent: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let indicator: OpenAIServiceIndicator
}

struct OpenAIStatusGroup: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let components: [OpenAIStatusComponent]

    var indicator: OpenAIServiceIndicator {
        components.max { $0.indicator.rank < $1.indicator.rank }?.indicator ?? .unknown
    }
}

struct OpenAIStatusSnapshot: Codable, Equatable {
    let overallIndicator: OpenAIServiceIndicator
    let description: String?
    let groups: [OpenAIStatusGroup]
    let updatedAt: Date?
    let fetchedAt: Date

    func group(named name: String) -> OpenAIStatusGroup? {
        groups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var codex: OpenAIStatusGroup? { group(named: "Codex") }
    var chatGPT: OpenAIStatusGroup? { group(named: "ChatGPT") }
}

enum CodexDisplayLimit: String, CaseIterable, Identifiable {
    case weekly
    case session

    var id: String { rawValue }
    var title: String {
        self == .weekly
            ? CodexLocalization.text("每周额度", "Weekly quota")
            : CodexLocalization.text("短周期额度", "Session quota")
    }
    var shortLabel: String { self == .weekly ? "WEEK" : "SESSION" }

    static func resolve(title: String) -> CodexDisplayLimit {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .weekly
    }

    private var localizedTitles: [String] {
        self == .weekly ? ["每周额度", "Weekly quota"] : ["短周期额度", "Session quota"]
    }
}

enum CodexDisplayMetric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
    var title: String {
        self == .remaining
            ? CodexLocalization.text("显示剩余", "Show remaining")
            : CodexLocalization.text("显示已用", "Show used")
    }

    static func resolve(title: String) -> CodexDisplayMetric {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .remaining
    }

    private var localizedTitles: [String] {
        self == .remaining ? ["显示剩余", "Show remaining"] : ["显示已用", "Show used"]
    }
}

enum CodexRingStyle: String, CaseIterable, Identifiable {
    case classic
    case concentric
    case segmented
    case carousel

    static let carouselStyles: [CodexRingStyle] = [
        .classic,
        .concentric,
        .segmented,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return CodexLocalization.text("原版圆环", "Classic Ring")
        case .concentric: return CodexLocalization.text("同心多环", "Concentric Rings")
        case .segmented: return CodexLocalization.text("分段圆环", "Segmented Ring")
        case .carousel: return CodexLocalization.text("自动轮播", "Auto Carousel")
        }
    }

    static func resolve(title: String) -> CodexRingStyle {
        allCases.first { item in
            title == item.rawValue || item.localizedTitles.contains(title)
        } ?? .concentric
    }

    private var localizedTitles: [String] {
        switch self {
        case .classic: return ["原版圆环", "Classic Ring"]
        case .concentric: return ["同心多环", "Concentric Rings"]
        case .segmented: return ["分段圆环", "Segmented Ring"]
        case .carousel: return ["自动轮播", "Auto Carousel"]
        }
    }
}

enum CodexRefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .oneMinute: return CodexLocalization.text("1 分钟", "1 minute")
        case .fiveMinutes: return CodexLocalization.text("5 分钟", "5 minutes")
        case .fifteenMinutes: return CodexLocalization.text("15 分钟", "15 minutes")
        case .thirtyMinutes: return CodexLocalization.text("30 分钟", "30 minutes")
        }
    }

    static func resolve(title: String) -> CodexRefreshInterval {
        allCases.first { item in
            title == String(item.rawValue) || item.localizedTitles.contains(title)
        } ?? .fiveMinutes
    }

    private var localizedTitles: [String] {
        switch self {
        case .oneMinute: return ["1 分钟", "1 minute"]
        case .fiveMinutes: return ["5 分钟", "5 minutes"]
        case .fifteenMinutes: return ["15 分钟", "15 minutes"]
        case .thirtyMinutes: return ["30 分钟", "30 minutes"]
        }
    }
}

extension Date {
    var codexShortTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var codexRelativeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
