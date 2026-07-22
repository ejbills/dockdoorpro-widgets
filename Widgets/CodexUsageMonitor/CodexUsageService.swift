import Foundation

struct CodexUsageService {
    enum ServiceError: LocalizedError {
        case authMissing
        case authTokensMissing
        case authInvalid
        case loginExpired
        case invalidResponse
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .authMissing:
                return CodexLocalization.text(
                    "未找到 Codex 登录信息，请先在终端运行 codex 登录。",
                    "Codex sign-in information was not found. Run codex in Terminal and sign in first."
                )
            case .authTokensMissing:
                return CodexLocalization.text(
                    "Codex OAuth Token 缺失，请重新登录。",
                    "The Codex OAuth token is missing. Please sign in again."
                )
            case .authInvalid:
                return CodexLocalization.text(
                    "Codex 登录信息格式不正确，请重新登录。",
                    "Codex sign-in information is invalid. Please sign in again."
                )
            case .loginExpired:
                return CodexLocalization.text(
                    "Codex 登录已过期，请在终端重新运行 codex。",
                    "Your Codex sign-in has expired. Run codex again in Terminal."
                )
            case .invalidResponse:
                return CodexLocalization.text(
                    "Codex 返回了无法识别的额度数据。",
                    "Codex returned unrecognized quota data."
                )
            case let .server(code):
                return CodexLocalization.text(
                    "Codex 服务请求失败（HTTP \(code)）。",
                    "The Codex service request failed (HTTP \(code))."
                )
            }
        }

    }

    private struct Credentials {
        let accessToken: String
        let refreshToken: String
        let idToken: String?
        let accountId: String?
    }

    private struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let credits: Credits?
        let additionalRateLimits: [AdditionalLimit]?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case credits
            case additionalRateLimits = "additional_rate_limits"
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let resetAt: Int
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = Self.double(container, .usedPercent) ?? 0
            resetAt = Self.int(container, .resetAt) ?? 0
            limitWindowSeconds = Self.int(container, .limitWindowSeconds) ?? 0
        }

        private static func double(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> Double? {
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let value = try? container.decode(String.self, forKey: key) { return Double(value) }
            return nil
        }

        private static func int(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> Int? {
            if let value = try? container.decode(Int.self, forKey: key) { return value }
            if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
            if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
            return nil
        }
    }

    private struct Credits: Decodable {
        let balance: Double?

        enum CodingKeys: String, CodingKey { case balance }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(Double.self, forKey: .balance) {
                balance = value
            } else if let value = try? container.decode(String.self, forKey: .balance) {
                balance = Double(value)
            } else {
                balance = nil
            }
        }
    }

    private struct AdditionalLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }
    }

    private struct ResetCreditsResponse: Decodable {
        struct Credit: Decodable {
            let status: String
            let expiresAt: String?

            enum CodingKeys: String, CodingKey {
                case status
                case expiresAt = "expires_at"
            }
        }

        let credits: [Credit]
        let availableCount: Int

        enum CodingKeys: String, CodingKey {
            case credits
            case availableCount = "available_count"
        }
    }

    private struct ResetCreditInventory {
        let availableCount: Int
        let nextExpiresAt: Date?
    }

    private struct StatusResponse: Decodable {
        struct Page: Decodable {
            let updatedAt: String?
            enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" }
        }
        struct Status: Decodable {
            let description: String?
            let indicator: String
        }
        let page: Page?
        let status: Status
    }

    private struct IncidentResponse: Decodable {
        struct Summary: Decodable {
            struct Affected: Decodable {
                let componentId: String
                let status: String?
                enum CodingKeys: String, CodingKey {
                    case componentId = "component_id"
                    case status
                }
            }

            struct Structure: Decodable {
                struct Item: Decodable {
                    struct Group: Decodable {
                        struct Child: Decodable {
                            let componentId: String
                            let name: String?
                            let hidden: Bool?
                            enum CodingKeys: String, CodingKey {
                                case componentId = "component_id"
                                case name, hidden
                            }
                        }
                        let id: String
                        let name: String?
                        let hidden: Bool?
                        let components: [Child]?
                    }
                    let group: Group?
                }
                let items: [Item]?
            }

            let affectedComponents: [Affected]?
            let structure: Structure?
            enum CodingKeys: String, CodingKey {
                case affectedComponents = "affected_components"
                case structure
            }
        }
        let summary: Summary?
    }

    func fetchUsage(source: CodexQuotaUsageSource) async throws -> CodexQuotaFetchResult {
        switch source {
        case .automatic, .oauth:
            return CodexQuotaFetchResult(
                snapshot: try await fetchOAuthUsage(),
                resolvedSource: .oauth
            )
        }
    }

    private func fetchOAuthUsage() async throws -> CodexUsageSnapshot {
        var credentials = try loadCredentials()
        let response: UsageResponse
        do {
            response = try await requestUsage(credentials)
        } catch ServiceError.loginExpired where !credentials.refreshToken.isEmpty {
            credentials = try await refresh(credentials)
            response = try await requestUsage(credentials)
        }

        let identity = identity(from: credentials.idToken)
        let accountId = credentials.accountId ?? identity.accountId
        let accessToken = credentials.accessToken
        async let resetCreditTask = fetchResetCredits(
            accessToken: accessToken,
            accountId: accountId
        )

        let mainWindows = [
            makeWindow(
                response.rateLimit?.primaryWindow,
                id: "session",
                title: CodexLocalization.text("短周期", "Session")
            ),
            makeWindow(
                response.rateLimit?.secondaryWindow,
                id: "weekly",
                title: CodexLocalization.text("每周", "Weekly")
            ),
        ].compactMap { $0 }

        let weekly = mainWindows
            .filter { $0.durationSeconds >= 2 * 24 * 60 * 60 }
            .max { $0.durationSeconds < $1.durationSeconds }
        let session = mainWindows
            .filter { $0.durationSeconds < 2 * 24 * 60 * 60 }
            .min { $0.durationSeconds < $1.durationSeconds }

        var extras: [CodexQuotaWindow] = []
        for (index, limit) in (response.additionalRateLimits ?? []).enumerated() {
            let name = limit.limitName ?? limit.meteredFeature ?? CodexLocalization.text(
                "额外额度 \(index + 1)",
                "Extra quota \(index + 1)"
            )
            if let window = makeWindow(
                limit.rateLimit?.secondaryWindow ?? limit.rateLimit?.primaryWindow,
                id: "extra-\(index)",
                title: name
            ) {
                extras.append(window)
            }
        }

        let resetCredits = try? await resetCreditTask
        return CodexUsageSnapshot(
            accountEmail: identity.email,
            plan: response.planType ?? identity.plan,
            sessionWindow: session,
            weeklyWindow: weekly ?? mainWindows.max { $0.durationSeconds < $1.durationSeconds },
            extraWindows: extras,
            creditsBalance: response.credits?.balance,
            resetCreditsAvailable: resetCredits?.availableCount,
            resetCreditsExpiresAt: resetCredits?.nextExpiresAt,
            fetchedAt: Date()
        )
    }

    func fetchStatus() async throws -> OpenAIStatusSnapshot {
        let summaryURL = URL(string: "https://status.openai.com/proxy/status.openai.com")!
        let statusURL = URL(string: "https://status.openai.com/api/v2/status.json")!

        async let incidentData = requestData(summaryURL, timeout: 12)
        async let statusData = requestData(statusURL, timeout: 12)

        let (incidentPayload, statusPayload) = try await (incidentData, statusData)
        let incident = try JSONDecoder().decode(IncidentResponse.self, from: incidentPayload)
        let status = try JSONDecoder().decode(StatusResponse.self, from: statusPayload)

        guard let summary = incident.summary,
              let items = summary.structure?.items
        else {
            throw ServiceError.invalidResponse
        }

        let affected = Dictionary(
            uniqueKeysWithValues: (summary.affectedComponents ?? []).map {
                ($0.componentId, $0.status ?? "degraded_performance")
            }
        )

        let wanted = Set(["ChatGPT", "Codex"])
        let groups: [OpenAIStatusGroup] = items.compactMap { item in
            guard let group = item.group,
                  group.hidden != true,
                  let name = group.name,
                  wanted.contains(name)
            else { return nil }

            let components = (group.components ?? []).compactMap { child -> OpenAIStatusComponent? in
                guard child.hidden != true,
                      let childName = child.name,
                      !childName.isEmpty
                else { return nil }
                let raw = affected[child.componentId] ?? "operational"
                return OpenAIStatusComponent(
                    id: child.componentId,
                    name: childName,
                    indicator: OpenAIServiceIndicator(status: raw)
                )
            }
            return OpenAIStatusGroup(id: group.id, name: name, components: components)
        }

        guard !groups.isEmpty else { throw ServiceError.invalidResponse }
        return OpenAIStatusSnapshot(
            overallIndicator: OpenAIServiceIndicator(overallIndicator: status.status.indicator),
            description: status.status.description,
            groups: groups,
            updatedAt: status.page?.updatedAt.flatMap(parseISO8601),
            fetchedAt: Date()
        )
    }

    private func requestUsage(_ credentials: Credentials) async throws -> UsageResponse {
        let accountId = credentials.accountId ?? identity(from: credentials.idToken).accountId
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DockDoorCodexUsage/1.0", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let data = try await authorizedData(request)
        guard let response = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            throw ServiceError.invalidResponse
        }
        return response
    }

    private func fetchResetCredits(
        accessToken: String,
        accountId: String?
    ) async throws -> ResetCreditInventory {
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        let data = try await authorizedData(request)
        let response = try JSONDecoder().decode(ResetCreditsResponse.self, from: data)
        let now = Date()
        let nextExpiresAt = response.credits
            .filter { $0.status == "available" }
            .compactMap { $0.expiresAt.flatMap(parseISO8601) }
            .filter { $0 > now }
            .min()
        return ResetCreditInventory(
            availableCount: response.availableCount,
            nextExpiresAt: nextExpiresAt
        )
    }

    private func authorizedData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw ServiceError.loginExpired
        default: throw ServiceError.server(http.statusCode)
        }
    }

    private func requestData(_ url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200...299 ~= http.statusCode
        else { throw ServiceError.invalidResponse }
        return data
    }

    private func makeWindow(
        _ window: Window?,
        id: String,
        title: String
    ) -> CodexQuotaWindow? {
        guard let window, window.limitWindowSeconds > 0 else { return nil }
        return CodexQuotaWindow(
            id: id,
            title: title,
            usedPercent: max(0, min(100, window.usedPercent)),
            resetAt: window.resetAt > 0 ? Date(timeIntervalSince1970: TimeInterval(window.resetAt)) : nil,
            durationSeconds: window.limitWindowSeconds
        )
    }

    private func authFileURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let configured = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty
        {
            return URL(fileURLWithPath: configured).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    private func loadCredentials() throws -> Credentials {
        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { throw ServiceError.authMissing }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.authInvalid
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            throw ServiceError.authTokensMissing
        }
        guard let access = (tokens["access_token"] ?? tokens["accessToken"]) as? String,
              !access.isEmpty
        else { throw ServiceError.authTokensMissing }

        let refresh = (tokens["refresh_token"] ?? tokens["refreshToken"]) as? String ?? ""
        let idToken = (tokens["id_token"] ?? tokens["idToken"]) as? String
        let accountId = (tokens["account_id"] ?? tokens["accountId"]) as? String
        return Credentials(
            accessToken: access,
            refreshToken: refresh,
            idToken: idToken,
            accountId: accountId
        )
    }

    private func refresh(_ credentials: Credentials) async throws -> Credentials {
        guard !credentials.refreshToken.isEmpty else { throw ServiceError.loginExpired }
        var request = URLRequest(
            url: URL(string: "https://auth.openai.com/oauth/token")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 400, 401, 403: throw ServiceError.loginExpired
        default: throw ServiceError.server(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["access_token"] is String
        else { throw ServiceError.invalidResponse }

        return Credentials(
            accessToken: json["access_token"] as? String ?? credentials.accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            idToken: json["id_token"] as? String ?? credentials.idToken,
            accountId: credentials.accountId
        )
    }

    private func identity(from idToken: String?) -> (email: String?, plan: String?, accountId: String?) {
        guard let idToken else { return (nil, nil, nil) }
        let pieces = idToken.split(separator: ".")
        guard pieces.count > 1 else { return (nil, nil, nil) }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil, nil) }

        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        return (
            payload["email"] as? String ?? profile?["email"] as? String,
            auth?["chatgpt_plan_type"] as? String ?? payload["chatgpt_plan_type"] as? String,
            auth?["chatgpt_account_id"] as? String ?? payload["chatgpt_account_id"] as? String
        )
    }

    private func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}
