import Foundation

struct CodexTokenSample: Identifiable, Sendable {
    let id: String
    let date: Date
    let model: String
    let effort: String
    let input: Int
    let cached: Int
    let output: Int
    let reasoning: Int
    var total: Int { input + output }
}

struct CodexSessionSummary: Identifiable, Sendable {
    let id: String
    let model: String
    let lastEvent: Date?
    let contextTokens: Int?
    let contextWindow: Int?
    let sampleCount: Int
}

struct CodexAnalyticsSnapshot: Sendable {
    var samples: [CodexTokenSample] = []
    var sessions: [CodexSessionSummary] = []
    var checkedAt: Date?
    var bytesRead = 0
    var readMilliseconds = 0
    var unavailableFiles = 0
    var input: Int { samples.reduce(0) { $0 + $1.input } }
    var output: Int { samples.reduce(0) { $0 + $1.output } }
    var cached: Int { samples.reduce(0) { $0 + $1.cached } }
    var total: Int { input + output }
    var latest: CodexSessionSummary? { sessions.max { ($0.lastEvent ?? .distantPast) < ($1.lastEvent ?? .distantPast) } }
    static let empty = CodexAnalyticsSnapshot()
}

/// Bounded, incremental telemetry. This is independent of the upstream quota
/// parser: only changed bytes in eight recent logs are sampled, every 30 seconds.
/// No transcript bodies are decoded, no full-history scan or disk cache is used.
actor CodexUsageAnalyticsReader {
    private struct FileState {
        var offset: UInt64 = 0
        var modified: Date = .distantPast
        var identity: Int = 0
        var pending = Data()
        var model = "Unknown"
        var effort = "Unknown"
        var previous: [String: Int]?
        var samples: [CodexTokenSample] = []
        var lastEvent: Date?
        var contextTokens: Int?
        var contextWindow: Int?
    }
    private var files: [URL: FileState] = [:]
    private var cached = CodexAnalyticsSnapshot.empty
    private let maximumRead = 1_048_576
    private let iso = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    func read(now: Date = Date(), urls: [URL]? = nil) -> CodexAnalyticsSnapshot {
        if urls == nil, let checked = cached.checkedAt, now.timeIntervalSince(checked) < 30 { return cached }
        let started = Date()
        let selected = Array((urls ?? CodexSessionsStore.recentRolloutFiles(limit: 8)).prefix(8))
        files = files.filter { selected.contains($0.key) }
        var bytes = 0
        var unavailable = 0
        for url in selected {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let length = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                let modified = attrs[.modificationDate] as? Date ?? .distantPast
                let identity = (attrs[.systemFileNumber] as? NSNumber)?.intValue ?? 0
                var state = files[url] ?? FileState()
                if state.identity != identity || length < state.offset || (length == state.offset && modified != state.modified) {
                    state = FileState()
                }
                if state.offset != length {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let start = max(state.offset, length > UInt64(maximumRead) ? length - UInt64(maximumRead) : 0)
                    let skipped = start > state.offset
                    if skipped {
                        state.pending = Data(); state.previous = nil
                        seedContext(in: url, before: Int(start), state: &state)
                    }
                    try handle.seek(toOffset: start)
                    var data = try handle.read(upToCount: maximumRead) ?? Data()
                    bytes += data.count
                    state.offset = start + UInt64(data.count)
                    if skipped {
                        if let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: data.index(after: newline))) }
                        else { data = Data() }
                    }
                    state.pending.append(data)
                    // Incomplete trailing lines wait for a later append. Bound a
                    // very long transcript line so it cannot grow memory forever.
                    if let newline = state.pending.lastIndex(of: 10) {
                        let complete = state.pending.prefix(through: newline)
                        for line in complete.split(separator: 10) {
                            consume(Data(line), state: &state, fallback: modified, file: url.lastPathComponent)
                        }
                        state.pending = Data(state.pending.suffix(from: state.pending.index(after: newline)))
                    }
                    if state.pending.count > maximumRead { state.pending = Data() }
                    state.samples = Array(state.samples.suffix(512))
                }
                state.modified = modified
                state.identity = identity
                files[url] = state
            } catch { unavailable += 1 }
        }
        cached = CodexAnalyticsSnapshot(
            samples: files.values.flatMap(\.samples).sorted { $0.date < $1.date },
            sessions: files.map { url, state in
                CodexSessionSummary(id: url.lastPathComponent, model: state.model, lastEvent: state.lastEvent,
                                    contextTokens: state.contextTokens, contextWindow: state.contextWindow,
                                    sampleCount: state.samples.count)
            }.sorted { ($0.lastEvent ?? .distantPast) > ($1.lastEvent ?? .distantPast) },
            checkedAt: now, bytesRead: bytes, readMilliseconds: Int(Date().timeIntervalSince(started) * 1000),
            unavailableFiles: unavailable)
        return cached
    }

    private func consume(_ data: Data, state: inout FileState, fallback: Date, file: String) {
        guard data.range(of: Data("\"token_count\"".utf8)) != nil || data.range(of: Data("\"turn_context\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        if object["type"] as? String == "turn_context" {
            let collaboration = (payload["collaboration_mode"] as? [String: Any])?["settings"] as? [String: Any]
            state.model = payload["model"] as? String ?? collaboration?["model"] as? String ?? state.model
            state.effort = payload["effort"] as? String ?? payload["reasoning_effort"] as? String ?? collaboration?["reasoning_effort"] as? String ?? state.effort
            return
        }
        guard object["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any] else { return }
        let text = object["timestamp"] as? String ?? ""
        let date = fractional.date(from: text) ?? iso.date(from: text) ?? fallback
        let last = counts(info["last_token_usage"])
        let total = counts(info["total_token_usage"])
        state.lastEvent = date
        state.contextWindow = (info["model_context_window"] as? NSNumber)?.intValue
        state.contextTokens = last.map { ($0["input_tokens"] ?? 0) + ($0["output_tokens"] ?? 0) }
        var delta = last
        if let total, let previous = state.previous {
            let keys = ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"]
            let values = Dictionary(uniqueKeysWithValues: keys.map { ($0, (total[$0] ?? 0) - (previous[$0] ?? 0)) })
            // A counter reset starts a new baseline; never turn a reset into a giant delta.
            if values.values.allSatisfy({ $0 >= 0 }) { delta = values }
        }
        state.previous = total ?? state.previous
        guard let delta else { return }
        let input = delta["input_tokens"] ?? 0, output = delta["output_tokens"] ?? 0
        guard input + output > 0 else { return }
        state.samples.append(CodexTokenSample(id: "\(file):\(state.offset):\(state.samples.count)", date: date,
            model: state.model, effort: state.effort, input: input,
            cached: min(input, delta["cached_input_tokens"] ?? 0), output: output,
            reasoning: min(output, delta["reasoning_output_tokens"] ?? 0)))
    }

    // Seed a tail's starting model from the nearest earlier context marker.
    // Mapped backwards search runs only when bytes are skipped, never per line.
    private func seedContext(in url: URL, before offset: Int, state: inout FileState) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        let end = min(offset, data.count)
        guard end > 0,
              let marker = data.range(of: Data("\"turn_context\"".utf8), options: .backwards, in: 0..<end) else { return }
        let start = data[..<marker.lowerBound].lastIndex(of: 10).map { $0 + 1 } ?? 0
        guard let newline = data[marker.upperBound...].firstIndex(of: 10), newline <= end else { return }
        consume(Data(data[start..<newline]), state: &state, fallback: .distantPast, file: url.lastPathComponent)
    }

    private func counts(_ value: Any?) -> [String: Int]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: Int] = [:]
        for key in ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"] {
            let number = (object[key] as? NSNumber)?.intValue ?? (object[key] as? String).flatMap(Int.init) ?? 0
            result[key] = max(0, min(number, 1_000_000_000_000))
        }
        return result
    }
}

func codexTokenLabel(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return String(value)
}
