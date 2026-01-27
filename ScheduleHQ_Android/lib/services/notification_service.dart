import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

/// Service for handling Firebase Cloud Messaging (FCM) push notifications.
/// 
/// This service:
/// - Requests notification permissions
/// - Retrieves and stores FCM tokens
/// - Handles foreground/background notification events
/// 
/// Note: Actual notification triggers are NOT implemented yet.
/// This is just the framework for future notifications.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _initialized = false;
  String? _currentToken;

  /// Get the current FCM token
  String? get currentToken => _currentToken;

  /// Initialize the notification service.
  /// Should be called after Firebase is initialized and user is logged in.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request permission (required for iOS, optional but recommended for Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      log('Notification permission: ${settings.authorizationStatus}', 
          name: 'NotificationService');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get the FCM token
        await _getAndSaveToken();

        // Listen for token refresh
        _messaging.onTokenRefresh.listen(_onTokenRefresh);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);

        // Handle background message taps (when app is in background)
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

        _initialized = true;
        log('Notification service initialized', name: 'NotificationService');
      } else {
        log('Notification permission denied', name: 'NotificationService');
      }
    } catch (e) {
      log('Error initializing notifications: $e', name: 'NotificationService');
    }
  }

  /// Get the FCM token and save it to Firestore
  Future<void> _getAndSaveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        _currentToken = token;
        await _saveTokenToFirestore(token);
        log('FCM Token obtained', name: 'NotificationService');
      }
    } catch (e) {
      log('Error getting FCM token: $e', name: 'NotificationService');
    }
  }

  /// Handle token refresh
  void _onTokenRefresh(String token) {
    log('FCM Token refreshed', name: 'NotificationService');
    _currentToken = token;
    _saveTokenToFirestore(token);
  }

  /// Save the FCM token to Firestore (linked to the current user)
  Future<void> _saveTokenToFirestore(String token) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      log('Cannot save token - no user logged in', name: 'NotificationService');
      return;
    }

    try {
      // Get user document to find managerUid and employeeId
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        log('Cannot save token - user document not found', name: 'NotificationService');
        return;
      }

      final userData = userDoc.data()!;
      final managerUid = userData['managerUid'] as String?;
      final employeeId = userData['employeeId'];

      if (managerUid == null || employeeId == null) {
        log('Cannot save token - user document missing managerUid or employeeId', 
            name: 'NotificationService');
        return;
      }

      // Save token to the employee document under manager's subcollection
      await _firestore
          .collection('managers')
          .doc(managerUid)
          .collection('employees')
          .doc(employeeId.toString())
          .update({
            'fcmToken': token,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          });

      log('FCM token saved to Firestore', name: 'NotificationService');
    } catch (e) {
      log('Error saving FCM token: $e', name: 'NotificationService');
    }
  }

  /// Handle foreground messages (app is open)
  void _onForegroundMessage(RemoteMessage message) {
    log('Foreground message received: ${message.notification?.title}', 
        name: 'NotificationService');
    
    // TODO: Show in-app notification or snackbar
    // For now, just log it
    
    final notification = message.notification;
    if (notification != null) {
      log('Title: ${notification.title}', name: 'NotificationService');
      log('Body: ${notification.body}', name: 'NotificationService');
    }

    // Handle data payload
    if (message.data.isNotEmpty) {
      log('Data: ${message.data}', name: 'NotificationService');
      _handleNotificationData(message.data);
    }
  }

  /// Handle notification tap when app was in background
  void _onMessageOpenedApp(RemoteMessage message) {
    log('Notification opened app: ${message.notification?.title}', 
        name: 'NotificationService');
    
    // Handle navigation based on notification type
    if (message.data.isNotEmpty) {
      _handleNotificationData(message.data);
    }
  }

  /// Process notification data payload
  void _handleNotificationData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    
    switch (type) {
      case 'schedule_published':
        // TODO: Navigate to schedule page
        log('Schedule published notification', name: 'NotificationService');
        break;
      case 'time_off_approved':
        // TODO: Navigate to time off page
        log('Time off approved notification', name: 'NotificationService');
        break;
      case 'time_off_denied':
        // TODO: Navigate to time off page
        log('Time off denied notification', name: 'NotificationService');
        break;
      default:
        log('Unknown notification type: $type', name: 'NotificationService');
    }
  }

  /// Check if there was a notification that launched the app
  Future<void> checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      log('App launched from notification', name: 'NotificationService');
      _handleNotificationData(initialMessage.data);
    }
  }

  /// Remove FCM token (call on logout)
  Future<void> removeToken() async {
    final user = AuthService.instance.currentUser;
    final token = _currentToken;

    if (user != null && token != null) {
      try {
        // Remove token from Firestore
        await _firestore
            .collection('employees')
            .doc(user.uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();

        log('FCM token removed from Firestore', name: 'NotificationService');
      } catch (e) {
        log('Error removing FCM token: $e', name: 'NotificationService');
      }
    }

    // Delete the token from FCM
    await _messaging.deleteToken();
    _currentToken = null;
    _initialized = false;
  }

  /// Subscribe to a topic (for broadcast notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      log('Subscribed to topic: $topic', name: 'NotificationService');
    } catch (e) {
      log('Error subscribing to topic: $e', name: 'NotificationService');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      log('Unsubscribed from topic: $topic', name: 'NotificationService');
    } catch (e) {
      log('Error unsubscribing from topic: $e', name: 'NotificationService');
    }
  }
}

/// Types of notifications that can be sent
/// (for reference when implementing triggers later)
enum NotificationType {
  /// New schedule has been published
  schedulePublished,
  
  /// Time-off request was approved
  timeOffApproved,
  
  /// Time-off request was denied
  timeOffDenied,
  
  /// Reminder about upcoming shift
  shiftReminder,
  
  /// General announcement from manager
  announcement,
}
