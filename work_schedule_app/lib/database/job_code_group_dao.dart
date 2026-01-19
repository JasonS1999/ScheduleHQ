import 'package:sqflite/sqflite.dart';
import '../models/job_code_group.dart';
import 'app_database.dart';

class JobCodeGroupDao {
  static const tableName = 'job_code_groups';

  Future<Database> get _db async => AppDatabase.instance.db;

  /// Get all groups sorted by sortOrder
  Future<List<JobCodeGroup>> getAll() async {
    final db = await _db;
    final result = await db.query(tableName, orderBy: 'sortOrder ASC, name ASC');
    return result.map((m) => JobCodeGroup.fromMap(m)).toList();
  }

  /// Get a group by name
  Future<JobCodeGroup?> getByName(String name) async {
    final db = await _db;
    final result = await db.query(
      tableName,
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return JobCodeGroup.fromMap(result.first);
  }

  /// Insert a new group
  Future<void> insert(JobCodeGroup group) async {
    final db = await _db;
    await db.insert(
      tableName,
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing group
  Future<void> update(JobCodeGroup group) async {
    final db = await _db;
    await db.update(
      tableName,
      group.toMap(),
      where: 'name = ?',
      whereArgs: [group.name],
    );
  }

  /// Delete a group by name
  Future<void> delete(String name) async {
    final db = await _db;
    // First, unassign all job codes from this group
    await db.update(
      'job_code_settings',
      {'sortGroup': null},
      where: 'sortGroup = ?',
      whereArgs: [name],
    );
    // Then delete the group
    await db.delete(tableName, where: 'name = ?', whereArgs: [name]);
  }

  /// Rename a group (updates all job codes referencing it)
  Future<void> rename(String oldName, String newName) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Get the old group data
      final oldGroup = await txn.query(
        tableName,
        where: 'name = ?',
        whereArgs: [oldName],
        limit: 1,
      );
      if (oldGroup.isEmpty) return;

      // Insert with new name
      await txn.insert(tableName, {
        'name': newName,
        'colorHex': oldGroup.first['colorHex'],
        'sortOrder': oldGroup.first['sortOrder'],
      });

      // Update all job codes to reference new name
      await txn.update(
        'job_code_settings',
        {'sortGroup': newName},
        where: 'sortGroup = ?',
        whereArgs: [oldName],
      );

      // Delete old group
      await txn.delete(tableName, where: 'name = ?', whereArgs: [oldName]);
    });
  }
}
