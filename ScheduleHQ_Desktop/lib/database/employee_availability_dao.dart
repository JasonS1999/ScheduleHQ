import 'package:sqflite/sqflite.dart';
import '../models/employee_availability.dart';
import 'app_database.dart';

class EmployeeAvailabilityDao {
  Future<Database> get _db async => await AppDatabase.instance.db;

  // Get all generic availability patterns for an employee
  Future<List<EmployeeAvailability>> getGenericAvailability(int employeeId) async {
    final db = await _db;
    final maps = await db.query(
      'employee_availability',
      where: 'employeeId = ? AND availabilityType = ?',
      whereArgs: [employeeId, 'generic'],
      orderBy: 'dayOfWeek',
    );
    return maps.map((map) => EmployeeAvailability.fromMap(map)).toList();
  }

  // Get all biweekly availability patterns for an employee
  Future<List<EmployeeAvailability>> getBiweeklyAvailability(int employeeId) async {
    final db = await _db;
    final maps = await db.query(
      'employee_availability',
      where: 'employeeId = ? AND availabilityType = ?',
      whereArgs: [employeeId, 'biweekly'],
      orderBy: 'weekNumber, dayOfWeek',
    );
    return maps.map((map) => EmployeeAvailability.fromMap(map)).toList();
  }

  // Get all monthly overrides for an employee
  Future<List<EmployeeAvailability>> getMonthlyOverrides(int employeeId) async {
    final db = await _db;
    final maps = await db.query(
      'employee_availability',
      where: 'employeeId = ? AND availabilityType = ?',
      whereArgs: [employeeId, 'monthly'],
      orderBy: 'specificDate',
    );
    return maps.map((map) => EmployeeAvailability.fromMap(map)).toList();
  }

  // Get monthly override for a specific date
  Future<EmployeeAvailability?> getMonthlyOverride(int employeeId, String date) async {
    final db = await _db;
    final maps = await db.query(
      'employee_availability',
      where: 'employeeId = ? AND availabilityType = ? AND specificDate = ?',
      whereArgs: [employeeId, 'monthly', date],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return EmployeeAvailability.fromMap(maps.first);
  }

  // Check if employee is available at a specific date and time
  Future<Map<String, dynamic>> isAvailable(
    int employeeId,
    DateTime dateTime,
    String? shiftStartTime,
    String? shiftEndTime,
  ) async {
    // Format the date
    final dateStr = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    
    // Priority 1: Check monthly override first
    final monthlyOverride = await getMonthlyOverride(employeeId, dateStr);
    if (monthlyOverride != null) {
      return _checkTimeAvailability(monthlyOverride, shiftStartTime, shiftEndTime, 'monthly');
    }

    // Priority 2: Check biweekly pattern
    final biweeklyPatterns = await getBiweeklyAvailability(employeeId);
    if (biweeklyPatterns.isNotEmpty) {
      final weekNumber = _getWeekNumber(dateTime);
      final dayOfWeek = dateTime.weekday % 7; // Convert to 0=Sunday
      
      final matchingPattern = biweeklyPatterns.firstWhere(
        (pattern) => pattern.dayOfWeek == dayOfWeek && pattern.weekNumber == weekNumber,
        orElse: () => EmployeeAvailability(
          employeeId: employeeId,
          availabilityType: 'biweekly',
          allDay: true,
          available: true,
        ),
      );
      
      if (matchingPattern.id != null) {
        return _checkTimeAvailability(matchingPattern, shiftStartTime, shiftEndTime, 'biweekly');
      }
    }

    // Priority 3: Check generic pattern
    final genericPatterns = await getGenericAvailability(employeeId);
    if (genericPatterns.isNotEmpty) {
      final dayOfWeek = dateTime.weekday % 7; // Convert to 0=Sunday
      
      final matchingPattern = genericPatterns.firstWhere(
        (pattern) => pattern.dayOfWeek == dayOfWeek,
        orElse: () => EmployeeAvailability(
          employeeId: employeeId,
          availabilityType: 'generic',
          allDay: true,
          available: true,
        ),
      );
      
      if (matchingPattern.id != null) {
        return _checkTimeAvailability(matchingPattern, shiftStartTime, shiftEndTime, 'generic');
      }
    }

    // No restrictions found - available by default
    return {
      'available': true,
      'reason': 'No availability restrictions set',
      'type': 'none',
    };
  }

  // Helper to check time-based availability
  Map<String, dynamic> _checkTimeAvailability(
    EmployeeAvailability pattern,
    String? shiftStartTime,
    String? shiftEndTime,
    String type,
  ) {
    if (!pattern.available) {
      return {
        'available': false,
        'reason': 'Employee marked as unavailable',
        'type': type,
      };
    }

    if (pattern.allDay) {
      return {
        'available': true,
        'reason': 'Available all day',
        'type': type,
      };
    }

    // Check time range if specified
    if (shiftStartTime != null && shiftEndTime != null && 
        pattern.startTime != null && pattern.endTime != null) {
      if (_isTimeInRange(shiftStartTime, shiftEndTime, pattern.startTime!, pattern.endTime!)) {
        return {
          'available': true,
          'reason': 'Available during shift time (${pattern.startTime} - ${pattern.endTime})',
          'type': type,
          'startTime': pattern.startTime,
          'endTime': pattern.endTime,
        };
      } else {
        return {
          'available': false,
          'reason': 'Outside available time (${pattern.startTime} - ${pattern.endTime})',
          'type': type,
          'startTime': pattern.startTime,
          'endTime': pattern.endTime,
        };
      }
    }

    if (pattern.startTime != null && pattern.endTime != null) {
      return {
        'available': true,
        'reason': 'Available (${pattern.startTime} - ${pattern.endTime})',
        'type': type,
        'startTime': pattern.startTime,
        'endTime': pattern.endTime,
      };
    }
    return {
      'available': true,
      'reason': 'Available',
      'type': type,
    };
  }

  // Helper to check if shift time overlaps with available time
  bool _isTimeInRange(String shiftStart, String shiftEnd, String availStart, String availEnd) {
    // Convert HH:MM strings to comparable integers (HHMM format)
    int toMinutes(String time) {
      final parts = time.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }
    
    final shiftStartMins = toMinutes(shiftStart);
    final shiftEndMins = toMinutes(shiftEnd);
    final availStartMins = toMinutes(availStart);
    final availEndMins = toMinutes(availEnd);
    
    return shiftStartMins >= availStartMins && shiftEndMins <= availEndMins;
  }

  // Get week number (1 or 2) for biweekly pattern
  int _getWeekNumber(DateTime date) {
    // Calculate week of year
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    final weekOfYear = ((daysSinceFirstDay + firstDayOfYear.weekday) / 7).floor();
    
    // Return 1 or 2 based on odd/even week
    return (weekOfYear % 2) + 1;
  }

  // Insert new availability entry
  Future<int> insertAvailability(EmployeeAvailability availability) async {
    final db = await _db;
    return await db.insert('employee_availability', availability.toMap());
  }

  // Update existing availability entry
  Future<int> updateAvailability(EmployeeAvailability availability) async {
    final db = await _db;
    return await db.update(
      'employee_availability',
      availability.toMap(),
      where: 'id = ?',
      whereArgs: [availability.id],
    );
  }

  // Delete availability entry
  Future<int> deleteAvailability(int id) async {
    final db = await _db;
    return await db.delete(
      'employee_availability',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete all availability entries for an employee
  Future<int> deleteAllForEmployee(int employeeId) async {
    final db = await _db;
    return await db.delete(
      'employee_availability',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
    );
  }
}
