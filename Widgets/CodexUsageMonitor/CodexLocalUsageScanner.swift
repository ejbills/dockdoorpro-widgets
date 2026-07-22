import Foundation

struct CodexLocalUsageScanner: Sendable {
    private static let cacheVersion = 6
    private static let inheritedForkEventWindow: TimeInterval = 1
    private static let maxBufferedLineBytes = 1024 * 1024
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let contextMarker = Data("\"turn_context\"".utf8)
    private static let sessionMarker = Data("\"session_meta\"".utf8)
    private static let settingsMarker = Data("\"thread_settings_applied\"".utf8)

    private struct TokenTotals: Codable, Equatable {
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
    }

    private struct TokenEvent: Codable, Equatable {
        let id: String
        let timestamp: Date
        let turnID: String?
        let model: String
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int
        let isPriority: Bool
    }

    private struct CachedFile: Codable {
        var size: Int64
        var modifiedAt: Date
        var offset: UInt64
        var currentModel: String?
        var currentTurnID: String?
        var currentServiceTier: String?
        var previousTotals: TokenTotals?
        var isSubagent: Bool
        var ownedAfter: Date?
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
        var priorityTokens = 0
        var knownCost = 0.0
        var hasKnownCost = false
        var usedDynamicPricing = false
        var usedBuiltInPricing = false
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
                currentModel: nil,
                currentTurnID: nil,
                currentServiceTier: nil,
                previousTotals: nil,
                isSubagent: false,
                ownedAfter: nil,
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
                            if buffer.range(of: self.contextMarker) != nil,
                               let model = self.modelFromLargeTurnContextPrefix(buffer)
                            {
                                state.currentModel = model
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
        guard isToken || isContext || isSession || isSettings else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        if type == "session_meta" {
            let source = payload["source"]
            let sourceIsSubagent = (source as? String)?.lowercased() == "subagent"
                || (source as? [String: Any])?["subagent"] != nil
            if sourceIsSubagent {
                state.isSubagent = true
                let rawTimestamp = payload["timestamp"] as? String ?? object["timestamp"] as? String
                if let rawTimestamp, let timestamp = self.parseISO8601(rawTimestamp) {
                    state.ownedAfter = state.ownedAfter ?? timestamp
                }
            }
            return
        }

        if type == "turn_context" {
            state.currentModel = self.model(in: payload) ?? self.model(in: payload["info"] as? [String: Any])
            state.currentTurnID = payload["turn_id"] as? String ?? payload["turnId"] as? String
            if let tier = payload["service_tier"] as? String ?? payload["serviceTier"] as? String {
                state.currentServiceTier = tier.lowercased()
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
            return
        }

        guard type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestampText = object["timestamp"] as? String,
              let timestamp = self.parseISO8601(timestampText),
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
                    output: max(0, total.output - previous.output)
                )
                let isMonotonic = total.input >= previous.input
                    && total.cached >= previous.cached
                    && total.cacheWrite >= previous.cacheWrite
                    && total.output >= previous.output
                let deltaIsContainedByLast = totalDelta.input <= last.input
                    && totalDelta.cached <= last.cached
                    && totalDelta.cacheWrite <= last.cacheWrite
                    && totalDelta.output <= last.output
                // Prefer authoritative cumulative growth when it is monotonic and no
                // larger than the per-request hint. This matches CodexBar's containment
                // rule and avoids recounting repeated or interleaved `last` snapshots.
                delta = isMonotonic && deltaIsContainedByLast ? totalDelta : last
            } else {
                delta = last
            }
        } else if let total {
            let previous = state.previousTotals ?? TokenTotals(input: 0, cached: 0, cacheWrite: 0, output: 0)
            delta = TokenTotals(
                input: max(0, total.input - previous.input),
                cached: max(0, total.cached - previous.cached),
                cacheWrite: max(0, total.cacheWrite - previous.cacheWrite),
                output: max(0, total.output - previous.output)
            )
        } else {
            delta = nil
        }
        if let total { state.previousTotals = total }
        guard let delta, delta.input > 0 || delta.output > 0 else { return }
        // Forked rollout files replay the parent's complete token history at the
        // child's creation timestamp. Ignore that one-second replay burst, while
        // keeping subsequent requests that are genuinely owned by the subagent.
        if state.isSubagent,
           let ownedAfter = state.ownedAfter,
           timestamp <= ownedAfter.addingTimeInterval(self.inheritedForkEventWindow)
        {
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
        let eventID = [
            timestampText,
            turnID ?? "",
            String(delta.input),
            String(delta.cached),
            String(delta.cacheWrite),
            String(delta.output),
            model,
            state.currentServiceTier ?? "standard",
        ].joined(separator: "|")

        state.events.append(TokenEvent(
            id: eventID,
            timestamp: timestamp,
            turnID: turnID,
            model: model,
            input: delta.input,
            cached: delta.cached,
            cacheWrite: delta.cacheWrite,
            output: delta.output,
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
        var byDay: [String: DayAccumulator] = [:]
        var tokensByModel: [String: Int] = [:]
        for file in cache.files.values {
            for event in file.events where event.timestamp >= startDate {
                guard seenEvents.insert(event.id).inserted else { continue }
                let isPriority = event.isPriority
                let dayKey = self.dayKey(event.timestamp)
                var accumulator = byDay[dayKey] ?? DayAccumulator()
                accumulator.input += event.input
                accumulator.cached += event.cached
                accumulator.cacheWrite += event.cacheWrite
                accumulator.output += event.output
                if isPriority { accumulator.priorityTokens += event.input + event.output }
                if let estimate = self.estimatedCost(
                    event,
                    isPriority: isPriority,
                    catalog: pricingCatalog
                ) {
                    accumulator.knownCost += estimate.cost
                    accumulator.hasKnownCost = true
                    switch estimate.source {
                    case .dynamic: accumulator.usedDynamicPricing = true
                    case .builtIn, .priority: accumulator.usedBuiltInPricing = true
                    }
                }
                byDay[dayKey] = accumulator
                tokensByModel[event.model, default: 0] += event.input + event.output
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
                priorityTokens: accumulator.priorityTokens,
                estimatedCostUSD: accumulator.hasKnownCost ? accumulator.knownCost : nil
            ))
        }

        let todayKey = self.dayKey(today)
        let todayEntry = daily.first { $0.dayKey == todayKey }
        let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        let knownCosts = daily.compactMap(\.estimatedCostUSD)
        let usedDynamicPricing = byDay.values.contains { $0.usedDynamicPricing }
        let usedBuiltInPricing = byDay.values.contains { $0.usedBuiltInPricing }
        let mostUsedModel = tokensByModel.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }?.key

        return CodexRecentUsageSnapshot(
            todayTokens: todayEntry?.totalTokens ?? 0,
            todayEstimatedCostUSD: todayEntry?.estimatedCostUSD,
            last30DaysTokens: totalTokens,
            last30DaysEstimatedCostUSD: knownCosts.isEmpty ? nil : knownCosts.reduce(0, +),
            daily: daily,
            mostUsedModel: mostUsedModel == "unknown" ? nil : mostUsedModel,
            pricingSource: usedDynamicPricing
                ? (usedBuiltInPricing
                    ? CodexLocalization.text("models.dev + 内置回退", "models.dev + built-in fallback")
                    : CodexLocalization.text("models.dev 动态价表", "models.dev dynamic pricing"))
                : CodexLocalization.text("内置价表", "Built-in pricing"),
            updatedAt: now
        )
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

    private static func modelFromLargeTurnContextPrefix(_ data: Data) -> String? {
        guard let text = String(data: data.prefix(128 * 1024), encoding: .utf8) else { return nil }
        let expression = try? NSRegularExpression(pattern: #""model"\s*:\s*"([^"]+)""#)
        guard let match = expression?.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ),
        let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return self.normalizeModel(String(text[range]))
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
            output: integer("output_tokens")
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
