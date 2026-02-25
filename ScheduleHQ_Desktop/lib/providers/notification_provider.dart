import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_item.dart';
import '../services/auth_service.dart';
import '../utils/app_constants.dart';
import 'base_provider.dart';

class NotificationProvider extends BaseProvider {
  List<NotificationItem> _notifications = [];
  Set<String> _seenDocIds = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  bool _isPanelOpen = false;
  bool _newNotificationArrived = false;

  List<NotificationItem> get notifications => List.of(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get hasUnread => unreadCount > 0;
  bool get isPanelOpen => _isPanelOpen;
  bool get newNotificationArrived => _newNotificationArrived;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load seen doc IDs
      final seenList = prefs.getStringList(AppConstants.seenNotificationIdsKey);
      _seenDocIds = seenList != null ? Set<String>.from(seenList) : {};

      // Load persisted notifications
      final jsonStr = prefs.getString(AppConstants.notificationsKey);
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _notifications = list
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList();
        // Sort newest first
        _notifications.sort((a, b) => b.arrivedAt.compareTo(a.arrivedAt));
      }

      setLoadingState(LoadingState.success);
    } catch (e) {
      debugPrint('NotificationProvider.initialize error: $e');
      setLoadingState(LoadingState.error, error: e.toString());
    }
  }

  void startPolling() {
    stopPolling();
    final uid = AuthService.instance.currentUserUid;
    if (uid == null) return;

    _subscription = FirebaseFirestore.instance
        .collection('managers')
        .doc(uid)
        .collection('timeOff')
        .snapshots()
        .listen(
          (snapshot) => _handleSnapshot(snapshot, uid),
          onError: (e) => debugPrint('Notification stream error: $e'),
        );
  }

  void stopPolling() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handleSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot, String uid) async {
    try {
      final currentDocIds = snapshot.docs.map((d) => d.id).toSet();
      final newItems = <NotificationItem>[];

      for (final doc in snapshot.docs) {
        final docId = doc.id;
        if (_seenDocIds.contains(docId)) continue;

        final data = doc.data();
        final status = (data['status'] as String?)?.toLowerCase() ?? '';
        final autoApproved = data['autoApproved'] as bool? ?? false;

        // Notify on pending requests from employees, or entries that were
        // auto-approved by the system (employee-submitted, not manager-created)
        final isNotifiable = status == 'pending' ||
            (status == 'approved' && autoApproved);

        if (!isNotifiable) {
          _seenDocIds.add(docId);
          continue;
        }

        // Resolve employee name
        final employeeName = (data['employeeName'] as String?) ??
            (data['name'] as String?) ??
            'Unknown Employee';

        final timeOffType =
            (data['type'] as String?) ?? (data['timeOffType'] as String?) ?? 'pto';

        final date = (data['date'] as String?) ??
            (data['startDate'] as String?) ??
            '';
        final endDate = data['endDate'] as String?;

        newItems.add(NotificationItem(
          id: docId,
          employeeName: employeeName,
          timeOffType: timeOffType,
          date: date,
          endDate: endDate,
          status: status,
          arrivedAt: DateTime.now(),
        ));

        _seenDocIds.add(docId);
      }

      if (newItems.isNotEmpty) {
        _notifications = [...newItems, ..._notifications];
        // Sort newest first
        _notifications.sort((a, b) => b.arrivedAt.compareTo(a.arrivedAt));
        _newNotificationArrived = true;
        await _persist();
        notifyListeners();
        // Reset one-shot flag after frame
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _newNotificationArrived = false;
        });
      }

      // Prune stale seen IDs: keep only those present in current snapshot
      // or still in our notifications list (so deleting a notification doesn't
      // re-trigger it on next poll)
      final notifIds = _notifications.map((n) => n.id).toSet();
      _seenDocIds.retainWhere(
          (id) => currentDocIds.contains(id) || notifIds.contains(id));

      // Always persist updated seenIds
      await _persistSeenIds();
    } catch (e) {
      debugPrint('NotificationProvider._handleSnapshot error: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    _notifications[idx] = _notifications[idx].copyWith(isRead: true);
    await _persist();
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteNotification(String id) async {
    _notifications = _notifications.where((n) => n.id != id).toList();
    // Keep id in _seenDocIds so it doesn't re-appear on next poll
    await _persist();
    notifyListeners();
  }

  void togglePanel() {
    _isPanelOpen = !_isPanelOpen;
    notifyListeners();
  }

  void closePanel() {
    if (_isPanelOpen) {
      _isPanelOpen = false;
      notifyListeners();
    }
  }

  @override
  Future<void> refresh() async {
    final uid = AuthService.instance.currentUserUid;
    if (uid == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('managers')
        .doc(uid)
        .collection('timeOff')
        .get();
    await _handleSnapshot(snapshot, uid);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr =
          jsonEncode(_notifications.map((n) => n.toJson()).toList());
      await prefs.setString(AppConstants.notificationsKey, jsonStr);
      await _persistSeenIds();
    } catch (e) {
      debugPrint('NotificationProvider._persist error: $e');
    }
  }

  Future<void> _persistSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          AppConstants.seenNotificationIdsKey, _seenDocIds.toList());
    } catch (e) {
      debugPrint('NotificationProvider._persistSeenIds error: $e');
    }
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
