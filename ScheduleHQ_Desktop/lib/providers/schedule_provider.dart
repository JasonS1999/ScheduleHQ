import '../database/shift_dao.dart';
import '../database/shift_runner_dao.dart';
import '../database/shift_runner_settings_dao.dart';
import '../database/employee_dao.dart';
import '../database/shift_type_dao.dart';
import '../database/time_off_dao.dart';
import '../database/employee_availability_dao.dart';
import '../models/shift.dart';
import '../models/shift_runner.dart';
import '../models/shift_runner_settings.dart';
import '../models/employee.dart';
import '../models/shift_type.dart' as model;
import '../models/time_off_entry.dart';
import '../utils/app_constants.dart';
import 'base_provider.dart';

/// Provider for managing schedule data and operations
class ScheduleProvider extends BaseProvider with CrudProviderMixin<Shift> {
  final ShiftDao _shiftDao;
  final ShiftRunnerDao _shiftRunnerDao;
  final ShiftRunnerSettingsDao _shiftRunnerSettingsDao;
  final EmployeeDao _employeeDao;
  final ShiftTypeDao _shiftTypeDao;
  final TimeOffDao _timeOffDao;
  final EmployeeAvailabilityDao _availabilityDao;

  // Date range for current schedule view
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 28)); // 4 weeks default
  
  // Schedule data
  List<Shift> _shifts = [];
  List<ShiftRunner> _shiftRunners = [];
  ShiftRunnerSettings? _shiftRunnerSettings;
  List<Employee> _employees = [];
  List<model.ShiftType> _shiftTypes = [];
  List<TimeOffEntry> _timeOffEntries = [];
  
  // View settings
  int _weeksToShow = AppConstants.defaultScheduleWeeksToShow;
  bool _showWeekends = true;
  bool _show24HourTime = false;

  ScheduleProvider({
    ShiftDao? shiftDao,
    ShiftRunnerDao? shiftRunnerDao,
    ShiftRunnerSettingsDao? shiftRunnerSettingsDao,
    EmployeeDao? employeeDao,
    ShiftTypeDao? shiftTypeDao,
    TimeOffDao? timeOffDao,
    EmployeeAvailabilityDao? availabilityDao,
  }) : _shiftDao = shiftDao ?? ShiftDao(),
        _shiftRunnerDao = shiftRunnerDao ?? ShiftRunnerDao(),
        _shiftRunnerSettingsDao = shiftRunnerSettingsDao ?? ShiftRunnerSettingsDao(),
        _employeeDao = employeeDao ?? EmployeeDao(),
        _shiftTypeDao = shiftTypeDao ?? ShiftTypeDao(),
        _timeOffDao = timeOffDao ?? TimeOffDao(),
        _availabilityDao = availabilityDao ?? EmployeeAvailabilityDao();

  // Getters
  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;
  List<Shift> get shifts => List.unmodifiable(_shifts);
  List<ShiftRunner> get shiftRunners => List.unmodifiable(_shiftRunners);
  ShiftRunnerSettings? get shiftRunnerSettings => _shiftRunnerSettings;
  List<Employee> get employees => List.unmodifiable(_employees);
  List<model.ShiftType> get shiftTypes => List.unmodifiable(_shiftTypes);
  List<TimeOffEntry> get timeOffEntries => List.unmodifiable(_timeOffEntries);
  int get weeksToShow => _weeksToShow;
  bool get showWeekends => _showWeekends;
  bool get show24HourTime => _show24HourTime;

  @override
  List<Shift> get items => _shifts;

  /// Initialize the provider
  Future<void> initialize() async {
    await executeWithState(() async {
      await _loadEmployees();
      await _loadShiftTypes();
      await _loadTimeOffEntries();
      await _loadShiftRunnerSettings();
      await _loadShiftRunners();
      await _loadShifts();
    }, errorPrefix: 'Failed to initialize schedule data');
  }

  /// Public method to load schedule data (for external callers)
  Future<void> loadSchedule() async {
    await initialize();
  }

  @override
  Future<void> refresh() async {
    await initialize();
  }

  /// Set the date range for the schedule view
  Future<void> setDateRange(DateTime start, DateTime end) async {
    if (start.isAfter(end)) {
      throw ArgumentError('Start date must be before end date');
    }

    _startDate = start;
    _endDate = end;
    await _loadShifts();
  }

  /// Set the number of weeks to show in the schedule
  Future<void> setWeeksToShow(int weeks) async {
    if (weeks < 1 || weeks > AppConstants.maxScheduleWeeksToShow) {
      throw ArgumentError('Weeks to show must be between 1 and ${AppConstants.maxScheduleWeeksToShow}');
    }

    _weeksToShow = weeks;
    final start = _getStartOfWeek(DateTime.now());
    final end = start.add(Duration(days: weeks * 7));
    await setDateRange(start, end);
  }

  /// Toggle weekend display
  void setShowWeekends(bool show) {
    if (_showWeekends != show) {
      _showWeekends = show;
      notifyListeners();
    }
  }

  /// Toggle 24-hour time format
  void setShow24HourTime(bool show24Hour) {
    if (_show24HourTime != show24Hour) {
      _show24HourTime = show24Hour;
      notifyListeners();
    }
  }

  /// Move schedule view to next period
  Future<void> goToNextPeriod() async {
    final duration = Duration(days: _weeksToShow * 7);
    await setDateRange(_startDate.add(duration), _endDate.add(duration));
  }

  /// Move schedule view to previous period
  Future<void> goToPreviousPeriod() async {
    final duration = Duration(days: _weeksToShow * 7);
    await setDateRange(_startDate.subtract(duration), _endDate.subtract(duration));
  }

  /// Go to current week
  Future<void> goToCurrentWeek() async {
    final start = _getStartOfWeek(DateTime.now());
    final end = start.add(Duration(days: _weeksToShow * 7));
    await setDateRange(start, end);
  }

  /// Load shifts for the current date range
  Future<void> _loadShifts() async {
    _shifts = await _shiftDao.getByDateRange(_startDate, _endDate);
    setItems(_shifts);
  }

  /// Load shift runners
  Future<void> _loadShiftRunners() async {
    _shiftRunners = await _shiftRunnerDao.getForDateRange(_startDate, _endDate);
  }

  /// Load shift runner settings
  Future<void> _loadShiftRunnerSettings() async {
    final settingsMap = await _shiftRunnerSettingsDao.getAllSettings();
    // For now, just get the first setting or create a default
    _shiftRunnerSettings = settingsMap.values.firstOrNull;
  }

  /// Create a new shift
  Future<bool> createShift({
    required int employeeId,
    required DateTime startTime,
    required DateTime endTime,
    String? label,
    String? notes,
  }) async {
    // Validate shift times
    final validationErrors = _validateShiftTimes(startTime, endTime);
    if (validationErrors.isNotEmpty) {
      setLoadingState(LoadingState.error, error: validationErrors.first);
      return false;
    }

    // Check for conflicts
    final conflicts = await _checkShiftConflicts(employeeId, startTime, endTime);
    if (conflicts.isNotEmpty) {
      setLoadingState(LoadingState.error, error: 'Shift conflicts with existing shifts');
      return false;
    }

    final shift = Shift(
      employeeId: employeeId,
      startTime: startTime,
      endTime: endTime,
      label: label,
      notes: notes,
    );

    return await executeWithState(() async {
      final id = await _shiftDao.insert(shift);
      final createdShift = shift.copyWith(id: id);
      _shifts.add(createdShift);
      setItems(_shifts);
      return true;
    }, errorPrefix: 'Failed to create shift') ?? false;
  }

  /// Update an existing shift
  Future<bool> updateShift(
    Shift shift, {
    int? employeeId,
    DateTime? startTime,
    DateTime? endTime,
    String? label,
    String? notes,
  }) async {
    if (shift.id == null) {
      setLoadingState(LoadingState.error, error: 'Cannot update shift without ID');
      return false;
    }

    final newStartTime = startTime ?? shift.startTime;
    final newEndTime = endTime ?? shift.endTime;
    final newEmployeeId = employeeId ?? shift.employeeId;

    // Validate shift times
    final validationErrors = _validateShiftTimes(newStartTime, newEndTime);
    if (validationErrors.isNotEmpty) {
      setLoadingState(LoadingState.error, error: validationErrors.first);
      return false;
    }

    // Check for conflicts (excluding the current shift)
    final conflicts = await _checkShiftConflicts(
      newEmployeeId,
      newStartTime,
      newEndTime,
      excludeShiftId: shift.id,
    );
    if (conflicts.isNotEmpty) {
      setLoadingState(LoadingState.error, error: 'Shift conflicts with existing shifts');
      return false;
    }

    final updatedShift = shift.copyWith(
      employeeId: employeeId,
      startTime: startTime,
      endTime: endTime,
      label: label,
      notes: notes,
    );

    return await executeWithState(() async {
      await _shiftDao.update(updatedShift);
      
      // Update in local list
      final index = _shifts.indexWhere((s) => s.id == shift.id);
      if (index != -1) {
        _shifts[index] = updatedShift;
        setItems(_shifts);
        
        // Update selected item if it's the one being updated
        if (selectedItem?.id == shift.id) {
          selectItem(updatedShift);
        }
      }
      return true;
    }, errorPrefix: 'Failed to update shift') ?? false;
  }

  /// Delete a shift
  Future<bool> deleteShift(Shift shift) async {
    if (shift.id == null) {
      setLoadingState(LoadingState.error, error: 'Cannot delete shift without ID');
      return false;
    }

    return await executeWithState(() async {
      await _shiftDao.delete(shift.id!);
      
      // Remove from local list
      _shifts.removeWhere((s) => s.id == shift.id);
      
      // Clear selection if deleted shift was selected
      if (selectedItem?.id == shift.id) {
        clearSelection();
      }
      
      setItems(_shifts);
      return true;
    }, errorPrefix: 'Failed to delete shift') ?? false;
  }

  /// Delete all shifts for an employee on a specific date
  Future<bool> deleteShiftsByEmployeeAndDate(int employeeId, DateTime date) async {
    return await executeWithState(() async {
      await _shiftDao.deleteByEmployeeAndDate(employeeId, date);
      
      // Remove from local list
      final dateOnly = DateTime(date.year, date.month, date.day);
      _shifts.removeWhere((shift) {
        final shiftDate = DateTime(
          shift.startTime.year,
          shift.startTime.month,
          shift.startTime.day,
        );
        return shift.employeeId == employeeId && shiftDate.isAtSameMomentAs(dateOnly);
      });
      
      setItems(_shifts);
      return true;
    }, errorPrefix: 'Failed to delete shifts') ?? false;
  }

  /// Get shifts for a specific employee
  List<Shift> getShiftsForEmployee(int employeeId) {
    return _shifts.where((shift) => shift.employeeId == employeeId).toList();
  }

  /// Get shifts for a specific date
  List<Shift> getShiftsForDate(DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    return _shifts.where((shift) {
      final shiftDate = DateTime(
        shift.startTime.year,
        shift.startTime.month,
        shift.startTime.day,
      );
      return shiftDate.isAtSameMomentAs(targetDate);
    }).toList();
  }

  /// Get shifts for a specific employee and date
  List<Shift> getShiftsForEmployeeAndDate(int employeeId, DateTime date) {
    return getShiftsForDate(date)
        .where((shift) => shift.employeeId == employeeId)
        .toList();
  }

  /// Calculate total hours for an employee in the current date range
  double getTotalHoursForEmployee(int employeeId) {
    final employeeShifts = getShiftsForEmployee(employeeId);
    double totalHours = 0;
    
    for (final shift in employeeShifts) {
      final duration = shift.endTime.difference(shift.startTime);
      totalHours += duration.inMinutes / 60.0;
    }
    
    return totalHours;
  }

  /// Calculate total hours for a specific date
  double getTotalHoursForDate(DateTime date) {
    final dateShifts = getShiftsForDate(date);
    double totalHours = 0;
    
    for (final shift in dateShifts) {
      final duration = shift.endTime.difference(shift.startTime);
      totalHours += duration.inMinutes / 60.0;
    }
    
    return totalHours;
  }

  /// Get schedule statistics
  Map<String, dynamic> getScheduleStats() {
    final now = DateTime.now();
    final employeeHours = <int, double>{};
    final dailyHours = <String, double>{};
    
    for (final shift in _shifts) {
      final duration = shift.endTime.difference(shift.startTime);
      final hours = duration.inMinutes / 60.0;
      
      // Employee hours
      employeeHours[shift.employeeId] = (employeeHours[shift.employeeId] ?? 0) + hours;
      
      // Daily hours
      final dateKey = '${shift.startTime.year}-${shift.startTime.month}-${shift.startTime.day}';
      dailyHours[dateKey] = (dailyHours[dateKey] ?? 0) + hours;
    }

    return {
      'totalShifts': _shifts.length,
      'totalHours': _shifts.fold<double>(0, (sum, shift) {
        final duration = shift.endTime.difference(shift.startTime);
        return sum + (duration.inMinutes / 60.0);
      }),
      'employeeHours': employeeHours,
      'dailyHours': dailyHours,
      'averageShiftLength': _shifts.isNotEmpty
          ? _shifts.fold<double>(0, (sum, shift) {
              final duration = shift.endTime.difference(shift.startTime);
              return sum + (duration.inMinutes / 60.0);
            }) / _shifts.length
          : 0,
    };
  }

  /// Validate shift times
  List<String> _validateShiftTimes(DateTime startTime, DateTime endTime) {
    final errors = <String>[];

    if (startTime.isAfter(endTime)) {
      errors.add('Start time must be before end time');
    }

    final duration = endTime.difference(startTime);
    if (duration.inMinutes < AppConstants.minShiftMinutes) {
      errors.add('Shift must be at least ${AppConstants.minShiftMinutes} minutes');
    }

    if (duration.inHours > AppConstants.maxShiftHours) {
      errors.add('Shift cannot be longer than ${AppConstants.maxShiftHours} hours');
    }

    return errors;
  }

  /// Check for shift conflicts
  Future<List<Shift>> _checkShiftConflicts(
    int employeeId,
    DateTime startTime,
    DateTime endTime, {
    int? excludeShiftId,
  }) async {
    // For now, use in-memory data. In a full implementation,
    // you might want to query the database for a wider range
    return _shifts.where((shift) {
      // Skip the shift being updated
      if (excludeShiftId != null && shift.id == excludeShiftId) {
        return false;
      }

      // Only check same employee
      if (shift.employeeId != employeeId) {
        return false;
      }

      // Check for time overlap
      return startTime.isBefore(shift.endTime) && endTime.isAfter(shift.startTime);
    }).toList();
  }

  /// Get the start of the week (Monday) for a given date
  DateTime _getStartOfWeek(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysFromMonday));
  }

  /// Generate date headers for the current schedule view
  List<DateTime> getDateHeaders() {
    final dates = <DateTime>[];
    var current = _startDate;
    while (current.isBefore(_endDate)) {
      if (_showWeekends || (current.weekday != DateTime.saturday && current.weekday != DateTime.sunday)) {
        dates.add(current);
      }
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  /// Copy shifts from one date to another
  Future<bool> copyShifts(DateTime fromDate, DateTime toDate, List<int> employeeIds) async {
    final shiftsTosCopy = getShiftsForDate(fromDate)
        .where((shift) => employeeIds.contains(shift.employeeId))
        .toList();

    if (shiftsTosCopy.isEmpty) return true;

    return await executeWithState(() async {
      final dayDifference = toDate.difference(fromDate).inDays;
      
      for (final shift in shiftsTosCopy) {
        final newStartTime = shift.startTime.add(Duration(days: dayDifference));
        final newEndTime = shift.endTime.add(Duration(days: dayDifference));
        
        final newShift = Shift(
          employeeId: shift.employeeId,
          startTime: newStartTime,
          endTime: newEndTime,
          label: shift.label,
          notes: shift.notes,
        );
        
        await _shiftDao.insert(newShift);
      }
      
      // Reload shifts to include the new ones
      await _loadShifts();
      return true;
    }, errorPrefix: 'Failed to copy shifts') ?? false;
  }

  /// Load employees
  Future<void> _loadEmployees() async {
    _employees = await _employeeDao.getEmployees();
  }

  /// Load shift types with defaults
  Future<void> _loadShiftTypes() async {
    await _shiftTypeDao.insertDefaultsIfEmpty();
    _shiftTypes = await _shiftTypeDao.getAll();
  }

  /// Load time off entries
  Future<void> _loadTimeOffEntries() async {
    _timeOffEntries = await _timeOffDao.getAllTimeOff();
  }

  /// Clear a shift runner assignment
  Future<bool> clearShiftRunner(DateTime date, String shiftType) async {
    return await executeWithLoading(() async {
      await _shiftRunnerDao.clear(date, shiftType);
      await _loadShiftRunners(); // Refresh data
      return true;
    }) ?? false;
  }

  /// Upsert a shift runner assignment
  Future<bool> upsertShiftRunner(ShiftRunner runner) async {
    return await executeWithLoading(() async {
      await _shiftRunnerDao.upsert(runner);
      await _loadShiftRunners(); // Refresh data
      return true;
    }) ?? false;
  }

  /// Check if an employee is available at a specific time
  Future<Map<String, dynamic>> checkEmployeeAvailability(
    int employeeId,
    DateTime dateTime,
    String? shiftStartTime,
    String? shiftEndTime,
  ) async {
    return await _availabilityDao.isAvailable(
      employeeId,
      dateTime,
      shiftStartTime,
      shiftEndTime,
    );
  }

  /// Get shift runner for a specific date and shift type
  String? getRunnerForCell(DateTime day, String shiftType) {
    final runner = _shiftRunners.where((r) =>
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day &&
          r.shiftType == shiftType).firstOrNull;
    return runner?.runnerName;
  }

  /// Get shift type information by key
  model.ShiftType? getShiftType(String shiftType) {
    return _shiftTypes.where((st) => st.key == shiftType).firstOrNull;
  }

  /// Find employee by name
  Employee? getEmployeeByName(String name) {
    return _employees.where((e) => e.name == name).firstOrNull;
  }

  /// Get employee shifts for a date range
  Future<List<Shift>> getEmployeeShiftsForDateRange(
    int employeeId,
    DateTime start,
    DateTime end,
  ) async {
    return await _shiftDao.getByEmployeeAndDateRange(employeeId, start, end);
  }
}