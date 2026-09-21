import DockDoorWidgetSDK
import SwiftUI

@MainActor
struct CodexUsagePanelView: View {
    let model: CodexUsageModel
    let dismiss: () -> Void
    @State private var page: CodexDashboardPage = .overview
    @State private var selectedWindow = 168
    @State private var modelFilter = "All models"
    private var theme: CodexTheme { CodexTheme.current(widgetId: codexUsageWidgetId) }
    private var spacing: CGFloat {
        switch WidgetDefaults.string(key: "cardDensity", widgetId: codexUsageWidgetId, default: "Standard") {
        case "Compact": return 8
        case "Spacious": return 18
        default: return 12
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                header
                HStack(spacing: 4) {
                    ForEach(CodexDashboardPage.allCases) { option in
                        Button { page = option } label: {
                            VStack(spacing: 4) {
                                Image(systemName: option.symbol)
                                Text(option.rawValue).lineLimit(1)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(theme.accent.opacity(page == option ? 0.22 : 0.06),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == option ? .isSelected : [])
                    }
                }
                if page == .activity || page == .models { filters }
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        if model.layout.pages[page, default: []].isEmpty {
                            Label("No cards on this page", systemImage: "square.dashed")
                                .font(.callout).frame(maxWidth: .infinity, minHeight: 100)
                        }
                        ForEach(model.layout.pages[page, default: []]) { card in
                            cardShell(card, now: timeline.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                HStack {
                    Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous page")
                    Spacer()
                    Text("\(page.rawValue) · \((CodexDashboardPage.allCases.firstIndex(of: page) ?? 0) + 1) of \(CodexDashboardPage.allCases.count)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next page")
                }.buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 350, height: 600)
            .background(CodexThemeBackground(theme: theme))
            .tint(theme.accent)
            .task(id: timeline.date) {
                await model.tick()
                await model.tickAnalytics()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Usage").font(.headline)
                Text("Read-only local snapshot").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Text("Appearance is in DockDoor widget settings.")
                Button("Reset card layout") { model.layout = .initial }
            } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Dashboard options")
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close Codex Usage")
        }
    }

    private var filters: some View {
        HStack {
            Picker("Period", selection: $selectedWindow) {
                Text("24 hours").tag(24)
                Text("7 days").tag(168)
                Text("Sampled logs").tag(0)
            }.labelsHidden().pickerStyle(.menu)
            Picker("Model", selection: $modelFilter) {
                Text("All models").tag("All models")
                ForEach(Array(Set(model.analytics.samples.map(\.model))).sorted(), id: \.self) { Text($0).tag($0) }
            }.labelsHidden().pickerStyle(.menu)
        }.font(.caption)
    }

    private func cardShell(_ card: CodexDashboardCard, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Menu("Move to page") {
                        ForEach(CodexDashboardPage.allCases) { target in
                            Button(target.rawValue) { move(card, to: target) }
                        }
                    }
                    Button("Move up") {
                        guard let cards = model.layout.pages[page], let index = cards.firstIndex(of: card), index > 0 else { return }
                        move(card, to: page, before: cards[index - 1])
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("\(card.title) options")
            }
            content(card, now: now)
        }
        .padding(spacing)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(0.17)))
    }

    private func content(_ card: CodexDashboardCard, now: Date) -> some View {
        CodexDashboardCardContent(card: card, snapshot: model.snapshot, analytics: model.analytics,
                                  lastRead: model.lastRead, now: now, theme: theme,
                                  hours: selectedWindow, modelFilter: modelFilter)
    }

    private func navigate(_ delta: Int) {
        let pages = CodexDashboardPage.allCases
        page = pages[((pages.firstIndex(of: page) ?? 0) + delta + pages.count) % pages.count]
    }

    private func move(_ card: CodexDashboardCard, to target: CodexDashboardPage, before: CodexDashboardCard? = nil) {
        model.layout.move(card, to: target, before: before)
        page = target
    }
}
