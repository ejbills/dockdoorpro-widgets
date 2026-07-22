import Foundation

struct CodexPricingCatalog: Codable {
    var providers: [String: CodexPricingProvider]

    init(providers: [String: CodexPricingProvider]) {
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodexPricingCodingKey.self)
        if let providersKey = CodexPricingCodingKey(stringValue: "providers"),
           let decoded = try? container.decode(
               [String: CodexPricingProvider].self,
               forKey: providersKey
           )
        {
            providers = Self.normalizedProviders(decoded)
            return
        }

        var decoded: [String: CodexPricingProvider] = [:]
        for key in container.allKeys {
            guard var provider = try? container.decode(CodexPricingProvider.self, forKey: key) else {
                continue
            }
            provider.mapKey = key.stringValue
            decoded[key.stringValue] = provider
        }
        providers = Self.normalizedProviders(decoded)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodexPricingCodingKey.self)
        try container.encode(
            providers,
            forKey: CodexPricingCodingKey(stringValue: "providers")!
        )
    }

    func lookup(model rawModel: String) -> CodexDynamicPricing? {
        providers["openai"]?.lookup(model: rawModel)
    }

    var hasOpenAIPricing: Bool {
        providers["openai"]?.models.values.contains { $0.isPriceable } == true
    }

    func mergingFallback(from old: CodexPricingCatalog) -> CodexPricingCatalog {
        var result = self
        for (providerID, oldProvider) in old.providers {
            guard var provider = result.providers[providerID] else {
                result.providers[providerID] = oldProvider
                continue
            }
            for (key, model) in oldProvider.models
                where model.isPriceable && provider.models[key] == nil
            {
                provider.models[key] = model
            }
            result.providers[providerID] = provider
        }
        return result
    }

    private static func normalizedProviders(
        _ raw: [String: CodexPricingProvider]
    ) -> [String: CodexPricingProvider] {
        raw.reduce(into: [:]) { result, entry in
            var provider = entry.value
            provider.mapKey = provider.mapKey ?? entry.key
            let identifier = (provider.id ?? entry.key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            result[identifier] = provider
        }
    }
}

struct CodexPricingProvider: Codable {
    var id: String?
    var name: String?
    var models: [String: CodexPricingModel]
    var mapKey: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        let modelContainer = try container.nestedContainer(
            keyedBy: CodexPricingCodingKey.self,
            forKey: .models
        )
        var decoded: [String: CodexPricingModel] = [:]
        for key in modelContainer.allKeys {
            if let model = try? modelContainer.decode(CodexPricingModel.self, forKey: key) {
                decoded[key.stringValue] = model
            }
        }
        models = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(models, forKey: .models)
    }

    func lookup(model rawModel: String) -> CodexDynamicPricing? {
        for candidate in CodexPricingModel.candidates(rawModel) {
            if let direct = models[candidate]?.pricing { return direct }
            if let match = models.values.first(where: {
                $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == candidate
            })?.pricing {
                return match
            }
        }
        return nil
    }
}

struct CodexPricingModel: Codable {
    let id: String
    let name: String?
    let cost: CodexPricingCost?
    let limit: CodexPricingLimit?

    var isPriceable: Bool { cost?.input != nil && cost?.output != nil }

    var pricing: CodexDynamicPricing? {
        guard let input = cost?.input, let output = cost?.output else { return nil }
        let unit = 1_000_000.0
        let long = cost?.contextOver200K
        return CodexDynamicPricing(
            input: input / unit,
            cachedRead: cost?.cacheRead.map { $0 / unit },
            cacheWrite: cost?.cacheWrite.map { $0 / unit },
            output: output / unit,
            threshold: long == nil ? nil : 200_000,
            longInput: long?.input.map { $0 / unit },
            longCachedRead: long?.cacheRead.map { $0 / unit },
            longCacheWrite: long?.cacheWrite.map { $0 / unit },
            longOutput: long?.output.map { $0 / unit },
            contextWindow: limit?.context
        )
    }

    static func candidates(_ raw: String) -> [String] {
        var values: [String] = []
        func append(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !values.contains(normalized) else { return }
            values.append(normalized)
        }

        append(raw)
        if raw.hasPrefix("openai/") { append(String(raw.dropFirst("openai/".count))) }
        var index = 0
        while index < values.count {
            let candidate = values[index]
            if let at = candidate.firstIndex(of: "@") {
                append(String(candidate[..<at]))
            }
            if let dated = candidate.range(
                of: #"-\d{4}-\d{2}-\d{2}$"#,
                options: .regularExpression
            ) {
                append(String(candidate[..<dated.lowerBound]))
            }
            index += 1
        }
        return values
    }
}

