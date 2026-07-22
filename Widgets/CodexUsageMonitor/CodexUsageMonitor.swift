import Combine
import DockDoorWidgetSDK
import Foundation

@MainActor
final class CodexUsageMonitor: ObservableObject {
    @Published private(set) var usage: CodexUsageSnapshot?
    @Published private(set) var recentUsage: CodexRecentUsageSnapshot?
    @Published private(set) var serviceStatus: OpenAIStatusSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var usageError: String?
    @Published private(set) var tokenUsageError: String?
    @Published private(set) var statusError: String?
    @Published private(set) var settingsRevision = 0
    @Published private(set) var resolvedQuotaUsageSource: CodexQuotaUsageSource?

    let widgetId: String

    private let service: CodexUsageService
    private let localUsageScanner: CodexLocalUsageScanner
    private var refreshLoop: Task<Void, Never>?
    private var refreshOperation: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?
    private var hasStarted = false
    private var scheduledInterval: CodexRefreshInterval
    private var scheduledQuotaUsageSource: CodexQuotaUsageSource

    init(
        widgetId: String,
        service: CodexUsageService = CodexUsageService(),
        localUsageScanner: CodexLocalUsageScanner = CodexLocalUsageScanner()
    ) {
        self.widgetId = widgetId
        self.service = service
        self.localUsageScanner = localUsageScanner
        scheduledInterval = Self.readRefreshInterval(widgetId: widgetId)
        scheduledQuotaUsageSource = Self.readQuotaUsageSource(widgetId: widgetId)
        usage = Self.readCache(CodexUsageSnapshot.self, key: Self.usageCacheKey(widgetId))
        recentUsage = Self.readCache(CodexRecentUsageSnapshot.self, key: Self.tokenUsageCacheKey(widgetId))
        serviceStatus = Self.readCache(OpenAIStatusSnapshot.self, key: Self.statusCacheKey(widgetId))
        resolvedQuotaUsageSource = UserDefaults.standard.string(
            forKey: Self.resolvedSourceCacheKey(widgetId)
        ).flatMap(CodexQuotaUsageSource.init(rawValue:))

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { @MainActor [weak self] _ in
            self?.configurationDidChange()
        }
    }

    deinit {
        refreshLoop?.cancel()
        refreshOperation?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        scheduleRefreshLoop()
    }

    func refresh() {
        refreshOperation?.cancel()
        isRefreshing = true
        refreshOperation = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
    }

    func syncConfiguration() {
        let interval = Self.readRefreshInterval(widgetId: widgetId)
        if interval != scheduledInterval {
            scheduledInterval = interval
            scheduleRefreshLoop()
        }
        let source = Self.readQuotaUsageSource(widgetId: widgetId)
        if source != scheduledQuotaUsageSource {
            scheduledQuotaUsageSource = source
            if hasStarted { refresh() }
        }
    }

    func window(for limit: CodexDisplayLimit) -> CodexQuotaWindow? {
        switch limit {
        case .weekly: return usage?.weeklyWindow
        case .session: return usage?.sessionWindow ?? usage?.weeklyWindow
        }
    }

    func writeSetting(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: Self.settingKey(key, widgetId))
        configurationDidChange()
    }

    func writeSetting(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: Self.settingKey(key, widgetId))
        configurationDidChange()
    }

    #if CODEX_USAGE_TESTING
    func setTestingData(
        usage: CodexUsageSnapshot?,
        status: OpenAIStatusSnapshot?,
        recentUsage: CodexRecentUsageSnapshot? = nil
    ) {
        self.usage = usage
        serviceStatus = status
        self.recentUsage = recentUsage
        resolvedQuotaUsageSource = .oauth
        isRefreshing = false
        hasStarted = true
    }
    #endif

    private func performRefresh() async {
        let quotaSource = scheduledQuotaUsageSource
        async let usageResult = Self.capture { try await self.service.fetchUsage(source: quotaSource) }
        async let tokenUsageResult = Self.capture { try await self.localUsageScanner.scan() }
        async let statusResult = Self.capture { try await self.service.fetchStatus() }

        switch await usageResult {
        case let .success(result):
            usage = result.snapshot
            resolvedQuotaUsageSource = result.resolvedSource
            usageError = nil
            Self.cache(result.snapshot, key: Self.usageCacheKey(widgetId))
            UserDefaults.standard.set(
                result.resolvedSource.rawValue,
                forKey: Self.resolvedSourceCacheKey(widgetId)
            )
        case let .failure(error):
            if !Task.isCancelled { usageError = error.localizedDescription }
        }

        switch await tokenUsageResult {
        case let .success(snapshot):
            recentUsage = snapshot
            tokenUsageError = nil
            Self.cache(snapshot, key: Self.tokenUsageCacheKey(widgetId))
        case let .failure(error):
            if !Task.isCancelled { tokenUsageError = error.localizedDescription }
        }

        switch await statusResult {
        case let .success(snapshot):
            serviceStatus = snapshot
            statusError = nil
            Self.cache(snapshot, key: Self.statusCacheKey(widgetId))
        case let .failure(error):
            if !Task.isCancelled { statusError = error.localizedDescription }
        }
        isRefreshing = false
    }

    private func configurationDidChange() {
        settingsRevision &+= 1
        let interval = Self.readRefreshInterval(widgetId: widgetId)
        if interval != scheduledInterval {
            scheduledInterval = interval
            scheduleRefreshLoop()
        }
        let source = Self.readQuotaUsageSource(widgetId: widgetId)
        if source != scheduledQuotaUsageSource {
            scheduledQuotaUsageSource = source
            if hasStarted { refresh() }
        }
    }

    private func scheduleRefreshLoop() {
        refreshLoop?.cancel()
        guard hasStarted else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.scheduledInterval.rawValue) * 1_000_000_000
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private nonisolated static func capture<T>(
        _ operation: @escaping () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    private static func readRefreshInterval(widgetId: String) -> CodexRefreshInterval {
        CodexRefreshInterval.resolve(title: WidgetDefaults.string(
            key: "refreshInterval",
            widgetId: widgetId,
            default: CodexRefreshInterval.fiveMinutes.title
        ))
    }

    private static func readQuotaUsageSource(widgetId: String) -> CodexQuotaUsageSource {
        CodexQuotaUsageSource.resolve(title: WidgetDefaults.string(
            key: "quotaUsageSource",
            widgetId: widgetId,
            default: CodexQuotaUsageSource.automatic.title
        ))
    }

    private static func cache<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func readCache<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func settingKey(_ key: String, _ widgetId: String) -> String {
        "widget.\(widgetId).\(key)"
    }

    private static func usageCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedUsage"
    }

    private static func statusCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedStatus"
    }

    private static func tokenUsageCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedRecentTokenUsage"
    }

    private static func resolvedSourceCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedResolvedQuotaUsageSource"
    }
}
