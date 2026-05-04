import AppKit
import EventKit
import Foundation
import SQLite3

struct ThingsCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date

    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startDate)
    }

    var dayKey: String {
        isoDayString(startDate)
    }
}

struct ThingsTask: Identifiable, Equatable {
    enum Source: String {
        case inbox = "Inbox"
        case today = "Today"
        case upcoming = "Upcoming"
        case anytime = "Anytime"
        case someday = "Someday"
        case deadline = "Deadlines"
    }

    let id: String
    let title: String
    let projectTitle: String?
    let startDate: String?
    let deadline: String?
    let todayIndex: Int
    let source: Source

    var contextLine: String {
        if let projectTitle, !projectTitle.isEmpty {
            return projectTitle
        }
        if let startDate {
            return relativeDate(startDate)
        }
        if let deadline {
            return "Deadline \(relativeDate(deadline))"
        }
        return projectTitle ?? ""
    }

    var dueLine: String? {
        guard let deadline else { return nil }
        return relativeDate(deadline)
    }
}

struct ThingsSnapshot: Equatable {
    var inbox: [ThingsTask] = []
    var today: [ThingsTask] = []
    var upcoming: [ThingsTask] = []
    var anytime: [ThingsTask] = []
    var someday: [ThingsTask] = []
    var deadlines: [ThingsTask] = []
    var events: [ThingsCalendarEvent] = []
    var errorMessage: String?

    static let loading = ThingsSnapshot(errorMessage: nil)
}

final class ThingsStore: ObservableObject {
    @Published private(set) var snapshot = ThingsSnapshot.loading

    private let database = ThingsDatabase()
    private let calendar = ThingsCalendarStore()
    private var lastRefresh = Date.distantPast
    private let cacheDuration: TimeInterval = 10

    @MainActor
    func refresh(force: Bool = false) {
        if !force && Date().timeIntervalSince(lastRefresh) < cacheDuration {
            return
        }

        lastRefresh = Date()

        do {
            var nextSnapshot = try database.snapshot()
            nextSnapshot.events = calendar.events()
            snapshot = nextSnapshot
        } catch {
            snapshot = ThingsSnapshot(errorMessage: error.localizedDescription)
        }
    }

    @MainActor
    func complete(_ task: ThingsTask) -> Bool {
        do {
            guard let token = try database.authToken(),
                  !token.isEmpty,
                  let url = thingsUpdateURL(taskID: task.id, token: token)
            else {
                return false
            }

            NSWorkspace.shared.open(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.refresh(force: true)
            }
            return true
        } catch {
            return false
        }
    }

    private func thingsUpdateURL(taskID: String, token: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encodedID = taskID.addingPercentEncoding(withAllowedCharacters: allowed) ?? taskID
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
        return URL(string: "things:///update?id=\(encodedID)&completed=true&auth-token=\(encodedToken)")
    }
}

final class ThingsCalendarStore {
    private let store = EKEventStore()

    func events(days: Int = 90) -> [ThingsCalendarEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            guard status == .fullAccess else {
                return []
            }
        } else {
            guard status == .authorized else {
                return []
            }
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(80)
            .map {
                ThingsCalendarEvent(
                    id: $0.eventIdentifier ?? "\($0.title ?? "")-\($0.startDate.timeIntervalSince1970)",
                    title: $0.title ?? "Untitled Event",
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            }
    }
}

enum ThingsDatabaseError: LocalizedError {
    case databaseNotFound
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Open Things"
        case .openFailed:
            return "Open Things"
        case .queryFailed:
            return "Open Things"
        }
    }
}

final class ThingsDatabase {
    private let fileManager = FileManager.default

    func snapshot() throws -> ThingsSnapshot {
        let path = try databasePath()
        let inbox = try fetchTasks(path: path, source: .inbox)
        let today = try fetchTasks(path: path, source: .today)
        let upcoming = try fetchTasks(path: path, source: .upcoming)
        let anytime = try fetchTasks(path: path, source: .anytime)
        let someday = try fetchTasks(path: path, source: .someday)
        let deadlines = try fetchTasks(path: path, source: .deadline)
        return ThingsSnapshot(
            inbox: inbox,
            today: today,
            upcoming: upcoming,
            anytime: anytime,
            someday: someday,
            deadlines: deadlines,
            errorMessage: nil
        )
    }

    func authToken() throws -> String? {
        let path = try databasePath()
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open Things database"
            if let db {
                sqlite3_close(db)
            }
            throw ThingsDatabaseError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT uriSchemeAuthenticationToken
            FROM TMSettings
            WHERE uuid = 'RhAzEf6qDxCD5PmnZVtBZR'
            LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw ThingsDatabaseError.queryFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return text(statement, 0)
    }

    private func databasePath() throws -> String {
        let groupDirectory = NSString(string: "~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac").expandingTildeInPath

        if let entries = try? fileManager.contentsOfDirectory(atPath: groupDirectory) {
            let migrated = entries
                .filter { $0.hasPrefix("ThingsData-") }
                .sorted()
                .map {
                    groupDirectory + "/" + $0 + "/Things Database.thingsdatabase/main.sqlite"
                }
                .first { fileManager.fileExists(atPath: $0) }

            if let migrated {
                return migrated
            }
        }

        let legacy = groupDirectory + "/Things Database.thingsdatabase/main.sqlite"
        if fileManager.fileExists(atPath: legacy) {
            return legacy
        }

        throw ThingsDatabaseError.databaseNotFound
    }

