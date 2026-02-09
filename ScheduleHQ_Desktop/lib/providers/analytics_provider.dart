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
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final StoreHoursDao _storeHoursDao = StoreHoursDao();

  // Analytics data
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<ShiftType> _shiftTypes = [];
  StoreHours _storeHours = StoreHours.defaults();
  
  // Filters
  String _searchQuery = '';
  String? _selectedJobCode;

  // Mid shift definitions: (startHour, startMinute, endHour, endMinute)  
  static const List<(int, int, int, int)> midShiftPatterns = [
    (11, 0, 19, 0),  // 11-7
    (12, 0, 20, 0),  // 12-8
    (10, 0, 19, 0),  // 10-7
    (11, 0, 20, 0),  // 11-8
  ];

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

  /// Check if a shift is a mid shift based on predefined patterns
  bool isMidShift(Shift shift) {
    final startTime = shift.startTime;
    final endTime = shift.endTime;

    final startHour = startTime.hour;
    final startMinute = startTime.minute;
    final endHour = endTime.hour;
    final endMinute = endTime.minute;

    return midShiftPatterns.any((pattern) {
      return startHour == pattern.$1 &&
             startMinute == pattern.$2 &&
             endHour == pattern.$3 &&
             endMinute == pattern.$4;
    });
  }

  /// Calculate mid shift percentage for an employee in the selected month
  double calculateMidShiftPercentage(Employee employee, List<Shift> shifts, List<ShiftRunner> shiftRunners) {
    final employeeId = employee.id;
    if (employeeId == null) return 0.0;

    // Get shift runners for this employee in the selected month
    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    final employeeShiftRunners = shiftRunners
        .where((sr) => sr.employeeId == employeeId)
        .where((sr) {
          return sr.date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
                 sr.date.isBefore(monthEnd);
        })
        .toList();

    if (employeeShiftRunners.isEmpty) return 0.0;

    int totalShifts = employeeShiftRunners.length;
    int midShifts = 0;

    for (final shiftRunner in employeeShiftRunners) {
      final shift = shifts.firstWhere(
        (s) => s.employeeId == employeeId && 
               s.startTime.year == shiftRunner.date.year && 
               s.startTime.month == shiftRunner.date.month && 
               s.startTime.day == shiftRunner.date.day,
        orElse: () => shifts.first,
      );
      if (isMidShift(shift)) {
        midShifts++;
      }
    }

    return totalShifts > 0 ? (midShifts / totalShifts) * 100 : 0.0;
  }

  /// Calculate total hours worked for an employee in the selected month
  double calculateTotalHours(Employee employee, List<Shift> shifts, List<ShiftRunner> shiftRunners) {
    final employeeId = employee.id;
    if (employeeId == null) return 0.0;

    // Get shift runners for this employee in the selected month
    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    final employeeShiftRunners = shiftRunners
        .where((sr) => sr.employeeId == employeeId)
        .where((sr) {
          return sr.date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
                 sr.date.isBefore(monthEnd);
        })
        .toList();

    double totalHours = 0.0;
    for (final shiftRunner in employeeShiftRunners) {
      final shift = shifts.firstWhere(
        (s) => s.employeeId == employeeId &&
               s.startTime.year == shiftRunner.date.year &&
               s.startTime.month == shiftRunner.date.month &&
               s.startTime.day == shiftRunner.date.day,
        orElse: () => shifts.first,
      );
      totalHours += shift.endTime.difference(shift.startTime).inMinutes / 60.0;
    }

    return totalHours;
  }

  /// Calculate shift count for an employee in the selected month
  int calculateShiftCount(Employee employee, List<Shift> shifts, List<ShiftRunner> shiftRunners) {
    final employeeId = employee.id;
    if (employeeId == null) return 0;

    // Get shift runners for this employee in the selected month
    final monthStart = _selectedMonth;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);

    return shiftRunners
        .where((sr) => sr.employeeId == employeeId)
        .where((sr) {
          return sr.date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
                 sr.date.isBefore(monthEnd);
        })
        .length;
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
    List<Shift> shifts,
    List<ShiftRunner> shiftRunners,
    List<JobCodeSettings> jobCodeSettings,
  ) async {
    final filteredEmployees = filterEmployees(employees, jobCodeSettings);
    final List<EmployeeAnalytics> analytics = [];

    for (final employee in filteredEmployees) {
      final totalHours = calculateTotalHours(employee, shifts, shiftRunners);
      final shiftCount = calculateShiftCount(employee, shifts, shiftRunners);
      final midShiftPercentage = calculateMidShiftPercentage(employee, shifts, shiftRunners);

      analytics.add(EmployeeAnalytics(
        employee: employee,
        totalHours: totalHours,
        shiftCount: shiftCount,
        midShiftPercentage: midShiftPercentage,
        averageHoursPerShift: shiftCount > 0 ? totalHours / shiftCount : 0.0,
      ));
    }

    // Sort by total hours descending
    analytics.sort((a, b) => b.totalHours.compareTo(a.totalHours));

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
  final double totalHours;
  final int shiftCount;
  final double midShiftPercentage;
  final double averageHoursPerShift;

  const EmployeeAnalytics({
    required this.employee,
    required this.totalHours,
    required this.shiftCount,
    required this.midShiftPercentage,
    required this.averageHoursPerShift,
  });
}