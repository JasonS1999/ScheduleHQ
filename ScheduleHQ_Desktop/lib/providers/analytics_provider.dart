import '../database/shift_dao.dart';
import '../database/shift_runner_dao.dart';
import '../database/shift_type_dao.dart';
import '../database/store_hours_dao.dart';
import '../models/employee.dart';
import '../models/shift.dart';
import '../models/shift_runner.dart';
import '../models/job_code_settings.dart';
import '../models/store_hours.dart';
import '../models/shift_type.dart';
import 'base_provider.dart';

/// Provider for managing analytics data and calculations
class AnalyticsProvider extends BaseProvider {
  final ShiftDao _shiftDao = ShiftDao();
  final ShiftRunnerDao _shiftRunnerDao = ShiftRunnerDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final StoreHoursDao _storeHoursDao = StoreHoursDao();

  // Analytics data
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<ShiftType> _shiftTypes = [];
  StoreHours _storeHours = StoreHours.defaults();

  // Filters
  String _searchQuery = '';
  String? _selectedJobCode;

  // Getters
  DateTime get selectedMonth => _selectedMonth;
  List<ShiftType> get shiftTypes => List.unmodifiable(_shiftTypes);
  StoreHours get storeHours => _storeHours;
  String get searchQuery => _searchQuery;
  String? get selectedJobCode => _selectedJobCode;

  /// Load all analytics data
  Future<void> loadData() async {
    await executeWithLoading(() async {
      final shiftTypes = await _shiftTypeDao.getAll();
      final storeHours = await _storeHoursDao.getStoreHours();

      _shiftTypes = shiftTypes;
      _storeHours = storeHours;
    });
  }

  /// Update selected month filter
  void setSelectedMonth(DateTime month) {
    _selectedMonth = DateTime(month.year, month.month, 1);
    notifyListeners();
  }

  /// Update search query filter
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Update job code filter
  void setSelectedJobCode(String? jobCode) {
    _selectedJobCode = jobCode;
    notifyListeners();
  }

  /// Check if a shift is a non-working entry (OFF, PTO, VAC, REQ OFF)
  static bool _isNonWorkingShift(Shift shift) {
    if (shift.label == null || shift.label!.isEmpty) return false;
    final label = shift.label!.toLowerCase();
    return label == 'off' || label == 'pto' || label == 'vac' || label == 'req off';
  }

  /// Calculate total working hours for an employee in the selected month
  double calculateTotalHours(Employee employee, List<Shift> shifts) {
    final employeeId = employee.id;
    if (employeeId == null) return 0.0;

    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    double totalHours = 0.0;
    for (final shift in shifts) {
      if (shift.employeeId != employeeId) continue;
      if (shift.startTime.isBefore(monthStart) || !shift.startTime.isBefore(monthEnd)) continue;
      if (_isNonWorkingShift(shift)) continue;
      totalHours += shift.endTime.difference(shift.startTime).inMinutes / 60.0;
    }

    return totalHours;
  }

  /// Calculate working shift count for an employee in the selected month
  int calculateShiftCount(Employee employee, List<Shift> shifts) {
    final employeeId = employee.id;
    if (employeeId == null) return 0;

    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    return shifts
        .where((s) => s.employeeId == employeeId)
        .where((s) => !s.startTime.isBefore(monthStart) && s.startTime.isBefore(monthEnd))
        .where((s) => !_isNonWorkingShift(s))
        .length;
  }

  /// Count runner assignments per shift type for an employee in the selected month
  Map<String, int> calculateRunnerCountsByShiftType(Employee employee, List<ShiftRunner> shiftRunners) {
    final employeeId = employee.id;
    if (employeeId == null) return {};

    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    final employeeShiftRunners = shiftRunners
        .where((sr) => sr.employeeId == employeeId)
        .where((sr) {
          return !sr.date.isBefore(monthStart) && sr.date.isBefore(monthEnd);
        });

    final counts = <String, int>{};
    for (final sr in employeeShiftRunners) {
      counts[sr.shiftType] = (counts[sr.shiftType] ?? 0) + 1;
    }

    return counts;
  }

  /// Filter employees based on search query and job code
  List<Employee> filterEmployees(List<Employee> employees, List<JobCodeSettings> jobCodeSettings) {
    List<Employee> filtered = employees;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where((e) => e.displayName.toLowerCase().contains(query) ||
                       e.jobCode.toLowerCase().contains(query))
          .toList();
    }

    // Apply job code filter
    if (_selectedJobCode != null && _selectedJobCode!.isNotEmpty) {
      filtered = filtered.where((e) => e.jobCode == _selectedJobCode).toList();
    }

    return filtered;
  }

  /// Get analytics data for filtered employees
  Future<List<EmployeeAnalytics>> getEmployeeAnalytics(
    List<Employee> employees,
    List<JobCodeSettings> jobCodeSettings,
  ) async {
    // Load shifts and runners for the selected month directly from database
    final monthStart = _selectedMonth;
    final monthLastDay = DateTime(monthStart.year, monthStart.month + 1, 0);

    final shifts = await _shiftDao.getByMonth(monthStart.year, monthStart.month);
    final shiftRunners = await _shiftRunnerDao.getForDateRange(monthStart, monthLastDay);

    final filteredEmployees = filterEmployees(employees, jobCodeSettings);
    final List<EmployeeAnalytics> analytics = [];

    for (final employee in filteredEmployees) {
      final totalHours = calculateTotalHours(employee, shifts);
      final totalShifts = calculateShiftCount(employee, shifts);

      // Calculate weeks in the selected month for avg hours/week
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
      final daysInMonth = monthEnd.difference(monthStart).inDays;
      final weeksInMonth = daysInMonth / 7.0;
      final avgHoursPerWeek = weeksInMonth > 0 ? totalHours / weeksInMonth : 0.0;

      final runnerCounts = calculateRunnerCountsByShiftType(employee, shiftRunners);
      final totalRunnerCount = runnerCounts.values.fold(0, (sum, v) => sum + v);

      analytics.add(EmployeeAnalytics(
        employee: employee,
        totalShifts: totalShifts,
        avgHoursPerWeek: avgHoursPerWeek,
        runnerCountsByShiftType: runnerCounts,
        totalRunnerCount: totalRunnerCount,
      ));
    }

    // Sort by job code sort order (ascending), then by name
    final orderByJobCode = <String, int>{
      for (final jc in jobCodeSettings) jc.code.toLowerCase(): jc.sortOrder,
    };
    int orderFor(String jobCode) => orderByJobCode[jobCode.toLowerCase()] ?? 999999;

    analytics.sort((a, b) {
      final aOrder = orderFor(a.employee.jobCode);
      final bOrder = orderFor(b.employee.jobCode);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.employee.displayName.compareTo(b.employee.displayName);
    });

    return analytics;
  }

  /// Get available job codes for filtering
  List<String> getAvailableJobCodes(List<Employee> employees) {
    final jobCodes = employees.map((e) => e.jobCode).toSet().toList();
    jobCodes.sort();
    return jobCodes;
  }

  @override
  Future<void> refresh() async {
    await loadData();
  }
}

/// Data class for employee analytics
class EmployeeAnalytics {
  final Employee employee;
  final int totalShifts;
  final double avgHoursPerWeek;
  final Map<String, int> runnerCountsByShiftType;
  final int totalRunnerCount;

  const EmployeeAnalytics({
    required this.employee,
    required this.totalShifts,
    required this.avgHoursPerWeek,
    required this.runnerCountsByShiftType,
    required this.totalRunnerCount,
  });
}
