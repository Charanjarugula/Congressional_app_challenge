import SwiftUI
import UIKit
import UserNotifications

@main
struct CourtlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--onboarding-ui-checks") {
                    OnboardingPreviewHarness()
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
            .environment(session)
        }
    }
}

/// Push token registration and notification taps. The token is stored server-side so
/// notifications can reach this device; taps become deep links the tab shell opens.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await API.Devices.register(token: token, environment: AppConfig.apnsEnvironment)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the simulator. Nothing to do.
    }

    /// A push arrived while the app is open: show it, and let the lists refresh.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        DeepLinkCenter.shared.pushArrived(kind: info["kind"] as? String)
        // The thread on screen shows the message itself; a banner and sound over it would be noise.
        if let chatID = DeepLinkCenter.chatID(in: info), DeepLinkCenter.shared.visibleChatID == chatID {
            return [.badge]
        }
        return [.banner, .list, .sound, .badge]
    }

    /// The player tapped a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = DeepLink(userInfo: response.notification.request.content.userInfo) else { return }
        DeepLinkCenter.shared.open(link)
    }
}
