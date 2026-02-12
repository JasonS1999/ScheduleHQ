import '../database/employee_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/employee.dart';
import '../models/job_code_settings.dart';
import '../utils/app_constants.dart';
import 'base_provider.dart';

/// Provider for managing employee data and operations
class EmployeeProvider extends BaseProvider with CrudProviderMixin<Employee>, SearchProviderMixin {
  final EmployeeDao _employeeDao;
  final JobCodeSettingsDao _jobCodeDao;
  
  List<JobCodeSettings> _jobCodes = [];
  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];

  EmployeeProvider({
    EmployeeDao? employeeDao,
    JobCodeSettingsDao? jobCodeDao,
  }) : _employeeDao = employeeDao ?? EmployeeDao(),
        _jobCodeDao = jobCodeDao ?? JobCodeSettingsDao();

  /// All employees (unfiltered)
  List<Employee> get allEmployees => List.unmodifiable(_allEmployees);
  
  /// Public getter for employees (alias for allEmployees for compatibility)
  List<Employee> get employees => List.unmodifiable(_allEmployees);
  
  /// Filtered employees based on search query
  List<Employee> get filteredEmployees => List.unmodifiable(_filteredEmployees);
  
  /// Job codes for employee organization
  List<JobCodeSettings> get jobCodes => List.unmodifiable(_jobCodes);
  
  /// Error getter for compatibility (delegates to base class)
  String? get error => errorMessage;
  
  @override
  List<Employee> get items => _filteredEmployees;

  /// Initialize the provider by loading employees and job codes
  Future<void> initialize() async {
    await executeWithState(() async {
      await _loadJobCodes();
      await _loadEmployees();
    }, errorPrefix: 'Failed to initialize employee data');
  }

  /// Public method to load employees (for external callers)
  Future<void> loadEmployees() async {
    await executeWithState(() async {
      await _loadJobCodes();
      await _loadEmployees();
    }, errorPrefix: 'Failed to load employee data');
  }

  @override
  Future<void> refresh() async {
    await initialize();
  }

  /// Load all employees from database
  Future<void> _loadEmployees() async {
    final employees = await _employeeDao.getEmployees();
    _allEmployees = List.from(employees);
    _sortEmployees();
    _applySearchFilter();
  }

  /// Load job codes for employee organization
  Future<void> _loadJobCodes() async {
    await _jobCodeDao.insertDefaultsIfMissing();
    _jobCodes = await _jobCodeDao.getAll();
  }

  /// Sort employees by job code order and name
  void _sortEmployees() {
    if (_allEmployees.isEmpty || _jobCodes.isEmpty) return;

    final orderByJobCodeLower = <String, int>{
      for (final jc in _jobCodes) jc.code.toLowerCase(): jc.sortOrder,
    };

    int orderFor(String jobCode) => orderByJobCodeLower[jobCode.toLowerCase()] ?? 999999;

    _allEmployees.sort((a, b) {
      final aOrder = orderFor(a.jobCode);
      final bOrder = orderFor(b.jobCode);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);

      final jobCodeCmp = a.jobCode.toLowerCase().compareTo(b.jobCode.toLowerCase());
      if (jobCodeCmp != 0) return jobCodeCmp;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// Apply search filter to employees
  void _applySearchFilter() {
    if (searchQuery.isEmpty) {
      _filteredEmployees = List.from(_allEmployees);
    } else {
      _filteredEmployees = _allEmployees.where((employee) {
        return employee.name.toLowerCase().contains(searchQuery) ||
               employee.jobCode.toLowerCase().contains(searchQuery) ||
               (employee.email?.toLowerCase().contains(searchQuery) ?? false) ||
               (employee.nickname?.toLowerCase().contains(searchQuery) ?? false);
      }).toList();
    }
    setItems(_filteredEmployees);
  }

  @override
  void onSearchQueryChanged() {
    _applySearchFilter();
  }

  /// Create a new employee
  Future<bool> createEmployee({
    required String firstName,
    required String jobCode,
    String? lastName,
    String? nickname,
    String? email,
    String? uid,
    int vacationWeeksAllowed = 0,
    int vacationWeeksUsed = 0,
  }) async {
    final employee = Employee(
      firstName: firstName.trim(),
      lastName: lastName?.trim(),
      nickname: nickname?.trim(),
      jobCode: jobCode,
      email: email?.trim(),
      uid: uid,
      vacationWeeksAllowed: vacationWeeksAllowed,
      vacationWeeksUsed: vacationWeeksUsed,
    );

    return await executeWithState(() async {
      final id = await _employeeDao.insertEmployee(employee);
      final createdEmployee = employee.copyWith(id: id);
      _allEmployees.add(createdEmployee);
      _sortEmployees();
      _applySearchFilter();
      return true;
    }, errorPrefix: 'Failed to create employee') ?? false;
  }

  /// Update an existing employee
  Future<bool> updateEmployee(Employee employee, {
    String? firstName,
    String? lastName,
    String? nickname,
    String? jobCode,
    String? email,
    String? uid,
    int? vacationWeeksAllowed,
    int? vacationWeeksUsed,
  }) async {
    if (employee.id == null) {
      setLoadingState(LoadingState.error, error: 'Cannot update employee without ID');
      return false;
    }

    final updatedEmployee = employee.copyWith(
      firstName: firstName?.trim(),
      lastName: lastName?.trim(),
      nickname: nickname?.trim(),
      jobCode: jobCode,
      email: email?.trim(),
      uid: uid,
      vacationWeeksAllowed: vacationWeeksAllowed,
      vacationWeeksUsed: vacationWeeksUsed,
    );

    return await executeWithState(() async {
      await _employeeDao.updateEmployee(updatedEmployee);
      
      // Update in local list
      final index = _allEmployees.indexWhere((e) => e.id == employee.id);
      if (index != -1) {
        _allEmployees[index] = updatedEmployee;
        _sortEmployees();
        _applySearchFilter();
        
        // Update selected item if it's the one being updated
        if (selectedItem?.id == employee.id) {
          selectItem(updatedEmployee);
        }
      }
      return true;
    }, errorPrefix: 'Failed to update employee') ?? false;
  }

  /// Delete an employee
  Future<bool> deleteEmployee(Employee employee) async {
    if (employee.id == null) {
      setLoadingState(LoadingState.error, error: 'Cannot delete employee without ID');
      return false;
    }

    return await executeWithState(() async {
      await _employeeDao.deleteEmployee(employee.id!);
      
      // Remove from local lists
      _allEmployees.removeWhere((e) => e.id == employee.id);
      _filteredEmployees.removeWhere((e) => e.id == employee.id);
      
      // Clear selection if deleted employee was selected
      if (selectedItem?.id == employee.id) {
        clearSelection();
      }
      
      setItems(_filteredEmployees);
      return true;
    }, errorPrefix: 'Failed to delete employee') ?? false;
  }

  /// Get employee by ID
  Future<Employee?> getEmployeeById(int id) async {
    // First check local cache
    final localEmployee = _allEmployees.firstWhere(
      (e) => e.id == id,
      orElse: () => Employee(jobCode: ''), // Placeholder for not found
    );
    
    if (localEmployee.jobCode.isNotEmpty) {
      return localEmployee;
    }

    // If not in cache, fetch from database
    return await executeWithState<Employee?>(() async {
      return await _employeeDao.getById(id);
    }, errorPrefix: 'Failed to get employee by ID');
  }

  /// Get employees by job code
  List<Employee> getEmployeesByJobCode(String jobCode) {
    return _filteredEmployees.where((e) => e.jobCode == jobCode).toList();
  }

  /// Get employees with vacation time available
  List<Employee> getEmployeesWithVacation() {
    return _filteredEmployees.where((e) => 
      e.vacationWeeksAllowed > e.vacationWeeksUsed,
    ).toList();
  }

  /// Get employees without email addresses (for Firebase sync)
  List<Employee> getEmployeesWithoutEmail() {
    return _filteredEmployees.where((e) => 
      e.email == null || e.email!.isEmpty,
    ).toList();
  }

  /// Bulk update employees (useful for data imports)
  Future<bool> bulkUpdateEmployees(List<Employee> employees) async {
    if (employees.isEmpty) return true;

    return await executeWithState(() async {
      for (final employee in employees) {
        if (employee.id != null) {
          await _employeeDao.updateEmployee(employee);
        } else {
          await _employeeDao.insertEmployee(employee);
        }
      }
      
      // Reload all employees after bulk update
      await _loadEmployees();
      return true;
    }, errorPrefix: 'Failed to bulk update employees') ?? false;
  }

  /// Get statistics about employees
  Map<String, dynamic> getEmployeeStats() {
    final stats = <String, dynamic>{
      'total': _allEmployees.length,
      'filtered': _filteredEmployees.length,
      'byJobCode': <String, int>{},
      'withEmail': _allEmployees.where((e) => e.email?.isNotEmpty == true).length,
      'totalVacationWeeks': _allEmployees.fold(0, (sum, e) => sum + e.vacationWeeksAllowed),
    };

    // Count by job code
    for (final employee in _allEmployees) {
      final jobCode = employee.jobCode;
      stats['byJobCode'][jobCode] = (stats['byJobCode'][jobCode] ?? 0) + 1;
    }

    return stats;
  }

  /// Validate employee data before save
  List<String> validateEmployee({
    required String firstName,
    required String jobCode,
    String? email,
  }) {
    final errors = <String>[];

    if (firstName.trim().isEmpty) {
      errors.add('First name is required');
    } else if (firstName.trim().length > AppConstants.maxNameLength) {
      errors.add('First name is too long');
    }

    if (jobCode.trim().isEmpty) {
      errors.add('Job code is required');
    }

    if (email != null && email.isNotEmpty) {
      if (email.length > AppConstants.maxEmailLength) {
        errors.add('Email is too long');
      }
      // Basic email validation
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        errors.add('Invalid email format');
      }
    }

    return errors;
  }

  /// Check if employee name is unique
  bool isNameUnique(String firstName, {int? excludeId}) {
    return !_allEmployees.any((e) => 
      e.firstName?.toLowerCase() == firstName.toLowerCase() && 
      e.id != excludeId,
    );
  }

  /// Get suggestions for job codes based on existing data
  List<String> getJobCodeSuggestions() {
    final suggestions = _jobCodes.map((jc) => jc.code).toList();
    
    // Add any job codes from employees that aren't in settings
    final employeeJobCodes = _allEmployees
        .map((e) => e.jobCode)
        .where((code) => !suggestions.contains(code))
        .toSet()
        .toList();
    
    suggestions.addAll(employeeJobCodes);
    suggestions.sort();
    
    return suggestions;
  }
}