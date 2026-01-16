import 'dart:async';
import 'dart:developer';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Future<void> _onCreate(Database db, int version) async {
  log("🛠 Creating database schema...", name: 'AppDatabase');

  await db.execute('''
    CREATE TABLE employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      jobCode TEXT,
      vacationWeeksAllowed INTEGER DEFAULT 0,
      vacationWeeksUsed INTEGER DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY,
      ptoHoursPerTrimester INTEGER NOT NULL,
      ptoHoursPerRequest INTEGER NOT NULL,
      maxCarryoverHours INTEGER NOT NULL,
      assistantVacationDays INTEGER NOT NULL DEFAULT 0,
      swingVacationDays INTEGER NOT NULL DEFAULT 0,
      minimumHoursBetweenShifts INTEGER NOT NULL DEFAULT 0,
      inventoryDay INTEGER NOT NULL DEFAULT 0,
      scheduleStartDay INTEGER NOT NULL DEFAULT 0,
      blockOverlaps INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE time_off (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employeeId INTEGER NOT NULL,
      date TEXT NOT NULL,
      timeOffType TEXT NOT NULL,
      hours INTEGER NOT NULL,
      vacationGroupId TEXT,
      isAllDay INTEGER NOT NULL DEFAULT 1,
      startTime TEXT,
      endTime TEXT,
      FOREIGN KEY(employeeId) REFERENCES employees(id)
    )
  ''');

  await db.execute('''
    CREATE TABLE pto_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employeeId INTEGER NOT NULL,
      trimesterStart TEXT NOT NULL,
      carryoverHours INTEGER NOT NULL,
      UNIQUE(employeeId, trimesterStart)
    )
  ''');

  await db.execute('''
    CREATE TABLE job_code_settings (
      code TEXT PRIMARY KEY,
      hasPTO INTEGER NOT NULL,
      defaultScheduledHours INTEGER NOT NULL,
      defaultVacationDays INTEGER NOT NULL,
      colorHex TEXT NOT NULL,
      sortOrder INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE employee_availability (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employeeId INTEGER NOT NULL,
      availabilityType TEXT NOT NULL,
      dayOfWeek INTEGER,
      weekNumber INTEGER,
      specificDate TEXT,
      startTime TEXT,
      endTime TEXT,
      allDay INTEGER NOT NULL,
      available INTEGER NOT NULL,
      FOREIGN KEY(employeeId) REFERENCES employees(id)
    )
  ''');

  await db.execute('''
    CREATE TABLE shift_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      jobCode TEXT NOT NULL,
      templateName TEXT NOT NULL,
      startTime TEXT NOT NULL,
      FOREIGN KEY(jobCode) REFERENCES job_code_settings(code)
    )
  ''');

  await db.execute('''
    CREATE TABLE shifts (
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

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_shifts_employee_date 
    ON shifts(employeeId, startTime)
  ''');

  await db.execute('''
    CREATE TABLE schedule_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      note TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_schedule_notes_date 
    ON schedule_notes(date)
  ''');

  log("✅ Schema created", name: 'AppDatabase');
} 

/// Simple singleton wrapper around a sqflite [Database].
///
/// Usage:
///   await AppDatabase.instance.init();
///   final db = await AppDatabase.instance.db;
class AppDatabase {
  AppDatabase._privateConstructor();
  static final AppDatabase instance = AppDatabase._privateConstructor();

  Database? _db;

  /// Returns an open database instance, initializing it if necessary.
  Future<Database> get db async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  /// Initializes and opens the database. Safe to call multiple times.
  /// Initializes and opens the database. Safe to call multiple times.
  /// If [dbPath] is provided, it will be used instead of the default file path
  /// which is useful for tests (e.g., ':memory:').
  Future<void> init({String? dbPath}) async {
    if (_db != null) return;

    final path = dbPath ?? join(await getDatabasesPath(), 'work_schedule.db');

    _db = await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add blockOverlaps column to settings with default 0
          await db.execute('ALTER TABLE settings ADD COLUMN blockOverlaps INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 3) {
          // Add employee_availability table
          await db.execute('''
            CREATE TABLE employee_availability (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              employeeId INTEGER NOT NULL,
              availabilityType TEXT NOT NULL,
              dayOfWeek INTEGER,
              weekNumber INTEGER,
              specificDate TEXT,
              startTime TEXT,
              endTime TEXT,
              allDay INTEGER NOT NULL,
              available INTEGER NOT NULL,
              FOREIGN KEY(employeeId) REFERENCES employees(id)
            )
          ''');
        }
        if (oldVersion < 4) {
          // Add shift_templates table
          await db.execute('''
            CREATE TABLE shift_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              jobCode TEXT NOT NULL,
              templateName TEXT NOT NULL,
              startTime TEXT NOT NULL,
              FOREIGN KEY(jobCode) REFERENCES job_code_settings(code)
            )
          ''');
        }
        if (oldVersion < 5) {
          // Add shifts table for persistent schedule storage
          await db.execute('''
            CREATE TABLE shifts (
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
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_shifts_employee_date 
            ON shifts(employeeId, startTime)
          ''');
        }
        if (oldVersion < 6) {
          // Add schedule_notes table
          await db.execute('''
            CREATE TABLE schedule_notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL UNIQUE,
              note TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_schedule_notes_date 
            ON schedule_notes(date)
          ''');
        }
        if (oldVersion < 7) {
          // Add time range columns to time_off table for partial day time off
          await db.execute('ALTER TABLE time_off ADD COLUMN isAllDay INTEGER NOT NULL DEFAULT 1');
          await db.execute('ALTER TABLE time_off ADD COLUMN startTime TEXT');
          await db.execute('ALTER TABLE time_off ADD COLUMN endTime TEXT');
        }
        if (oldVersion < 8) {
          // Add sortOrder column to job_code_settings for custom ordering
          await db.execute('ALTER TABLE job_code_settings ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0');
          // Initialize sort order based on current defaults
          await db.execute("UPDATE job_code_settings SET sortOrder = CASE code WHEN 'gm' THEN 1 WHEN 'assistant' THEN 2 WHEN 'swing' THEN 3 WHEN 'mit' THEN 4 WHEN 'breakfast mgr' THEN 5 ELSE 99 END");
        }
      },
    );
  }

  /// Closes the database if it's open.
  Future<void> close() async {
    final database = _db;
    if (database != null) {
      await database.close();
      _db = null;
    }
  }
}
