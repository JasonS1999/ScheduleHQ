import 'package:sqflite/sqflite.dart';
import '../models/shift_runner_color.dart';
import 'app_database.dart';

class ShiftRunnerColorDao {
  Future<List<ShiftRunnerColor>> getAll() async {
    final db = await AppDatabase.instance.db;
    final result = await db.query('shift_runner_colors');
    return result.map((row) => ShiftRunnerColor.fromMap(row)).toList();
  }

  Future<ShiftRunnerColor?> getForShiftType(String shiftType) async {
    final db = await AppDatabase.instance.db;
    final result = await db.query(
      'shift_runner_colors',
      where: 'shiftType = ?',
      whereArgs: [shiftType],
    );
    if (result.isEmpty) return null;
    return ShiftRunnerColor.fromMap(result.first);
  }

  Future<Map<String, String>> getColorMap() async {
    final colors = await getAll();
    final map = Map<String, String>.from(ShiftRunnerColor.defaultColors);
    for (final color in colors) {
      map[color.shiftType] = color.colorHex;
    }
    return map;
  }

  Future<void> upsert(ShiftRunnerColor color) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'shift_runner_colors',
      color.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> resetToDefaults() async {
    final db = await AppDatabase.instance.db;
    await db.delete('shift_runner_colors');
  }

  Future<void> insertDefaultsIfMissing() async {
    final db = await AppDatabase.instance.db;
    for (final entry in ShiftRunnerColor.defaultColors.entries) {
      await db.insert(
        'shift_runner_colors',
        {'shiftType': entry.key, 'colorHex': entry.value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
