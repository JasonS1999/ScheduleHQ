import SwiftUI
import UserNotifications

/// AppDelegate for handling push notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("Received notification in foreground: \(userInfo)")

        // Show banner even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("User tapped notification: \(userInfo)")

        // Handle different notification types
        handleNotification(userInfo)

        completionHandler()
    }

    // MARK: - Notification Handling

    private func handleNotification(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "schedule_published":
            NotificationCenter.default.post(name: .schedulePublished, object: nil)

        case "time_off_approved":
            NotificationCenter.default.post(name: .timeOffStatusChanged, object: nil, userInfo: ["approved": true])

        case "time_off_denied":
            NotificationCenter.default.post(name: .timeOffStatusChanged, object: nil, userInfo: ["approved": false])

        case "shift_reminder":
            if let shiftId = userInfo["shiftId"] as? String {
                NotificationCenter.default.post(name: .shiftReminder, object: nil, userInfo: ["shiftId": shiftId])
            }

        case "announcement":
            NotificationCenter.default.post(name: .announcement, object: nil, userInfo: userInfo)

        default:
            print("Unknown notification type: \(type)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let schedulePublished = Notification.Name("schedulePublished")
    static let timeOffStatusChanged = Notification.Name("timeOffStatusChanged")
    static let shiftReminder = Notification.Name("shiftReminder")
    static let announcement = Notification.Name("announcement")
}
