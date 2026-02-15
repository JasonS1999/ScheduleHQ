import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/time_off_entry.dart';
import '../models/employee.dart';
import '../models/settings.dart' as app_models;
import '../services/auth_service.dart';
import '../services/firestore_sync_service.dart';
import '../services/pto_trimester_service.dart';
import '../database/time_off_dao.dart';
import '../database/job_code_settings_dao.dart';
import 'base_provider.dart';

/// Provider for managing approval queue and time-off request workflows
class ApprovalProvider extends BaseProvider {
  final TimeOffDao _timeOffDao = TimeOffDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();
  late final PtoTrimesterService _ptoService;

  // Approval queue data
  List<TimeOffEntry> _approvedEntries = [];
  Map<int, Employee> _employeeById = {};
  final Map<String, Color> _jobCodeColorCache = {};

  // Cached request data (replaces real-time streams to avoid platform thread crash)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingRequests = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _deniedRequests = [];
  bool _isLoadingRequests = false;

  ApprovalProvider() {
    _ptoService = PtoTrimesterService(timeOffDao: _timeOffDao);
  }

  // Getters
  List<TimeOffEntry> get approvedEntries => List.unmodifiable(_approvedEntries);
  Map<int, Employee> get employeeById => Map.unmodifiable(_employeeById);
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get pendingRequests =>
      List.unmodifiable(_pendingRequests);
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get deniedRequests =>
      List.unmodifiable(_deniedRequests);
  bool get isLoadingRequests => _isLoadingRequests;

  String? get _managerUid => AuthService.instance.currentUserUid;

  CollectionReference<Map<String, dynamic>>? get _requestsRef {
    final uid = _managerUid;
    return uid != null
        ? FirebaseFirestore.instance
            .collection('managers')
            .doc(uid)
            .collection('timeOff')
        : null;
  }

  /// Initialize approval provider with employee data
  void initializeEmployees(List<Employee> employees) {
    _employeeById = {for (var e in employees) if (e.id != null) e.id!: e};
    notifyListeners();
  }

