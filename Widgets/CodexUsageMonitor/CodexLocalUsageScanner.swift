import Foundation

struct CodexLocalUsageScanner: Sendable {
    private static let cacheVersion = 7
    private static let inheritedForkEventWindow: TimeInterval = 1
    private static let activeSessionWindow: TimeInterval = 15 * 60
    private static let topModelLimit = 8
    private static let topProjectLimit = 8
    private static let recentSessionLimit = 12
    private static let recentContextLimit = 12
    private static let maxBufferedLineBytes = 1024 * 1024
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let contextMarker = Data("\"turn_context\"".utf8)
    private static let sessionMarker = Data("\"session_meta\"".utf8)
    private static let settingsMarker = Data("\"thread_settings_applied\"".utf8)
    private static let taskStartedMarker = Data("\"task_started\"".utf8)
    private static let taskCompleteMarker = Data("\"task_complete\"".utf8)
    private static let turnAbortedMarker = Data("\"turn_aborted\"".utf8)
    private static let contextCompactedMarker = Data("\"context_compacted\"".utf8)
    private static let compactedMarker = Data("\"compacted\"".utf8)

    private struct TokenTotals: Codable, Equatable {
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let reasoning: Int

        var total: Int { input + output }
    }

    private struct TokenEvent: Codable, Equatable {
        let id: String
        let timestamp: Date
        let turnID: String?
        let sessionID: String?
        let logicalSessionID: String?
        let projectPath: String?
        let model: String
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let reasoning: Int
        let isPriority: Bool

        var tokens: Int { input + output }
    }

    private struct ContextSample: Codable {
        let timestamp: Date
        let turnID: String?
        let model: String?
        let projectPath: String?
        let contextWindow: Int
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let reasoning: Int
    }

    private struct CachedFile: Codable {
        var size: Int64
        var modifiedAt: Date
        var offset: UInt64
        var sessionID: String?
        var parentSessionID: String?
        var sessionStartedAt: Date?
        var sessionCWD: String?
        var currentCWD: String?
        var currentModel: String?
        var currentTurnID: String?
        var currentServiceTier: String?
        var previousTotals: TokenTotals?
        var isSubagent: Bool
        var ownedAfter: Date?
        var lastActivityAt: Date?
        var latestContext: ContextSample?
        var compactionCount: Int
        var lastCompactionAt: Date?
        var activeTurnIDs: Set<String>
        var completedTurnDurationsMS: [String: Int64]
        var abortedTurnIDs: Set<String>
        var turnTimeToFirstTokenMS: [String: Int64]
        var events: [TokenEvent]
    }

    private struct ScannerCache: Codable {
        var version: Int
        var files: [String: CachedFile]
    }

    private struct DayAccumulator {
        var input = 0
        var cached = 0
        var cacheWrite = 0
        var output = 0
        var reasoning = 0
        var priorityTokens = 0
        var requestCount = 0
        var turnIDs: Set<String> = []
        var knownCost = 0.0
        var hasKnownCost = false
        var usedDynamicPricing = false
        var usedBuiltInPricing = false
    }

    private struct UsageAccumulator {
        var input = 0
        var cached = 0
        var cacheWrite = 0
        var output = 0
        var reasoning = 0
        var priorityTokens = 0
        var requestCount = 0
        var priorityRequestCount = 0
        var turnIDs: Set<String> = []
        var knownCost = 0.0
        var hasKnownCost = false

        mutating func add(
            _ event: TokenEvent,
            isPriority: Bool,
            estimatedCost: Double?
        ) {
            input += event.input
            cached += event.cached
            cacheWrite += event.cacheWrite
            output += event.output
            reasoning += event.reasoning
            requestCount += 1
            if let turnID = event.turnID { turnIDs.insert(turnID) }
            if isPriority {
                priorityTokens += event.tokens
                priorityRequestCount += 1
            }
            if let estimatedCost {
                knownCost += estimatedCost
                hasKnownCost = true
            }
        }
    }

    private struct ProjectAccumulator {
        var usage = UsageAccumulator()
        var logicalSessionIDs: Set<String> = []
        var lastActiveAt = Date.distantPast
    }

    private struct SessionAccumulator {
        var projectPath: String?
        var hasRootMetadata = false
        var modelTokens: [String: Int] = [:]
        var usage = UsageAccumulator()
        var startedAt = Date.distantFuture
        var lastActiveAt = Date.distantPast
        var completedTurnDurationsMS: [String: Int64] = [:]
        var abortedTurnIDs: Set<String> = []
        var turnTimeToFirstTokenMS: [String: Int64] = [:]
        var compactionCount = 0
        var activeTurnIDs: Set<String> = []
    }

