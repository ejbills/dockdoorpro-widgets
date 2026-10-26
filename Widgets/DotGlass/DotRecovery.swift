import AppKit
import Foundation

/// Presentation states are derived from the owned session, not browser navigation.
enum DotConnectionState: String {
    case setup = "Connect your Dot"
    case authentication = "Secure ChatGPT sign-in"
    case connecting = "Connecting"
    case reconnecting = "Reconnecting"
    case ready = "Connected to ChatGPT"
    case paused = "Connection paused"
    case deliveryAttention = "Check message delivery"
}

@MainActor
final class DotRecovery {
    weak var connection: DotConnection?
    private(set) var attempts = 0
    private var deadline: Date?
    private var wakeObserver: NSObjectProtocol?

    init(connection: DotConnection) {
        self.connection = connection
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let connection = self.connection,
                      !connection.voiceConnected, !connection.voiceStarting,
                      connection.pendingToken == nil, !connection.needsSetup,
                      !connection.showConnection, connection.isPanelVisible else { return }
                self.attempts = 0
                connection.reload()
            }
        }
    }
    deinit { if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) } }

    func begin(now: Date = Date()) { deadline = now.addingTimeInterval(18) }
    func beginIfNeeded() { if deadline == nil { begin() } }
    func cancel() { deadline = nil; attempts = 0 }
    func succeeded() { cancel() }

    func tick(now: Date = Date()) {
        guard let deadline, now >= deadline, let connection,
              !connection.ready, !connection.needsSetup, !connection.showConnection,
              !connection.voiceConnected, !connection.voiceStarting,
              connection.pendingToken == nil else { return }
        guard attempts < 3 else {
            self.deadline = nil
            connection.loading = false
            connection.notice = "We couldn’t reconnect. Your conversation and draft are still here. Try again or sign in again."
            return
        }
        attempts += 1
        connection.reload()
        self.deadline = now.addingTimeInterval(18 + Double(attempts * 3))
    }
}
