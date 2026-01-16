import 'package:sqflite/sqflite.dart';
import '../models/job_code_settings.dart';
import 'app_database.dart';

class JobCodeSettingsDao {
  static const tableName = 'job_code_settings';

  Future<Database> get _db async => AppDatabase.instance.db;

  // ------------------------------------------------------------
  // GET ALL (sorted by sortOrder)
  // ------------------------------------------------------------
  Future<List<JobCodeSettings>> getAll() async {
    final db = await _db;
    final result = await db.query(tableName, orderBy: 'sortOrder ASC, code ASC');
    return result.map((m) => JobCodeSettings.fromMap(m)).toList();
  }

  // ------------------------------------------------------------
  // GET BY CODE
  // ------------------------------------------------------------
  Future<JobCodeSettings?> getByCode(String code) async {
    final db = await _db;
    final result = await db.query(
      tableName,
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return JobCodeSettings.fromMap(result.first);
  }

  // ------------------------------------------------------------
  // INSERT DEFAULTS IF MISSING
  // ------------------------------------------------------------
  Future<void> insertDefaultsIfMissing() async {
    final db = await _db;

    final defaults = [
      JobCodeSettings(
        code: 'gm',
        hasPTO: true,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#8E24AA',
        sortOrder: 1,
      ),
      JobCodeSettings(
        code: 'assistant',
        hasPTO: true,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#4285F4',
        sortOrder: 2,
      ),
      JobCodeSettings(
        code: 'swing',
        hasPTO: true,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#DB4437',
        sortOrder: 3,
      ),
      JobCodeSettings(
        code: 'mit',
        hasPTO: true,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#009688',
        sortOrder: 4,
      ),
      JobCodeSettings(
        code: 'breakfast mgr',
        hasPTO: true,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#F4B400',
        sortOrder: 5,
      ),
    ];

    for (final jc in defaults) {
      await db.insert(
        tableName,
        jc.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ------------------------------------------------------------
  // GET COLOR FOR JOB CODE
  // ------------------------------------------------------------
  Future<String> getColorForJobCode(String code) async {
    final db = await _db;

    final result = await db.query(
      tableName,
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final settings = JobCodeSettings.fromMap(result.first);
      if (settings.colorHex.isNotEmpty) {
        return settings.colorHex;
      }
    }

    // fallback defaults
    switch (code.toLowerCase()) {
      case 'assistant':
        return '#4285F4';
      case 'swing':
        return '#DB4437';
      case 'gm':
        return '#8E24AA';
      case 'mit':
        return '#009688';
      case 'breakfast mgr':
        return '#F4B400';
      default:
        return '#4285F4';
    }
  }

  // ------------------------------------------------------------
  // UPSERT
  // ------------------------------------------------------------
  Future<void> upsert(JobCodeSettings settings) async {
    final db = await _db;
    await db.insert(
      tableName,
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------
  // RENAME CODE (handles changing the primary key safely)
  // Returns true when rename succeeds, false if a target code already exists.
  // ------------------------------------------------------------
  /// Renames a job code and updates referencing rows.
  /// Returns the number of employee rows updated, or -1 if the target code already exists.
  Future<int> renameCode(String oldCode, JobCodeSettings newSettings) async {
    if (oldCode == newSettings.code) return 0;
    final db = await _db;
    return await db.transaction<int>((txn) async {
      // Check conflict (case-sensitive)
      final existing = await txn.query(
        tableName,
        where: 'code = ? COLLATE BINARY',
        whereArgs: [newSettings.code],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Target code already exists — abort
        return -1;
      }

      // Insert new row with new code
      await txn.insert(
        tableName,
        newSettings.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update any employees that referenced the old code to point to the new code (case-sensitive match)
      final updated = await txn.update(
        'employees',
        {'jobCode': newSettings.code},
        where: 'jobCode = ? COLLATE BINARY',
        whereArgs: [oldCode],
      );

      // Remove old row (case-sensitive)
      await txn.delete(
        tableName,
        where: 'code = ? COLLATE BINARY',
        whereArgs: [oldCode],
      );

      return updated;
    });
  }

  // ------------------------------------------------------------
  // UPDATE SORT ORDERS
  // ------------------------------------------------------------
  Future<void> updateSortOrders(List<JobCodeSettings> orderedCodes) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedCodes.length; i++) {
        await txn.update(
          tableName,
          {'sortOrder': i + 1},
          where: 'code = ?',
          whereArgs: [orderedCodes[i].code],
        );
      }
    });
  }

  // ------------------------------------------------------------
  // GET NEXT SORT ORDER (for new job codes)
  // ------------------------------------------------------------
  Future<int> getNextSortOrder() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT MAX(sortOrder) as maxOrder FROM $tableName');
    final maxOrder = result.first['maxOrder'] as int? ?? 0;
    return maxOrder + 1;
  }

  // ------------------------------------------------------------
  // USAGE COUNTS (employees + templates)
  // ------------------------------------------------------------
  Future<Map<String, int>> getUsageCounts(String code) async {
    final db = await _db;
    final employeesResult = await db.rawQuery(
      'SELECT COUNT(*) as c FROM employees WHERE jobCode = ? COLLATE NOCASE',
      [code],
    );
    final templatesResult = await db.rawQuery(
      'SELECT COUNT(*) as c FROM shift_templates WHERE jobCode = ? COLLATE NOCASE',
      [code],
    );

    final employeesCount = (employeesResult.first['c'] as int?) ?? 0;
    final templatesCount = (templatesResult.first['c'] as int?) ?? 0;
    return {
      'employees': employeesCount,
      'templates': templatesCount,
    };
  }

  // ------------------------------------------------------------
  // DELETE JOB CODE
  // - If employees reference the code, you must pass reassignEmployeesTo.
  // - Shift templates for the deleted code are always deleted.
  // Returns:
  //  -1 if job code doesn't exist
  //  -2 if employees exist and no reassignment was provided
  //  >=0 number of employees reassigned
  // ------------------------------------------------------------
  Future<int> deleteJobCode(
    String code, {
    String? reassignEmployeesTo,
  }) async {
    final db = await _db;
    return db.transaction<int>((txn) async {
      final existing = await txn.query(
        tableName,
        where: 'code = ? COLLATE NOCASE',
        whereArgs: [code],
        limit: 1,
      );
      if (existing.isEmpty) return -1;

      final employeesResult = await txn.rawQuery(
        'SELECT COUNT(*) as c FROM employees WHERE jobCode = ? COLLATE NOCASE',
        [code],
      );
      final employeesCount = (employeesResult.first['c'] as int?) ?? 0;
      if (employeesCount > 0 && (reassignEmployeesTo == null || reassignEmployeesTo.trim().isEmpty)) {
        return -2;
      }

      int reassigned = 0;
      if (employeesCount > 0) {
        reassigned = await txn.update(
          'employees',
          {'jobCode': reassignEmployeesTo},
          where: 'jobCode = ? COLLATE NOCASE',
          whereArgs: [code],
        );
      }

      // Always delete templates for this job code (prevents orphaned templates)
      await txn.delete(
        'shift_templates',
        where: 'jobCode = ? COLLATE NOCASE',
        whereArgs: [code],
      );

      await txn.delete(
        tableName,
        where: 'code = ? COLLATE NOCASE',
        whereArgs: [code],
      );

      return reassigned;
    });
  }
}
