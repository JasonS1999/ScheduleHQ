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
        defaultScheduledHours: 40,
        defaultVacationDays: 10,
        colorHex: '#8E24AA',
        sortOrder: 1,
      ),
      JobCodeSettings(
        code: 'assistant',
        hasPTO: true,
        defaultScheduledHours: 40,
        defaultVacationDays: 5,
        colorHex: '#4285F4',
        sortOrder: 2,
      ),
      JobCodeSettings(
        code: 'swing',
        hasPTO: true,
        defaultScheduledHours: 40,
        defaultVacationDays: 5,
        colorHex: '#DB4437',
        sortOrder: 3,
      ),
      JobCodeSettings(
        code: 'mit',
        hasPTO: true,
        defaultScheduledHours: 40,
        defaultVacationDays: 5,
        colorHex: '#009688',
        sortOrder: 4,
      ),
      JobCodeSettings(
        code: 'breakfast mgr',
        hasPTO: true,
        defaultScheduledHours: 40,
        defaultVacationDays: 5,
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
}
