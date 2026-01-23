import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:work_schedule_app/database/app_database.dart';
import 'package:work_schedule_app/models/employee.dart';
import 'package:work_schedule_app/models/shift.dart';
import 'package:work_schedule_app/models/time_off_entry.dart';

/// Service for syncing data between local SQLite and Firestore.
/// 
/// Sync Strategy:
/// - Employee roster: Auto-sync on changes (create/update/delete)
/// - Schedules: Manual "Publish to Employees" action
/// - Time-off entries: Auto-sync approved entries
class FirestoreSyncService {
  static final FirestoreSyncService _instance = FirestoreSyncService._internal();
  static FirestoreSyncService get instance => _instance;

  FirestoreSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // Collection references
  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _firestore.collection('employees');
  
  CollectionReference<Map<String, dynamic>> get _shiftsRef =>
      _firestore.collection('shifts');
  
  CollectionReference<Map<String, dynamic>> get _timeOffRef =>
      _firestore.collection('timeOff');
  
  CollectionReference<Map<String, dynamic>> get _publishedSchedulesRef =>
      _firestore.collection('publishedSchedules');

  // ============== EMPLOYEE ACCOUNT SYNC ==============
  
  /// Call Cloud Function to create Firebase Auth accounts for all employees.
  /// This sets up UIDs for employees that were created before Cloud Functions existed.
  Future<Map<String, dynamic>> syncAllEmployeeAccounts() async {
    try {
      log('Calling syncAllEmployeeAccounts Cloud Function...', name: 'FirestoreSyncService');
      
      final callable = _functions.httpsCallable('syncAllEmployeeAccounts');
      final result = await callable.call();
      
      final data = Map<String, dynamic>.from(result.data as Map);
      log('Sync result: $data', name: 'FirestoreSyncService');
      
      // After Cloud Function updates Firestore, sync UIDs to local DB
      await syncEmployeeUidsFromFirestore();
      
      return data;
    } catch (e) {
      log('Error calling syncAllEmployeeAccounts: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  // ============== EMPLOYEE ROSTER SYNC ==============
  
  /// Sync a single employee to Firestore.
  /// Called automatically when employee is created or updated.
  Future<void> syncEmployee(Employee employee) async {
    if (employee.id == null) {
      log('Cannot sync employee without ID', name: 'FirestoreSyncService');
      return;
    }

    try {
      final docRef = _employeesRef.doc(employee.id.toString());
      
      await docRef.set({
        'localId': employee.id,
        'name': employee.name,
        'jobCode': employee.jobCode,
        'email': employee.email,
        'uid': employee.uid,
        'vacationWeeksAllowed': employee.vacationWeeksAllowed,
        'vacationWeeksUsed': employee.vacationWeeksUsed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      log('Synced employee ${employee.name} to Firestore', 
          name: 'FirestoreSyncService');
    } catch (e) {
      log('Error syncing employee: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Sync all employees to Firestore.
  Future<void> syncAllEmployees() async {
    try {
      final db = await AppDatabase.instance.db;
      final maps = await db.query('employees');
      final employees = maps.map((m) => Employee.fromMap(m)).toList();
      
      final batch = _firestore.batch();
      
      for (final employee in employees) {
        if (employee.id == null) continue;
        
        final docRef = _employeesRef.doc(employee.id.toString());
        batch.set(docRef, {
          'localId': employee.id,
          'name': employee.name,
          'jobCode': employee.jobCode,
          'email': employee.email,
          'uid': employee.uid,
          'vacationWeeksAllowed': employee.vacationWeeksAllowed,
          'vacationWeeksUsed': employee.vacationWeeksUsed,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
      log('Synced ${employees.length} employees to Firestore', 
          name: 'FirestoreSyncService');
    } catch (e) {
      log('Error syncing all employees: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Delete an employee from Firestore.
  Future<void> deleteEmployee(int employeeId) async {
    try {
      await _employeesRef.doc(employeeId.toString()).delete();
      
      // Also delete their shifts and time-off
      final shiftsQuery = await _shiftsRef
          .where('employeeLocalId', isEqualTo: employeeId)
          .get();
      
      final timeOffQuery = await _timeOffRef
          .where('employeeLocalId', isEqualTo: employeeId)
          .get();
      
      final batch = _firestore.batch();
      for (final doc in shiftsQuery.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in timeOffQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      log('Deleted employee $employeeId from Firestore', 
          name: 'FirestoreSyncService');
    } catch (e) {
      log('Error deleting employee from Firestore: $e', 
          name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Sync employee UIDs from Firestore back to local database.
  /// This pulls UIDs that were set by Cloud Functions when accounts were created.
  Future<int> syncEmployeeUidsFromFirestore() async {
    try {
      final db = await AppDatabase.instance.db;
      
      // Get all employees from Firestore
      final snapshot = await _employeesRef.get();
      
      int updatedCount = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final localId = data['localId'] as int?;
        final uid = data['uid'] as String?;
        
        if (localId != null && uid != null) {
          // Update local database with the UID
          final result = await db.update(
            'employees',
            {'uid': uid},
            where: 'id = ? AND (uid IS NULL OR uid != ?)',
            whereArgs: [localId, uid],
          );
          
          if (result > 0) {
            updatedCount++;
            log('Synced UID for employee $localId', name: 'FirestoreSyncService');
          }
        }
      }
      
      log('Synced $updatedCount employee UIDs from Firestore', 
          name: 'FirestoreSyncService');
      return updatedCount;
    } catch (e) {
      log('Error syncing employee UIDs: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  // ============== SCHEDULE PUBLISHING ==============
  
  /// Publish shifts for a date range to Firestore.
  /// This is the manual "Publish to Employees" action.
  Future<PublishResult> publishSchedule({
    required DateTime startDate,
    required DateTime endDate,
    List<int>? employeeIds, // If null, publish for all employees
  }) async {
    try {
      // First, sync employee UIDs from Firestore to ensure we have the latest
      await syncEmployeeUidsFromFirestore();
      
      final db = await AppDatabase.instance.db;
      
      // Build query for shifts in the date range
      String whereClause = "date(startTime) >= date(?) AND date(startTime) <= date(?)";
      List<dynamic> whereArgs = [
        startDate.toIso8601String().split('T')[0],
        endDate.toIso8601String().split('T')[0],
      ];
      
      if (employeeIds != null && employeeIds.isNotEmpty) {
        final placeholders = employeeIds.map((_) => '?').join(',');
        whereClause += " AND employeeId IN ($placeholders)";
        whereArgs.addAll(employeeIds);
      }
      
      final shiftMaps = await db.query(
        'shifts',
        where: whereClause,
        whereArgs: whereArgs,
      );
      
      final shifts = shiftMaps.map((m) => Shift.fromMap(m)).toList();
      
      if (shifts.isEmpty) {
        return PublishResult(
          success: true,
          shiftsPublished: 0,
          message: 'No shifts found in the selected date range',
        );
      }
      
      // Get employee info for all shifts
      final employeeIdsInShifts = shifts.map((s) => s.employeeId).toSet();
      final employeeMaps = await db.query(
        'employees',
        where: 'id IN (${employeeIdsInShifts.map((_) => '?').join(',')})',
        whereArgs: employeeIdsInShifts.toList(),
      );
      final employeeMap = {
        for (final m in employeeMaps)
          m['id'] as int: Employee.fromMap(m)
      };
      
      // Create a batch operation
      final batch = _firestore.batch();
      final publishedAt = FieldValue.serverTimestamp();
      final publishId = DateTime.now().millisecondsSinceEpoch.toString();
      
      int publishedCount = 0;
      int skippedNoUid = 0;
      
      for (final shift in shifts) {
        if (shift.id == null) continue;
        
        final employee = employeeMap[shift.employeeId];
        if (employee == null) continue;
        
        // Skip employees without UID - they won't be able to see their schedule
        if (employee.uid == null || employee.uid!.isEmpty) {
          skippedNoUid++;
          log('Skipping shift for ${employee.name} - no Firebase UID (email: ${employee.email})', 
              name: 'FirestoreSyncService');
          continue;
        }
        
        final docRef = _shiftsRef.doc('${shift.employeeId}_${shift.id}');
        
        batch.set(docRef, {
          'localId': shift.id,
          'employeeLocalId': shift.employeeId,
          'employeeUid': employee.uid,
          'employeeName': employee.name,
          'startTime': Timestamp.fromDate(shift.startTime),
          'endTime': Timestamp.fromDate(shift.endTime),
          'label': shift.label,
          'notes': shift.notes,
          'publishedAt': publishedAt,
          'publishId': publishId,
          'date': shift.startTime.toIso8601String().split('T')[0],
        });
        
        publishedCount++;
      }
      
      // Record the publish event
      batch.set(_publishedSchedulesRef.doc(publishId), {
        'startDate': startDate.toIso8601String().split('T')[0],
        'endDate': endDate.toIso8601String().split('T')[0],
        'employeeIds': employeeIds,
        'shiftsCount': publishedCount,
        'publishedAt': publishedAt,
      });
      
      await batch.commit();
      
      log('Published $publishedCount shifts to Firestore (skipped $skippedNoUid without UID)', 
          name: 'FirestoreSyncService');
      
      String message = 'Successfully published $publishedCount shifts';
      if (skippedNoUid > 0) {
        message += '\n⚠️ $skippedNoUid shifts skipped (employees without Firebase accounts)';
      }
      
      return PublishResult(
        success: true,
        shiftsPublished: publishedCount,
        message: message,
      );
    } catch (e) {
      log('Error publishing schedule: $e', name: 'FirestoreSyncService');
      return PublishResult(
        success: false,
        shiftsPublished: 0,
        message: 'Error publishing schedule: $e',
      );
    }
  }

  /// Get the last publish info for a date range.
  Future<Map<String, dynamic>?> getLastPublishInfo({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final query = await _publishedSchedulesRef
          .where('startDate', isLessThanOrEqualTo: endDate.toIso8601String().split('T')[0])
          .where('endDate', isGreaterThanOrEqualTo: startDate.toIso8601String().split('T')[0])
          .orderBy('publishedAt', descending: true)
          .limit(1)
          .get();
      
      if (query.docs.isEmpty) return null;
      
      return query.docs.first.data();
    } catch (e) {
      log('Error getting publish info: $e', name: 'FirestoreSyncService');
      return null;
    }
  }

  // ============== TIME OFF SYNC ==============
  
  /// Sync a time-off entry to Firestore.
  /// Called when manager approves or enters time-off.
  Future<void> syncTimeOffEntry(TimeOffEntry entry, Employee employee) async {
    if (entry.id == null) {
      log('Cannot sync time-off entry without ID', name: 'FirestoreSyncService');
      return;
    }

    try {
      final docRef = _timeOffRef.doc('${entry.employeeId}_${entry.id}');
      
      await docRef.set({
        'localId': entry.id,
        'employeeLocalId': entry.employeeId,
        'employeeUid': employee.uid,
        'employeeName': employee.name,
        'date': entry.date.toIso8601String().split('T')[0],
        'timeOffType': entry.timeOffType,
        'hours': entry.hours,
        'vacationGroupId': entry.vacationGroupId,
        'isAllDay': entry.isAllDay,
        'startTime': entry.startTime,
        'endTime': entry.endTime,
        'status': 'approved', // Manager-entered time-off is pre-approved
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      log('Synced time-off entry to Firestore', name: 'FirestoreSyncService');
    } catch (e) {
      log('Error syncing time-off entry: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Delete a time-off entry from Firestore.
  Future<void> deleteTimeOffEntry(int employeeId, int entryId) async {
    try {
      await _timeOffRef.doc('${employeeId}_$entryId').delete();
      log('Deleted time-off entry from Firestore', name: 'FirestoreSyncService');
    } catch (e) {
      log('Error deleting time-off entry: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Sync all time-off for a date range.
  Future<void> syncAllTimeOff({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final db = await AppDatabase.instance.db;
      
      final timeOffMaps = await db.query(
        'time_off',
        where: "date >= ? AND date <= ?",
        whereArgs: [
          startDate.toIso8601String().split('T')[0],
          endDate.toIso8601String().split('T')[0],
        ],
      );
      
      final entries = timeOffMaps.map((m) => TimeOffEntry.fromMap(m)).toList();
      
      // Get employees
      final employeeIds = entries.map((e) => e.employeeId).toSet();
      final employeeMaps = await db.query(
        'employees',
        where: 'id IN (${employeeIds.map((_) => '?').join(',')})',
        whereArgs: employeeIds.toList(),
      );
      final employeeMap = {
        for (final m in employeeMaps)
          m['id'] as int: Employee.fromMap(m)
      };
      
      final batch = _firestore.batch();
      
      for (final entry in entries) {
        if (entry.id == null) continue;
        final employee = employeeMap[entry.employeeId];
        if (employee == null) continue;
        
        final docRef = _timeOffRef.doc('${entry.employeeId}_${entry.id}');
        batch.set(docRef, {
          'localId': entry.id,
          'employeeLocalId': entry.employeeId,
          'employeeUid': employee.uid,
          'employeeName': employee.name,
          'date': entry.date.toIso8601String().split('T')[0],
          'timeOffType': entry.timeOffType,
          'hours': entry.hours,
          'vacationGroupId': entry.vacationGroupId,
          'isAllDay': entry.isAllDay,
          'startTime': entry.startTime,
          'endTime': entry.endTime,
          'status': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
      log('Synced ${entries.length} time-off entries to Firestore', 
          name: 'FirestoreSyncService');
    } catch (e) {
      log('Error syncing all time-off: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  // ============== TIME-OFF REQUESTS (from employees) ==============
  
  /// Listen to pending time-off requests from employees.
  Stream<List<TimeOffRequest>> watchPendingRequests() {
    return _firestore
        .collection('timeOffRequests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TimeOffRequest.fromFirestore(doc))
            .toList());
  }

  /// Approve a time-off request.
  Future<void> approveTimeOffRequest(String requestId) async {
    try {
      final requestDoc = await _firestore
          .collection('timeOffRequests')
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        throw Exception('Request not found');
      }
      
      final data = requestDoc.data()!;
      
      // Update request status
      await requestDoc.reference.update({
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      
      // Create approved time-off entry
      await _timeOffRef.doc(requestId).set({
        'localId': null, // Will be set when synced to manager app
        'employeeLocalId': data['employeeLocalId'],
        'employeeUid': data['employeeUid'],
        'employeeName': data['employeeName'],
        'date': data['date'],
        'timeOffType': data['timeOffType'],
        'hours': data['hours'],
        'vacationGroupId': data['vacationGroupId'],
        'isAllDay': data['isAllDay'],
        'startTime': data['startTime'],
        'endTime': data['endTime'],
        'status': 'approved',
        'requestId': requestId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      log('Approved time-off request: $requestId', name: 'FirestoreSyncService');
    } catch (e) {
      log('Error approving request: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Deny a time-off request.
  Future<void> denyTimeOffRequest(String requestId, {String? reason}) async {
    try {
      await _firestore
          .collection('timeOffRequests')
          .doc(requestId)
          .update({
            'status': 'denied',
            'denialReason': reason,
            'reviewedAt': FieldValue.serverTimestamp(),
          });
      
      log('Denied time-off request: $requestId', name: 'FirestoreSyncService');
    } catch (e) {
      log('Error denying request: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Get count of pending requests.
  Future<int> getPendingRequestCount() async {
    try {
      final snapshot = await _firestore
          .collection('timeOffRequests')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      log('Error getting pending count: $e', name: 'FirestoreSyncService');
      return 0;
    }
  }
}

/// Result of a schedule publish operation.
class PublishResult {
  final bool success;
  final int shiftsPublished;
  final String message;

  PublishResult({
    required this.success,
    required this.shiftsPublished,
    required this.message,
  });
}

/// Time-off request from an employee.
class TimeOffRequest {
  final String id;
  final int employeeLocalId;
  final String? employeeUid;
  final String employeeName;
  final DateTime date;
  final String timeOffType;
  final int hours;
  final String? vacationGroupId;
  final bool isAllDay;
  final String? startTime;
  final String? endTime;
  final String status; // pending, approved, denied
  final String? denialReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  TimeOffRequest({
    required this.id,
    required this.employeeLocalId,
    this.employeeUid,
    required this.employeeName,
    required this.date,
    required this.timeOffType,
    required this.hours,
    this.vacationGroupId,
    required this.isAllDay,
    this.startTime,
    this.endTime,
    required this.status,
    this.denialReason,
    required this.createdAt,
    this.reviewedAt,
  });

  factory TimeOffRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TimeOffRequest(
      id: doc.id,
      employeeLocalId: data['employeeLocalId'] ?? 0,
      employeeUid: data['employeeUid'],
      employeeName: data['employeeName'] ?? 'Unknown',
      date: DateTime.parse(data['date']),
      timeOffType: data['timeOffType'] ?? 'pto',
      hours: data['hours'] ?? 0,
      vacationGroupId: data['vacationGroupId'],
      isAllDay: data['isAllDay'] ?? true,
      startTime: data['startTime'],
      endTime: data['endTime'],
      status: data['status'] ?? 'pending',
      denialReason: data['denialReason'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';
}
