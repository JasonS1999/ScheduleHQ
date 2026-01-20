import 'package:sqflite/sqflite.dart';
import '../models/weekly_template.dart';
import 'app_database.dart';

class WeeklyTemplateDao {
  /// Get all template entries for a specific employee
  Future<List<WeeklyTemplateEntry>> getTemplateForEmployee(int employeeId) async {
    final db = await AppDatabase.instance.db;
    final result = await db.query(
      'employee_weekly_templates',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'dayOfWeek ASC',
    );
    return result.map((row) => WeeklyTemplateEntry.fromMap(row)).toList();
  }

  /// Get template entry for a specific employee and day
  Future<WeeklyTemplateEntry?> getEntryForDay(int employeeId, int dayOfWeek) async {
    final db = await AppDatabase.instance.db;
    final result = await db.query(
      'employee_weekly_templates',
      where: 'employeeId = ? AND dayOfWeek = ?',
      whereArgs: [employeeId, dayOfWeek],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return WeeklyTemplateEntry.fromMap(result.first);
  }

  /// Save or update a template entry for a specific day
  Future<void> saveEntry(WeeklyTemplateEntry entry) async {
    final db = await AppDatabase.instance.db;
    
    // Check if entry exists
    final existing = await db.query(
      'employee_weekly_templates',
      where: 'employeeId = ? AND dayOfWeek = ?',
      whereArgs: [entry.employeeId, entry.dayOfWeek],
      limit: 1,
    );

    if (existing.isEmpty) {
      // Insert new entry
      await db.insert(
        'employee_weekly_templates',
        entry.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      // Update existing entry
      await db.update(
        'employee_weekly_templates',
        entry.toMap()..remove('id'),
        where: 'employeeId = ? AND dayOfWeek = ?',
        whereArgs: [entry.employeeId, entry.dayOfWeek],
      );
    }
  }

  /// Save entire week template for an employee (replaces all existing entries)
  Future<void> saveWeekTemplate(int employeeId, List<WeeklyTemplateEntry> entries) async {
    final db = await AppDatabase.instance.db;
    
    await db.transaction((txn) async {
      // Delete all existing entries for this employee
      await txn.delete(
        'employee_weekly_templates',
        where: 'employeeId = ?',
        whereArgs: [employeeId],
      );
      
      // Insert new entries
      for (final entry in entries) {
        await txn.insert(
          'employee_weekly_templates',
          entry.toMap()..remove('id'),
        );
      }
    });
  }

  /// Delete all template entries for an employee
  Future<void> deleteTemplateForEmployee(int employeeId) async {
    final db = await AppDatabase.instance.db;
    await db.delete(
      'employee_weekly_templates',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
    );
  }

  /// Delete a specific day's entry
  Future<void> deleteEntry(int employeeId, int dayOfWeek) async {
    final db = await AppDatabase.instance.db;
    await db.delete(
      'employee_weekly_templates',
      where: 'employeeId = ? AND dayOfWeek = ?',
      whereArgs: [employeeId, dayOfWeek],
    );
  }

  /// Check if an employee has any template entries
  Future<bool> hasTemplate(int employeeId) async {
    final db = await AppDatabase.instance.db;
    final result = await db.query(
      'employee_weekly_templates',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get all employees who have at least one template entry with a shift
  /// Returns list of employee IDs
  Future<List<int>> getEmployeeIdsWithTemplates() async {
    final db = await AppDatabase.instance.db;
    final result = await db.rawQuery('''
      SELECT DISTINCT employeeId 
      FROM employee_weekly_templates 
      WHERE (startTime IS NOT NULL AND endTime IS NOT NULL) OR isOff = 1
    ''');
    return result.map((row) => row['employeeId'] as int).toList();
  }

  /// Get all template entries for multiple employees at once
  Future<Map<int, List<WeeklyTemplateEntry>>> getTemplatesForEmployees(List<int> employeeIds) async {
    if (employeeIds.isEmpty) return {};
    
    final db = await AppDatabase.instance.db;
    final placeholders = List.filled(employeeIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT * FROM employee_weekly_templates WHERE employeeId IN ($placeholders) ORDER BY employeeId, dayOfWeek',
      employeeIds,
    );
    
    final Map<int, List<WeeklyTemplateEntry>> templates = {};
    for (final row in result) {
      final entry = WeeklyTemplateEntry.fromMap(row);
      templates.putIfAbsent(entry.employeeId, () => []).add(entry);
    }
    return templates;
  }
}