    private func fetchTasks(path: String, source: ThingsTask.Source) throws -> [ThingsTask] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open Things database"
            if let db {
                sqlite3_close(db)
            }
            throw ThingsDatabaseError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = query(for: source)
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw ThingsDatabaseError.queryFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        var tasks: [ThingsTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = text(statement, 0) ?? UUID().uuidString
            let rawTitle = text(statement, 1) ?? "Untitled"
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            tasks.append(ThingsTask(
                id: id,
                title: title.isEmpty ? "Untitled" : title,
                projectTitle: text(statement, 2),
                startDate: text(statement, 3),
                deadline: text(statement, 4),
                todayIndex: int(statement, 5) ?? Int.max,
                source: source
            ))
        }

        return tasks
    }

    private func query(for source: ThingsTask.Source) -> String {
        let baseSelect = """
            SELECT DISTINCT
                TASK.uuid,
                TASK.title,
                PROJECT.title AS project_title,
                \(isoDateExpression("TASK.startDate")) AS start_date,
                \(isoDateExpression("TASK.deadline")) AS deadline,
                TASK.todayIndex AS today_index
            FROM TMTask AS TASK
            LEFT OUTER JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
            WHERE
                TASK.type = 0
                AND TASK.status = 0
                AND TASK.trashed = 0
                AND (PROJECT.uuid IS NULL OR PROJECT.trashed = 0)
        """

        switch source {
        case .inbox:
            return """
                \(baseSelect)
                    AND TASK.start = 0
                ORDER BY TASK."index", TASK.title
                LIMIT 60
            """
        case .today:
            return """
                \(baseSelect)
                    AND (
                        (TASK.startDate IS NOT NULL AND TASK.start = 1)
                        OR (TASK.startDate <= \(todayThingsDateExpression()) AND TASK.start = 2)
                        OR (TASK.startDate IS NULL AND TASK.deadline <= \(todayThingsDateExpression()) AND TASK.deadlineSuppressionDate IS NULL)
                    )
                ORDER BY
                    CASE WHEN TASK.todayIndex IS NULL THEN 1 ELSE 0 END,
                    TASK.todayIndex,
                    TASK."index",
                    TASK.title
            """
        case .upcoming:
            return """
                \(baseSelect)
                    AND (
                        (TASK.startDate > \(todayThingsDateExpression()) AND TASK.start = 2)
                        OR (TASK.deadline > \(todayThingsDateExpression()) AND TASK.startDate IS NULL)
                    )
                ORDER BY
                    CASE WHEN TASK.startDate IS NOT NULL THEN TASK.startDate ELSE TASK.deadline END,
                    TASK."index",
                    TASK.title
                LIMIT 80
            """
        case .anytime:
            return """
                \(baseSelect)
                    AND TASK.start = 1
                ORDER BY TASK."index", TASK.title
                LIMIT 60
            """
        case .someday:
            return """
                \(baseSelect)
                    AND TASK.start = 2
                    AND TASK.startDate IS NULL
                ORDER BY TASK."index", TASK.title
                LIMIT 60
            """
        case .deadline:
            return """
                \(baseSelect)
                    AND TASK.deadline IS NOT NULL
                ORDER BY TASK.deadline, TASK."index", TASK.title
                LIMIT 40
            """
        }
    }

    private func isoDateExpression(_ column: String) -> String {
        "CASE WHEN \(column) THEN printf('%d-%02d-%02d', (\(column) & 134152192) >> 16, (\(column) & 61440) >> 12, (\(column) & 3968) >> 7) ELSE \(column) END"
    }

    private func todayThingsDateExpression() -> String {
        "((strftime('%Y', date('now', 'localtime')) << 16) | (strftime('%m', date('now', 'localtime')) << 12) | (strftime('%d', date('now', 'localtime')) << 7))"
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: raw)
    }

    private func int(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, index))
    }
}

func relativeDate(_ isoDate: String) -> String {
    guard let date = thingsDate(from: isoDate) else {
        return isoDate
    }

    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "Today"
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow"
    }
    if calendar.isDateInYesterday(date) {
        return "Yesterday"
    }

    let startOfToday = calendar.startOfDay(for: Date())
    let startOfTarget = calendar.startOfDay(for: date)
    if let days = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day {
        if days < 0 {
            return "\(abs(days))d overdue"
        }
        if days < 7 {
            return "In \(days)d"
        }
    }

    let display = DateFormatter()
    display.dateFormat = "MMM d"
    return display.string(from: date)
}

func isTodayDate(_ isoDate: String?) -> Bool {
    guard let isoDate, let date = thingsDate(from: isoDate) else {
        return false
    }
    return Calendar.current.isDateInToday(date)
}

func dayNumber(_ isoDate: String?) -> String {
    guard let isoDate, let date = thingsDate(from: isoDate) else {
        return ""
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "d"
    return formatter.string(from: date)
}

func dayNumber(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "d"
    return formatter.string(from: date)
}

func dayLabel(_ isoDate: String?) -> String {
    guard let isoDate, let date = thingsDate(from: isoDate) else {
        return "No Date"
    }

    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "Today"
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow"
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    return formatter.string(from: date)
}

func dayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "Today"
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow"
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    return formatter.string(from: date)
}

func isoDayString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

func daysLeftText(_ isoDate: String?) -> String? {
    guard let isoDate, let date = thingsDate(from: isoDate) else {
        return nil
    }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let target = calendar.startOfDay(for: date)
    guard let days = calendar.dateComponents([.day], from: today, to: target).day else {
        return nil
    }

    if days < 0 {
        return "\(abs(days))d overdue"
    }
    if days == 0 {
        return "today"
    }
    if days == 1 {
        return "tomorrow"
    }
    return "\(days)d left"
}

private func thingsDate(from isoDate: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: isoDate)
}
