import Foundation

struct CodexQuotaPaceInsight: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let expectedUsedPercent: Double?
    let deltaPercent: Double?
    let percentPerHour: Double?
    let projectedExhaustionAt: Date?
    let resetAt: Date?
    let willLastToReset: Bool?
    let speedMultiplierToReset: Double?
    let sampleCount: Int
    let updatedAt: Date
}

struct CodexQuotaPaceSnapshot: Codable, Equatable {
    let insights: [CodexQuotaPaceInsight]
    let updatedAt: Date

    func insight(id: String) -> CodexQuotaPaceInsight? {
        insights.first { $0.id == id }
    }
}

struct CodexQuotaPaceStore {
    private struct Point: Codable, Equatable {
        let capturedAt: Date
        let usedPercent: Double
        let resetAt: Date?
        let durationSeconds: Int
        let title: String
    }

    private struct Document: Codable {
        var version: Int
        var pointsByWindow: [String: [Point]]
    }

    private static let version = 1
    private static let retention: TimeInterval = 45 * 24 * 60 * 60
    private static let maximumPointsPerWindow = 512
    private static let minimumSampleSpacing: TimeInterval = 20

    func record(
        usage: CodexUsageSnapshot,
        widgetId: String,
        now: Date = Date()
    ) -> CodexQuotaPaceSnapshot {
        let key = "widget.\(widgetId).quotaPaceHistory"
        var document = Self.load(key: key)
        let cutoff = now.addingTimeInterval(-Self.retention)
        document.pointsByWindow = document.pointsByWindow.mapValues { points in
            points.filter { $0.capturedAt >= cutoff }
        }

        let windows = [usage.sessionWindow, usage.weeklyWindow].compactMap { $0 }
        for window in windows {
            var points = document.pointsByWindow[window.id] ?? []
            let point = Point(
                capturedAt: now,
                usedPercent: window.usedPercent,
                resetAt: window.resetAt,
                durationSeconds: window.durationSeconds,
                title: window.title
            )

            if let last = points.last,
               now.timeIntervalSince(last.capturedAt) < Self.minimumSampleSpacing
            {
                points[points.count - 1] = point
            } else {
                points.append(point)
            }
            if points.count > Self.maximumPointsPerWindow {
                points.removeFirst(points.count - Self.maximumPointsPerWindow)
            }
            document.pointsByWindow[window.id] = points
        }
        Self.save(document, key: key)

        let insights = windows.map { window in
            Self.makeInsight(
                window: window,
                points: document.pointsByWindow[window.id] ?? [],
                now: now
            )
        }
        return CodexQuotaPaceSnapshot(insights: insights, updatedAt: now)
    }

    private static func makeInsight(
        window: CodexQuotaWindow,
        points: [Point],
        now: Date
    ) -> CodexQuotaPaceInsight {
        let cyclePoints = points.filter { point in
            guard point.durationSeconds == window.durationSeconds else { return false }
            switch (point.resetAt, window.resetAt) {
            case let (lhs?, rhs?):
                return abs(lhs.timeIntervalSince(rhs)) < 90
            case (nil, nil):
                return true
            default:
                return false
            }
        }

        let duration = TimeInterval(max(0, window.durationSeconds))
        let cycleStart = window.resetAt?.addingTimeInterval(-duration)
        let elapsed = cycleStart.map { max(0, now.timeIntervalSince($0)) }
        let expectedUsedPercent: Double? = {
            guard duration > 0, let elapsed else { return nil }
            return min(100, max(0, elapsed / duration * 100))
        }()
        let delta = expectedUsedPercent.map { window.usedPercent - $0 }

        let lookback = max(
            60 * 60,
            min(24 * 60 * 60, duration > 0 ? duration / 4 : 6 * 60 * 60)
        )
        let recent = cyclePoints.filter {
            now.timeIntervalSince($0.capturedAt) <= lookback
        }
        let sampledRate: Double? = {
            guard let first = recent.first, let last = recent.last else { return nil }
            let interval = last.capturedAt.timeIntervalSince(first.capturedAt)
            guard interval >= 60 else { return nil }
            let consumed = last.usedPercent - first.usedPercent
            guard consumed >= 0 else { return nil }
            return consumed / interval * 3600
        }()
        let averageRate: Double? = {
            guard let elapsed, elapsed >= 15 * 60, window.usedPercent > 0 else { return nil }
            return window.usedPercent / elapsed * 3600
        }()
        let rate = sampledRate ?? averageRate

        let projection: (date: Date?, lasts: Bool?, multiplier: Double?) = {
            guard let resetAt = window.resetAt, resetAt > now else {
                return (nil, nil, nil)
            }
            guard let rate, rate > 0 else {
                return (nil, true, nil)
            }
            let remaining = max(0, 100 - window.usedPercent)
            let remainingHours = resetAt.timeIntervalSince(now) / 3600
            let allowedRate = remainingHours > 0 ? remaining / remainingHours : 0
            let multiplier = rate > 0 ? allowedRate / rate : nil
            let exhaustion = now.addingTimeInterval(remaining / rate * 3600)
            return (exhaustion, exhaustion >= resetAt, multiplier)
        }()

        return CodexQuotaPaceInsight(
            id: window.id,
            title: window.title,
            usedPercent: window.usedPercent,
            expectedUsedPercent: expectedUsedPercent,
            deltaPercent: delta,
            percentPerHour: rate,
            projectedExhaustionAt: projection.date,
            resetAt: window.resetAt,
            willLastToReset: projection.lasts,
            speedMultiplierToReset: projection.multiplier,
            sampleCount: cyclePoints.count,
            updatedAt: now
        )
    }

    private static func load(key: String) -> Document {
        guard let data = UserDefaults.standard.data(forKey: key),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version == version
        else {
            return Document(version: version, pointsByWindow: [:])
        }
        return document
    }

    private static func save(_ document: Document, key: String) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
