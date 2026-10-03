import Foundation

struct DotMessage: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let isMine: Bool
    let hasAttachment: Bool
    var readReceipt: String? = nil
}

struct DotSnapshot: Decodable {
    let signedIn: Bool?
    let conversation: String
    let name: String
    let ready: Bool
    let typing: Bool
    let mediaPlaying: Bool
    let messages: [DotMessage]
    let acknowledgement: String?
}

enum DotPhase: String {
    case connecting = "Connecting"
    case ready = "Here with you"
    case thinking = "Thinking"
    case speaking = "Speaking"
    case inCall = "On a call"
    case sending = "Sending"
    case offline = "Connection paused"
}

enum DotURLPolicy {
    static let dotHome = URL(string: "https://chatgpt.com/dots/home")!
    static let home = URL(string: "https://chatgpt.com/")!

    static func conversation(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              url.host == "chatgpt.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              url.path.range(of: "^/dots/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/?$", options: .regularExpression) != nil
        else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.query = nil
        parts?.fragment = nil
        return parts?.url
    }

    static func allowsNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return ["chatgpt.com", "auth.openai.com", "auth0.openai.com", "login.openai.com",
                "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com",
                "login.live.com"].contains(host)
    }
}

struct DotVoiceSnapshot: Decodable {
    let connected: Bool
    let level: Double
    let meterAvailable: Bool
    var muted: Bool? = nil
}

/// Turns incoming audio metadata into a stable speaking on/off signal.
/// The ring uses this boolean; loudness never changes its animation strength.
struct DotSpeechActivity {
    private(set) var isSpeaking = false
    private var holdUntil = Date.distantPast

    mutating func update(connected: Bool, level: Double, now: Date = Date()) -> Bool {
        guard connected else {
            isSpeaking = false
            holdUntil = .distantPast
            return false
        }
        let finiteLevel = level.isFinite ? max(0, level) : 0
        if finiteLevel >= 0.01 {
            isSpeaking = true
            holdUntil = now.addingTimeInterval(0.42)
        } else if now >= holdUntil {
            isSpeaking = false
        }
        return isSpeaking
    }
}
