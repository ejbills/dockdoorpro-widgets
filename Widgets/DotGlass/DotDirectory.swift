import Foundation

struct DotProfile: Identifiable, Codable, Equatable {
    var id: String { url }
    let url: String
    var name: String
}

/// Local bookmarks only; conversations and account credentials are never stored here.
struct DotDirectory: Codable {
    var profiles: [DotProfile] = []

    mutating func remember(url raw: String, name: String) {
        guard let url = DotURLPolicy.conversation(raw)?.absoluteString else { return }
        let label = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !label.isEmpty else { return }
        if let index = profiles.firstIndex(where: { $0.url == url }) {
            if label != "Your dot" { profiles[index].name = label }
        } else if profiles.count < 100 {
            profiles.append(DotProfile(url: url, name: label))
        }
    }
}
