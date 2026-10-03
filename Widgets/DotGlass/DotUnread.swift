import Foundation

/// Only messages arriving after the initial conversation snapshot are new.
/// Stores identifiers, never message text. Streaming edits cannot inflate counts.
struct DotUnread {
    private(set) var room = ""
    private var seen = Set<String>()
    private var pending = Set<String>()
    private var unread = Set<String>()
    private var baselineReady = false
    private var tail: String?
    var count: Int { unread.count }

    mutating func reset() { self = DotUnread() }

    mutating func update(room: String, messages: [DotMessage], typing: Bool, reading: Bool) -> Int {
        if room != self.room { reset(); self.room = room }
        let incoming = Set(messages.filter { !$0.isMine }.map(\.id))
        guard baselineReady else {
            // Empty loading snapshots must not turn existing history into new replies.
            if !messages.isEmpty { seen = incoming; tail = messages.last?.id; baselineReady = true }
            return 0
        }
        // Only rows appended after our last observed tail are arrivals. Loading older
        // virtualized history above it must not generate notifications.
        let candidates: [DotMessage]
        if let tail, let index = messages.firstIndex(where: { $0.id == tail }) {
            candidates = Array(messages.dropFirst(index + 1))
        } else { candidates = [] }
        let arrivals = Set(candidates.filter { !$0.isMine }.map(\.id)).subtracting(seen)
        tail = messages.last?.id ?? tail
        seen.formUnion(incoming)
        if seen.count > 500 { seen = incoming.union(unread).union(pending) }
        pending.formUnion(arrivals)
        if reading { unread.removeAll(); pending.removeAll(); return 0 }
        guard !typing else { return 0 }
        let count = pending.subtracting(unread).count
        unread.formUnion(pending); pending.removeAll()
        if unread.count > 500 { unread = Set(unread.sorted().suffix(500)) }
        return count
    }

    mutating func markRead() { unread.removeAll(); pending.removeAll() }
}
