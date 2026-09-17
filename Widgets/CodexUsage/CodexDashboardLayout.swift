import Foundation
import SwiftUI
import AppKit
import DockDoorWidgetSDK

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
    mutating func move(_ card: CodexDashboardCard, to page: CodexDashboardPage, before target: CodexDashboardCard? = nil) {
        guard target != card else { return }
        for source in CodexDashboardPage.allCases { pages[source]?.removeAll { $0 == card } }
        let index = target.flatMap { pages[page]?.firstIndex(of: $0) } ?? (pages[page]?.count ?? 0)
        pages[page, default: []].insert(card, at: index)
    }
}

/// Hover uses public AppKit feedback. Strength remains hardware-controlled.
@MainActor
final class CodexDashboardHaptics {
    private var last = Date.distantPast
    private var pending: Task<Void, Never>?
    func hover() {
        guard WidgetDefaults.bool(key: "hoverHaptics", widgetId: codexUsageWidgetId), Date().timeIntervalSince(last) > 0.12 else { return }
        last = Date()
        pending?.cancel()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled, WidgetDefaults.bool(key: "hoverHaptics", widgetId: codexUsageWidgetId) else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}
