import SwiftUI

enum ThingsStyle {
    static let inbox = Color(red: 0.08, green: 0.63, blue: 0.95)
    static let today = Color(red: 1.00, green: 0.84, blue: 0.08)
    static let deadline = Color(red: 0.93, green: 0.20, blue: 0.38)
    static let anytime = Color(red: 0.35, green: 0.78, blue: 0.74)
    static let someday = Color(red: 0.82, green: 0.78, blue: 0.52)
    static let rowFill = Color.white.opacity(0.08)
    static let selectedFill = Color.white.opacity(0.15)
    static let divider = Color.white.opacity(0.20)
    static let eventTime = Color(red: 0.78, green: 0.17, blue: 0.96)
}

private enum ThingsPanelSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case today = "Today"
    case upcoming = "Upcoming"
    case anytime = "Anytime"
    case someday = "Someday"
    case deadlines = "Deadlines"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inbox: return "inbox"
        case .today: return "star.fill"
        case .upcoming: return "calendar"
        case .anytime: return "square.stack.3d.up.fill"
        case .someday: return "archivebox.fill"
        case .deadlines: return "flag.fill"
        }
    }

    var tint: Color {
        switch self {
        case .inbox: return ThingsStyle.inbox
        case .today: return ThingsStyle.today
        case .upcoming: return ThingsStyle.deadline
        case .anytime: return ThingsStyle.anytime
        case .someday: return ThingsStyle.someday
        case .deadlines: return ThingsStyle.deadline
        }
    }
}

struct ThingsTodayPanel: View {
    let dismiss: () -> Void
    @ObservedObject var store: ThingsStore

    @State private var selection: ThingsPanelSection = .today

