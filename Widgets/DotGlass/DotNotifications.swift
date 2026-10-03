import AppKit
import UserNotifications

/// Notifications belong to the hosting app (DockDoor Pro); no Tracker helper,
/// account credentials, or conversation content leave this widget.
@MainActor
final class DotNotifications {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private let defaults: UserDefaults
    private let prefix = "dot-glass."
    private var pending = Set<String>()
    init(defaults: UserDefaults) { self.defaults = defaults }
    var enabled: Bool { defaults.bool(forKey: "dot-glass.notifications") }

    func enable() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            defaults.set(granted, forKey: "dot-glass.notifications")
            return granted
        } catch { return false }
    }

    func disable() {
        defaults.set(false, forKey: "dot-glass.notifications")
        clear()
    }

    func notify() {
        guard enabled else { return }
        let id = prefix + UUID().uuidString
        pending.insert(id)
        let content = UNMutableNotificationContent()
        content.title = "Dot Glass"
        content.body = "Your Dot has a new message. Open the Dot Glass tile to read it."
        content.sound = .default
        // Deliberately omit private message content from lock-screen previews.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.pending.remove(id) }
                else if !self.pending.contains(id) { self.center.removeDeliveredNotifications(withIdentifiers: [id]) }
            }
        }
        if pending.count > 100 { clear() }
    }

    func clear() {
        guard !pending.isEmpty else { return }
        // Remove only this widget's notifications, never DockDoor/other widgets'.
        center.removePendingNotificationRequests(withIdentifiers: Array(pending))
        center.removeDeliveredNotifications(withIdentifiers: Array(pending))
        pending.removeAll()
    }
}
