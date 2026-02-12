import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import '../models/time_off_entry.dart';
import '../services/auto_sync_service.dart';

class TimeOffDao {
  Future<Database> get _db async => AppDatabase.instance.db;

  // ------------------------------------------------------------
  // GET ALL TIME OFF
  // ------------------------------------------------------------
  Future<List<TimeOffEntry>> getAllTimeOff() async {
    final db = await _db;
    final result = await db.query('time_off', orderBy: 'date ASC');
    return result.map((row) => TimeOffEntry.fromMap(row)).toList();
  }

  // ------------------------------------------------------------
  // GET ALL TIME OFF RAW (without expanding, for editing/deletion)
  // ------------------------------------------------------------
  Future<List<TimeOffEntry>> getAllTimeOffRaw() async {
    final db = await _db;
    final result = await db.query('time_off', orderBy: 'date ASC');
    return result.map((row) => TimeOffEntry.fromMap(row)).toList();
  }

  // ------------------------------------------------------------
  // GET ALL TIME OFF FOR A MONTH
  // ------------------------------------------------------------
  Future<List<TimeOffEntry>> getAllTimeOffForMonth(int year, int month) async {
    final db = await _db;

    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);

    final result = await db.query(
      'time_off',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        monthStart.toIso8601String(),
        monthEnd.toIso8601String(),
      ],
      orderBy: 'date ASC',
    );

    return result.map((row) => TimeOffEntry.fromMap(row)).toList();
  }

  // ------------------------------------------------------------
  // INSERT
  // ------------------------------------------------------------
  Future<int> insertTimeOff(TimeOffEntry entry) async {
    final db = await _db;
    final id = await db.insert('time_off', entry.toMap());
    
    // Notify auto-sync service of the change
    AutoSyncService.instance.onTimeOffDataChanged();
    
    return id;
  }

  // ------------------------------------------------------------
  // UPDATE
  // ------------------------------------------------------------
  Future<int> updateTimeOff(TimeOffEntry entry) async {
    final db = await _db;
    if (entry.id == null) throw Exception("Missing ID");
    final result = await db.update(
      'time_off',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    
    // Notify auto-sync service of the change
    AutoSyncService.instance.onTimeOffDataChanged();
    
    return result;
  }

  // ------------------------------------------------------------
  // DELETE
  // ------------------------------------------------------------
  Future<int> deleteTimeOff(int id) async {
    final db = await _db;
    final result = await db.delete(
      'time_off',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    // Notify auto-sync service of the change
    AutoSyncService.instance.onTimeOffDataChanged();
    
    return result;
  }

  // ------------------------------------------------------------
  // INSERT RANGE (one row per day)
  // ------------------------------------------------------------
  Future<List<int>> insertTimeOffRange({
    required int employeeId,
    required DateTime startDate,
    required DateTime endDate,
    required String timeOffType,
    required int totalHours,
    required String vacationGroupId,
    bool isAllDay = true,
    String? startTime,
    String? endTime,
  }) async {
    final db = await _db;
    final dayCount = endDate.difference(startDate).inDays + 1;
    final hoursPerDay = dayCount > 0 ? (totalHours / dayCount).round() : totalHours;

    final List<int> ids = [];
    var current = DateTime(startDate.year, startDate.month, startDate.day);
    final endNorm = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(endNorm)) {
      final id = await db.insert('time_off', {
        'employeeId': employeeId,
        'date': current.toIso8601String(),
        'endDate': null,
        'timeOffType': timeOffType,
        'hours': hoursPerDay > 0 ? hoursPerDay : 8,
        'vacationGroupId': vacationGroupId,
        'isAllDay': isAllDay ? 1 : 0,
        'startTime': startTime,
        'endTime': endTime,
      });
      ids.add(id);
      current = DateTime(current.year, current.month, current.day + 1);
    }

    AutoSyncService.instance.onTimeOffDataChanged();
    return ids;
  }

  // ------------------------------------------------------------
  // DELETE VACATION GROUP
  // ------------------------------------------------------------
  Future<int> deleteVacationGroup(String groupId) async {
    final db = await _db;
    final result = await db.delete(
      'time_off',
      where: 'vacationGroupId = ?',
      whereArgs: [groupId],
    );
    
    // Notify auto-sync service of the change
    AutoSyncService.instance.onTimeOffDataChanged();
    
    return result;
  }

  // ------------------------------------------------------------
  // CHECK FOR EXISTING TIME OFF IN RANGE
  // ------------------------------------------------------------
  Future<bool> hasTimeOffInRange(int employeeId, DateTime start, DateTime end) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM time_off
      WHERE employeeId = ?
        AND date >= ?
        AND date <= ?
    ''', [employeeId, start.toIso8601String(), end.toIso8601String()]);

    final total = result.first['total'] as num?;
    return (total?.toInt() ?? 0) > 0;
  }

  // ------------------------------------------------------------
  // GET ENTRIES BY VACATION GROUP
  // ------------------------------------------------------------
  Future<List<TimeOffEntry>> getEntriesByGroup(String groupId) async {
    final db = await _db;
    final result = await db.query(
      'time_off',
      where: 'vacationGroupId = ?',
      whereArgs: [groupId],
      orderBy: 'date ASC',
    );

    return result.map((row) => TimeOffEntry.fromMap(row)).toList();
  }

  // ------------------------------------------------------------
  // PTO HOURS USED IN RANGE
  // ------------------------------------------------------------
  Future<int> getPtoUsedInRange(
      int employeeId, DateTime start, DateTime end) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT SUM(hours) AS total
      FROM time_off
      WHERE employeeId = ?
        AND date >= ?
        AND date <= ?
        AND timeOffType = 'pto'
    ''', [
      employeeId,
      start.toIso8601String(),
      end.toIso8601String(),
    ]);

    final total = result.first['total'] as num?;
    return total?.toInt() ?? 0;
  }

  // ------------------------------------------------------------
  // GET ENTRIES IN RANGE (for overlap details)
  // ------------------------------------------------------------
  Future<List<TimeOffEntry>> getTimeOffInRange(int employeeId, DateTime start, DateTime end) async {
    final db = await _db;

    final result = await db.query(
      'time_off',
      where: 'employeeId = ? AND date >= ? AND date <= ?',
      whereArgs: [employeeId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date ASC',
    );

    return result.map((row) => TimeOffEntry.fromMap(row)).toList();
  }
}