struct CodexPricingCost: Codable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?
    let contextOver200K: CodexLongContextPricing?

    private enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case contextOver200K = "context_over_200k"
    }
}

struct CodexLongContextPricing: Codable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?

    private enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

struct CodexPricingLimit: Codable {
    let context: Int?
}

private struct CodexPricingCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue) }
}

struct CodexDynamicPricing {
    let input: Double
    let cachedRead: Double?
    let cacheWrite: Double?
    let output: Double
    let threshold: Int?
    let longInput: Double?
    let longCachedRead: Double?
    let longCacheWrite: Double?
    let longOutput: Double?
    let contextWindow: Int?
}

actor CodexPricingCatalogStore {
    static let shared = CodexPricingCatalogStore()

    private struct Artifact: Codable {
        let version: Int
        let fetchedAt: Date
        let catalog: CodexPricingCatalog
    }

    private let cacheVersion = 1
    private let ttl: TimeInterval = 24 * 60 * 60
    private var didLoad = false
    private var artifact: Artifact?
    private var refreshTask: Task<Artifact?, Never>?

    func catalogForScan(now: Date = Date()) async -> CodexPricingCatalog? {
        loadIfNeeded()
        if let artifact, now.timeIntervalSince(artifact.fetchedAt) <= ttl {
            return artifact.catalog
        }
        if let stale = artifact?.catalog {
            if refreshTask == nil {
                refreshTask = Task { await Self.fetchArtifact(version: self.cacheVersion) }
                Task { await self.finishBackgroundRefresh() }
            }
            return stale
        }
        return await refreshNow()?.catalog
    }

    private func finishBackgroundRefresh() async {
        _ = await refreshNow()
    }

    private func refreshNow() async -> Artifact? {
        if refreshTask == nil {
            refreshTask = Task { await Self.fetchArtifact(version: self.cacheVersion) }
        }
        guard let task = refreshTask else { return artifact }
        let fetched = await task.value
        refreshTask = nil
        if let fetched {
            let merged = artifact.map {
                Artifact(
                    version: fetched.version,
                    fetchedAt: fetched.fetchedAt,
                    catalog: fetched.catalog.mergingFallback(from: $0.catalog)
                )
            } ?? fetched
            artifact = merged
            save(merged)
        }
        return artifact
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: Self.cacheURL()) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(Artifact.self, from: data),
              decoded.version == cacheVersion
        else { return }
        artifact = decoded
    }

    private func save(_ artifact: Artifact) {
        let url = Self.cacheURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(artifact) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func fetchArtifact(version: Int) async -> Artifact? {
        var request = URLRequest(
            url: URL(string: "https://models.dev/api.json")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DockDoorCodexUsage/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              200...299 ~= http.statusCode,
              let catalog = try? JSONDecoder().decode(CodexPricingCatalog.self, from: data),
              catalog.hasOpenAIPricing
        else { return nil }
        return Artifact(version: version, fetchedAt: Date(), catalog: catalog)
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DockDoorPro/CodexUsageMonitor/model-pricing", isDirectory: true)
            .appendingPathComponent("models-dev-v1.json", isDirectory: false)
    }
}

enum CodexPricingEngine {
    struct Result {
        let cost: Double
        let source: Source
    }

    enum Source {
        case dynamic
        case builtIn
        case priority
    }

    private struct Pricing {
        let input: Double
        let cachedRead: Double?
        let cacheWrite: Double?
        let output: Double
        let threshold: Int?
        let longInput: Double?
        let longCachedRead: Double?
        let longCacheWrite: Double?
        let longOutput: Double?
        let priorityInput: Double?
        let priorityCachedRead: Double?
        let priorityCacheWrite: Double?
        let priorityOutput: Double?
    }

    static func estimate(
        model rawModel: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int,
        outputTokens: Int,
        isPriority: Bool,
        catalog: CodexPricingCatalog?
    ) -> Result? {
        let model = normalizeModel(rawModel)
        guard model != "unknown" else { return nil }
        let builtIn = builtInPricing[model]

        if isPriority,
           inputTokens <= 272_000,
           let builtIn,
           let input = builtIn.priorityInput,
           let output = builtIn.priorityOutput
        {
            let priority = Pricing(
                input: input,
                cachedRead: builtIn.priorityCachedRead,
                cacheWrite: builtIn.priorityCacheWrite,
                output: output,
                threshold: nil,
                longInput: nil,
                longCachedRead: nil,
                longCacheWrite: nil,
                longOutput: nil,
                priorityInput: nil,
                priorityCachedRead: nil,
                priorityCacheWrite: nil,
                priorityOutput: nil
            )
            return Result(
                cost: cost(
                    priority,
                    input: inputTokens,
                    cached: cachedInputTokens,
                    cacheWrite: cacheWriteInputTokens,
                    output: outputTokens
                ),
                source: .priority
            )
        }

        if let dynamic = catalog?.lookup(model: rawModel)
            ?? (rawModel == model ? nil : catalog?.lookup(model: model))
        {
            let bundledLong = dynamic.threshold == nil ? builtIn : nil
            let merged = Pricing(
                input: dynamic.input,
                cachedRead: dynamic.cachedRead ?? builtIn?.cachedRead,
                cacheWrite: dynamic.cacheWrite ?? builtIn?.cacheWrite,
                output: dynamic.output,
                threshold: builtIn?.threshold ?? dynamic.threshold,
                longInput: dynamic.longInput ?? bundledLong?.longInput,
                longCachedRead: dynamic.longCachedRead
                    ?? (dynamic.threshold != nil
                        ? dynamic.cachedRead ?? dynamic.longInput ?? dynamic.input
                        : bundledLong?.longCachedRead),
                longCacheWrite: dynamic.longCacheWrite
                    ?? (dynamic.threshold != nil
                        ? dynamic.cacheWrite ?? dynamic.longInput ?? dynamic.input
                        : bundledLong?.longCacheWrite),
                longOutput: dynamic.longOutput ?? bundledLong?.longOutput,
                priorityInput: builtIn?.priorityInput,
                priorityCachedRead: builtIn?.priorityCachedRead,
                priorityCacheWrite: builtIn?.priorityCacheWrite,
                priorityOutput: builtIn?.priorityOutput
            )
            return Result(
                cost: cost(
                    merged,
                    input: inputTokens,
                    cached: cachedInputTokens,
                    cacheWrite: cacheWriteInputTokens,
                    output: outputTokens
                ),
                source: .dynamic
            )
        }

        guard let builtIn else { return nil }
        return Result(
            cost: cost(
                builtIn,
                input: inputTokens,
                cached: cachedInputTokens,
                cacheWrite: cacheWriteInputTokens,
                output: outputTokens
            ),
            source: .builtIn
        )
    }

    static func normalizeModel(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("openai/") { value = String(value.dropFirst("openai/".count)) }
        if value == "gpt-5.6" { return "gpt-5.6-sol" }
        if builtInPricing[value] != nil { return value }
        if let dated = value.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(value[..<dated.lowerBound])
            if builtInPricing[base] != nil { return base }
        }
        return value.isEmpty ? "unknown" : value
    }

    private static func cost(
        _ pricing: Pricing,
        input: Int,
        cached: Int,
        cacheWrite: Int,
        output: Int
    ) -> Double {
        let totalInput = max(0, input)
        let cachedRead = min(max(0, cached), totalInput)
        let remainder = totalInput - cachedRead
        let written = min(max(0, cacheWrite), remainder)
        let uncached = remainder - written
        let long = pricing.threshold.map { totalInput > $0 } ?? false

        let inputRate = long ? pricing.longInput ?? pricing.input : pricing.input
        let readRate = long
            ? pricing.longCachedRead ?? pricing.cachedRead ?? inputRate
            : pricing.cachedRead ?? pricing.input
        let writeRate = long
            ? pricing.longCacheWrite ?? pricing.cacheWrite ?? inputRate
            : pricing.cacheWrite ?? pricing.input
        let outputRate = long ? pricing.longOutput ?? pricing.output : pricing.output

        return Double(uncached) * inputRate
            + Double(cachedRead) * readRate
            + Double(written) * writeRate
            + Double(max(0, output)) * outputRate
    }

    private static let builtInPricing: [String: Pricing] = {
        func standard(
            _ input: Double,
            _ cached: Double?,
            _ output: Double,
            cacheWrite: Double? = nil,
            threshold: Int? = nil,
            longInput: Double? = nil,
            longCached: Double? = nil,
            longOutput: Double? = nil,
            longCacheWrite: Double? = nil,
            priorityInput: Double? = nil,
            priorityCached: Double? = nil,
            priorityOutput: Double? = nil,
            priorityCacheWrite: Double? = nil
        ) -> Pricing {
            Pricing(
                input: input,
                cachedRead: cached,
                cacheWrite: cacheWrite,
                output: output,
                threshold: threshold,
                longInput: longInput,
                longCachedRead: longCached,
                longCacheWrite: longCacheWrite,
                longOutput: longOutput,
                priorityInput: priorityInput,
                priorityCachedRead: priorityCached,
                priorityCacheWrite: priorityCacheWrite,
                priorityOutput: priorityOutput
            )
        }

        let gpt5 = standard(1.25e-6, 1.25e-7, 1e-5)
        let mini = standard(2.5e-7, 2.5e-8, 2e-6)
        let gpt52 = standard(1.75e-6, 1.75e-7, 1.4e-5)
        return [
            "gpt-5": gpt5,
            "gpt-5-codex": gpt5,
            "gpt-5-mini": mini,
            "gpt-5-nano": standard(5e-8, 5e-9, 4e-7),
            "gpt-5-pro": standard(1.5e-5, nil, 1.2e-4),
            "gpt-5.1": gpt5,
            "gpt-5.1-codex": gpt5,
            "gpt-5.1-codex-max": gpt5,
            "gpt-5.1-codex-mini": mini,
            "gpt-5.2": gpt52,
            "gpt-5.2-codex": gpt52,
            "gpt-5.2-pro": standard(2.1e-5, nil, 1.68e-4),
            "gpt-5.3-codex": gpt52,
            "gpt-5.3-codex-spark": standard(0, 0, 0),
            "gpt-5.4": standard(
                2.5e-6, 2.5e-7, 1.5e-5,
                threshold: 272_000,
                longInput: 5e-6,
                longCached: 5e-7,
                longOutput: 2.25e-5,
                priorityInput: 5e-6,
                priorityCached: 5e-7,
                priorityOutput: 3e-5
            ),
            "gpt-5.4-mini": standard(
                7.5e-7, 7.5e-8, 4.5e-6,
                priorityInput: 1.5e-6,
                priorityCached: 1.5e-7,
                priorityOutput: 9e-6
            ),
            "gpt-5.4-nano": standard(2e-7, 2e-8, 1.25e-6),
            "gpt-5.4-pro": standard(3e-5, nil, 1.8e-4),
            "gpt-5.5": standard(
                5e-6, 5e-7, 3e-5,
                threshold: 272_000,
                longInput: 1e-5,
                longCached: 1e-6,
                longOutput: 4.5e-5,
                priorityInput: 1.25e-5,
                priorityCached: 1.25e-6,
                priorityOutput: 7.5e-5
            ),
            "gpt-5.5-pro": standard(3e-5, nil, 1.8e-4),
            "gpt-5.6-sol": standard(
                5e-6, 5e-7, 3e-5,
                cacheWrite: 6.25e-6,
                threshold: 272_000,
                longInput: 1e-5,
                longCached: 1e-6,
                longOutput: 4.5e-5,
                longCacheWrite: 1.25e-5,
                priorityInput: 1e-5,
                priorityCached: 1e-6,
                priorityOutput: 6e-5,
                priorityCacheWrite: 1.25e-5
            ),
            "gpt-5.6-terra": standard(
                2.5e-6, 2.5e-7, 1.5e-5,
                cacheWrite: 3.125e-6,
                threshold: 272_000,
                longInput: 5e-6,
                longCached: 5e-7,
                longOutput: 2.25e-5,
                longCacheWrite: 6.25e-6,
                priorityInput: 5e-6,
                priorityCached: 5e-7,
                priorityOutput: 3e-5,
                priorityCacheWrite: 6.25e-6
            ),
            "gpt-5.6-luna": standard(
                1e-6, 1e-7, 6e-6,
                cacheWrite: 1.25e-6,
                threshold: 272_000,
                longInput: 2e-6,
                longCached: 2e-7,
                longOutput: 9e-6,
                longCacheWrite: 2.5e-6,
                priorityInput: 2e-6,
                priorityCached: 2e-7,
                priorityOutput: 1.2e-5,
                priorityCacheWrite: 2.5e-6
            ),
        ]
    }()
}
