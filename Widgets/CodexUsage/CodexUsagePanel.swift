import SwiftUI
import DockDoorWidgetSDK
import UniformTypeIdentifiers

@MainActor
struct CodexUsagePanelView: View {
    let model: CodexUsageModel
    let dismiss: () -> Void
    @State private var page: CodexDashboardPage = .overview
    @State private var targetedPage: CodexDashboardPage?
    @State private var detail: CodexDashboardCard?
    @State private var selectedWindow = 24
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
                            .background(theme.accent.opacity(targetedPage == option ? 0.4 : page == option ? 0.22 : 0.06),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { model.haptics.hover() } }
                        .onDrop(of: [.text], isTargeted: targetBinding(option)) { receive($0, to: option) }
                        .accessibilityAddTraits(page == option ? .isSelected : [])
                        .help("Open \(option.rawValue), or drop a card on this tab")
                    }
                }
                if page == .activity || page == .models { filters }
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        if model.layout.pages[page, default: []].isEmpty {
                            Label("Drop a card here", systemImage: "square.dashed")
                                .font(.callout).frame(maxWidth: .infinity, minHeight: 100)
                        }
                        ForEach(model.layout.pages[page, default: []]) { card in
                            cardShell(card, now: timeline.date)
                                .onDrop(of: [.text], isTargeted: nil) { receive($0, to: page, before: card) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                }
                .onDrop(of: [.text], isTargeted: nil) { receive($0, to: page) }
                HStack {
                    Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous page")
                    Spacer()
                    Text("\(page.rawValue) · \((CodexDashboardPage.allCases.firstIndex(of: page) ?? 0) + 1) of 4")
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
            .sheet(item: $detail) { card in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(card.title).font(.headline)
                        Spacer()
                        Button("Done") { detail = nil }
                    }
                    ScrollView { content(card, now: timeline.date) }
                    Text("Analytics sample eight recent local logs. They are not account-wide totals or billing figures.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(width: 390, height: 440)
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
                Text("Appearance and hover haptics are in DockDoor widget settings.")
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
            Group {
                Picker("Model", selection: $modelFilter) {
                    Text("All models").tag("All models")
                    ForEach(Array(Set(model.analytics.samples.map(\.model))).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }
        }.font(.caption)
    }

    private func cardShell(_ card: CodexDashboardCard, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.title, systemImage: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrag { NSItemProvider(object: "codex-usage-dashboard:\(card.rawValue)" as NSString) }
                    .help("Drag this heading onto another page tab")
                Menu {
                    Button("Details") { detail = card }
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
        .onHover { if $0 { model.haptics.hover() } }
    }

    private func content(_ card: CodexDashboardCard, now: Date) -> some View {
        CodexDashboardCardContent(card: card, snapshot: model.snapshot, analytics: model.analytics,
                                  lastRead: model.lastRead, now: now, theme: theme,
                                  hours: selectedWindow, modelFilter: modelFilter)
    }
    private func navigate(_ delta: Int) {
        let pages = CodexDashboardPage.allCases
        page = pages[((pages.firstIndex(of: page) ?? 0) + delta + pages.count) % pages.count]
        model.haptics.hover()
    }
    private func move(_ card: CodexDashboardCard, to target: CodexDashboardPage, before: CodexDashboardCard? = nil) {
        model.layout.move(card, to: target, before: before)
        page = target
        targetedPage = nil
        model.haptics.hover()
    }
    private func targetBinding(_ option: CodexDashboardPage) -> Binding<Bool> {
        Binding(get: { targetedPage == option }, set: { targetedPage = $0 ? option : nil })
    }
    private func receive(_ providers: [NSItemProvider], to target: CodexDashboardPage, before: CodexDashboardCard? = nil) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix("codex-usage-dashboard:"),
                  let card = CodexDashboardCard(rawValue: String(text.dropFirst("codex-usage-dashboard:".count))) else { return }
            Task { @MainActor in move(card, to: target, before: before) }
        }
        return true
    }
}
