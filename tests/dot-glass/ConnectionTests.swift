import AppKit
import Foundation

@main
struct ConnectionChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "dot-glass.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let connection = DotConnection(defaults: defaults)
        var speech = DotSpeechActivity()
        let speechStart = Date(timeIntervalSince1970: 100)
        precondition(speech.update(connected: true, level: 0.01, now: speechStart), "Quiet Dot speech must activate the speaking state")
        precondition(speech.update(connected: true, level: 0, now: speechStart.addingTimeInterval(0.2)), "Brief audio gaps must not flicker the speaking state")
        precondition(!speech.update(connected: true, level: 0, now: speechStart.addingTimeInterval(0.43)), "Speaking must settle after incoming audio stops")
        precondition(!speech.update(connected: false, level: 1, now: speechStart.addingTimeInterval(0.5)), "Disconnect must not retain speech activity")
        connection.loadSaved()
        precondition(connection.needsSetup && !connection.loading)
        connection.startCall()
        precondition(!connection.voiceStarting, "Calling must require a ready conversation")
        let room = "https://chatgpt.com/dots/00000000-0000-0000-0000-000000000001"
        let message = DotMessage(id: "fixture", text: "Test fixture only", isMine: false, hasAttachment: false)
        func snapshot(_ url: String, acknowledgement: String? = nil, messages: [DotMessage]? = nil) -> DotSnapshot {
            DotSnapshot(signedIn: false, conversation: url, name: "Fixture", ready: true, typing: false, mediaPlaying: false, messages: messages ?? [message], acknowledgement: acknowledgement)
        }
        connection.receive(snapshot(room))
        precondition(connection.ready && connection.messages == [message])
        precondition(defaults.string(forKey: "dot-glass.conversationURL") == room)
        precondition(defaults.string(forKey: "dotGlass.conversationURL") == nil)
        let acknowledged = DotMessage(id: "fixture", text: "Test fixture only", isMine: false, hasAttachment: false, readReceipt: "Read 10:44 PM")
        connection.receive(snapshot(room, messages: [acknowledged]))
        connection.receive(snapshot(room))
        precondition(connection.messages.first?.readReceipt == "Read 10:44 PM", "An observed receipt should remain with its message for this connection")
        connection.draft = "Keep my draft"
        connection.receive(snapshot("https://untrusted.example/dots/00000000-0000-0000-0000-000000000001"))
        precondition(!connection.ready && connection.messages.isEmpty)
        connection.receive(snapshot(room))
        precondition(connection.draft == "Keep my draft", "Navigation must preserve per-room drafts")
        connection.pendingToken = "pending-fixture"
        connection.reload()
        precondition(connection.pendingToken != nil && connection.showConnection)
        connection.receive(snapshot(room, acknowledgement: "different-token"))
        precondition(connection.pendingToken != nil)
        connection.receive(snapshot(room, acknowledgement: "pending-fixture"))
        precondition(connection.pendingToken == nil)
        connection.voiceConnected = true
        let panel = UUID()
        connection.panelAppeared(panel)
        connection.panelDisappeared(panel)
        precondition(connection.voiceConnected, "Hiding the panel must retain an active call")
        connection.voiceConnected = false
        connection.voiceStarting = true
        connection.panelAppeared(panel)
        connection.panelDisappeared(panel)
        precondition(connection.voiceStarting, "Auto-dismiss must not cancel call setup")
        connection.voiceStarting = false
        connection.voiceConnected = true
        connection.reload()
        precondition(connection.voiceConnected && connection.notice == "End your call before reconnecting.")
        connection.voiceConnected = false
        connection.stopAudio()
        connection.receiveVoice(DotVoiceSnapshot(connected: true, level: 1, meterAvailable: true))
        precondition(!connection.voiceConnected, "Late call events must not revive an ended call")
        connection.receiveVoice(DotVoiceSnapshot(connected: false, level: 0, meterAvailable: false))
        connection.receiveVoice(DotVoiceSnapshot(connected: true, level: .nan, meterAvailable: true))
        precondition(connection.voiceLevel == 0, "Meter input must be finite")
        connection.receiveVoice(DotVoiceSnapshot(connected: true, level: 0, meterAvailable: true, muted: true))
        precondition(connection.microphoneMuted && connection.voiceConnected, "Mute must be visible without ending a call")
        connection.receiveVoice(DotVoiceSnapshot(connected: true, level: 0, meterAvailable: true, muted: false))
        precondition(!connection.microphoneMuted, "Unmuting must clear the native warning")
        connection.voiceConnected = false
        print("Connection checks passed: setup, call guard, origin, drafts, pending delivery, reconnect, stale voice, bounded meter")
    }
}
