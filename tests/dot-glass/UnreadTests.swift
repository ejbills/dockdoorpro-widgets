import Foundation

@main struct UnreadTests {
    static func main() {
        func message(_ id: String, mine: Bool = false) -> DotMessage {
            DotMessage(id: id, text: "Fixture", isMine: mine, hasAttachment: false)
        }
        var state = DotUnread()
        precondition(state.update(room: "a", messages: [], typing: false, reading: false) == 0)
        precondition(state.update(room: "a", messages: [message("old")], typing: false, reading: false) == 0)
        precondition(state.count == 0, "Loaded history is not unread")
        let stream = [message("old"), message("reply"), message("out", mine: true)]
        precondition(state.update(room: "a", messages: stream, typing: true, reading: false) == 0)
        precondition(state.update(room: "a", messages: stream, typing: false, reading: false) == 1)
        precondition(state.update(room: "a", messages: stream, typing: false, reading: false) == 0)
        precondition(state.count == 1, "Streaming edits and outgoing messages don't inflate badges")
        precondition(state.update(room: "a", messages: [message("older")] + stream, typing: false, reading: false) == 0, "Loading older history must not notify")
        state.markRead(); precondition(state.count == 0)
        precondition(state.update(room: "a", messages: stream + [message("visible")], typing: false, reading: true) == 0)
        precondition(state.count == 0)
        precondition(state.update(room: "b", messages: [message("history")], typing: false, reading: false) == 0)
        let data = Data(#"{"id":"one","text":"Hello","isMine":true,"hasAttachment":false,"readReceipt":"Read 10:44 PM"}"#.utf8)
        precondition(try! JSONDecoder().decode(DotMessage.self, from: data).readReceipt == "Read 10:44 PM")
        let old = Data(#"{"id":"one","text":"Hello","isMine":true,"hasAttachment":false}"#.utf8)
        precondition(try! JSONDecoder().decode(DotMessage.self, from: old).readReceipt == nil)
        print("Unread baseline, stream deduplication, visible reading, room switching and receipt compatibility passed")
    }
}
