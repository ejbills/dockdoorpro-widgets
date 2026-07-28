import Foundation

struct CodexAccountInsightsSnapshot: Codable, Equatable, Sendable {
    let officialUsage: CodexOfficialAccountUsage?
    let fetchedAt: Date
    let issues: [CodexAccountInsightIssue]

    var hasData: Bool { officialUsage != nil }
}

struct CodexOfficialAccountUsage: Codable, Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
    let dailyUsageBuckets: [CodexOfficialDailyUsageBucket]
}

struct CodexOfficialDailyUsageBucket: Codable, Equatable, Sendable, Identifiable {
    let startDate: String
    let tokens: Int64

    var id: String { startDate }
}

struct CodexAccountInsightIssue: Codable, Equatable, Sendable {
    enum Component: String, Codable, Equatable, Sendable {
        case officialUsage
    }

    enum Reason: String, Codable, Equatable, Sendable {
        case requestFailed
        case invalidResponse
    }

    let component: Component
    let reason: Reason
}

/// Fetches the same aggregate token-activity profile used by Codex
/// `account/usage/read`, without launching the Codex CLI.
///
/// The request is read-only and sends only the current OAuth access token and
/// account identifier. Refreshed credentials remain in memory and are never
/// written back to `~/.codex/auth.json`.
struct CodexAccountInsightsService: Sendable {
    enum ServiceError: LocalizedError, Sendable {
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
                    "未找到 Codex 登录信息。",
                    "Codex sign-in information was not found."
                )
            case .authTokensMissing:
                return CodexLocalization.text(
                    "Codex OAuth Token 缺失。",
                    "The Codex OAuth token is missing."
                )
            case .authInvalid:
                return CodexLocalization.text(
                    "Codex 登录信息格式不正确。",
                    "Codex sign-in information is invalid."
                )
            case .loginExpired:
                return CodexLocalization.text(
                    "Codex 登录已过期，请重新登录。",
                    "Your Codex sign-in has expired. Please sign in again."
                )
            case .invalidResponse:
                return CodexLocalization.text(
                    "官方活动数据暂不可用。",
                    "Official activity data is temporarily unavailable."
                )
            case let .server(code):
                return CodexLocalization.text(
                    "官方活动请求失败（HTTP \(code)）。",
                    "Official activity request failed (HTTP \(code))."
                )
            }
        }
    }

    private let credentialBroker: CodexOAuthCredentialBroker

    init(credentialBroker: CodexOAuthCredentialBroker = .shared) {
        self.credentialBroker = credentialBroker
    }

    private struct ProfileResponse: Decodable {
        let stats: Stats
    }

    private struct Stats: Decodable {
        let lifetimeTokens: Int64?
        let peakDailyTokens: Int64?
        let longestRunningTurnSeconds: Int64?
        let currentStreakDays: Int64?
        let longestStreakDays: Int64?
        let dailyUsageBuckets: [DailyBucket]?

        enum CodingKeys: String, CodingKey {
            case lifetimeTokens = "lifetime_tokens"
            case peakDailyTokens = "peak_daily_tokens"
            case longestRunningTurnSeconds = "longest_running_turn_sec"
            case currentStreakDays = "current_streak_days"
            case longestStreakDays = "longest_streak_days"
            case dailyUsageBuckets = "daily_usage_buckets"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lifetimeTokens = container.flexibleInt64(forKey: .lifetimeTokens)
            peakDailyTokens = container.flexibleInt64(forKey: .peakDailyTokens)
            longestRunningTurnSeconds = container.flexibleInt64(
                forKey: .longestRunningTurnSeconds
            )
            currentStreakDays = container.flexibleInt64(forKey: .currentStreakDays)
            longestStreakDays = container.flexibleInt64(forKey: .longestStreakDays)
            dailyUsageBuckets = try container.decodeIfPresent(
                [DailyBucket].self,
                forKey: .dailyUsageBuckets
            )
        }
    }

    private struct DailyBucket: Decodable {
        let startDate: String
        let tokens: Int64

        enum CodingKeys: String, CodingKey {
            case startDate = "start_date"
            case tokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startDate = try container.decode(String.self, forKey: .startDate)
            tokens = container.flexibleInt64(forKey: .tokens) ?? 0
        }
    }

    func fetch() async throws -> CodexAccountInsightsSnapshot {
        var credentials = try await credentialBroker.credentials()
        let profile: ProfileResponse
        do {
            profile = try await requestProfile(credentials)
        } catch ServiceError.loginExpired where !credentials.refreshToken.isEmpty {
            credentials = try await credentialBroker.refreshedCredentials(
                rejecting: credentials.accessToken
            )
            profile = try await requestProfile(credentials)
        }

        let stats = profile.stats
        let usage = CodexOfficialAccountUsage(
            lifetimeTokens: stats.lifetimeTokens,
            peakDailyTokens: stats.peakDailyTokens,
            longestRunningTurnSeconds: stats.longestRunningTurnSeconds,
            currentStreakDays: stats.currentStreakDays,
            longestStreakDays: stats.longestStreakDays,
            dailyUsageBuckets: (stats.dailyUsageBuckets ?? []).map {
                CodexOfficialDailyUsageBucket(
                    startDate: $0.startDate,
                    tokens: max(0, $0.tokens)
                )
            }
        )
        return CodexAccountInsightsSnapshot(
            officialUsage: usage,
            fetchedAt: Date(),
            issues: []
        )
    }

    private func requestProfile(
        _ credentials: CodexOAuthCredentials
    ) async throws -> ProfileResponse {
        let accountId = credentials.accountId ?? identityAccountId(from: credentials.idToken)
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DockDoorCodexUsage/1.0", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            guard let profile = try? JSONDecoder().decode(ProfileResponse.self, from: data) else {
                throw ServiceError.invalidResponse
            }
            return profile
        case 401, 403:
            throw ServiceError.loginExpired
        default:
            throw ServiceError.server(http.statusCode)
        }
    }

    private func identityAccountId(from idToken: String?) -> String? {
        guard let idToken else { return nil }
        let pieces = idToken.split(separator: ".")
        guard pieces.count > 1 else { return nil }
        var encoded = String(pieces[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
            ?? payload["chatgpt_account_id"] as? String
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt64(forKey key: Key) -> Int64? {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decode(Double.self, forKey: key) { return Int64(value) }
        if let value = try? decode(String.self, forKey: key) { return Int64(value) }
        return nil
    }
}
