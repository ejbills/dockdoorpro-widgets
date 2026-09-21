import Foundation

enum CodexDashboardPage: String, CaseIterable, Identifiable {
    case overview = "Overview", activity = "Activity", models = "Models", health = "Health"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .activity: return "chart.xyaxis.line"
        case .models: return "square.stack.3d.up"
        case .health: return "heart.text.square"
        }
    }
}

enum CodexDashboardCard: String, CaseIterable, Identifiable {
    case quota, limits, totals, daily, hourly, context, pulse, model, mix, efficiency, sources, sessions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quota: return "Quota"
        case .limits: return "Usage limits"
        case .totals: return "Token activity"
        case .daily: return "Daily activity"
        case .hourly: return "Hourly activity"
        case .context: return "Context window"
        case .pulse: return "Session pulse"
        case .model: return "Recorded model"
        case .mix: return "Model mix"
        case .efficiency: return "Cache efficiency"
        case .sources: return "Data health"
        case .sessions: return "Recent sessions"
        }
    }
    var page: CodexDashboardPage {
        switch self {
        case .quota, .limits, .pulse: return .overview
        case .totals, .daily, .hourly: return .activity
        case .model, .mix, .efficiency: return .models
        case .context, .sources, .sessions: return .health
        }
    }
}

struct CodexDashboardLayout {
    var pages: [CodexDashboardPage: [CodexDashboardCard]]
    static var initial: Self {
        Self(pages: Dictionary(uniqueKeysWithValues: CodexDashboardPage.allCases.map { page in
            (page, CodexDashboardCard.allCases.filter { $0.page == page })
        }))
    }

    /// Card placement is runtime state, not a user setting, so it lives under
    /// `<pluginId>.<key>` like NetworkMonitor's selected interface.
    private static let defaultsKey = "\(codexUsageWidgetId).layout"

    static func restore() -> Self {
        guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] else { return .initial }
        var layout = Self(pages: Dictionary(uniqueKeysWithValues: CodexDashboardPage.allCases.map { page in
            (page, (stored[page.rawValue] ?? []).compactMap(CodexDashboardCard.init(rawValue:)))
        }))
        let placed = Set(layout.pages.values.joined())
        for card in CodexDashboardCard.allCases where !placed.contains(card) {
            layout.pages[card.page, default: []].append(card)
        }
        return layout
    }

    func save() {
        let stored = Dictionary(uniqueKeysWithValues: pages.map { ($0.key.rawValue, $0.value.map(\.rawValue)) })
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
    }
    mutating func move(_ card: CodexDashboardCard, to page: CodexDashboardPage, before target: CodexDashboardCard? = nil) {
        guard target != card else { return }
        for source in CodexDashboardPage.allCases { pages[source]?.removeAll { $0 == card } }
        let index = target.flatMap { pages[page]?.firstIndex(of: $0) } ?? (pages[page]?.count ?? 0)
        pages[page, default: []].insert(card, at: index)
    }
}
