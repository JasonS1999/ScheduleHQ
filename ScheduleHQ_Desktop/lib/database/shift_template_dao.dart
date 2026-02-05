import 'package:sqflite/sqflite.dart';
import '../models/shift_template.dart';
import 'app_database.dart';

class ShiftTemplateDao {
  Future<Database> get _db async => await AppDatabase.instance.db;

  // Get all templates
  Future<List<ShiftTemplate>> getAllTemplates() async {
    final db = await _db;
    final maps = await db.query('shift_templates', orderBy: 'templateName');
    return maps.map((map) => ShiftTemplate.fromMap(map)).toList();
  }

  // Alias for getAllTemplates
  Future<List<ShiftTemplate>> getAll() async => getAllTemplates();

  // Insert a new template
  Future<int> insertTemplate(ShiftTemplate template) async {
    final db = await _db;
    return await db.insert('shift_templates', template.toMap());
  }

  // Update existing template
  Future<int> updateTemplate(ShiftTemplate template) async {
    final db = await _db;
    return await db.update(
      'shift_templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }

  // Upsert template (insert or replace)
  Future<void> upsert(ShiftTemplate template) async {
    final db = await _db;
    await db.insert(
      'shift_templates',
      template.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Delete template
  Future<int> deleteTemplate(int id) async {
    final db = await _db;
    return await db.delete(
      'shift_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Alias for deleteTemplate
  Future<int> delete(int id) async => deleteTemplate(id);

  // Insert default templates if none exist
  Future<void> insertDefaultTemplatesIfMissing() async {
    final existing = await getAllTemplates();
    if (existing.isNotEmpty) return;

    await insertTemplate(ShiftTemplate(templateName: 'Opener', startTime: '06:00', endTime: '14:00'));
    await insertTemplate(ShiftTemplate(templateName: 'Lunch', startTime: '10:00', endTime: '18:00'));
    await insertTemplate(ShiftTemplate(templateName: 'Dinner', startTime: '14:00', endTime: '22:00'));
    await insertTemplate(ShiftTemplate(templateName: 'Closer', startTime: '18:00', endTime: '01:00'));
  }
}
