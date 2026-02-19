import Foundation
import UserNotifications

/// For testing without APNs: show a local notification when the app sees new drops from the API.
enum LocalNotificationHelper {

    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return settings.authorizationStatus == .authorized
    }

    /// Schedule a local notification for a new drop (no APNs required). Use when app fetches and sees new drops.
    static func notifyNewDrop(venueName: String, dateStr: String? = nil, timeStr: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "New drop"
        content.body = venueName
        if let d = dateStr, let t = timeStr, !d.isEmpty, !t.isEmpty {
            content.body = "\(venueName) — \(d) \(t)"
        } else if let d = dateStr, !d.isEmpty {
            content.body = "\(venueName) — \(d)"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "new-drop-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
