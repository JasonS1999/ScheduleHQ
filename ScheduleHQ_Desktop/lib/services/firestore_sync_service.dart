import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:schedulehq_desktop/database/app_database.dart';
import 'package:schedulehq_desktop/database/time_off_dao.dart';
import 'package:schedulehq_desktop/models/employee.dart';
import 'package:schedulehq_desktop/models/shift.dart';
import 'package:schedulehq_desktop/models/time_off_entry.dart';
import 'auth_service.dart';

/// Service for syncing data between local SQLite and Firestore.
///
/// All data is stored per-manager using subcollections under their UID.
/// This allows each manager to have their own roster, schedules, and time-off.
///
/// Sync Strategy:
/// - Employee roster: Auto-sync on changes (create/update/delete)
/// - Schedules: Manual "Publish to Employees" action
/// - Time-off entries: Auto-sync approved entries
class FirestoreSyncService {
  static final FirestoreSyncService _instance =
      FirestoreSyncService._internal();
  static FirestoreSyncService get instance => _instance;

  FirestoreSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Get the current manager's UID
  String? get _managerUid => AuthService.instance.currentUserUid;

  /// Get the manager's document reference
  DocumentReference<Map<String, dynamic>>? get _managerDocRef {
    final uid = _managerUid;
    if (uid == null) return null;
    return _firestore.collection('managers').doc(uid);
  }

