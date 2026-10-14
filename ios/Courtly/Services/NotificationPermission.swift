import Foundation
import UIKit
import UserNotifications

enum NotificationPermission {
    /// Shows the system prompt and, when granted, asks APNs for a device token.
    static func request() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }

    static func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}