    func scan(historyDays: Int = 30) async throws -> CodexRecentUsageSnapshot {
        let catalog = await CodexPricingCatalogStore.shared.catalogForScan()
        return try await Task.detached(priority: .utility) {
            try Self.scanSynchronously(historyDays: historyDays, pricingCatalog: catalog)
        }.value
    }

    private static func scanSynchronously(
        historyDays: Int,
        pricingCatalog: CodexPricingCatalog?
    ) throws -> CodexRecentUsageSnapshot {
        let days = max(1, min(90, historyDays))
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let cacheURL = self.cacheURL()
        var cache = self.loadCache(cacheURL) ?? ScannerCache(version: self.cacheVersion, files: [:])
        if cache.version != self.cacheVersion {
            cache = ScannerCache(version: self.cacheVersion, files: [:])
        }

        let files = self.sessionFiles(modifiedSince: startDate)
        let activePaths = Set(files.map(\.path))
        cache.files = cache.files.filter { activePaths.contains($0.key) }

        for fileURL in files {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let old = cache.files[fileURL.path]

            if let old, old.size == fileSize {
                var unchanged = old
                unchanged.modifiedAt = modifiedAt
                unchanged.events.removeAll { $0.timestamp < startDate }
                cache.files[fileURL.path] = unchanged
                continue
            }

            cache.files[fileURL.path] = try self.scanFile(
                fileURL,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                cached: old,
                startDate: startDate
            )
        }

        try self.saveCache(cache, to: cacheURL)
        return self.aggregate(
            cache: cache,
            startDate: startDate,
            today: today,
            now: now,
            days: days,
            pricingCatalog: pricingCatalog
        )
    }

    private static func scanFile(
        _ fileURL: URL,
        fileSize: Int64,
        modifiedAt: Date,
        cached: CachedFile?,
        startDate: Date
    ) throws -> CachedFile {
        var state: CachedFile
        if let cached, fileSize >= Int64(cached.offset) {
            state = cached
            state.size = fileSize
            state.modifiedAt = modifiedAt
            state.events.removeAll { $0.timestamp < startDate }
        } else {
            state = CachedFile(
                size: fileSize,
                modifiedAt: modifiedAt,
                offset: 0,
                sessionID: nil,
                parentSessionID: nil,
                sessionStartedAt: nil,
                sessionCWD: nil,
                currentCWD: nil,
                currentModel: nil,
                currentTurnID: nil,
                currentServiceTier: nil,
                previousTotals: nil,
                isSubagent: false,
                ownedAfter: nil,
                lastActivityAt: nil,
                latestContext: nil,
                compactionCount: 0,
                lastCompactionAt: nil,
                activeTurnIDs: [],
                completedTurnDurationsMS: [:],
                abortedTurnIDs: [],
                turnTimeToFirstTokenMS: [:],
                events: []
            )
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: state.offset)

        var committedOffset = state.offset
        var currentLineLength = 0
        var buffer = Data()
        var discardingOversizedLine = false

        func finishLine() {
            if !discardingOversizedLine, !buffer.isEmpty {
                self.processLine(buffer, state: &state, startDate: startDate)
            }
            committedOffset += UInt64(currentLineLength + 1)
            currentLineLength = 0
            buffer.removeAll(keepingCapacity: true)
            discardingOversizedLine = false
        }

        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            var segmentStart = chunk.startIndex
            while segmentStart < chunk.endIndex {
                if let newline = chunk[segmentStart...].firstIndex(of: 0x0A) {
                    let segment = chunk[segmentStart..<newline]
                    currentLineLength += segment.count
                    if !discardingOversizedLine {
                        buffer.append(contentsOf: segment)
                    }
                    finishLine()
                    segmentStart = chunk.index(after: newline)
                } else {
                    let segment = chunk[segmentStart..<chunk.endIndex]
                    currentLineLength += segment.count
                    if !discardingOversizedLine {
                        buffer.append(contentsOf: segment)
                        if buffer.count > self.maxBufferedLineBytes {
                            if buffer.range(of: self.contextMarker) != nil {
                                self.updateStateFromLargeTurnContextPrefix(
                                    buffer,
                                    state: &state
                                )
                            }
                            buffer.removeAll(keepingCapacity: false)
                            discardingOversizedLine = true
                        }
                    }
                    segmentStart = chunk.endIndex
                }
            }
        }