  // Collection references (per-manager subcollections)
  CollectionReference<Map<String, dynamic>>? get _employeesRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('employees');
  }

  // Shifts are now organized by month: managers/{uid}/schedules/{YYYY-MM}/shifts
  CollectionReference<Map<String, dynamic>>? _shiftsRefForMonth(String yearMonth) {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('schedules').doc(yearMonth).collection('shifts');
  }

  /// Get reference to the schedules collection (contains month subdocuments)
  CollectionReference<Map<String, dynamic>>? get _schedulesRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('schedules');
  }

  /// Get month string (YYYY-MM) from a date
  String _getMonthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  CollectionReference<Map<String, dynamic>>? get _timeOffRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('timeOff');
  }

  // Note: timeOffRequests has been consolidated into timeOff collection
  // All requests (pending, approved, denied) now live in timeOff
  // Note: publishedSchedules collection has been removed - publish state is tracked via 'published' field on shifts

  CollectionReference<Map<String, dynamic>>? get _shiftRunnersRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('shiftRunners');
  }

  CollectionReference<Map<String, dynamic>>? get _employeeAvailabilityRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('employeeAvailability');
  }

  CollectionReference<Map<String, dynamic>>? get _weeklyTemplatesRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('weeklyTemplates');
  }

  CollectionReference<Map<String, dynamic>>? get _shiftTemplatesRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('shiftTemplates');
  }

  CollectionReference<Map<String, dynamic>>? get _scheduleNotesRef {
    final ref = _managerDocRef;
    if (ref == null) return null;
    return ref.collection('scheduleNotes');
  }

  // ============== EMPLOYEE ACCOUNT SYNC ==============

  /// Sync employee accounts by triggering Firestore document updates.
  /// This works on all platforms (including Windows) by touching employee documents
  /// which triggers the onEmployeeUpdatedInManager Cloud Function.
  Future<Map<String, dynamic>> syncAllEmployeeAccounts() async {
    final uid = _managerUid;
    if (uid == null) {
      throw Exception('Not logged in');
    }

    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      throw Exception('Not logged in');
    }

    try {
      log(
        'Syncing employee accounts via Firestore triggers...',
        name: 'FirestoreSyncService',
      );

      // Get all employees without UIDs
      final snapshot = await employeesRef.get();
      
      int total = snapshot.docs.length;
      int needsSync = 0;
      int triggered = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final existingUid = data['uid'] as String?;
        
        // If already has UID, skip
        if (existingUid != null && existingUid.isNotEmpty) {
          continue;
        }
        
        needsSync++;
        
        // Touch the document to trigger onEmployeeUpdatedInManager
        // The Cloud Function will create the account
        await doc.reference.update({
          'syncRequestedAt': FieldValue.serverTimestamp(),
        });
        triggered++;
        
        log(
          'Triggered sync for employee ${doc.id}',
          name: 'FirestoreSyncService',
        );
      }

      // Wait a moment for Cloud Functions to process
      if (triggered > 0) {
        log(
          'Waiting for Cloud Functions to process $triggered employees...',
          name: 'FirestoreSyncService',
        );
        await Future.delayed(const Duration(seconds: 3));
      }

      // Sync UIDs back to local DB
      final syncedCount = await syncEmployeeUidsFromFirestore();

      final result = {
        'total': total,
        'needsSync': needsSync,
        'triggered': triggered,
        'syncedToLocal': syncedCount,
      };
      
      log('Sync result: $result', name: 'FirestoreSyncService');
      return result;
    } catch (e) {
      log(
        'Error syncing employee accounts: $e',
        name: 'FirestoreSyncService',
      );
      rethrow;
    }
  }

  // ============== EMPLOYEE ROSTER SYNC ==============

  /// Sync a single employee to Firestore.
  /// Called automatically when employee is created or updated.
  Future<void> syncEmployee(Employee employee) async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      log('Cannot sync employee - not logged in', name: 'FirestoreSyncService');
      return;
    }

    if (employee.id == null) {
      log('Cannot sync employee without ID', name: 'FirestoreSyncService');
      return;
    }

    try {
      final docRef = employeesRef.doc(employee.id.toString());

      final data = <String, dynamic>{
        'localId': employee.id,
        'name': employee.name,
        'jobCode': employee.jobCode,
        'email': employee.email,
        'vacationWeeksAllowed': employee.vacationWeeksAllowed,
        'vacationWeeksUsed': employee.vacationWeeksUsed,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // Only set uid if we have one locally - don't overwrite server-created UIDs
      if (employee.uid != null) {
        data['uid'] = employee.uid;
      }

      await docRef.set(data, SetOptions(merge: true));

      log(
        'Synced employee ${employee.name} to Firestore',
        name: 'FirestoreSyncService',
      );
    } catch (e) {
      log('Error syncing employee: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Sync all employees to Firestore.
  Future<void> syncAllEmployees() async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      log(
        'Cannot sync employees - not logged in',
        name: 'FirestoreSyncService',
      );
      return;
    }

    try {
      final db = await AppDatabase.instance.db;
      final maps = await db.query('employees');
      final employees = maps.map((m) => Employee.fromMap(m)).toList();

      final batch = _firestore.batch();

      for (final employee in employees) {
        if (employee.id == null) continue;

        final docRef = employeesRef.doc(employee.id.toString());
        final data = <String, dynamic>{
          'localId': employee.id,
          'name': employee.name,
          'jobCode': employee.jobCode,
          'email': employee.email,
          'vacationWeeksAllowed': employee.vacationWeeksAllowed,
          'vacationWeeksUsed': employee.vacationWeeksUsed,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        // Only set uid if we have one locally - don't overwrite server-created UIDs
        if (employee.uid != null) {
          data['uid'] = employee.uid;
        }
        batch.set(docRef, data, SetOptions(merge: true));
      }

      await batch.commit();
      log(
        'Synced ${employees.length} employees to Firestore',
        name: 'FirestoreSyncService',
      );

      // Trigger UID creation for employees without UIDs
      await triggerUidCreationForEmployees();
    } catch (e) {
      log('Error syncing all employees: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Trigger Firebase function to create UIDs for employees without them.
  /// The onDocumentUpdated function will create accounts when it sees no UID.
  Future<void> triggerUidCreationForEmployees() async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) return;

    try {
      // Find employees without UIDs
      final snapshot = await employeesRef.where('uid', isNull: true).get();
      
      if (snapshot.docs.isEmpty) {
        log('All employees have UIDs', name: 'FirestoreSyncService');
        return;
      }

      log(
        'Found ${snapshot.docs.length} employees without UIDs, triggering creation...',
        name: 'FirestoreSyncService',
      );

      // Touch each document to trigger the onDocumentUpdated function
      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'uidRequested': FieldValue.serverTimestamp(),
        });
      }

      log(
        'Triggered UID creation for ${snapshot.docs.length} employees',
        name: 'FirestoreSyncService',
      );
    } catch (e) {
      log('Error triggering UID creation: $e', name: 'FirestoreSyncService');
    }
  }

  /// Delete an employee from Firestore.
  Future<void> deleteEmployee(int employeeId) async {
    final employeesRef = _employeesRef;
    final timeOffRef = _timeOffRef;
    final schedulesRef = _schedulesRef;

    if (employeesRef == null || schedulesRef == null || timeOffRef == null) {
      log(
        'Cannot delete employee - not logged in',
        name: 'FirestoreSyncService',
      );
      return;
    }

    try {
      await employeesRef.doc(employeeId.toString()).delete();

      // Get all months and delete shifts for this employee
      final monthsSnapshot = await schedulesRef.get();
      final batch = _firestore.batch();
      
      for (final monthDoc in monthsSnapshot.docs) {
        final shiftsRef = schedulesRef.doc(monthDoc.id).collection('shifts');
        final shiftsQuery = await shiftsRef
            .where('employeeLocalId', isEqualTo: employeeId)
            .get();
        for (final doc in shiftsQuery.docs) {
          batch.delete(doc.reference);
        }
      }

      final timeOffQuery = await timeOffRef
          .where('employeeLocalId', isEqualTo: employeeId)
          .get();

      for (final doc in timeOffQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      log(
        'Deleted employee $employeeId from Firestore',
        name: 'FirestoreSyncService',
      );
    } catch (e) {
      log(
        'Error deleting employee from Firestore: $e',
        name: 'FirestoreSyncService',
      );
      rethrow;
    }
  }

  /// Check if a UID looks like a valid Firebase Auth UID
  /// Firebase UIDs are typically 28 characters of alphanumeric characters
  bool _isValidFirebaseUid(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    // Firebase UIDs are typically 28 chars, alphanumeric
    // Invalid UIDs: "Admin", "admin", short strings, etc.
    if (uid.length < 20) return false;
    if (uid.toLowerCase() == 'admin') return false;
    // Must be alphanumeric (Firebase UIDs use base64-like chars)
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(uid);
  }

  /// Clear invalid UIDs from Firestore employees collection.
  /// Call this to fix employees with corrupted UIDs like "Admin".
  /// @deprecated Use [fixInvalidEmployeeUids] instead.
  Future<int> clearInvalidEmployeeUids() async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      log('Cannot clear UIDs - not logged in', name: 'FirestoreSyncService');
      return 0;
    }

    try {
      final snapshot = await employeesRef.get();
      int clearedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        
        if (uid != null && !_isValidFirebaseUid(uid)) {
          // Clear the invalid UID
          await doc.reference.update({'uid': FieldValue.delete()});
          clearedCount++;
          log(
            'Cleared invalid UID "$uid" from employee ${data['name']}',
            name: 'FirestoreSyncService',
          );
        }
      }

      log('Cleared $clearedCount invalid UIDs', name: 'FirestoreSyncService');
      return clearedCount;
    } catch (e) {
      log('Error clearing invalid UIDs: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Fix invalid employee UIDs by clearing them in Firestore.
  /// This preserves all employee data including role, just clears the invalid UID.
  /// Returns a map with 'fixed', 'alreadyValid', and 'noUid' counts.
  Future<Map<String, dynamic>> fixInvalidEmployeeUids() async {
    if (_managerUid == null) {
      log('Cannot fix UIDs - not logged in', name: 'FirestoreSyncService');
      return {'error': 'Not logged in'};
    }

    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      log('Cannot fix UIDs - employees ref is null', name: 'FirestoreSyncService');
      return {'error': 'Not logged in'};
    }

    try {
      final snapshot = await employeesRef.get();
      int fixed = 0;
      int alreadyValid = 0;
      int noUid = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        
        if (uid == null || uid.isEmpty) {
          noUid++;
        } else if (!_isValidFirebaseUid(uid)) {
          // Clear invalid UID but preserve all other fields including role
          await doc.reference.update({'uid': FieldValue.delete()});
          final name = data['firstName'] ?? data['name'] ?? doc.id;
          log('Cleared invalid UID "$uid" for employee $name (role preserved)', 
              name: 'FirestoreSyncService');
          fixed++;
        } else {
          alreadyValid++;
        }
      }
      
      final result = {
        'fixed': fixed,
        'alreadyValid': alreadyValid,
        'noUid': noUid,
      };
      
      log('Fix UIDs result: $result', name: 'FirestoreSyncService');
      return result;
    } catch (e) {
      log('Error fixing UIDs: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Update all shifts in Firestore for employees with corrected UIDs.
  /// Call this after clearing invalid UIDs and the employee has a new valid UID.
  Future<int> refreshShiftEmployeeUids() async {
    final schedulesRef = _schedulesRef;
    final employeesRef = _employeesRef;
    if (schedulesRef == null || employeesRef == null) {
      log('Cannot refresh shift UIDs - not logged in', name: 'FirestoreSyncService');
      return 0;
    }

    try {
      // Get all employees with valid UIDs
      final employeesSnapshot = await employeesRef.get();
      final employeeUidMap = <int, String>{};
      
      for (final doc in employeesSnapshot.docs) {
        final data = doc.data();
        final localId = data['localId'] as int?;
        final uid = data['uid'] as String?;
        if (localId != null && _isValidFirebaseUid(uid)) {
          employeeUidMap[localId] = uid!;
        }
      }

      // Get all months and update shifts with invalid/mismatched UIDs
      final monthsSnapshot = await schedulesRef.get();
      int updatedCount = 0;

      for (final monthDoc in monthsSnapshot.docs) {
        final shiftsRef = schedulesRef.doc(monthDoc.id).collection('shifts');
        final shiftsSnapshot = await shiftsRef.get();
        final batch = _firestore.batch();
        int batchCount = 0;
        
        for (final doc in shiftsSnapshot.docs) {
          final data = doc.data();
          final employeeLocalId = data['employeeLocalId'] as int?;
          final currentUid = data['employeeUid'] as String?;
          
          if (employeeLocalId != null) {
            final correctUid = employeeUidMap[employeeLocalId];
            
            // Update if current UID is invalid or doesn't match
            if (correctUid != null && currentUid != correctUid) {
              batch.update(doc.reference, {'employeeUid': correctUid});
              batchCount++;
            }
          }
        }

        if (batchCount > 0) {
          await batch.commit();
          updatedCount += batchCount;
        }
      }

      log('Updated $updatedCount shifts with corrected UIDs', name: 'FirestoreSyncService');
      return updatedCount;
    } catch (e) {
      log('Error refreshing shift UIDs: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Sync employee UIDs from Firestore back to local database.
  /// This pulls UIDs that were set by Cloud Functions when accounts were created.
  Future<int> syncEmployeeUidsFromFirestore() async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) {
      log('Cannot sync UIDs - not logged in', name: 'FirestoreSyncService');
      return 0;
    }

    try {
      final db = await AppDatabase.instance.db;

      // Get all employees from Firestore
      final snapshot = await employeesRef.get();

      int updatedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final localId = data['localId'] as int?;
        final uid = data['uid'] as String?;

        // Only sync valid Firebase UIDs
        if (localId != null && _isValidFirebaseUid(uid)) {
          // Update local database with the UID
          final result = await db.update(
            'employees',
            {'uid': uid},
            where: 'id = ? AND (uid IS NULL OR uid != ?)',
            whereArgs: [localId, uid],
          );

          if (result > 0) {
            updatedCount++;
            log(
              'Synced UID for employee $localId',
              name: 'FirestoreSyncService',
            );
          }
        }
      }

      log(
        'Synced $updatedCount employee UIDs from Firestore',
        name: 'FirestoreSyncService',
      );
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
    if (_managerDocRef == null) {
      return PublishResult(
        success: false,
        shiftsPublished: 0,
        message: 'Not logged in',
      );
    }

    try {
      // First, sync employee UIDs from Firestore to ensure we have the latest
      await syncEmployeeUidsFromFirestore();

      final db = await AppDatabase.instance.db;

      // Build query for shifts in the date range
      String whereClause =
          "date(startTime) >= date(?) AND date(startTime) <= date(?)";
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
        for (final m in employeeMaps) m['id'] as int: Employee.fromMap(m),
      };

      // Group shifts by month for the new structure
      final shiftsByMonth = <String, List<Shift>>{};
      for (final shift in shifts) {
        final monthKey = _getMonthKey(shift.startTime);
        shiftsByMonth.putIfAbsent(monthKey, () => []).add(shift);
      }

      final publishId = DateTime.now().millisecondsSinceEpoch.toString();

      int publishedCount = 0;
      int skippedNoUid = 0;
      final Set<String> publishedUids = {};

      // Process each month
      for (final entry in shiftsByMonth.entries) {
        final monthKey = entry.key;
        final monthShifts = entry.value;
        final shiftsRef = _shiftsRefForMonth(monthKey);
        if (shiftsRef == null) continue;

        final batch = _firestore.batch();

        for (final shift in monthShifts) {
          if (shift.id == null) continue;

          final employee = employeeMap[shift.employeeId];
          if (employee == null) continue;

          // Skip employees without UID - they won't be able to see their schedule
          if (employee.uid == null || employee.uid!.isEmpty) {
            skippedNoUid++;
            log(
              'Skipping shift for ${employee.name} - no Firebase UID (email: ${employee.email})',
              name: 'FirestoreSyncService',
            );
            continue;
          }

          final docRef = shiftsRef.doc('${shift.employeeId}_${shift.id}');

          batch.set(docRef, {
            'localId': shift.id,
            'employeeLocalId': shift.employeeId,
            'employeeUid': employee.uid,
            'employeeName': employee.name,
            'startTime': Timestamp.fromDate(shift.startTime),
            'endTime': Timestamp.fromDate(shift.endTime),
            'label': shift.label,
            'notes': shift.notes,
            'date': shift.startTime.toIso8601String().split('T')[0],
            'month': monthKey,
            'managerUid': _managerUid,
          });

          publishedCount++;
          publishedUids.add(employee.uid!);
        }

        await batch.commit();
      }

      log(
        'Published $publishedCount shifts to Firestore (skipped $skippedNoUid without UID)',
        name: 'FirestoreSyncService',
      );

      String message = 'Successfully published $publishedCount shifts';
      if (skippedNoUid > 0) {
        message +=
            '\n⚠️ $skippedNoUid shifts skipped (employees without Firebase accounts)';
      }

      return PublishResult(
        success: true,
        shiftsPublished: publishedCount,
        message: message,
        publishedEmployeeUids: publishedUids.toList(),
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
  /// NOTE: publishedSchedules collection has been removed - this now returns null
  Future<Map<String, dynamic>?> getLastPublishInfo({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // publishedSchedules collection removed - no longer tracking publish history
    return null;
  }

  /// Unpublish shifts for a date range.
  /// This DELETES shifts from Firestore, making them invisible to employees.
  /// The shifts still exist in the local database.
  Future<PublishResult> unpublishSchedule({
    required DateTime startDate,
    required DateTime endDate,
    List<int>? employeeIds, // If null, unpublish for all employees
  }) async {
    if (_managerDocRef == null) {
      return PublishResult(
        success: false,
        shiftsPublished: 0,
        message: 'Not logged in',
      );
    }

    try {
      // Get all months in the date range
      final months = <String>{};
      var current = DateTime(startDate.year, startDate.month);
      final lastMonth = DateTime(endDate.year, endDate.month);
      while (!current.isAfter(lastMonth)) {
        months.add(_getMonthKey(current));
        current = DateTime(current.year, current.month + 1);
      }

      int deletedCount = 0;

      for (final monthKey in months) {
        final shiftsRef = _shiftsRefForMonth(monthKey);
        if (shiftsRef == null) continue;

        // Query shifts in date range
        var query = shiftsRef
            .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String().split('T')[0])
            .where('date', isLessThanOrEqualTo: endDate.toIso8601String().split('T')[0]);

        final snapshot = await query.get();

        final batch = _firestore.batch();
        int batchCount = 0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          // Skip if employee filter is specified and this employee isn't in it
          if (employeeIds != null && employeeIds.isNotEmpty) {
            final empId = data['employeeLocalId'] as int?;
            if (empId == null || !employeeIds.contains(empId)) continue;
          }

          batch.delete(doc.reference);
          batchCount++;
        }

        if (batchCount > 0) {
          await batch.commit();
          deletedCount += batchCount;
        }
      }

      log(
        'Unpublished (deleted) $deletedCount shifts from Firestore',
        name: 'FirestoreSyncService',
      );

      return PublishResult(
        success: true,
        shiftsPublished: deletedCount,
        message: 'Successfully unpublished $deletedCount shifts',
      );
    } catch (e) {
      log('Error unpublishing schedule: $e', name: 'FirestoreSyncService');
      return PublishResult(
        success: false,
        shiftsPublished: 0,
        message: 'Error unpublishing schedule: $e',
      );
    }
  }

  // ============== TIME OFF SYNC ==============

  /// Sync a time-off entry to Firestore.
  /// Called when manager approves or enters time-off.
  /// Handles both new entries and updates to existing ones.
  Future<void> syncTimeOffEntry(TimeOffEntry entry, Employee employee) async {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) {
      log('Cannot sync time-off - not logged in', name: 'FirestoreSyncService');
      return;
    }

    if (entry.id == null) {
      log(
        'Cannot sync time-off entry without ID',
        name: 'FirestoreSyncService',
      );
      return;
    }

    try {
      // First, find and delete any existing docs for this entry
      // This handles entries that might have different doc IDs (e.g., from Android app)
      final existingDocs = await timeOffRef
          .where('localId', isEqualTo: entry.id)
          .where('employeeLocalId', isEqualTo: entry.employeeId)
          .get();
      
      for (final doc in existingDocs.docs) {
        await doc.reference.delete();
        log('Deleted old time-off doc: ${doc.id}', name: 'FirestoreSyncService');
      }

      // Now create/update with consistent doc ID format
      final docRef = timeOffRef.doc('${entry.employeeId}_${entry.id}');

      // Build the data map, only including endDate if it has a value
      final data = <String, dynamic>{
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
        'managerUid': _managerUid,
      };
      
      // Only set endDate if we have one - don't overwrite with null
      if (entry.endDate != null) {
        data['endDate'] = entry.endDate!.toIso8601String().split('T')[0];
      }

      await docRef.set(data);

      log('Synced time-off entry to Firestore', name: 'FirestoreSyncService');
    } catch (e) {
      log('Error syncing time-off entry: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// One-time migration: rename 'sick' timeOffType to 'requested' in Firestore.
  /// Safe to call multiple times — returns 0 if no 'sick' docs remain.
  Future<int> migrateSickToRequested() async {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) return 0;

    try {
      final snapshot = await timeOffRef
          .where('timeOffType', isEqualTo: 'sick')
          .get();

      if (snapshot.docs.isEmpty) return 0;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'timeOffType': 'requested'});
      }
      await batch.commit();

      log(
        'Migration: Renamed ${snapshot.docs.length} sick entries to requested in Firestore',
        name: 'FirestoreSyncService',
      );
      return snapshot.docs.length;
    } catch (e) {
      log('Error migrating sick to requested: $e', name: 'FirestoreSyncService');
      return 0;
    }
  }

  /// Delete a time-off entry from Firestore.
  /// Deletes from the unified timeOff collection.
  Future<void> deleteTimeOffEntry(int employeeId, int entryId) async {
    final timeOffRef = _timeOffRef;
    
    if (timeOffRef == null) {
      log(
        'Cannot delete time-off - not logged in',
        name: 'FirestoreSyncService',
      );
      return;
    }

    try {
      // Delete from timeOff collection using the standard document ID format
      await timeOffRef.doc('${employeeId}_$entryId').delete();
      log(
        'Deleted time-off entry from Firestore',
        name: 'FirestoreSyncService',
      );
      
      // Also search for any docs with matching localId (for entries created from requests)
      final matchingDocs = await timeOffRef
          .where('localId', isEqualTo: entryId)
          .where('employeeLocalId', isEqualTo: employeeId)
          .get();
      
      for (final doc in matchingDocs.docs) {
        if (doc.id != '${employeeId}_$entryId') {
          await doc.reference.delete();
          log(
            'Deleted matching time-off doc: ${doc.id}',
            name: 'FirestoreSyncService',
          );
        }
      }
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
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) {
      log('Cannot sync time-off - not logged in', name: 'FirestoreSyncService');
      return;
    }

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

      log(
        'Found ${timeOffMaps.length} time-off entries in local DB',
        name: 'FirestoreSyncService',
      );

      final entries = timeOffMaps.map((m) => TimeOffEntry.fromMap(m)).toList();

      if (entries.isEmpty) {
        log('No time-off entries to sync', name: 'FirestoreSyncService');
        return;
      }

      // Get employees
      final employeeIds = entries.map((e) => e.employeeId).toSet();
      final employeeMaps = await db.query(
        'employees',
        where: 'id IN (${employeeIds.map((_) => '?').join(',')})',
        whereArgs: employeeIds.toList(),
      );
      final employeeMap = {
        for (final m in employeeMaps) m['id'] as int: Employee.fromMap(m),
      };

      final batch = _firestore.batch();
      int syncedCount = 0;

      for (final entry in entries) {
        if (entry.id == null) continue;
        final employee = employeeMap[entry.employeeId];
        if (employee == null) {
          log(
            'Skipping time-off entry ${entry.id} - employee ${entry.employeeId} not found',
            name: 'FirestoreSyncService',
          );
          continue;
        }

        final docRef = timeOffRef.doc('${entry.employeeId}_${entry.id}');
        
        // Build the data map, only including endDate if it has a value
        // to avoid overwriting existing endDate in Firestore with null
        final data = <String, dynamic>{
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
          'managerUid': _managerUid,
        };
        
        // Only set endDate if we have one - don't overwrite with null
        if (entry.endDate != null) {
          data['endDate'] = entry.endDate!.toIso8601String().split('T')[0];
        }
        
        batch.set(docRef, data, SetOptions(merge: true));
        syncedCount++;
      }

      if (syncedCount > 0) {
        await batch.commit();
        log(
          'Synced $syncedCount time-off entries to Firestore',
          name: 'FirestoreSyncService',
        );
      } else {
        log('No time-off entries synced (all skipped)', name: 'FirestoreSyncService');
      }
    } catch (e) {
      log('Error syncing all time-off: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  // ============== TIME-OFF REQUESTS (from employees) ==============

  /// Listen to pending time-off requests from employees.
  /// Now uses the unified timeOff collection.
  Stream<List<TimeOffRequest>> watchPendingRequests() {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) {
      return Stream.value([]);
    }

    return timeOffRef
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TimeOffRequest.fromFirestore(doc))
              .toList(),
        );
  }

  /// Approve a time-off request.
  /// Updates the entry in the unified timeOff collection.
  Future<void> approveTimeOffRequest(String requestId) async {
    final timeOffRef = _timeOffRef;

    if (timeOffRef == null) {
      throw Exception('Not logged in');
    }

    try {
      final requestDoc = await timeOffRef.doc(requestId).get();

      if (!requestDoc.exists) {
        throw Exception('Request not found');
      }

      final data = requestDoc.data()!;

      // Parse dates
      final startDate = DateTime.parse(data['date'] as String);
      final endDateStr = data['endDate'] as String?;
      final endDate = endDateStr != null ? DateTime.parse(endDateStr) : null;

      // Insert into local database as a single entry with date range
      final timeOffDao = TimeOffDao();
      final entry = TimeOffEntry(
        id: null,
        employeeId: data['employeeLocalId'] as int,
        date: startDate,
        endDate: endDate,
        timeOffType: data['timeOffType'] as String,
        hours: (data['hours'] as int?) ?? 8,
        vacationGroupId: data['vacationGroupId'] as String?,
        isAllDay: (data['isAllDay'] as bool?) ?? true,
        startTime: data['startTime'] as String?,
        endTime: data['endTime'] as String?,
      );
      final localId = await timeOffDao.insertTimeOff(entry);

      // Update the existing document with approved status and local ID
      await requestDoc.reference.update({
        'localId': localId,
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'managerUid': _managerUid,
      });

      final dayCount = endDate != null ? endDate.difference(startDate).inDays + 1 : 1;
      log(
        'Approved time-off request: $requestId ($dayCount days, local ID: $localId)',
        name: 'FirestoreSyncService',
      );
    } catch (e) {
      log('Error approving request: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Deny a time-off request.
  /// Updates the entry in the unified timeOff collection.
  Future<void> denyTimeOffRequest(String requestId, {String? reason}) async {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) {
      throw Exception('Not logged in');
    }

    try {
      await timeOffRef.doc(requestId).update({
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

  /// Import all approved time-off requests from Firestore to local database.
  /// This is useful for syncing requests that were approved before this feature existed.
  /// Now uses the unified timeOff collection.
  Future<int> importApprovedTimeOffRequests() async {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) {
      log('Cannot import - not logged in', name: 'FirestoreSyncService');
      return 0;
    }

    try {
      final snapshot = await timeOffRef
          .where('status', isEqualTo: 'approved')
          .get();

      final timeOffDao = TimeOffDao();
      int importedCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        
        // Skip if employeeLocalId is missing
        if (data['employeeLocalId'] == null) {
          log('Skipping request ${doc.id}: missing employeeLocalId', name: 'FirestoreSyncService');
          continue;
        }

        // Convert date to ISO format for comparison
        String dateStr = data['date'] as String;
        if (!dateStr.contains('T')) {
          dateStr = DateTime.parse(dateStr).toIso8601String();
        }

        // Check if this entry already exists in local database
        final db = await AppDatabase.instance.db;
        final existing = await db.query(
          'time_off',
          where: 'employeeId = ? AND date = ?',
          whereArgs: [
            data['employeeLocalId'],
            dateStr,
          ],
        );

        if (existing.isNotEmpty) {
          log('Skipping request ${doc.id}: already exists locally', name: 'FirestoreSyncService');
          continue;
        }

        // Insert the approved request into local database
        final entry = TimeOffEntry(
          id: null,
          employeeId: data['employeeLocalId'] as int,
          date: DateTime.parse(data['date'] as String),
          timeOffType: data['timeOffType'] as String,
          hours: (data['hours'] as int?) ?? 8,
          vacationGroupId: data['vacationGroupId'] as String?,
          isAllDay: (data['isAllDay'] as bool?) ?? true,
          startTime: data['startTime'] as String?,
          endTime: data['endTime'] as String?,
        );
        
        final localId = await timeOffDao.insertTimeOff(entry);
        
        // Update the Firestore request with the local ID
        await doc.reference.update({'localId': localId});
        
        importedCount++;
        log('Imported approved request ${doc.id} (local ID: $localId)', name: 'FirestoreSyncService');
      }

      log('Imported $importedCount approved time-off requests', name: 'FirestoreSyncService');
      return importedCount;
    } catch (e) {
      log('Error importing approved requests: $e', name: 'FirestoreSyncService');
      rethrow;
    }
  }

  /// Get count of pending requests.
  /// Now uses the unified timeOff collection.
  Future<int> getPendingRequestCount() async {
    final timeOffRef = _timeOffRef;
    if (timeOffRef == null) return 0;

    try {
      final snapshot = await timeOffRef
          .where('status', isEqualTo: 'pending')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      log('Error getting pending count: $e', name: 'FirestoreSyncService');
      return 0;
    }
  }

  // ============== DATA DOWNLOAD (Cloud to Local) ==============

  /// Download employees and time-off from cloud to local database.
  /// NOTE: Shifts are NOT downloaded - local DB is the source of truth for shifts.
  /// Call this when logging in on a new device.
  Future<void> downloadAllDataFromCloud() async {
    final employeesRef = _employeesRef;
    final timeOffRef = _timeOffRef;

    if (employeesRef == null || timeOffRef == null) {
      throw Exception('Not logged in');
    }

    final db = await AppDatabase.instance.db;

    try {
      // Download employees
      final employeesSnapshot = await employeesRef.get();
      for (final doc in employeesSnapshot.docs) {
        final data = doc.data();
        await db.insert('employees', {
          'id': data['localId'],
          'name': data['name'],
          'jobCode': data['jobCode'],
          'email': data['email'],
          'uid': data['uid'],
          'vacationWeeksAllowed': data['vacationWeeksAllowed'] ?? 0,
          'vacationWeeksUsed': data['vacationWeeksUsed'] ?? 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      log(
        'Downloaded ${employeesSnapshot.docs.length} employees',
        name: 'FirestoreSyncService',
      );

      // NOTE: Shifts are NOT downloaded from cloud
      // Local database is the source of truth for shifts
      // Published shifts in Firestore are only for employee viewing
      log(
        'Shifts not downloaded - local DB is source of truth. Use Publish to push shifts to cloud.',
        name: 'FirestoreSyncService',
      );

      // Download time-off - deduplicate by (employeeId, date) and store with endDate
      final timeOffSnapshot = await timeOffRef.get();
      
      // Group by employeeId + date to remove duplicates
      final Map<String, Map<String, dynamic>> uniqueTimeOff = {};
      for (final doc in timeOffSnapshot.docs) {
        final data = doc.data();
        final employeeLocalId = data['employeeLocalId'] as int?;
        if (employeeLocalId == null) continue;
        
        final dateStr = data['date'] as String;
        final key = '${employeeLocalId}_$dateStr';
        
        // Keep only the first entry for each employee+date combination
        if (!uniqueTimeOff.containsKey(key)) {
          // Use localId if available, otherwise generate one from the key
          int localId;
          if (data['localId'] != null) {
            localId = data['localId'] as int;
          } else {
            // Generate a consistent ID from employeeId + date
            localId = key.hashCode.abs() % 900000 + 100000;
          }
          
          // Convert date to full ISO format for consistency with local storage
          String fullDateStr = dateStr;
          if (!fullDateStr.contains('T')) {
            fullDateStr = DateTime.parse(fullDateStr).toIso8601String();
          }
          
          // Handle endDate for multi-day entries
          String? fullEndDateStr;
          final endDateStr = data['endDate'] as String?;
          if (endDateStr != null) {
            fullEndDateStr = endDateStr.contains('T') 
                ? endDateStr 
                : DateTime.parse(endDateStr).toIso8601String();
          }
          
          uniqueTimeOff[key] = {
            'id': localId,
            'employeeId': employeeLocalId,
            'date': fullDateStr,
            'endDate': fullEndDateStr,
            'timeOffType': data['timeOffType'],
            'hours': data['hours'],
            'vacationGroupId': data['vacationGroupId'],
            'isAllDay': (data['isAllDay'] ?? true) ? 1 : 0,
            'startTime': data['startTime'],
            'endTime': data['endTime'],
          };
        }
      }
      
      // Clear existing time-off and insert deduplicated entries
      await db.delete('time_off');
      for (final entry in uniqueTimeOff.values) {
        await db.insert('time_off', entry, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      
      log(
        'Downloaded ${uniqueTimeOff.length} time-off entries (deduplicated from ${timeOffSnapshot.docs.length})',
        name: 'FirestoreSyncService',
      );

      // Download shift runners
      final shiftRunnersRef = _shiftRunnersRef;
      if (shiftRunnersRef != null) {
        final runnersSnapshot = await shiftRunnersRef.get();
        for (final doc in runnersSnapshot.docs) {
          final data = doc.data();
          await db.insert('shift_runners', {
            'id': data['localId'],
            'date': data['date'],
            'shiftType': data['shiftType'],
            'runnerName': data['runnerName'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        log(
          'Downloaded ${runnersSnapshot.docs.length} shift runners',
          name: 'FirestoreSyncService',
        );
      }

      // Download employee availability
      final availabilityRef = _employeeAvailabilityRef;
      if (availabilityRef != null) {
        final availabilitySnapshot = await availabilityRef.get();
        for (final doc in availabilitySnapshot.docs) {
          final data = doc.data();
          if (data['localId'] == null) continue;
          await db.insert('employee_availability', {
            'id': data['localId'],
            'employeeId': data['employeeId'],
            'availabilityType': data['availabilityType'],
            'dayOfWeek': data['dayOfWeek'],
            'weekNumber': data['weekNumber'],
            'specificDate': data['specificDate'],
            'startTime': data['startTime'],
            'endTime': data['endTime'],
            'allDay': data['allDay'],
            'available': data['available'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        log(
          'Downloaded ${availabilitySnapshot.docs.length} employee availability entries',
          name: 'FirestoreSyncService',
        );
      }

      // Download weekly templates
      final weeklyTemplatesRef = _weeklyTemplatesRef;
      if (weeklyTemplatesRef != null) {
        final weeklySnapshot = await weeklyTemplatesRef.get();
        for (final doc in weeklySnapshot.docs) {
          final data = doc.data();
          if (data['localId'] == null) continue;
          await db.insert('employee_weekly_templates', {
            'id': data['localId'],
            'employeeId': data['employeeId'],
            'dayOfWeek': data['dayOfWeek'],
            'startTime': data['startTime'],
            'endTime': data['endTime'],
            'isOff': data['isOff'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        log(
          'Downloaded ${weeklySnapshot.docs.length} weekly template entries',
          name: 'FirestoreSyncService',
        );
      }

      // Download shift templates
      final shiftTemplatesRef = _shiftTemplatesRef;
      if (shiftTemplatesRef != null) {
        final shiftTemplatesSnapshot = await shiftTemplatesRef.get();
        for (final doc in shiftTemplatesSnapshot.docs) {
          final data = doc.data();
          if (data['localId'] == null) continue;
          await db.insert('shift_templates', {
            'id': data['localId'],
            'templateName': data['templateName'],
            'startTime': data['startTime'],
            'endTime': data['endTime'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        log(
          'Downloaded ${shiftTemplatesSnapshot.docs.length} shift templates',
          name: 'FirestoreSyncService',
        );
      }

      // Download schedule notes
      final scheduleNotesRef = _scheduleNotesRef;
      if (scheduleNotesRef != null) {
        final notesSnapshot = await scheduleNotesRef.get();
        for (final doc in notesSnapshot.docs) {
          final data = doc.data();
          if (data['localId'] == null) continue;
          final now = DateTime.now().toIso8601String();
          await db.insert('schedule_notes', {
            'id': data['localId'],
            'date': data['date'],
            'note': data['note'],
            'createdAt': data['createdAt'] ?? now,
            'updatedAt': data['updatedAt'] ?? now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        log(
          'Downloaded ${notesSnapshot.docs.length} schedule notes',
          name: 'FirestoreSyncService',
        );
      }

      // Note: We don't call importApprovedTimeOffRequests() here because
      // the timeOff subcollection already contains all approved entries.
      // That function is only needed for incremental syncs, not full downloads.
      
    } catch (e) {
      log(
        'Error downloading data from cloud: $e',
        name: 'FirestoreSyncService',
      );
      rethrow;
    }
  }

  /// Check if cloud data exists for this manager
  Future<bool> hasCloudData() async {
    final employeesRef = _employeesRef;
    if (employeesRef == null) return false;

    try {
      final snapshot = await employeesRef.limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      log('Error checking cloud data: $e', name: 'FirestoreSyncService');
      return false;
    }
  }

  /// Upload all local data to cloud (except shifts).
  /// Shifts are only uploaded when explicitly published.
  /// Call this to backup employees, time-off, etc to cloud.
  Future<void> uploadAllDataToCloud() async {
    log('Starting uploadAllDataToCloud...', name: 'FirestoreSyncService');
    
    // Sync employees (needed for UIDs)
    await syncAllEmployees();

    final db = await AppDatabase.instance.db;

    // NOTE: Shifts are NOT synced here - they only go to Firestore when published
    // This keeps local DB as source of truth and avoids sync conflicts
    log('Shifts are not synced to cloud - use Publish to make shifts visible to employees', name: 'FirestoreSyncService');

    // Sync all time-off
    final now = DateTime.now();
    final startOfYear = DateTime(now.year - 1, 1, 1);
    final endOfYear = DateTime(now.year + 1, 12, 31);
    await syncAllTimeOff(startDate: startOfYear, endDate: endOfYear);

    // Sync all shift runners
    final runnerMaps = await db.query('shift_runners');
    if (runnerMaps.isNotEmpty) {
      final shiftRunnersRef = _shiftRunnersRef;
      if (shiftRunnersRef != null) {
        // Build a map of employeeId -> uid for looking up UIDs
        final employeeMaps = await db.query('employees');
        final employeeUidMap = <int, String?>{};
        for (final emp in employeeMaps) {
          final empId = emp['id'] as int?;
          if (empId != null) {
            employeeUidMap[empId] = emp['uid'] as String?;
          }
        }
        
        final batch = _firestore.batch();
        for (final runnerMap in runnerMaps) {
          final id = runnerMap['id'] as int?;
          if (id == null) continue;
          
          final date = runnerMap['date'] as String;
          final shiftType = runnerMap['shiftType'] as String;
          final employeeId = runnerMap['employeeId'] as int?;
          final employeeUid = employeeId != null ? employeeUidMap[employeeId] : null;
          
          final docRef = shiftRunnersRef.doc('${date}_$shiftType');
          batch.set(docRef, {
            'localId': id,
            'date': date,
            'shiftType': shiftType,
            'runnerName': runnerMap['runnerName'],
            'employeeId': employeeId,
            'employeeUid': employeeUid,
            'managerUid': _managerUid,
          });
        }
        await batch.commit();
        log(
          'Uploaded ${runnerMaps.length} shift runners to cloud',
          name: 'FirestoreSyncService',
        );
      }
    }

    // Sync all employee availability
    final availabilityMaps = await db.query('employee_availability');
    if (availabilityMaps.isNotEmpty) {
      final availabilityRef = _employeeAvailabilityRef;
      if (availabilityRef != null) {
        final batch = _firestore.batch();
        for (final avail in availabilityMaps) {
          final id = avail['id'] as int?;
          if (id == null) continue;
          
          final docRef = availabilityRef.doc('$id');
          batch.set(docRef, {
            'localId': id,
            'employeeId': avail['employeeId'],
            'availabilityType': avail['availabilityType'],
            'dayOfWeek': avail['dayOfWeek'],
            'weekNumber': avail['weekNumber'],
            'specificDate': avail['specificDate'],
            'startTime': avail['startTime'],
            'endTime': avail['endTime'],
            'allDay': avail['allDay'],
            'available': avail['available'],
            'managerUid': _managerUid,
          });
        }
        await batch.commit();
        log(
          'Uploaded ${availabilityMaps.length} employee availability entries to cloud',
          name: 'FirestoreSyncService',
        );
      }
    }

    // Sync all weekly templates
    final weeklyTemplateMaps = await db.query('employee_weekly_templates');
    if (weeklyTemplateMaps.isNotEmpty) {
      final weeklyTemplatesRef = _weeklyTemplatesRef;
      if (weeklyTemplatesRef != null) {
        final batch = _firestore.batch();
        for (final template in weeklyTemplateMaps) {
          final id = template['id'] as int?;
          if (id == null) continue;
          
          final docRef = weeklyTemplatesRef.doc('$id');
          batch.set(docRef, {
            'localId': id,
            'employeeId': template['employeeId'],
            'dayOfWeek': template['dayOfWeek'],
            'startTime': template['startTime'],
            'endTime': template['endTime'],
            'isOff': template['isOff'],
            'managerUid': _managerUid,
          });
        }
        await batch.commit();
        log(
          'Uploaded ${weeklyTemplateMaps.length} weekly template entries to cloud',
          name: 'FirestoreSyncService',
        );
      }
    }

    // Sync all shift templates
    final shiftTemplateMaps = await db.query('shift_templates');
    if (shiftTemplateMaps.isNotEmpty) {
      final shiftTemplatesRef = _shiftTemplatesRef;
      if (shiftTemplatesRef != null) {
        final batch = _firestore.batch();
        for (final template in shiftTemplateMaps) {
          final id = template['id'] as int?;
          if (id == null) continue;
          
          final docRef = shiftTemplatesRef.doc('$id');
          batch.set(docRef, {
            'localId': id,
            'templateName': template['templateName'],
            'startTime': template['startTime'],
            'endTime': template['endTime'],
            'managerUid': _managerUid,
          });
        }
        await batch.commit();
        log(
          'Uploaded ${shiftTemplateMaps.length} shift templates to cloud',
          name: 'FirestoreSyncService',
        );
      }
    }

    // Sync all schedule notes
    final scheduleNoteMaps = await db.query('schedule_notes');
    if (scheduleNoteMaps.isNotEmpty) {
      final scheduleNotesRef = _scheduleNotesRef;
      if (scheduleNotesRef != null) {
        final batch = _firestore.batch();
        for (final noteMap in scheduleNoteMaps) {
          final id = noteMap['id'] as int?;
          if (id == null) continue;
          
          final date = noteMap['date'] as String;
          final docRef = scheduleNotesRef.doc(date);
          batch.set(docRef, {
            'localId': id,
            'date': date,
            'note': noteMap['note'],
            'createdAt': noteMap['createdAt'],
            'updatedAt': noteMap['updatedAt'],
            'managerUid': _managerUid,
          });
        }
        await batch.commit();
        log(
          'Uploaded ${scheduleNoteMaps.length} schedule notes to cloud',
          name: 'FirestoreSyncService',
        );
      }
    }

    // Migrate any orphaned entries from root timeOff collection
    await migrateRootTimeOffEntries();

    // Import any approved time-off requests that aren't in local database
    await importApprovedTimeOffRequests();
  }

  /// Migrate time-off entries from root 'timeOff' collection to manager subcollection.
  /// This is a one-time migration for entries created before the fix.
  Future<int> migrateRootTimeOffEntries() async {
    final timeOffRef = _timeOffRef;
    final managerUid = _managerUid;
    
    if (timeOffRef == null || managerUid == null) {
      log('Cannot migrate: not logged in', name: 'FirestoreSyncService');
      return 0;
    }

    try {
      // Query root timeOff collection for entries belonging to this manager's employees
      final rootTimeOffRef = _firestore.collection('timeOff');
      final snapshot = await rootTimeOffRef
          .where('managerUid', isEqualTo: managerUid)
          .get();

      if (snapshot.docs.isEmpty) {
        // Also try to find entries by employeeUid matching our employees
        final employeesRef = _employeesRef;
        if (employeesRef != null) {
          final employeesSnapshot = await employeesRef.get();
          final employeeUids = employeesSnapshot.docs
              .map((doc) => doc.data()['uid'] as String?)
              .where((uid) => uid != null)
              .toSet();

          if (employeeUids.isNotEmpty) {
            // Query for entries matching any of our employee UIDs
            for (final uid in employeeUids) {
              final entriesForEmployee = await rootTimeOffRef
                  .where('employeeUid', isEqualTo: uid)
                  .get();

              for (final doc in entriesForEmployee.docs) {
                await _migrateTimeOffDoc(doc, timeOffRef);
              }
            }
          }
        }
        log('No root timeOff entries to migrate', name: 'FirestoreSyncService');
        return 0;
      }

      int migratedCount = 0;
      for (final doc in snapshot.docs) {
        final migrated = await _migrateTimeOffDoc(doc, timeOffRef);
        if (migrated) migratedCount++;
      }

      log('Migrated $migratedCount time-off entries from root collection', name: 'FirestoreSyncService');
      return migratedCount;
    } catch (e) {
      log('Error migrating root timeOff entries: $e', name: 'FirestoreSyncService');
      return 0;
    }
  }

  /// Helper to migrate a single timeOff document
  Future<bool> _migrateTimeOffDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    CollectionReference<Map<String, dynamic>> targetRef,
  ) async {
    try {
      final data = doc.data();
      if (data == null) return false;

      // Check if already exists in target collection
      final existingQuery = await targetRef
          .where('employeeUid', isEqualTo: data['employeeUid'])
          .where('date', isEqualTo: data['date'])
          .where('timeOffType', isEqualTo: data['timeOffType'])
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        // Already migrated, delete from root
        await doc.reference.delete();
        return false;
      }

      // Copy to manager subcollection
      await targetRef.doc(doc.id).set({
        ...data,
        'managerUid': _managerUid,
        'migratedAt': FieldValue.serverTimestamp(),
      });

      // Delete from root collection
      await doc.reference.delete();
      
      log('Migrated timeOff entry ${doc.id}', name: 'FirestoreSyncService');
      return true;
    } catch (e) {
      log('Error migrating doc ${doc.id}: $e', name: 'FirestoreSyncService');
      return false;
    }
  }
}

/// Result of a schedule publish operation.
class PublishResult {
  final bool success;
  final int shiftsPublished;
  final String message;
  final List<String> publishedEmployeeUids;

  PublishResult({
    required this.success,
    required this.shiftsPublished,
    required this.message,
    this.publishedEmployeeUids = const [],
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

  factory TimeOffRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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
