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

  ApprovalProvider() {
    _ptoService = PtoTrimesterService(timeOffDao: _timeOffDao);
  }

  // Getters
  List<TimeOffEntry> get approvedEntries => List.unmodifiable(_approvedEntries);
  Map<int, Employee> get employeeById => Map.unmodifiable(_employeeById);

  String? get _managerUid => AuthService.instance.currentUserUid;

  CollectionReference<Map<String, dynamic>>? get _requestsRef {
    final uid = _managerUid;
    return uid != null
        ? FirebaseFirestore.instance
            .collection('managers')
            .doc(uid)
            .collection('time_off_requests')
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

  /// Get pending time-off requests from Firestore
  Stream<QuerySnapshot<Map<String, dynamic>>>? getPendingRequestsStream() {
    return _requestsRef?.where('status', isEqualTo: 'pending').snapshots();
  }

  /// Approve a time-off request
  Future<bool> approveRequest(
    DocumentSnapshot<Map<String, dynamic>> doc,
    app_models.Settings settings,
  ) async {
    try {
      final data = doc.data();
      if (data == null) return false;

      final employeeId = data['employee_id'] as int?;
      if (employeeId == null) return false;

      final employee = _employeeById[employeeId];
      if (employee == null) return false;

      // Calculate PTO validation if needed
      final timeOffType = data['time_off_type'] as String? ?? 'pto';
      if (timeOffType == 'pto') {
        final isValid = await _validatePtoRequest(data, employee, settings);
        if (!isValid) {
          setErrorMessage('PTO request would exceed available hours');
          return false;
        }
      }

      // Create time-off entry
      final entry = _createTimeOffEntryFromFirestore(data);
      
      // Add to local database
      await _timeOffDao.insertTimeOff(entry);

      // Update Firestore document status
      await doc.reference.update({
        'status': 'approved',
        'approved_at': FieldValue.serverTimestamp(),
      });

      // Sync to Firestore for employee app
      await FirestoreSyncService.instance.syncTimeOffEntry(entry, employee);

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
        'denial_reason': reason,
        'denied_at': FieldValue.serverTimestamp(),
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

      // Delete from local database
      await _timeOffDao.deleteTimeOff(entry.id!);

      // Delete from Firestore employee sync
      await FirestoreSyncService.instance.deleteTimeOffEntry(entry.employeeId, entry.id!);

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
      final startDate = (data['start_date'] as Timestamp).toDate();
      final endDate = data['end_date'] != null 
          ? (data['end_date'] as Timestamp).toDate()
          : startDate;
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
    final startDate = (data['start_date'] as Timestamp).toDate();
    final endDate = data['end_date'] != null 
        ? (data['end_date'] as Timestamp).toDate()
        : null;

    return TimeOffEntry(
      id: null,
      employeeId: data['employee_id'] as int,
      date: startDate,
      endDate: endDate,
      timeOffType: data['time_off_type'] as String? ?? 'pto',
      hours: data['hours'] as int? ?? 8,
      isAllDay: data['is_all_day'] as bool? ?? true,
      startTime: data['start_time'] as String?,
      endTime: data['end_time'] as String?,
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

  @override
  Future<void> refresh() async {
    await loadApprovedEntries();
  }
}