        state.offset = committedOffset
        state.size = fileSize
        state.modifiedAt = modifiedAt
        return state
    }

    private static func processLine(
        _ data: Data,
        state: inout CachedFile,
        startDate: Date
    ) {
        let isToken = data.range(of: self.tokenMarker) != nil
        let isContext = data.range(of: self.contextMarker) != nil
        let isSession = data.range(of: self.sessionMarker) != nil
        let isSettings = data.range(of: self.settingsMarker) != nil
        let isTask = data.range(of: self.taskStartedMarker) != nil
            || data.range(of: self.taskCompleteMarker) != nil
            || data.range(of: self.turnAbortedMarker) != nil
        let isCompaction = data.range(of: self.contextCompactedMarker) != nil
            || data.range(of: self.compactedMarker) != nil
        guard isToken || isContext || isSession || isSettings || isTask || isCompaction else {
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }
        let rawTimestamp = object["timestamp"] as? String
        let eventTimestamp = rawTimestamp.flatMap(self.parseISO8601)

        if type == "session_meta" {
            let source = payload["source"]
            let sourceIsSubagent = (source as? String)?.lowercased() == "subagent"
                || (source as? [String: Any])?["subagent"] != nil
            let sessionID = payload["id"] as? String ?? payload["session_id"] as? String
            let nestedParentID = (((source as? [String: Any])?["subagent"] as? [String: Any])?[
                "thread_spawn"
            ] as? [String: Any])?["parent_thread_id"] as? String
            if state.sessionID == nil {
                state.sessionID = sessionID
                state.parentSessionID = payload["parent_thread_id"] as? String
                    ?? payload["forked_from_id"] as? String
                    ?? nestedParentID
                let cwd = self.normalizedProjectPath(payload["cwd"] as? String)
                state.sessionCWD = cwd
                state.currentCWD = cwd
                let timestamp = (payload["timestamp"] as? String).flatMap(self.parseISO8601)
                    ?? eventTimestamp
                state.sessionStartedAt = timestamp
                state.lastActivityAt = timestamp
            }
            if sourceIsSubagent {
                state.isSubagent = true
                state.parentSessionID = state.parentSessionID
                    ?? payload["parent_thread_id"] as? String
                    ?? payload["forked_from_id"] as? String
                    ?? nestedParentID
                let timestamp = (payload["timestamp"] as? String).flatMap(self.parseISO8601)
                    ?? eventTimestamp
                if let timestamp {
                    state.ownedAfter = state.ownedAfter ?? timestamp
                }
            }
            return
        }

        if type == "turn_context" {
            state.currentModel = self.model(in: payload) ?? self.model(in: payload["info"] as? [String: Any])
            state.currentTurnID = payload["turn_id"] as? String ?? payload["turnId"] as? String
            if let cwd = self.normalizedProjectPath(payload["cwd"] as? String) {
                state.currentCWD = cwd
            }
            if let tier = payload["service_tier"] as? String ?? payload["serviceTier"] as? String {
                state.currentServiceTier = tier.lowercased()
            }
            if let eventTimestamp, !self.isInheritedReplay(eventTimestamp, state: state) {
                state.lastActivityAt = max(state.lastActivityAt ?? eventTimestamp, eventTimestamp)
            }
            return
        }

        if type == "event_msg",
           payload["type"] as? String == "thread_settings_applied",
           let settings = payload["thread_settings"] as? [String: Any]
        {
            if let tier = settings["service_tier"] as? String ?? settings["serviceTier"] as? String {
                state.currentServiceTier = tier.lowercased()
            }
            if let model = self.model(in: settings) {
                state.currentModel = self.normalizeModel(model)
            }
            if let cwd = self.normalizedProjectPath(settings["cwd"] as? String) {
                state.currentCWD = cwd
            }
            return
        }

        if type == "event_msg",
           let eventName = payload["type"] as? String,
           ["task_started", "task_complete", "turn_aborted"].contains(eventName),
           let eventTimestamp,
           !self.isInheritedReplay(eventTimestamp, state: state)
        {
            let turnID = payload["turn_id"] as? String
                ?? payload["turnId"] as? String
                ?? payload["id"] as? String
            state.lastActivityAt = max(state.lastActivityAt ?? eventTimestamp, eventTimestamp)
            guard let turnID else { return }
            state.currentTurnID = turnID
            switch eventName {
            case "task_started":
                state.activeTurnIDs.insert(turnID)
            case "task_complete":
                state.activeTurnIDs.remove(turnID)
                if let duration = self.int64(payload["duration_ms"]) {
                    state.completedTurnDurationsMS[turnID] = max(0, duration)
                }
                if let timeToFirstToken = self.int64(payload["time_to_first_token_ms"]) {
                    state.turnTimeToFirstTokenMS[turnID] = max(0, timeToFirstToken)
                }
            case "turn_aborted":
                state.activeTurnIDs.remove(turnID)
                state.abortedTurnIDs.insert(turnID)
            default:
                break
            }
            return
        }

        if (type == "compacted"
            || (type == "event_msg" && payload["type"] as? String == "context_compacted")),
           let eventTimestamp,
           !self.isInheritedReplay(eventTimestamp, state: state)
        {
            if state.lastCompactionAt.map({
                abs(eventTimestamp.timeIntervalSince($0)) > self.inheritedForkEventWindow
            }) ?? true {
                state.compactionCount += 1
                state.lastCompactionAt = eventTimestamp
            }
            state.lastActivityAt = max(state.lastActivityAt ?? eventTimestamp, eventTimestamp)
            return
        }

        guard type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestampText = rawTimestamp,
              let timestamp = eventTimestamp,
              let info = payload["info"] as? [String: Any]
        else { return }

        let total = self.totals(info["total_token_usage"] as? [String: Any])
        let last = self.totals(info["last_token_usage"] as? [String: Any])
        let delta: TokenTotals?
        if let last {
            if let total, let previous = state.previousTotals {
                let totalDelta = TokenTotals(
                    input: max(0, total.input - previous.input),
                    cached: max(0, total.cached - previous.cached),
                    cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                    output: max(0, total.output - previous.output),
                    reasoning: max(0, total.reasoning - previous.reasoning)
                )
                let isMonotonic = total.input >= previous.input
                    && total.cached >= previous.cached
                    && total.cacheWrite >= previous.cacheWrite
                    && total.output >= previous.output
                    && total.reasoning >= previous.reasoning
                let deltaIsContainedByLast = totalDelta.input <= last.input
                    && totalDelta.cached <= last.cached
                    && totalDelta.cacheWrite <= last.cacheWrite
                    && totalDelta.output <= last.output
                    && totalDelta.reasoning <= last.reasoning
                // Prefer authoritative cumulative growth when it is monotonic and no
                // larger than the per-request hint. This matches CodexBar's containment
                // rule and avoids recounting repeated or interleaved `last` snapshots.
                delta = isMonotonic && deltaIsContainedByLast ? totalDelta : last
            } else {
                delta = last
            }
        } else if let total {
            let previous = state.previousTotals ?? TokenTotals(
                input: 0,
                cached: 0,
                cacheWrite: 0,
                output: 0,
                reasoning: 0
            )
            delta = TokenTotals(
                input: max(0, total.input - previous.input),
                cached: max(0, total.cached - previous.cached),
                cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                output: max(0, total.output - previous.output),
                reasoning: max(0, total.reasoning - previous.reasoning)
            )
        } else {
            delta = nil
        }
        if let total { state.previousTotals = total }
        // Forked rollout files replay the parent's complete token history at the
        // child's creation timestamp. Ignore that one-second replay burst, while
        // keeping subsequent requests that are genuinely owned by the subagent.
        if self.isInheritedReplay(timestamp, state: state) {
            return
        }
        guard timestamp >= startDate else { return }

        let model = self.normalizeModel(
            self.model(in: info)
                ?? self.model(in: payload)
                ?? state.currentModel
                ?? "unknown"
        )
        let turnID = payload["turn_id"] as? String
            ?? payload["turnId"] as? String
            ?? payload["id"] as? String
            ?? info["turn_id"] as? String
            ?? info["turnId"] as? String
            ?? state.currentTurnID
        let contextWindow = max(0, self.integer(info["model_context_window"]))
        if let last {
            state.latestContext = ContextSample(
                timestamp: timestamp,
                turnID: turnID,
                model: model == "unknown" ? nil : model,
                projectPath: state.currentCWD ?? state.sessionCWD,
                contextWindow: contextWindow,
                input: last.input,
                cached: last.cached,
                cacheWrite: last.cacheWrite,
                output: last.output,
                reasoning: last.reasoning
            )
        }
        state.lastActivityAt = max(state.lastActivityAt ?? timestamp, timestamp)
        guard let delta, delta.input > 0 || delta.output > 0 else { return }
        let logicalSessionID = state.parentSessionID ?? state.sessionID
        let projectPath = state.currentCWD ?? state.sessionCWD
        let eventID = [
            timestampText,
            state.sessionID ?? "",
            turnID ?? "",
            String(delta.input),
            String(delta.cached),
            String(delta.cacheWrite),
            String(delta.output),
            String(delta.reasoning),
            model,
            state.currentServiceTier ?? "standard",
        ].joined(separator: "|")

        state.events.append(TokenEvent(
            id: eventID,
            timestamp: timestamp,
            turnID: turnID,
            sessionID: state.sessionID,
            logicalSessionID: logicalSessionID,
            projectPath: projectPath,
            model: model,
            input: delta.input,
            cached: delta.cached,
            cacheWrite: delta.cacheWrite,
            output: delta.output,
            reasoning: delta.reasoning,
            isPriority: ["priority", "fast"].contains(state.currentServiceTier ?? "")
        ))
    }

    private static func aggregate(
        cache: ScannerCache,
        startDate: Date,
        today: Date,
        now: Date,
        days: Int,
        pricingCatalog: CodexPricingCatalog?
    ) -> CodexRecentUsageSnapshot {
        let calendar = Calendar.current
        var seenEvents: Set<String> = []
        var uniqueEvents: [TokenEvent] = []
        var byDay: [String: DayAccumulator] = [:]
        var byModel: [String: UsageAccumulator] = [:]
        var byProject: [String: ProjectAccumulator] = [:]
        var bySession: [String: SessionAccumulator] = [:]
        var contextHealth: [CodexContextHealthSnapshot] = []

        for file in cache.files.values {
            let logicalSessionID = file.parentSessionID ?? file.sessionID
            if let logicalSessionID {
                var session = bySession[logicalSessionID] ?? SessionAccumulator()
                if !file.isSubagent || !session.hasRootMetadata {
                    session.projectPath = file.sessionCWD ?? file.currentCWD ?? session.projectPath
                    session.hasRootMetadata = !file.isSubagent
                }
                if let startedAt = file.sessionStartedAt {
                    session.startedAt = min(session.startedAt, startedAt)
                }
                if let lastActivityAt = file.lastActivityAt {
                    session.lastActiveAt = max(session.lastActiveAt, lastActivityAt)
                }
                session.completedTurnDurationsMS.merge(
                    file.completedTurnDurationsMS,
                    uniquingKeysWith: { current, _ in current }
                )
                session.abortedTurnIDs.formUnion(file.abortedTurnIDs)
                session.turnTimeToFirstTokenMS.merge(
                    file.turnTimeToFirstTokenMS,
                    uniquingKeysWith: { current, _ in current }
                )
                session.activeTurnIDs.formUnion(file.activeTurnIDs)
                session.compactionCount += file.compactionCount
                bySession[logicalSessionID] = session
            }

            if let context = file.latestContext,
               let sessionID = file.sessionID ?? logicalSessionID
            {
                let projectPath = context.projectPath
                    ?? file.currentCWD
                    ?? file.sessionCWD
                    ?? ""
                let active = !file.activeTurnIDs.isEmpty
                    && now.timeIntervalSince(context.timestamp) <= self.activeSessionWindow
                contextHealth.append(CodexContextHealthSnapshot(
                    sessionID: sessionID,
                    parentSessionID: file.parentSessionID,
                    projectName: self.projectName(for: projectPath),
                    projectPath: projectPath,
                    model: context.model,
                    capturedAt: context.timestamp,
                    contextWindowTokens: context.contextWindow,
                    usedContextTokens: context.contextWindow > 0
                        ? min(context.contextWindow, context.input + context.output)
                        : context.input + context.output,
                    inputTokens: context.input,
                    cachedInputTokens: context.cached,
                    cacheWriteInputTokens: context.cacheWrite,
                    outputTokens: context.output,
                    reasoningOutputTokens: context.reasoning,
                    compactionCount: file.compactionCount,
                    isSubagent: file.isSubagent,
                    isActive: active
                ))
            }

            for event in file.events where event.timestamp >= startDate {
                guard seenEvents.insert(event.id).inserted else { continue }
                uniqueEvents.append(event)
                let isPriority = event.isPriority
                let estimate = self.estimatedCost(
                    event,
                    isPriority: isPriority,
                    catalog: pricingCatalog
                )
                let dayKey = self.dayKey(event.timestamp)
                var accumulator = byDay[dayKey] ?? DayAccumulator()
                accumulator.input += event.input
                accumulator.cached += event.cached
                accumulator.cacheWrite += event.cacheWrite
                accumulator.output += event.output
                accumulator.reasoning += event.reasoning
                accumulator.requestCount += 1
                if let turnID = event.turnID { accumulator.turnIDs.insert(turnID) }
                if isPriority { accumulator.priorityTokens += event.tokens }
                if let estimate {
                    accumulator.knownCost += estimate.cost
                    accumulator.hasKnownCost = true
                    switch estimate.source {
                    case .dynamic: accumulator.usedDynamicPricing = true
                    case .builtIn, .priority: accumulator.usedBuiltInPricing = true
                    }
                }
                byDay[dayKey] = accumulator

                var model = byModel[event.model] ?? UsageAccumulator()
                model.add(event, isPriority: isPriority, estimatedCost: estimate?.cost)
                byModel[event.model] = model

                if let path = event.projectPath, !path.isEmpty {
                    var project = byProject[path] ?? ProjectAccumulator()
                    project.usage.add(
                        event,
                        isPriority: isPriority,
                        estimatedCost: estimate?.cost
                    )
                    if let logicalSessionID = event.logicalSessionID ?? event.sessionID {
                        project.logicalSessionIDs.insert(logicalSessionID)
                    }
                    project.lastActiveAt = max(project.lastActiveAt, event.timestamp)
                    byProject[path] = project
                }

                if let logicalSessionID = event.logicalSessionID ?? event.sessionID {
                    var session = bySession[logicalSessionID] ?? SessionAccumulator()
                    session.projectPath = session.projectPath ?? event.projectPath
                    session.usage.add(
                        event,
                        isPriority: isPriority,
                        estimatedCost: estimate?.cost
                    )
                    session.modelTokens[event.model, default: 0] += event.tokens
                    session.startedAt = min(session.startedAt, event.timestamp)
                    session.lastActiveAt = max(session.lastActiveAt, event.timestamp)
                    bySession[logicalSessionID] = session
                }
            }
        }

        var daily: [CodexTokenUsageDay] = []
        for offset in 0..<days {
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            let key = self.dayKey(date)
            let accumulator = byDay[key] ?? DayAccumulator()
            daily.append(CodexTokenUsageDay(
                dayKey: key,
                inputTokens: accumulator.input,
                cachedInputTokens: accumulator.cached,
                cacheWriteInputTokens: accumulator.cacheWrite,
                outputTokens: accumulator.output,
                reasoningOutputTokens: accumulator.reasoning,
                priorityTokens: accumulator.priorityTokens,
                requestCount: accumulator.requestCount,
                turnCount: accumulator.turnIDs.count,
                estimatedCostUSD: accumulator.hasKnownCost ? accumulator.knownCost : nil
            ))
        }

        let todayKey = self.dayKey(today)
        let todayEntry = daily.first { $0.dayKey == todayKey }
        let last7Days = Array(daily.suffix(7))
        let previous7Days = Array(daily.dropLast(min(7, daily.count)).suffix(7))
        let last30Days = Array(daily.suffix(30))
        let last7Start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let last30Start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let last7TurnCount = Set(uniqueEvents.lazy.compactMap {
            $0.timestamp >= last7Start ? $0.turnID : nil
        }).count
        let last30TurnCount = Set(uniqueEvents.lazy.compactMap {
            $0.timestamp >= last30Start ? $0.turnID : nil
        }).count
        let last7DaysSummary = self.periodSummary(
            last7Days,
            uniqueTurnCount: last7TurnCount
        )
        let last30DaysSummary = self.periodSummary(
            last30Days,
            uniqueTurnCount: last30TurnCount
        )
        let usedDynamicPricing = byDay.values.contains { $0.usedDynamicPricing }
        let usedBuiltInPricing = byDay.values.contains { $0.usedBuiltInPricing }
        let topModels = byModel.map { model, usage in
            CodexModelUsageSummary(
                model: model,
                tokens: usage.input + usage.output,
                estimatedCostUSD: usage.hasKnownCost ? usage.knownCost : nil,
                requestCount: usage.requestCount,
                turnCount: usage.turnIDs.count,
                standardTokens: max(0, usage.input + usage.output - usage.priorityTokens),
                priorityTokens: usage.priorityTokens,
                standardRequestCount: max(
                    0,
                    usage.requestCount - usage.priorityRequestCount
                ),
                priorityRequestCount: usage.priorityRequestCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
            return lhs.model < rhs.model
        }
        .prefix(self.topModelLimit)

        let topProjects = byProject.map { path, project in
            CodexProjectUsageSummary(
                projectName: self.projectName(for: path),
                projectPath: path,
                tokens: project.usage.input + project.usage.output,
                estimatedCostUSD: project.usage.hasKnownCost
                    ? project.usage.knownCost
                    : nil,
                requestCount: project.usage.requestCount,
                turnCount: project.usage.turnIDs.count,
                sessionCount: project.logicalSessionIDs.count,
                lastActiveAt: project.lastActiveAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName)
                == .orderedAscending
        }
        .prefix(self.topProjectLimit)

        let recentSessions = bySession.compactMap { sessionID, session
            -> CodexSessionUsageSummary? in
            guard session.lastActiveAt != .distantPast else { return nil }
            let startedAt = session.startedAt == .distantFuture
                ? session.lastActiveAt
                : session.startedAt
            let projectPath = session.projectPath ?? ""
            let dominantModel = session.modelTokens.max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key > rhs.key
            }?.key
            let taskTurnIDs = Set(session.completedTurnDurationsMS.keys)
                .union(session.abortedTurnIDs)
                .union(session.activeTurnIDs)
            let durationValues = session.completedTurnDurationsMS.values
            let ttftValues = session.turnTimeToFirstTokenMS.values
            return CodexSessionUsageSummary(
                id: sessionID,
                projectName: self.projectName(for: projectPath),
                projectPath: projectPath,
                dominantModel: dominantModel == "unknown" ? nil : dominantModel,
                tokens: session.usage.input + session.usage.output,
                estimatedCostUSD: session.usage.hasKnownCost
                    ? session.usage.knownCost
                    : nil,
                requestCount: session.usage.requestCount,
                turnCount: session.usage.turnIDs.union(taskTurnIDs).count,
                completedTurnCount: session.completedTurnDurationsMS.count,
                abortedTurnCount: session.abortedTurnIDs.count,
                startedAt: startedAt,
                lastActiveAt: session.lastActiveAt,
                averageTurnDurationSeconds: self.average(durationValues).map {
                    $0 / 1_000
                },
                averageTimeToFirstTokenMilliseconds: self.average(ttftValues),
                compactionCount: session.compactionCount,
                isActive: !session.activeTurnIDs.isEmpty
                    && now.timeIntervalSince(session.lastActiveAt)
                        <= self.activeSessionWindow
            )
        }
        .sorted { $0.lastActiveAt > $1.lastActiveAt }
        .prefix(self.recentSessionLimit)

        let previousDayTokens = daily.dropLast().last?.totalTokens ?? 0
        let previous7DaysTokens = previous7Days.reduce(0) { $0 + $1.totalTokens }
        let comparison = CodexUsageComparison(
            previousDayTokens: previousDayTokens,
            dayOverDayChangePercent: self.percentChange(
                current: todayEntry?.totalTokens ?? 0,
                previous: previousDayTokens
            ),
            previous7DaysTokens: previous7DaysTokens,
            sevenDayChangePercent: self.percentChange(
                current: last7DaysSummary.totalTokens,
                previous: previous7DaysTokens
            )
        )

        let mostUsedModel = topModels.first?.model
        let sortedContexts = contextHealth.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.capturedAt > rhs.capturedAt
        }

        return CodexRecentUsageSnapshot(
            todayTokens: todayEntry?.totalTokens ?? 0,
            todayEstimatedCostUSD: todayEntry?.estimatedCostUSD,
            last30DaysTokens: last30DaysSummary.totalTokens,
            last30DaysEstimatedCostUSD: last30DaysSummary.estimatedCostUSD,
            daily: daily,
            mostUsedModel: mostUsedModel == "unknown" ? nil : mostUsedModel,
            pricingSource: usedDynamicPricing
                ? (usedBuiltInPricing
                    ? CodexLocalization.text("models.dev + 内置回退", "models.dev + built-in fallback")
                    : CodexLocalization.text("models.dev 动态价表", "models.dev dynamic pricing"))
                : CodexLocalization.text("内置价表", "Built-in pricing"),
            updatedAt: now,
            last7DaysSummary: last7DaysSummary,
            last30DaysSummary: last30DaysSummary,
            comparison: comparison,
            topModels: Array(topModels),
            topProjects: Array(topProjects),
            recentSessions: Array(recentSessions),
            recentContextHealth: Array(sortedContexts.prefix(self.recentContextLimit))
        )
    }

    private static func periodSummary(
        _ daily: [CodexTokenUsageDay],
        uniqueTurnCount: Int? = nil
    ) -> CodexUsagePeriodSummary {
        let knownCosts = daily.compactMap(\.estimatedCostUSD)
        let peak = daily.max { lhs, rhs in
            if lhs.totalTokens != rhs.totalTokens {
                return lhs.totalTokens < rhs.totalTokens
            }
            return lhs.dayKey > rhs.dayKey
        }
        return CodexUsagePeriodSummary(
            dayCount: daily.count,
            inputTokens: daily.reduce(0) { $0 + $1.inputTokens },
            cachedInputTokens: daily.reduce(0) { $0 + $1.cachedInputTokens },
            cacheWriteInputTokens: daily.reduce(0) {
                $0 + $1.cacheWriteInputTokens
            },
            outputTokens: daily.reduce(0) { $0 + $1.outputTokens },
            reasoningOutputTokens: daily.reduce(0) {
                $0 + $1.reasoningOutputTokens
            },
            priorityTokens: daily.reduce(0) { $0 + $1.priorityTokens },
            estimatedCostUSD: knownCosts.isEmpty ? nil : knownCosts.reduce(0, +),
            requestCount: daily.reduce(0) { $0 + $1.requestCount },
            turnCount: uniqueTurnCount ?? daily.reduce(0) { $0 + $1.turnCount },
            activeDays: daily.lazy.filter { $0.totalTokens > 0 }.count,
            peakDayKey: peak?.totalTokens == 0 ? nil : peak?.dayKey,
            peakDayTokens: peak?.totalTokens ?? 0
        )
    }

    private static func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current - previous) / Double(previous)) * 100
    }

    private static func average<S: Sequence>(_ values: S) -> Double?
    where S.Element == Int64 {
        var total: Int64 = 0
        var count: Int64 = 0
        for value in values {
            total += value
            count += 1
        }
        guard count > 0 else { return nil }
        return Double(total) / Double(count)
    }

    private static func isInheritedReplay(
        _ timestamp: Date,
        state: CachedFile
    ) -> Bool {
        guard state.isSubagent, let ownedAfter = state.ownedAfter else { return false }
        return timestamp <= ownedAfter.addingTimeInterval(self.inheritedForkEventWindow)
    }

    private static func normalizedProjectPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    private static func projectName(for path: String) -> String {
        guard !path.isEmpty else {
            return CodexLocalization.text("未知项目", "Unknown project")
        }
        let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return max(0, number.intValue) }
        if let text = value as? String, let number = Int(text) { return max(0, number) }
        return 0
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    private static func jsonStringValue(named name: String, in text: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"""# + escapedName + #""\s*:\s*("(?:\\.|[^"])*")"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text),
              let data = String(text[range]).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func sessionFiles(modifiedSince startDate: Date) -> [URL] {
        let home = self.codexHome()
        let roots = [
            home.appendingPathComponent("sessions", isDirectory: true),
            home.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var files: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl",
                      let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= startDate
                else { continue }
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func codexHome() -> URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty
        {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DockDoorPro/CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent("local-token-cache.json", isDirectory: false)
    }

    private static func loadCache(_ url: URL) -> ScannerCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScannerCache.self, from: data)
    }

    private static func saveCache(_ cache: ScannerCache, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(cache)
        try data.write(to: url, options: .atomic)
    }

    private static func model(in dictionary: [String: Any]?) -> String? {
        guard let dictionary else { return nil }
        for key in ["model", "model_name"] {
            guard let value = dictionary[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func updateStateFromLargeTurnContextPrefix(
        _ data: Data,
        state: inout CachedFile
    ) {
        guard let text = String(data: data.prefix(128 * 1024), encoding: .utf8) else { return }
        if let model = self.jsonStringValue(named: "model", in: text) {
            state.currentModel = self.normalizeModel(model)
        }
        if let turnID = self.jsonStringValue(named: "turn_id", in: text) {
            state.currentTurnID = turnID
        }
        if let cwd = self.normalizedProjectPath(
            self.jsonStringValue(named: "cwd", in: text)
        ) {
            state.currentCWD = cwd
        }
    }

    private static func totals(_ dictionary: [String: Any]?) -> TokenTotals? {
        guard let dictionary else { return nil }
        func integer(_ key: String) -> Int {
            if let number = dictionary[key] as? NSNumber { return max(0, number.intValue) }
            if let text = dictionary[key] as? String, let value = Int(text) { return max(0, value) }
            return 0
        }
        return TokenTotals(
            input: integer("input_tokens"),
            cached: max(integer("cached_input_tokens"), integer("cache_read_input_tokens")),
            cacheWrite: max(integer("cache_write_input_tokens"), integer("cache_write_tokens")),
            output: integer("output_tokens"),
            reasoning: integer("reasoning_output_tokens")
        )
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func normalizeModel(_ raw: String) -> String {
        CodexPricingEngine.normalizeModel(raw)
    }

    private static func estimatedCost(
        _ event: TokenEvent,
        isPriority: Bool,
        catalog: CodexPricingCatalog?
    ) -> CodexPricingEngine.Result? {
        CodexPricingEngine.estimate(
            model: event.model,
            inputTokens: event.input,
            cachedInputTokens: event.cached,
            cacheWriteInputTokens: event.cacheWrite,
            outputTokens: event.output,
            isPriority: isPriority,
            catalog: catalog
        )
    }

}
