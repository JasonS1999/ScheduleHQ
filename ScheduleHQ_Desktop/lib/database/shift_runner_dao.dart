import 'package:sqflite/sqflite.dart';
import '../models/shift_runner.dart';
import 'app_database.dart';

class ShiftRunnerDao {
  static const tableName = 'shift_runners';

  Future<Database> get _db async => AppDatabase.instance.db;

  /// Get all shift runners for a date range
  Future<List<ShiftRunner>> getForDateRange(DateTime start, DateTime end) async {
    final db = await _db;
    final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    
    final result = await db.query(
      tableName,
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date ASC',
    );
    
    return result.map((m) => ShiftRunner.fromMap(m)).toList();
  }

  /// Get shift runner for a specific date and shift type
  Future<ShiftRunner?> getForDateAndShift(DateTime date, String shiftType) async {
    final db = await _db;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    final result = await db.query(
      tableName,
      where: 'date = ? AND shiftType = ?',
      whereArgs: [dateStr, shiftType],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return ShiftRunner.fromMap(result.first);
  }

  /// Insert or update a shift runner
  Future<void> upsert(ShiftRunner runner) async {
    final db = await _db;
    final dateStr = '${runner.date.year}-${runner.date.month.toString().padLeft(2, '0')}-${runner.date.day.toString().padLeft(2, '0')}';
    
    // Check if exists
    final existing = await db.query(
      tableName,
      where: 'date = ? AND shiftType = ?',
      whereArgs: [dateStr, runner.shiftType],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      // Update
      await db.update(
        tableName,
        {'runnerName': runner.runnerName, 'employeeId': runner.employeeId},
        where: 'date = ? AND shiftType = ?',
        whereArgs: [dateStr, runner.shiftType],
      );
    } else {
      // Insert
      await db.insert(tableName, runner.toMap());
    }
  }

  /// Delete a shift runner
  Future<void> delete(DateTime date, String shiftType) async {
    final db = await _db;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    await db.delete(
      tableName,
      where: 'date = ? AND shiftType = ?',
      whereArgs: [dateStr, shiftType],
    );
  }

  /// Clear shift runner (set to empty)
  Future<void> clear(DateTime date, String shiftType) async {
    await delete(date, shiftType);
  }

  /// One-time fix: populate employeeId for existing entries by matching runnerName to employee firstName
  Future<int> populateMissingEmployeeIds() async {
    final db = await _db;
    final result = await db.rawUpdate('''
      UPDATE shift_runners 
      SET employeeId = (
        SELECT id FROM employees 
        WHERE employees.firstName = shift_runners.runnerName
        LIMIT 1
      )
      WHERE employeeId IS NULL
    ''');
    return result;
  }
}
