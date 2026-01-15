import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import '../models/shift.dart';

class ShiftDao {
  Future<Database> get _db async => await AppDatabase.instance.db;

  /// Create the shifts table
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employeeId INTEGER NOT NULL,
        startTime TEXT NOT NULL,
        endTime TEXT NOT NULL,
        label TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (employeeId) REFERENCES employees(id) ON DELETE CASCADE
      )
    ''');
    
    // Create index for faster queries by employee and date
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shifts_employee_date 
      ON shifts(employeeId, startTime)
    ''');
  }

  /// Insert a new shift
  Future<int> insert(Shift shift) async {
    final db = await _db;
    return await db.insert('shifts', shift.toMap());
  }

  /// Update an existing shift
  Future<int> update(Shift shift) async {
    final db = await _db;
    return await db.update(
      'shifts',
      shift.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [shift.id],
    );
  }

  /// Delete a shift by ID
  Future<int> delete(int id) async {
    final db = await _db;
    return await db.delete('shifts', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all shifts for an employee on a specific date
  Future<int> deleteByEmployeeAndDate(int employeeId, DateTime date) async {
    final db = await _db;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    return await db.delete(
      'shifts',
      where: 'employeeId = ? AND startTime >= ? AND startTime < ?',
      whereArgs: [employeeId, startOfDay.toIso8601String(), endOfDay.toIso8601String()],
    );
  }

  /// Get all shifts
  Future<List<Shift>> getAll() async {
    final db = await _db;
    final maps = await db.query('shifts', orderBy: 'startTime ASC');
    return maps.map((m) => Shift.fromMap(m)).toList();
  }

  /// Get shifts for a specific employee
  Future<List<Shift>> getByEmployee(int employeeId) async {
    final db = await _db;
    final maps = await db.query(
      'shifts',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'startTime ASC',
    );
    return maps.map((m) => Shift.fromMap(m)).toList();
  }

  /// Get shifts for a date range (useful for weekly/monthly views)
  Future<List<Shift>> getByDateRange(DateTime start, DateTime end) async {
    final db = await _db;
    final maps = await db.query(
      'shifts',
      where: 'startTime >= ? AND startTime < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'startTime ASC',
    );
    return maps.map((m) => Shift.fromMap(m)).toList();
  }

  /// Get shifts for a specific employee within a date range
  Future<List<Shift>> getByEmployeeAndDateRange(
    int employeeId,
    DateTime start,
    DateTime end,
  ) async {
    final db = await _db;
    final maps = await db.query(
      'shifts',
      where: 'employeeId = ? AND startTime >= ? AND startTime < ?',
      whereArgs: [employeeId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'startTime ASC',
    );
    return maps.map((m) => Shift.fromMap(m)).toList();
  }

  /// Get shifts for a specific day
  Future<List<Shift>> getByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getByDateRange(startOfDay, endOfDay);
  }

  /// Get shifts for a specific week (Sunday to Saturday)
  Future<List<Shift>> getByWeek(DateTime anyDayInWeek) async {
    // Find Sunday of the week
    final sunday = anyDayInWeek.subtract(Duration(days: anyDayInWeek.weekday % 7));
    final startOfWeek = DateTime(sunday.year, sunday.month, sunday.day);
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    return getByDateRange(startOfWeek, endOfWeek);
  }

  /// Get shifts for a specific month
  Future<List<Shift>> getByMonth(int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1);
    return getByDateRange(startOfMonth, endOfMonth);
  }

  /// Check if a shift exists (for conflict detection)
  Future<bool> hasConflict(int employeeId, DateTime start, DateTime end, {int? excludeId}) async {
    final db = await _db;
    String where = 'employeeId = ? AND startTime < ? AND endTime > ?';
    List<dynamic> whereArgs = [employeeId, end.toIso8601String(), start.toIso8601String()];
    
    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }
    
    final result = await db.query(
      'shifts',
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Bulk insert shifts (useful for copy week functionality)
  Future<void> insertAll(List<Shift> shifts) async {
    final db = await _db;
    final batch = db.batch();
    for (var shift in shifts) {
      batch.insert('shifts', shift.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Delete all shifts in a date range (useful for clearing a week)
  Future<int> deleteByDateRange(DateTime start, DateTime end) async {
    final db = await _db;
    return await db.delete(
      'shifts',
      where: 'startTime >= ? AND startTime < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
  }
}