  /// Load approved time-off entries from local database
  Future<void> loadApprovedEntries() async {
    await executeWithLoading(() async {
      final entries = await _timeOffDao.getAllTimeOffRaw();
      
      // Filter to only approved entries (those in local database)
      _approvedEntries = entries.where((entry) => entry.id != null).toList();
      
      // Sort by date descending
      _approvedEntries.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  /// Preload job code colors for UI display
  Future<void> preloadJobCodeColors(List<Employee> employees) async {
    for (final e in employees) {
      final code = e.jobCode;
      if (_jobCodeColorCache.containsKey(code)) continue;

      final hex = await _jobCodeSettingsDao.getColorForJobCode(code);
      _jobCodeColorCache[code] = _colorFromHex(hex);
    }
    notifyListeners();
  }

  /// Get cached color for job code
  Color getJobCodeColor(String jobCode) {
    return _jobCodeColorCache[jobCode] ?? const Color(0xFF808080);
  }

  /// Convert hex color string to Color
  Color _colorFromHex(String hexString) {
    try {
      String hex = hexString.replaceAll('#', '').toUpperCase();
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return const Color(0xFF808080); // Default gray
    }
  }

  /// Fetch pending time-off requests from Firestore
  Future<void> fetchPendingRequests() async {
    final ref = _requestsRef;
    if (ref == null) return;
    try {
      _isLoadingRequests = true;
      notifyListeners();
      final snapshot = await ref.where('status', isEqualTo: 'pending').get();
      _pendingRequests = snapshot.docs;
    } catch (e) {
      debugPrint('Error fetching pending requests: $e');
    } finally {
      _isLoadingRequests = false;
      notifyListeners();
    }
  }

  /// Fetch denied time-off requests from Firestore
  Future<void> fetchDeniedRequests() async {
    final ref = _requestsRef;
    if (ref == null) return;
    try {
      _isLoadingRequests = true;
      notifyListeners();
      final snapshot = await ref
          .where('status', isEqualTo: 'denied')
          .orderBy('deniedAt', descending: true)
          .get();
      _deniedRequests = snapshot.docs;
    } catch (e) {
      debugPrint('Error fetching denied requests: $e');
    } finally {
      _isLoadingRequests = false;
      notifyListeners();
    }
  }

  /// Fetch requests based on view type
  Future<void> fetchRequests({required bool denied}) async {
    if (denied) {
      await fetchDeniedRequests();
    } else {
      await fetchPendingRequests();
    }
  }

  /// Manually add a time-off entry (manager-created, bypasses request flow)
  Future<bool> addManualEntry(TimeOffEntry entry, Employee employee) async {
    try {
      if (entry.endDate != null && entry.endDate != entry.date) {
        // Multi-day: expand to individual day rows
        final groupId = entry.vacationGroupId ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await _timeOffDao.insertTimeOffRange(
          employeeId: entry.employeeId,
          startDate: entry.date,
          endDate: entry.endDate!,
          timeOffType: entry.timeOffType,
          totalHours: entry.hours,
          vacationGroupId: groupId,
          isAllDay: entry.isAllDay,
          startTime: entry.startTime,
          endTime: entry.endTime,
        );
        // Sync each individual day to Firestore
        final dayEntries = await _timeOffDao.getEntriesByGroup(groupId);
        for (final dayEntry in dayEntries) {
          await FirestoreSyncService.instance.syncTimeOffEntry(dayEntry, employee);
        }
      } else {
        // Single day: insert as before
        final localId = await _timeOffDao.insertTimeOff(entry);
        final saved = entry.copyWith(id: localId);
        await FirestoreSyncService.instance.syncTimeOffEntry(saved, employee);
      }
      await loadApprovedEntries();
      return true;
    } catch (e) {
      setErrorMessage('Failed to add time-off entry: $e');
      return false;
    }
  }

  /// Approve a time-off request
  Future<bool> approveRequest(
    DocumentSnapshot<Map<String, dynamic>> doc,
    app_models.Settings settings,
  ) async {
    try {
      final data = doc.data();
      if (data == null) return false;

      final employeeId = data['employeeLocalId'] as int?;
      if (employeeId == null) return false;

      final employee = _employeeById[employeeId];
      if (employee == null) return false;

      // Calculate PTO validation if needed
      final timeOffType = data['timeOffType'] as String? ?? 'pto';
      if (timeOffType == 'pto') {
        final isValid = await _validatePtoRequest(data, employee, settings);
        if (!isValid) {
          setErrorMessage('PTO request would exceed available hours');
          return false;
        }
      }

      // Create time-off entry and insert locally
      final entry = _createTimeOffEntryFromFirestore(data);
      final endDateStr = data['endDate'] as String?;
      final endDate = endDateStr != null ? DateTime.parse(endDateStr) : null;

      if (endDate != null && endDate != entry.date) {
        // Multi-day: expand to individual day rows
        final groupId = entry.vacationGroupId ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await _timeOffDao.insertTimeOffRange(
          employeeId: entry.employeeId,
          startDate: entry.date,
          endDate: endDate,
          timeOffType: entry.timeOffType,
          totalHours: entry.hours,
          vacationGroupId: groupId,
          isAllDay: entry.isAllDay,
          startTime: entry.startTime,
          endTime: entry.endTime,
        );
        await doc.reference.delete();
        final dayEntries = await _timeOffDao.getEntriesByGroup(groupId);
        for (final dayEntry in dayEntries) {
          await FirestoreSyncService.instance.syncTimeOffEntry(dayEntry, employee);
        }
      } else {
        // Single day
        final localId = await _timeOffDao.insertTimeOff(entry);
        final saved = entry.copyWith(id: localId);
        await doc.reference.delete();
        await FirestoreSyncService.instance.syncTimeOffEntry(saved, employee);
      }

      // Reload approved entries
      await loadApprovedEntries();

      return true;
    } catch (e) {
      setErrorMessage('Failed to approve request: $e');
      return false;
    }
  }

  /// Deny a time-off request
  Future<bool> denyRequest(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String reason,
  ) async {
    try {
      await doc.reference.update({
        'status': 'denied',
        'denialReason': reason,
        'deniedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      setErrorMessage('Failed to deny request: $e');
      return false;
    }
  }

  /// Delete an approved time-off entry
  Future<bool> deleteApprovedEntry(TimeOffEntry entry) async {
    try {
      if (entry.id == null) return false;

      if (entry.vacationGroupId != null) {
        // Delete all days in the vacation group
        final groupEntries = await _timeOffDao.getEntriesByGroup(entry.vacationGroupId!);
        for (final groupEntry in groupEntries) {
          if (groupEntry.id != null) {
            await FirestoreSyncService.instance.deleteTimeOffEntry(entry.employeeId, groupEntry.id!);
          }
        }
        await _timeOffDao.deleteVacationGroup(entry.vacationGroupId!);
      } else {
        // Single day: delete just this entry
        await _timeOffDao.deleteTimeOff(entry.id!);
        await FirestoreSyncService.instance.deleteTimeOffEntry(entry.employeeId, entry.id!);
      }

      // Reload approved entries
      await loadApprovedEntries();

      return true;
    } catch (e) {
      setErrorMessage('Failed to delete entry: $e');
      return false;
    }
  }

  /// Validate PTO request against available hours
  Future<bool> _validatePtoRequest(
    Map<String, dynamic> data,
    Employee employee,
    app_models.Settings settings,
  ) async {
    try {
      final dateStr = data['date'] as String?;
      if (dateStr == null) return false;
      final startDate = DateTime.parse(dateStr);
      final endDateStr = data['endDate'] as String?;
      final endDate = endDateStr != null ? DateTime.parse(endDateStr) : startDate;
      final hours = data['hours'] as int? ?? 8;

      // Calculate total hours for multi-day requests
      final dayCount = endDate.difference(startDate).inDays + 1;
      final totalHours = dayCount * hours;

      // Check available PTO for the employee
      final availableHours = await _ptoService.getRemainingForDate(
        employee.id!,
        startDate,
      );

      return totalHours <= availableHours;
    } catch (e) {
      debugPrint('PTO validation error: $e');
      return false;
    }
  }

  /// Create TimeOffEntry from Firestore document data
  TimeOffEntry _createTimeOffEntryFromFirestore(Map<String, dynamic> data) {
    final startDate = DateTime.parse(data['date'] as String);
    final endDateStr = data['endDate'] as String?;
    final endDate = endDateStr != null ? DateTime.parse(endDateStr) : null;

    return TimeOffEntry(
      id: null,
      employeeId: data['employeeLocalId'] as int,
      date: startDate,
      endDate: endDate,
      timeOffType: data['timeOffType'] as String? ?? 'pto',
      hours: data['hours'] as int? ?? 8,
      isAllDay: data['isAllDay'] as bool? ?? true,
      startTime: data['startTime'] as String?,
      endTime: data['endTime'] as String?,
    );
  }

  /// Get formatted display string for time-off entry
  String formatTimeOffEntry(TimeOffEntry entry) {
    final employee = _employeeById[entry.employeeId];
    final employeeName = employee?.displayName ?? 'Unknown';
    
    if (entry.endDate != null && entry.endDate != entry.date) {
      // Multi-day entry
      final startStr = _formatDate(entry.date);
      final endStr = _formatDate(entry.endDate!);
      return '$employeeName: ${entry.timeOffType.toUpperCase()} $startStr - $endStr';
    } else {
      // Single day entry
      final dateStr = _formatDate(entry.date);
      if (entry.isAllDay) {
        return '$employeeName: ${entry.timeOffType.toUpperCase()} $dateStr (All Day)';
      } else {
        return '$employeeName: ${entry.timeOffType.toUpperCase()} $dateStr ${entry.startTime} - ${entry.endTime}';
      }
    }
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  /// Get employee name by ID
  String getEmployeeName(int employeeId) {
    return _employeeById[employeeId]?.displayName ?? 'Unknown Employee';
  }

  /// Get employee profile image URL by ID
  String? getEmployeeProfileImageURL(int employeeId) {
    return _employeeById[employeeId]?.profileImageURL;
  }

  @override
  Future<void> refresh() async {
    await loadApprovedEntries();
    await fetchPendingRequests();
    await fetchDeniedRequests();
  }
}