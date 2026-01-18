import 'package:flutter/material.dart';
import '../database/shift_dao.dart';
import '../database/shift_runner_dao.dart';
import '../database/employee_dao.dart';
import '../database/shift_type_dao.dart';
import '../database/store_hours_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/shift.dart';
import '../models/shift_runner.dart';
import '../models/employee.dart';
import '../models/store_hours.dart';
import '../models/job_code_settings.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final ShiftDao _shiftDao = ShiftDao();
  final ShiftRunnerDao _shiftRunnerDao = ShiftRunnerDao();
  final EmployeeDao _employeeDao = EmployeeDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final StoreHoursDao _storeHoursDao = StoreHoursDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Employee> _employees = [];
  List<Shift> _shifts = [];
  List<ShiftRunner> _shiftRunners = [];
  List<JobCodeSettings> _jobCodeSettings = [];
  StoreHours _storeHours = StoreHours.defaults();
  bool _isLoading = true;
  
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load shift types for shift runner display
    final shiftTypes = await _shiftTypeDao.getAll();
    ShiftRunner.setShiftTypes(shiftTypes);

    // Load employees
    final employees = await _employeeDao.getEmployees();

    // Load job code settings for ordering
    final jobCodeSettings = await _jobCodeSettingsDao.getAll();

    // Load store hours
    final storeHours = await _storeHoursDao.getStoreHours();

    // Get month date range
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

    // Load shifts for the month
    final shifts = await _shiftDao.getByDateRange(monthStart, monthEnd);

    // Load shift runners for the month
    final shiftRunners = await _shiftRunnerDao.getForDateRange(
      monthStart,
      monthEnd.subtract(const Duration(days: 1)),
    );

    setState(() {
      _employees = employees;
      _jobCodeSettings = jobCodeSettings;
      _shifts = shifts;
      _shiftRunners = shiftRunners;
      _storeHours = storeHours;
      _isLoading = false;
    });
  }

  // Sort employees by job code order then by name
  List<Employee> _getSortedEmployees() {
    final jobCodeOrder = <String, int>{};
    for (int i = 0; i < _jobCodeSettings.length; i++) {
      jobCodeOrder[_jobCodeSettings[i].code.toLowerCase()] = i;
    }
    
    final sorted = List<Employee>.from(_employees);
    sorted.sort((a, b) {
      final aOrder = jobCodeOrder[a.jobCode.toLowerCase()] ?? 999;
      final bOrder = jobCodeOrder[b.jobCode.toLowerCase()] ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  // Get filtered employees based on search and job code filter
  List<Employee> _getFilteredEmployees() {
    var employees = _getSortedEmployees();
    
    // Apply job code filter
    if (_selectedJobCode != null && _selectedJobCode!.isNotEmpty) {
      employees = employees.where((e) => 
        e.jobCode.toLowerCase() == _selectedJobCode!.toLowerCase()
      ).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      employees = employees.where((e) =>
        e.name.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    return employees;
  }

  // Get unique job codes from employees
  List<String> _getUniqueJobCodes() {
    final jobCodes = _employees.map((e) => e.jobCode).toSet().toList();
    
    // Sort by job code settings order
    final jobCodeOrder = <String, int>{};
    for (int i = 0; i < _jobCodeSettings.length; i++) {
      jobCodeOrder[_jobCodeSettings[i].code.toLowerCase()] = i;
    }
    
    jobCodes.sort((a, b) {
      final aOrder = jobCodeOrder[a.toLowerCase()] ?? 999;
      final bOrder = jobCodeOrder[b.toLowerCase()] ?? 999;
      return aOrder.compareTo(bOrder);
    });
    
    return jobCodes;
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
    _loadData();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
    _loadData();
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month - 1];
  }

  // Check if a shift is an opening shift
  bool _isOpenShift(Shift shift) {
    final dayOfWeek = shift.startTime.weekday % 7; // Convert to 0=Sunday
    final openTime = _storeHours.getOpenTimeForDay(dayOfWeek == 0 ? DateTime.sunday : dayOfWeek);
    final (openHour, openMinute) = StoreHours.parseTime(openTime);
    return shift.startTime.hour == openHour && shift.startTime.minute == openMinute;
  }

  // Check if a shift is a closing shift
  bool _isCloseShift(Shift shift) {
    final dayOfWeek = shift.startTime.weekday % 7;
    final closeTime = _storeHours.getCloseTimeForDay(dayOfWeek == 0 ? DateTime.sunday : dayOfWeek);
    final (closeHour, closeMinute) = StoreHours.parseTime(closeTime);
    return shift.endTime.hour == closeHour && shift.endTime.minute == closeMinute;
  }

  // Check if a shift matches a mid shift pattern
  bool _isMidShift(Shift shift) {
    for (final (startH, startM, endH, endM) in midShiftPatterns) {
      if (shift.startTime.hour == startH &&
          shift.startTime.minute == startM &&
          shift.endTime.hour == endH &&
          shift.endTime.minute == endM) {
        return true;
      }
    }
    return false;
  }

  // Get shift stats for an employee
  Map<String, int> _getEmployeeShiftStats(int employeeId) {
    final employeeShifts = _shifts.where((s) => s.employeeId == employeeId).toList();
    
    int opens = 0;
    int closes = 0;
    int mids = 0;
    int total = 0;

    for (final shift in employeeShifts) {
      // Skip non-shift entries (OFF, PTO, VAC, etc.)
      if (shift.label != null && 
          ['off', 'pto', 'vac', 'eto', 'req off'].contains(shift.label!.toLowerCase())) {
        continue;
      }
      
      total++;
      
      if (_isOpenShift(shift)) {
        opens++;
      } else if (_isCloseShift(shift)) {
        closes++;
      } else if (_isMidShift(shift)) {
        mids++;
      }
    }

    return {
      'total': total,
      'opens': opens,
      'closes': closes,
      'mids': mids,
    };
  }

  // Get shift runner counts by shift type for an employee
  Map<String, int> _getEmployeeRunnerStats(String employeeName) {
    final runnerCounts = <String, int>{};
    
    for (final runner in _shiftRunners) {
      if (runner.runnerName.toLowerCase() == employeeName.toLowerCase()) {
        runnerCounts[runner.shiftType] = (runnerCounts[runner.shiftType] ?? 0) + 1;
      }
    }
    
    return runnerCounts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Analytics'),
      ),
      body: Column(
        children: [
          // Month selector and filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Month selector row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMonth,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${_monthName(_selectedMonth.month)} ${_selectedMonth.year}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search and filter row
                Row(
                  children: [
                    // Search bar
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search employees...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Job code filter
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedJobCode,
                        decoration: InputDecoration(
                          labelText: 'Job Code',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All'),
                          ),
                          ..._getUniqueJobCodes().map((code) => DropdownMenuItem<String>(
                            value: code,
                            child: Text(code.toUpperCase()),
                          )),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedJobCode = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildAnalyticsContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    final filteredEmployees = _getFilteredEmployees();
    
    if (filteredEmployees.isEmpty) {
      return const Center(child: Text('No employees found'));
    }

    // Get shift types for rows
    final shiftTypes = ShiftRunner.shiftTypes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift Statistics Table (transposed - employees as columns)
          Text(
            'Shift Statistics',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildShiftStatsTable(filteredEmployees),
            ),
          ),
          const SizedBox(height: 24),
          // Shift Runner Statistics Table (transposed - employees as columns)
          if (shiftTypes.isNotEmpty) ...[
            Text(
              'Shifts Run (by Shift Type)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildRunnerStatsTable(filteredEmployees, shiftTypes),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftStatsTable(List<Employee> employees) {
    // Pre-calculate stats for all employees
    final allStats = <int, Map<String, int>>{};
    for (final emp in employees) {
      allStats[emp.id!] = _getEmployeeShiftStats(emp.id!);
    }

    const rowLabels = ['Total Shifts', 'Opens', 'Closes', 'Mids'];
    const statKeys = ['total', 'opens', 'closes', 'mids'];

    return DataTable(
      columnSpacing: 16,
      columns: [
        const DataColumn(label: Text('Stat', style: TextStyle(fontWeight: FontWeight.bold))),
        ...employees.map((emp) => DataColumn(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              emp.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        )),
      ],
      rows: List.generate(rowLabels.length, (idx) {
        return DataRow(cells: [
          DataCell(Text(rowLabels[idx], style: const TextStyle(fontWeight: FontWeight.bold))),
          ...employees.map((emp) {
            final stats = allStats[emp.id!]!;
            return DataCell(
              Center(child: Text('${stats[statKeys[idx]]}')),
            );
          }),
        ]);
      }),
    );
  }

  Widget _buildRunnerStatsTable(List<Employee> employees, List shiftTypes) {
    // Pre-calculate runner stats for all employees
    final allRunnerStats = <String, Map<String, int>>{};
    for (final emp in employees) {
      allRunnerStats[emp.name] = _getEmployeeRunnerStats(emp.name);
    }

    return DataTable(
      columnSpacing: 16,
      columns: [
        const DataColumn(label: Text('Shift Type', style: TextStyle(fontWeight: FontWeight.bold))),
        ...employees.map((emp) => DataColumn(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              emp.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        )),
      ],
      rows: [
        // Rows for each shift type
        ...shiftTypes.map((st) {
          return DataRow(cells: [
            DataCell(Text(st.label, style: const TextStyle(fontWeight: FontWeight.bold))),
            ...employees.map((emp) {
              final stats = allRunnerStats[emp.name]!;
              final count = stats[st.key] ?? 0;
              return DataCell(Center(child: Text('$count')));
            }),
          ]);
        }),
        // Total row
        DataRow(cells: [
          const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
          ...employees.map((emp) {
            final stats = allRunnerStats[emp.name]!;
            int total = 0;
            for (final count in stats.values) {
              total += count;
            }
            return DataCell(
              Center(child: Text('$total', style: const TextStyle(fontWeight: FontWeight.bold))),
            );
          }),
        ]),
      ],
    );
  }
}
