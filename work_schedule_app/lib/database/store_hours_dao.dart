import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import '../models/store_hours.dart';

class StoreHoursDao {
  Future<Database> get _db async => await AppDatabase.instance.db;

  /// Create the store_hours table
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS store_hours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sundayOpen TEXT NOT NULL DEFAULT '04:30',
        sundayClose TEXT NOT NULL DEFAULT '01:00',
        mondayOpen TEXT NOT NULL DEFAULT '04:30',
        mondayClose TEXT NOT NULL DEFAULT '01:00',
        tuesdayOpen TEXT NOT NULL DEFAULT '04:30',
        tuesdayClose TEXT NOT NULL DEFAULT '01:00',
        wednesdayOpen TEXT NOT NULL DEFAULT '04:30',
        wednesdayClose TEXT NOT NULL DEFAULT '01:00',
        thursdayOpen TEXT NOT NULL DEFAULT '04:30',
        thursdayClose TEXT NOT NULL DEFAULT '01:00',
        fridayOpen TEXT NOT NULL DEFAULT '04:30',
        fridayClose TEXT NOT NULL DEFAULT '01:00',
        saturdayOpen TEXT NOT NULL DEFAULT '04:30',
        saturdayClose TEXT NOT NULL DEFAULT '01:00'
      )
    ''');
  }

  /// Migrate from old schema (single openTime/closeTime) to per-day schema
  static Future<void> migrateToPerDayHours(Database db) async {
    // Check if we have the old columns
    final columns = await db.rawQuery("PRAGMA table_info(store_hours)");
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    
    if (columnNames.contains('openTime') && !columnNames.contains('mondayOpen')) {
      // Old schema - migrate to new
      final oldData = await db.query('store_hours', limit: 1);
      String oldOpen = StoreHours.defaultOpenTime;
      String oldClose = StoreHours.defaultCloseTime;
      
      if (oldData.isNotEmpty) {
        oldOpen = oldData.first['openTime'] as String? ?? StoreHours.defaultOpenTime;
        oldClose = oldData.first['closeTime'] as String? ?? StoreHours.defaultCloseTime;
      }
      
      // Drop old table and create new
      await db.execute('DROP TABLE IF EXISTS store_hours');
      await createTable(db);
      
      // Insert with old values for all days
      await db.insert('store_hours', {
        'sundayOpen': oldOpen,
        'sundayClose': oldClose,
        'mondayOpen': oldOpen,
        'mondayClose': oldClose,
        'tuesdayOpen': oldOpen,
        'tuesdayClose': oldClose,
        'wednesdayOpen': oldOpen,
        'wednesdayClose': oldClose,
        'thursdayOpen': oldOpen,
        'thursdayClose': oldClose,
        'fridayOpen': oldOpen,
        'fridayClose': oldClose,
        'saturdayOpen': oldOpen,
        'saturdayClose': oldClose,
      });
    }
  }

  /// Get store hours (there should only be one row)
  Future<StoreHours> getStoreHours() async {
    final db = await _db;
    final maps = await db.query('store_hours', limit: 1);
    if (maps.isEmpty) {
      // Insert defaults if no record exists
      final defaults = StoreHours.defaults();
      await db.insert('store_hours', defaults.toMap());
      return defaults;
    }
    return StoreHours.fromMap(maps.first);
  }

  /// Update store hours
  Future<void> updateStoreHours(StoreHours hours) async {
    final db = await _db;
    final existing = await db.query('store_hours', limit: 1);
    if (existing.isEmpty) {
      await db.insert('store_hours', hours.toMap());
    } else {
      await db.update(
        'store_hours',
        hours.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  /// Insert default store hours if table is empty
  Future<void> insertDefaultsIfEmpty() async {
    final db = await _db;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM store_hours'),
    );
    if (count == 0) {
      await db.insert('store_hours', StoreHours.defaults().toMap());
    }
  }
}
