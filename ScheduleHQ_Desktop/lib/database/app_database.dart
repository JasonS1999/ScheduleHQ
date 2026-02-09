import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Future<void> _onCreate(Database db, int version) async {
  log("🛠 Creating database schema...", name: 'AppDatabase');

  await db.execute('''
    CREATE TABLE employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firstName TEXT,
      lastName TEXT,
      nickname TEXT,
      jobCode TEXT,
      email TEXT,
      uid TEXT,
      vacationWeeksAllowed INTEGER DEFAULT 0,
      vacationWeeksUsed INTEGER DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_email 
    ON employees(email) WHERE email IS NOT NULL
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
      blockOverlaps INTEGER NOT NULL DEFAULT 0,
      autoSyncEnabled INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE time_off (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employeeId INTEGER NOT NULL,
      date TEXT NOT NULL,
      endDate TEXT,
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
      sortOrder INTEGER NOT NULL DEFAULT 0,
      maxHoursPerWeek INTEGER NOT NULL DEFAULT 40,
      sortGroup TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE job_code_groups (
      name TEXT PRIMARY KEY,
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
      templateName TEXT NOT NULL,
      startTime TEXT NOT NULL,
      endTime TEXT NOT NULL DEFAULT '17:00'
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

  await db.execute('''
    CREATE TABLE shift_runners (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      shiftType TEXT NOT NULL,
      runnerName TEXT NOT NULL,
      employeeId INTEGER,
      UNIQUE(date, shiftType)
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_shift_runners_date 
    ON shift_runners(date)
  ''');

  await db.execute('''
    CREATE TABLE shift_runner_colors (
      shiftType TEXT PRIMARY KEY,
      colorHex TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE shift_runner_settings (
      shiftType TEXT PRIMARY KEY,
      customLabel TEXT,
      shiftRangeStart TEXT,
      shiftRangeEnd TEXT,
      defaultStartTime TEXT,
      defaultEndTime TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE shift_types (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL UNIQUE,
      label TEXT NOT NULL,
      sortOrder INTEGER NOT NULL,
      rangeStart TEXT NOT NULL,
      rangeEnd TEXT NOT NULL,
      defaultShiftStart TEXT NOT NULL,
      defaultShiftEnd TEXT NOT NULL,
      colorHex TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE store_hours (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      storeName TEXT NOT NULL DEFAULT '',
      storeNsn TEXT NOT NULL DEFAULT '',
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

  // Insert default store hours
  await db.insert('store_hours', {
    'sundayOpen': '04:30',
    'sundayClose': '01:00',
    'mondayOpen': '04:30',
    'mondayClose': '01:00',
    'tuesdayOpen': '04:30',
    'tuesdayClose': '01:00',
    'wednesdayOpen': '04:30',
    'wednesdayClose': '01:00',
    'thursdayOpen': '04:30',
    'thursdayClose': '01:00',
    'fridayOpen': '04:30',
    'fridayClose': '01:00',
    'saturdayOpen': '04:30',
    'saturdayClose': '01:00',
  });

  await db.execute('''
    CREATE TABLE employee_weekly_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employeeId INTEGER NOT NULL,
      dayOfWeek INTEGER NOT NULL,
      startTime TEXT,
      endTime TEXT,
      isOff INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(employeeId) REFERENCES employees(id) ON DELETE CASCADE,
      UNIQUE(employeeId, dayOfWeek)
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_weekly_templates_employee 
    ON employee_weekly_templates(employeeId)
  ''');

  await db.execute('''
    CREATE TABLE tracked_employees (
      employeeId INTEGER PRIMARY KEY,
      sortOrder INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(employeeId) REFERENCES employees(id) ON DELETE CASCADE
    )
  ''');

  // P&L Tables
  await db.execute('''
    CREATE TABLE pnl_periods (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      month INTEGER NOT NULL,
      year INTEGER NOT NULL,
      avgWage REAL NOT NULL DEFAULT 0.0,
      autoLaborEnabled INTEGER NOT NULL DEFAULT 0,
      UNIQUE(month, year)
    )
  ''');

  await db.execute('''
    CREATE TABLE pnl_line_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      periodId INTEGER NOT NULL,
      label TEXT NOT NULL,
      value REAL NOT NULL DEFAULT 0.0,
      percentage REAL NOT NULL DEFAULT 0.0,
      comment TEXT NOT NULL DEFAULT '',
      isCalculated INTEGER NOT NULL DEFAULT 0,
      isUserAdded INTEGER NOT NULL DEFAULT 0,
      sortOrder INTEGER NOT NULL,
      category TEXT NOT NULL,
      FOREIGN KEY(periodId) REFERENCES pnl_periods(id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_pnl_line_items_period 
    ON pnl_line_items(periodId)
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
  String? _currentManagerUid;

  /// Returns an open database instance, initializing it if necessary.
  /// Note: You should call initForManager() first after user logs in.
  Future<Database> get db async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  /// Check if database is initialized for a specific manager
  bool isInitializedFor(String? managerUid) {
    return _db != null && _currentManagerUid == managerUid;
  }

  /// Initialize database for a specific manager.
  /// Call this after user logs in to ensure correct database is used.
  Future<void> initForManager(String managerUid) async {
    // If already initialized for this manager, do nothing
    if (_db != null && _currentManagerUid == managerUid) return;
    
    // Close existing database if open for different manager
    if (_db != null) {
      log('Switching database from $_currentManagerUid to $managerUid', name: 'AppDatabase');
      await _db!.close();
      _db = null;
    }
    
    _currentManagerUid = managerUid;
    await init(managerUid: managerUid);
  }

  /// Close the current database (call on logout)\n  /// Note: Use the close() method at the end of this class\n\n  /// Initializes and opens the database. Safe to call multiple times.
  /// If [dbPath] is provided, it will be used instead of the default file path
  /// which is useful for tests (e.g., ':memory:').
  /// If [managerUid] is provided, uses a per-manager database file.
  Future<void> init({String? dbPath, String? managerUid}) async {
    if (_db != null) return;

    String path;
    if (dbPath != null) {
      path = dbPath;
    } else {
      // Store database in AppData folder so it persists across app updates
      final appData = Platform.environment['APPDATA'] ?? await getDatabasesPath();
      final appDir = Directory(join(appData, 'WorkScheduleApp'));
      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }
      
      // Use manager-specific database file if UID provided
      final dbFileName = managerUid != null 
          ? 'work_schedule_$managerUid.db'
          : 'work_schedule.db';
      path = join(appDir.path, dbFileName);
      
      // Migration: check if old shared database exists and this is a new per-user db
      if (managerUid != null) {
        final oldSharedPath = join(appDir.path, 'work_schedule.db');
        final oldSharedFile = File(oldSharedPath);
        final newFile = File(path);
        if (oldSharedFile.existsSync() && !newFile.existsSync()) {
          log('Migrating shared database to per-manager database: $path', name: 'AppDatabase');
          await oldSharedFile.copy(path);
        }
      }
      
      // Legacy migration: check if old database exists in default getDatabasesPath location
      final oldPath = join(await getDatabasesPath(), 'work_schedule.db');
      final oldFile = File(oldPath);
      final newFile = File(path);
      if (oldFile.existsSync() && !newFile.existsSync()) {
        log('Migrating database from $oldPath to $path', name: 'AppDatabase');
        await oldFile.copy(path);
      }
    }
    
    log('Database path: $path', name: 'AppDatabase');

    _db = await openDatabase(
      path,
      version: 32,
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
              templateName TEXT NOT NULL,
              startTime TEXT NOT NULL
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
        if (oldVersion < 9) {
          // Add maxHoursPerWeek column to job_code_settings
          await db.execute('ALTER TABLE job_code_settings ADD COLUMN maxHoursPerWeek INTEGER NOT NULL DEFAULT 40');
        }

        if (oldVersion < 10) {
          // shift_templates: remove jobCode column (templates are now global/shared)
          await db.execute('PRAGMA foreign_keys=OFF');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_templates_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              templateName TEXT NOT NULL,
              startTime TEXT NOT NULL
            )
          ''');

          // Copy what we can from the old table if it exists
          try {
            await db.execute('''
              INSERT INTO shift_templates_new (templateName, startTime)
              SELECT DISTINCT templateName, startTime FROM shift_templates
            ''');
            await db.execute('DROP TABLE shift_templates');
          } catch (_) {
            // If the old schema doesn't match (or table doesn't exist), continue.
          }

          await db.execute('ALTER TABLE shift_templates_new RENAME TO shift_templates');
          await db.execute('PRAGMA foreign_keys=ON');
        }

        if (oldVersion < 11) {
          // Add endTime column to shift_templates for explicit end times
          await db.execute("ALTER TABLE shift_templates ADD COLUMN endTime TEXT NOT NULL DEFAULT '17:00'");
        }

        if (oldVersion < 12) {
          // Add shift_runners table for tracking shift leaders
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_runners (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL,
              shiftType TEXT NOT NULL,
              runnerName TEXT NOT NULL,
              UNIQUE(date, shiftType)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_shift_runners_date 
            ON shift_runners(date)
          ''');
        }

        if (oldVersion < 13) {
          // Add shift_runner_colors table for customizable colors
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_runner_colors (
              shiftType TEXT PRIMARY KEY,
              colorHex TEXT NOT NULL
            )
          ''');
        }

        if (oldVersion < 14) {
          // Add shift_runner_settings table for custom labels and default shifts
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_runner_settings (
              shiftType TEXT PRIMARY KEY,
              customLabel TEXT,
              shiftRangeStart TEXT,
              shiftRangeEnd TEXT,
              defaultStartTime TEXT,
              defaultEndTime TEXT
            )
          ''');
        }

        if (oldVersion < 15) {
          // Add shiftRangeStart and shiftRangeEnd columns to shift_runner_settings
          try {
            await db.execute('ALTER TABLE shift_runner_settings ADD COLUMN shiftRangeStart TEXT');
            await db.execute('ALTER TABLE shift_runner_settings ADD COLUMN shiftRangeEnd TEXT');
          } catch (_) {
            // Columns may already exist if table was created in v14 with the new schema
          }
        }

        if (oldVersion < 16) {
          // Add shift_types table for configurable shift types
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_types (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              key TEXT NOT NULL UNIQUE,
              label TEXT NOT NULL,
              sortOrder INTEGER NOT NULL,
              rangeStart TEXT NOT NULL,
              rangeEnd TEXT NOT NULL,
              defaultShiftStart TEXT NOT NULL,
              defaultShiftEnd TEXT NOT NULL,
              colorHex TEXT NOT NULL
            )
          ''');

          // Migrate existing data from shift_runner_colors and shift_runner_settings
          // First, check if we have any existing settings/colors
          final colors = await db.query('shift_runner_colors');
          final settings = await db.query('shift_runner_settings');
          
          final colorMap = <String, String>{};
          for (final row in colors) {
            colorMap[row['shiftType'] as String] = row['colorHex'] as String;
          }
          
          final settingsMap = <String, Map<String, dynamic>>{};
          for (final row in settings) {
            settingsMap[row['shiftType'] as String] = row;
          }

          // Default shift configurations
          final defaults = [
            {'key': 'open', 'label': 'Open', 'sortOrder': 0, 'rangeStart': '04:30', 'rangeEnd': '11:00', 'colorHex': '#FF9800'},
            {'key': 'lunch', 'label': 'Lunch', 'sortOrder': 1, 'rangeStart': '11:00', 'rangeEnd': '15:00', 'colorHex': '#4CAF50'},
            {'key': 'dinner', 'label': 'Dinner', 'sortOrder': 2, 'rangeStart': '15:00', 'rangeEnd': '20:00', 'colorHex': '#2196F3'},
            {'key': 'close', 'label': 'Close', 'sortOrder': 3, 'rangeStart': '20:00', 'rangeEnd': '01:00', 'colorHex': '#9C27B0'},
          ];

          for (final def in defaults) {
            final key = def['key'] as String;
            final existingSettings = settingsMap[key];
            
            await db.insert('shift_types', {
              'key': key,
              'label': existingSettings?['customLabel'] ?? def['label'],
              'sortOrder': def['sortOrder'],
              'rangeStart': existingSettings?['shiftRangeStart'] ?? def['rangeStart'],
              'rangeEnd': existingSettings?['shiftRangeEnd'] ?? def['rangeEnd'],
              'defaultShiftStart': existingSettings?['defaultStartTime'] ?? def['rangeStart'],
              'defaultShiftEnd': existingSettings?['defaultEndTime'] ?? def['rangeEnd'],
              'colorHex': colorMap[key] ?? def['colorHex'],
            });
          }
        }
        if (oldVersion < 17) {
          // Add store_hours table for configurable open/close times
          await db.execute('''
            CREATE TABLE store_hours (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              openTime TEXT NOT NULL,
              closeTime TEXT NOT NULL
            )
          ''');
          // Insert defaults
          await db.insert('store_hours', {
            'openTime': '04:30',
            'closeTime': '01:00',
          });
        }
        if (oldVersion < 18) {
          // Migrate store_hours to per-day schedule
          // Check if we have the old schema (single openTime/closeTime)
          final columns = await db.rawQuery("PRAGMA table_info(store_hours)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();
          
          if (columnNames.contains('openTime') && !columnNames.contains('mondayOpen')) {
            // Get existing values
            final oldData = await db.query('store_hours', limit: 1);
            String oldOpen = '04:30';
            String oldClose = '01:00';
            
            if (oldData.isNotEmpty) {
              oldOpen = oldData.first['openTime'] as String? ?? '04:30';
              oldClose = oldData.first['closeTime'] as String? ?? '01:00';
            }
            
            // Drop old table and create new
            await db.execute('DROP TABLE IF EXISTS store_hours');
            await db.execute('''
              CREATE TABLE store_hours (
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
            
            // Insert with old values for all days (preserve user's settings)
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
        if (oldVersion < 19) {
          // Add job_code_groups table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS job_code_groups (
              name TEXT PRIMARY KEY,
              colorHex TEXT NOT NULL,
              sortOrder INTEGER NOT NULL DEFAULT 0
            )
          ''');
          // Add sortGroup column to job_code_settings
          try {
            await db.execute('ALTER TABLE job_code_settings ADD COLUMN sortGroup TEXT');
          } catch (_) {
            // Column may already exist
          }
        }
        if (oldVersion < 20) {
          // Add storeName and storeNsn columns to store_hours
          try {
            await db.execute("ALTER TABLE store_hours ADD COLUMN storeName TEXT NOT NULL DEFAULT ''");
          } catch (_) {
            // Column may already exist
          }
          try {
            await db.execute("ALTER TABLE store_hours ADD COLUMN storeNsn TEXT NOT NULL DEFAULT ''");
          } catch (_) {
            // Column may already exist
          }
        }
        if (oldVersion < 21) {
          // Add employee_weekly_templates table for per-employee schedule templates
          await db.execute('''
            CREATE TABLE IF NOT EXISTS employee_weekly_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              employeeId INTEGER NOT NULL,
              dayOfWeek INTEGER NOT NULL,
              startTime TEXT,
              endTime TEXT,
              isOff INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY(employeeId) REFERENCES employees(id) ON DELETE CASCADE,
              UNIQUE(employeeId, dayOfWeek)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_weekly_templates_employee 
            ON employee_weekly_templates(employeeId)
          ''');
        }
        if (oldVersion < 22) {
          // Add email and uid columns to employees for Firebase sync
          try {
            await db.execute('ALTER TABLE employees ADD COLUMN email TEXT');
          } catch (_) {
            // Column may already exist
          }
          try {
            await db.execute('ALTER TABLE employees ADD COLUMN uid TEXT');
          } catch (_) {
            // Column may already exist
          }
          // Create unique index on email (for employees that have one)
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_email 
            ON employees(email) WHERE email IS NOT NULL
          ''');
        }
        if (oldVersion < 23) {
          // Add autoSyncEnabled column to settings
          try {
            await db.execute('ALTER TABLE settings ADD COLUMN autoSyncEnabled INTEGER NOT NULL DEFAULT 0');
          } catch (_) {
            // Column may already exist
          }
        }
        if (oldVersion < 24) {
          // Add endDate column to time_off for multi-day vacation entries
          try {
            await db.execute('ALTER TABLE time_off ADD COLUMN endDate TEXT');
          } catch (_) {
            // Column may already exist
          }
        }
        if (oldVersion < 25) {
          // Add tracked_employees table for PDF stats tracking
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tracked_employees (
              employeeId INTEGER PRIMARY KEY,
              sortOrder INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY(employeeId) REFERENCES employees(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 26) {
          // Ensure endDate column exists in time_off table (fix for missed migration)
          try {
            final tableInfo = await db.rawQuery("PRAGMA table_info(time_off)");
            final hasEndDate = tableInfo.any((col) => col['name'] == 'endDate');
            if (!hasEndDate) {
              await db.execute('ALTER TABLE time_off ADD COLUMN endDate TEXT');
              log('Added missing endDate column to time_off', name: 'AppDatabase');
            }
          } catch (e) {
            log('Error checking/adding endDate column: $e', name: 'AppDatabase');
          }
        }
        if (oldVersion < 27) {
          // Add P&L tables
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pnl_periods (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              month INTEGER NOT NULL,
              year INTEGER NOT NULL,
              avgWage REAL NOT NULL DEFAULT 0.0,
              UNIQUE(month, year)
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS pnl_line_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              periodId INTEGER NOT NULL,
              label TEXT NOT NULL,
              value REAL NOT NULL DEFAULT 0.0,
              percentage REAL NOT NULL DEFAULT 0.0,
              comment TEXT NOT NULL DEFAULT '',
              isCalculated INTEGER NOT NULL DEFAULT 0,
              isUserAdded INTEGER NOT NULL DEFAULT 0,
              sortOrder INTEGER NOT NULL,
              category TEXT NOT NULL,
              FOREIGN KEY(periodId) REFERENCES pnl_periods(id) ON DELETE CASCADE
            )
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_pnl_line_items_period 
            ON pnl_line_items(periodId)
          ''');
          log('Added P&L tables', name: 'AppDatabase');
        }
        if (oldVersion < 28) {
          // Add percentage column to pnl_line_items if it doesn't exist
          // This handles the case where P&L tables were created in v27 without the percentage column
          try {
            await db.execute('ALTER TABLE pnl_line_items ADD COLUMN percentage REAL NOT NULL DEFAULT 0.0');
            log('Added percentage column to pnl_line_items', name: 'AppDatabase');
          } catch (e) {
            // Column may already exist if table was created fresh with v28 schema
            log('percentage column already exists or table not found: $e', name: 'AppDatabase');
          }
        }
        if (oldVersion < 29) {
          // Add autoLaborEnabled column to pnl_periods
          try {
            await db.execute('ALTER TABLE pnl_periods ADD COLUMN autoLaborEnabled INTEGER NOT NULL DEFAULT 0');
            log('Added autoLaborEnabled column to pnl_periods', name: 'AppDatabase');
          } catch (e) {
            log('autoLaborEnabled column already exists or table not found: $e', name: 'AppDatabase');
          }
        }
        if (oldVersion < 30) {
          // Add firstName, lastName, nickname columns to employees
          try {
            await db.execute('ALTER TABLE employees ADD COLUMN firstName TEXT');
            await db.execute('ALTER TABLE employees ADD COLUMN lastName TEXT');
            await db.execute('ALTER TABLE employees ADD COLUMN nickname TEXT');
            log('Added firstName, lastName, nickname columns to employees', name: 'AppDatabase');
          } catch (e) {
            log('Employee name columns already exist or table not found: $e', name: 'AppDatabase');
          }
        }
        if (oldVersion < 31) {
          // Add employeeId column to shift_runners for linking to employee records
          try {
            await db.execute('ALTER TABLE shift_runners ADD COLUMN employeeId INTEGER');
            log('Added employeeId column to shift_runners', name: 'AppDatabase');
            
            // Populate employeeId for existing entries by matching runnerName to employee firstName
            await db.execute('''
              UPDATE shift_runners 
              SET employeeId = (
                SELECT id FROM employees 
                WHERE employees.firstName = shift_runners.runnerName
                LIMIT 1
              )
              WHERE employeeId IS NULL
            ''');
            log('Populated employeeId for existing shift_runners', name: 'AppDatabase');
          } catch (e) {
            log('employeeId column already exists or table not found: $e', name: 'AppDatabase');
          }
        }
        if (oldVersion < 32) {
          // Add date component columns to shifts table to fix DST issues
          try {
            await db.execute('ALTER TABLE shifts ADD COLUMN startDate TEXT');
            await db.execute('ALTER TABLE shifts ADD COLUMN startHour INTEGER');
            await db.execute('ALTER TABLE shifts ADD COLUMN startMinute INTEGER');
            await db.execute('ALTER TABLE shifts ADD COLUMN endDate TEXT');
            await db.execute('ALTER TABLE shifts ADD COLUMN endHour INTEGER');
            await db.execute('ALTER TABLE shifts ADD COLUMN endMinute INTEGER');
            log('Added date component columns to shifts table for DST fix', name: 'AppDatabase');
          } catch (e) {
            log('Date component columns already exist or error: $e', name: 'AppDatabase');
          }
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
      _currentManagerUid = null;
      log('Database closed', name: 'AppDatabase');
    }
  }
}
