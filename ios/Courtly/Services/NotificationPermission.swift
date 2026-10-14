import Foundation
import UserNotifications

enum NotificationPermission {
    /// Shows the system prompt. Returns the resulting grant, false if denied or on error.
    static func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
