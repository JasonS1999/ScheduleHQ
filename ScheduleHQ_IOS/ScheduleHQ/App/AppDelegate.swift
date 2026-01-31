import SwiftUI
import FirebaseMessaging
import UserNotifications

/// AppDelegate for handling push notifications and Firebase Cloud Messaging
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Set up Firebase Messaging delegate
        Messaging.messaging().delegate = self
        
        // Request notification permission
        requestNotificationPermission()
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // MARK: - Notification Permission
    
    private func requestNotificationPermission() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
                return
            }
            
            print("Notification permission granted: \(granted)")
        }
    }
    
    // MARK: - Remote Notification Registration
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Pass device token to Firebase
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
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
    
    // MARK: - MessagingDelegate
    
    /// Called when FCM token is refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM token received: \(token)")
        
        // Save token to Firestore for the current user
        saveFCMToken(token)
        
        // Subscribe to topics
        subscribeToTopics()
    }
    
    // MARK: - Token Management
    
    private func saveFCMToken(_ token: String) {
        guard let userId = AuthManager.shared.currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
            "platform": "ios"
        ]) { error in
            if let error = error {
                print("Error saving FCM token: \(error)")
            }
        }
    }
    
    private func subscribeToTopics() {
        // Subscribe to announcements topic
        Messaging.messaging().subscribe(toTopic: "announcements") { error in
            if let error = error {
                print("Error subscribing to announcements: \(error)")
            } else {
                print("Subscribed to announcements topic")
            }
        }
    }
    
    // MARK: - Notification Handling
    
    private func handleNotification(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        
        switch type {
        case "schedule_published":
            // Navigate to schedule view
            NotificationCenter.default.post(name: .schedulePublished, object: nil)
            
        case "time_off_approved":
            // Navigate to time off view
            NotificationCenter.default.post(name: .timeOffStatusChanged, object: nil, userInfo: ["approved": true])
            
        case "time_off_denied":
            // Navigate to time off view
            NotificationCenter.default.post(name: .timeOffStatusChanged, object: nil, userInfo: ["approved": false])
            
        case "shift_reminder":
            // Show shift details
            if let shiftId = userInfo["shiftId"] as? String {
                NotificationCenter.default.post(name: .shiftReminder, object: nil, userInfo: ["shiftId": shiftId])
            }
            
        case "announcement":
            // Show announcement
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

// MARK: - Firebase Imports

import FirebaseFirestore