    private var selectedTasks: [ThingsTask] {
        switch selection {
        case .inbox: return store.snapshot.inbox
        case .today: return store.snapshot.today
        case .upcoming: return store.snapshot.upcoming
        case .anytime: return store.snapshot.anytime
        case .someday: return store.snapshot.someday
        case .deadlines: return store.snapshot.deadlines
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .opacity(0.35)

            detail
        }
        .frame(width: 620)
        .frame(height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
        .onAppear { store.refresh(force: true) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarRow(.inbox)
            Spacer().frame(height: 8)
            sidebarRow(.today)
            sidebarRow(.upcoming)
            sidebarRow(.anytime)
            sidebarRow(.someday)
            Spacer().frame(height: 8)
            sidebarRow(.deadlines)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(width: 188)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let error = store.snapshot.errorMessage {
                emptyDetail(error, symbol: "star")
            } else {
                HStack(spacing: 12) {
                    panelIcon(selection, size: 31)
                        .frame(width: 38, height: 38)

                    Text(selection.rawValue)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.top, 24)

                if selectedTasks.isEmpty {
                    emptyDetail("No \(selection.rawValue) tasks", symbol: selection.symbol)
                } else if selection == .upcoming {
                    upcomingList
                } else {
                    taskList
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(width: 432)
    }

    private var taskList: some View {
        scrollShell {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(selectedTasks.prefix(40)) { task in
                    detailRow(task, showTodayStar: selection == .anytime && isTodayDate(task.startDate))
                }
            }
            .padding(.vertical, 2)
            .padding(.bottom, 18)
        }
    }

    private var upcomingList: some View {
        let groupedTasks = Dictionary(grouping: selectedTasks.prefix(80), by: { $0.startDate ?? $0.deadline ?? "" })
        let groupedEvents = Dictionary(grouping: store.snapshot.events, by: { $0.dayKey })
        let dates = upcomingDateKeys(taskKeys: groupedTasks.keys, eventKeys: groupedEvents.keys)

        return scrollShell {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(dates, id: \.self) { date in
                    upcomingDaySection(date: date, tasks: groupedTasks[date] ?? [], events: groupedEvents[date] ?? [])
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func scrollShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                content()
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 4)
            .allowsHitTesting(false)
        }
    }

    private func sidebarRow(_ section: ThingsPanelSection) -> some View {
        let count = count(for: section)
        let deadlineCount = section == .today
            ? store.snapshot.today.filter { isTodayDate($0.deadline) }.count
            : 0
        let regularCount = section == .today ? max(count - deadlineCount, 0) : count
        let showsCount = section == .inbox || section == .today

        return Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                panelIcon(section, size: 15)
                    .frame(width: 19, height: 19)

                Text(section.rawValue)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if showsCount && deadlineCount > 0 {
                    Text("\(deadlineCount)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ThingsStyle.deadline))
                }

                if showsCount && regularCount > 0 {
                    Text("\(regularCount)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selection == section ? ThingsStyle.selectedFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ task: ThingsTask, showTodayStar: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            completeButton(task)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if showTodayStar {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(ThingsStyle.today)
                    }

                    Text(task.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if let due = task.dueLine {
                        HStack(spacing: 5) {
                            Image(systemName: isTodayDate(task.deadline) ? "flag.fill" : "calendar")
                                .font(.system(size: 10, weight: .bold))
                            Text(due.lowercased())
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(isTodayDate(task.deadline) ? ThingsStyle.deadline : .secondary)
                        .lineLimit(1)
                    }
                }

                let context = contextLine(for: task)
                if !context.isEmpty {
                    Text(context)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }

    private func upcomingRow(_ task: ThingsTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            completeButton(task)

            Text(task.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let daysLeft = daysLeftText(task.deadline) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(daysLeft)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(ThingsStyle.deadline.opacity(isTodayDate(task.deadline) ? 1 : 0.72))
                .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }

    private func upcomingDaySection(date: String, tasks: [ThingsTask], events: [ThingsCalendarEvent]) -> some View {
        let isSparse = tasks.isEmpty && events.isEmpty

        return VStack(alignment: .leading, spacing: isSparse ? 4 : 10) {
            dayHeader(date)

            ForEach(events) { event in
                calendarEventRow(event)
            }

            ForEach(tasks) { task in
                upcomingRow(task)
            }
        }
        .frame(minHeight: isSparse ? 66 : 0, alignment: .top)
    }

    private func calendarEventRow(_ event: ThingsCalendarEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(event.timeText)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ThingsStyle.eventTime)
                .monospacedDigit()

            Text(event.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 4)
    }

    private func upcomingDateKeys(taskKeys: Dictionary<String, [ThingsTask]>.Keys, eventKeys: Dictionary<String, [ThingsCalendarEvent]>.Keys) -> [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let visibleWeek = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset + 1, to: start).map(isoDayString)
        }
        return Set(visibleWeek)
            .union(taskKeys)
            .union(eventKeys)
            .sorted()
    }

    private func dayHeader(_ isoDate: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dayNumber(isoDate))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)

            Text(dayLabel(isoDate))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(ThingsStyle.divider)
                .frame(height: 1)
                .padding(.top, 18)
        }
        .padding(.top, 2)
    }

    private func completeButton(_ task: ThingsTask) -> some View {
        Button {
            _ = store.complete(task)
        } label: {
            Image(systemName: "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panelIcon(_ section: ThingsPanelSection, size: CGFloat) -> some View {
        if section == .inbox {
            ThingsInboxGlyph()
                .fill(section.tint, style: FillStyle(eoFill: true))
        } else {
            Image(systemName: section.symbol)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(section.tint)
        }
    }

    private func contextLine(for task: ThingsTask) -> String {
        if let project = task.projectTitle, !project.isEmpty {
            return project
        }
        if selection == .today {
            return ""
        }
        return task.contextLine == task.dueLine ? "" : task.contextLine
    }

    private func emptyDetail(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func count(for section: ThingsPanelSection) -> Int {
        switch section {
        case .inbox: return store.snapshot.inbox.count
        case .today: return store.snapshot.today.count
        case .upcoming: return store.snapshot.upcoming.count
        case .anytime: return store.snapshot.anytime.count
        case .someday: return store.snapshot.someday.count
        case .deadlines: return store.snapshot.deadlines.count
        }
    }
}

private struct ThingsInboxGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let thickness = max(width * 0.23, 3)
        let corner = width * 0.12
        let innerWidth = width - thickness * 2
        let innerHeight = height - thickness * 1.45

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: width, height: height),
            cornerSize: CGSize(width: corner, height: corner)
        )
        path.addRoundedRect(
            in: CGRect(x: thickness, y: thickness, width: innerWidth, height: innerHeight),
            cornerSize: CGSize(width: corner * 0.55, height: corner * 0.55)
        )
        path.addRect(CGRect(x: width * 0.34, y: height * 0.58, width: width * 0.32, height: height * 0.28))
        return path
    }
}
