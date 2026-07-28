import Foundation

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
}

enum CodexOAuthCredentialError: LocalizedError, Sendable {
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
                "Codex OAuth 返回了无法识别的数据。",
                "Codex OAuth returned an unrecognized response."
            )
        case let .server(code):
            return CodexLocalization.text(
                "Codex OAuth 请求失败（HTTP \(code)）。",
                "The Codex OAuth request failed (HTTP \(code))."
            )
        }
    }
}

/// Serializes OAuth refreshes shared by quota and official-activity requests.
///
/// Refreshed credentials are cached in memory only. The broker reloads
/// `auth.json` whenever the file changes and never writes credentials to disk.
actor CodexOAuthCredentialBroker {
    static let shared = CodexOAuthCredentialBroker()

    private struct CachedCredentials {
        let credentials: CodexOAuthCredentials
        let authFileURL: URL
        let modificationDate: Date?
    }

    private var cached: CachedCredentials?
    private var refreshTask: Task<CodexOAuthCredentials, Error>?

    func credentials() throws -> CodexOAuthCredentials {
        let url = Self.authFileURL()
        let modificationDate = Self.modificationDate(for: url)
        if let cached,
           cached.authFileURL == url,
           cached.modificationDate == modificationDate
        {
            return cached.credentials
        }

        let loaded = try Self.loadCredentials(from: url)
        cached = CachedCredentials(
            credentials: loaded,
            authFileURL: url,
            modificationDate: modificationDate
        )
        return loaded
    }

    func refreshedCredentials(
        rejecting rejectedAccessToken: String
    ) async throws -> CodexOAuthCredentials {
        let current = try credentials()
        if current.accessToken != rejectedAccessToken {
            return current
        }
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<CodexOAuthCredentials, Error> {
            try await Self.refresh(current)
        }
        refreshTask = task

        do {
            let refreshed = try await task.value
            let url = Self.authFileURL()
            cached = CachedCredentials(
                credentials: refreshed,
                authFileURL: url,
                modificationDate: Self.modificationDate(for: url)
            )
            refreshTask = nil
            return refreshed
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private nonisolated static func authFileURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !configured.isEmpty
        {
            return URL(fileURLWithPath: configured).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    private nonisolated static func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private nonisolated static func loadCredentials(
        from url: URL
    ) throws -> CodexOAuthCredentials {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexOAuthCredentialError.authMissing
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexOAuthCredentialError.authInvalid
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            throw CodexOAuthCredentialError.authTokensMissing
        }
        guard let accessToken = (tokens["access_token"] ?? tokens["accessToken"]) as? String,
              !accessToken.isEmpty
        else {
            throw CodexOAuthCredentialError.authTokensMissing
        }

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: (tokens["refresh_token"] ?? tokens["refreshToken"]) as? String ?? "",
            idToken: (tokens["id_token"] ?? tokens["idToken"]) as? String,
            accountId: (tokens["account_id"] ?? tokens["accountId"]) as? String
        )
    }

    private nonisolated static func refresh(
        _ credentials: CodexOAuthCredentials
    ) async throws -> CodexOAuthCredentials {
        guard !credentials.refreshToken.isEmpty else {
            throw CodexOAuthCredentialError.loginExpired
        }
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
        guard let http = response as? HTTPURLResponse else {
            throw CodexOAuthCredentialError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            break
        case 400, 401, 403:
            throw CodexOAuthCredentialError.loginExpired
        default:
            throw CodexOAuthCredentialError.server(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              !accessToken.isEmpty
        else {
            throw CodexOAuthCredentialError.invalidResponse
        }

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            idToken: json["id_token"] as? String ?? credentials.idToken,
            accountId: credentials.accountId
        )
    }
}
