import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/employee.dart';
import '../models/settings.dart';
import '../providers/employee_provider.dart';
import '../services/app_colors.dart';
import '../providers/settings_provider.dart';
import '../providers/time_off_provider.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';

class PtoVacTrackerPage extends StatefulWidget {
  const PtoVacTrackerPage({super.key});

  @override
  State<PtoVacTrackerPage> createState() => _PtoVacTrackerPageState();
}

class _PtoVacTrackerPageState extends State<PtoVacTrackerPage>
    with LoadingStateMixin<PtoVacTrackerPage> {
  int _selectedTrimesterYear = DateTime.now().year;
  int? _selectedEmployeeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
    });
  }

  Future<void> _loadAllData() async {
    await _loadProvidersData();
    _setDefaultSelectedEmployee();
  }

  Future<void> _loadProvidersData() async {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final timeOffProvider = Provider.of<TimeOffProvider>(
      context,
      listen: false,
    );

    // Load all required data
    await Future.wait([
      employeeProvider.loadEmployees(),
      settingsProvider.loadSettings(),
      timeOffProvider.loadData(),
    ]);
  }

  void _setDefaultSelectedEmployee() {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    final timeOffProvider = Provider.of<TimeOffProvider>(
      context,
      listen: false,
    );

    final ptoEmployees = timeOffProvider.getPtoEnabledEmployees(
      employeeProvider.employees,
    );

    if (ptoEmployees.isNotEmpty && _selectedEmployeeId == null) {
      setState(() {
        _selectedEmployeeId = ptoEmployees.first.id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PTO / VAC Tracker")),
      body: Consumer3<EmployeeProvider, SettingsProvider, TimeOffProvider>(
        builder:
            (
              context,
              employeeProvider,
              settingsProvider,
              timeOffProvider,
              child,
            ) {
              if (isLoading ||
                  employeeProvider.isLoading ||
                  settingsProvider.isLoading ||
                  timeOffProvider.isLoading) {
                return const LoadingIndicator();
              }

              if (employeeProvider.errorMessage != null ||
                  settingsProvider.errorMessage != null ||
                  timeOffProvider.errorMessage != null) {
                return ErrorMessage(
                  message:
                      employeeProvider.errorMessage ??
                      settingsProvider.errorMessage ??
                      timeOffProvider.errorMessage!,
                  onRetry: _loadAllData,
                );
              }

              final settings = settingsProvider.settings;
              if (settings == null) {
                return const ErrorMessage(message: 'Settings not available');
              }

              return RefreshIndicator(
                onRefresh: _loadAllData,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPtoSummaryTable(
                        employeeProvider,
                        settingsProvider,
                        timeOffProvider,
                      ),
                      const SizedBox(height: 24),
                      _buildPtoTrimesterBreakdownSection(
                        employeeProvider,
                        settingsProvider,
                        timeOffProvider,
                      ),
                      const SizedBox(height: 24),
                      _buildVacationSection(employeeProvider, timeOffProvider),
                    ],
                  ),
                ),
              );
            },
      ),
    );
  }

  Widget _buildPtoSummaryTable(
    EmployeeProvider employeeProvider,
    SettingsProvider settingsProvider,
    TimeOffProvider timeOffProvider,
  ) {
    final settings = settingsProvider.settings!;
    final ptoEmployees = timeOffProvider.getPtoEnabledEmployees(
      employeeProvider.employees,
    );

    if (ptoEmployees.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "PTO Summary",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              const Text("No employees with PTO enabled found."),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PTO Summary",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAllPtoSummaries(
                  ptoEmployees,
                  settings,
                  timeOffProvider,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingIndicator();
                  }

                  if (snapshot.hasError) {
                    return ErrorMessage(
                      message:
                          'Failed to load PTO summaries: ${snapshot.error}',
                    );
                  }

                  final rows = snapshot.data ?? [];

                  return DataTable(
                    columns: const [
                      DataColumn(label: Text("Employee")),
                      DataColumn(label: Text("Allowance")),
                      DataColumn(label: Text("Carryover")),
                      DataColumn(label: Text("Used")),
                      DataColumn(label: Text("Remaining")),
                    ],
                    rows: rows.map((row) {
                      return DataRow(
                        cells: [
                          DataCell(Text(row['name'] ?? '')),
                          DataCell(Text("${row['allowance']}h")),
                          DataCell(Text("${row['carryover']}h")),
                          DataCell(Text("${row['used']}h")),
                          DataCell(Text("${row['remaining']}h")),
                        ],
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllPtoSummaries(
    List<Employee> ptoEmployees,
    Settings settings,
    TimeOffProvider timeOffProvider,
  ) async {
    final List<Map<String, dynamic>> summaries = [];

    for (final employee in ptoEmployees) {
      try {
        final pto = await timeOffProvider.calculatePto(employee, settings);
        summaries.add({
          'name': employee.displayName,
          'allowance': pto['allowance'] ?? 0,
          'carryover': pto['carryover'] ?? 0,
          'used': pto['used'] ?? 0,
          'remaining': pto['remaining'] ?? 0,
        });
      } catch (e) {
        debugPrint('Error calculating PTO for ${employee.displayName}: $e');
      }
    }

    return summaries;
  }

  Widget _buildPtoTrimesterBreakdownSection(
    EmployeeProvider employeeProvider,
    SettingsProvider settingsProvider,
    TimeOffProvider timeOffProvider,
  ) {
    final settings = settingsProvider.settings!;
    final ptoEmployees = timeOffProvider.getPtoEnabledEmployees(
      employeeProvider.employees,
    );

    if (ptoEmployees.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "PTO Trimester Breakdown",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              const Text("No employees with PTO enabled found."),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PTO trimester breakdown",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Row(
              children: [
                const Text("Year: "),
                DropdownButton<int>(
                  value: _selectedTrimesterYear,
                  items: List.generate(5, (i) => DateTime.now().year - 2 + i)
                      .map(
                        (year) => DropdownMenuItem(
                          value: year,
                          child: Text(year.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedTrimesterYear = value);
                    }
                  },
                ),
                const SizedBox(width: 24),
                const Text("Employee: "),
                DropdownButton<int?>(
                  value: _selectedEmployeeId,
                  items: ptoEmployees
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedEmployeeId = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (_) {
                final selectedEmployee = ptoEmployees
                    .where((e) => e.id == _selectedEmployeeId)
                    .firstOrNull;

                if (selectedEmployee == null) {
                  return const Text("Please select an employee.");
                }

                final summaries = timeOffProvider.calculateTrimesterSummaries(
                  selectedEmployee,
                  settings,
                  year: _selectedTrimesterYear,
                );

                if (summaries.isEmpty) {
                  return const Text("No data available for selected year.");
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text("Trimester")),
                      DataColumn(label: Text("Earned")),
                      DataColumn(label: Text("Carryover In")),
                      DataColumn(label: Text("Available")),
                      DataColumn(label: Text("Used")),
                      DataColumn(label: Text("Remaining")),
                      DataColumn(label: Text("Carryover Out")),
                    ],
                    rows: summaries.map((summary) {
                      return DataRow(
                        cells: [
                          DataCell(Text(summary.label)),
                          DataCell(Text("${summary.earned}h")),
                          DataCell(Text("${summary.carryoverIn}h")),
                          DataCell(Text("${summary.available}h")),
                          DataCell(Text("${summary.used}h")),
                          DataCell(Text("${summary.remaining}h")),
                          DataCell(Text("${summary.carryoverOut}h")),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacationSection(
    EmployeeProvider employeeProvider,
    TimeOffProvider timeOffProvider,
  ) {
    // Filter employees who have vacation weeks allocated
    final vacationEmployees = employeeProvider.employees
        .where((e) => e.vacationWeeksAllowed > 0)
        .toList();

    if (vacationEmployees.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Vacation Weeks",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              const Text("No employees with vacation weeks allocated."),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Vacation weeks",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...vacationEmployees.map(
              (e) => _buildVacationRow(e, timeOffProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacationRow(Employee employee, TimeOffProvider timeOffProvider) {
    final used = timeOffProvider.getVacationWeeksUsed(employee);
    final remaining = timeOffProvider.getVacationWeeksRemaining(employee);
    final allowed = employee.vacationWeeksAllowed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              employee.displayName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text("Allowed: $allowed")),
          Expanded(child: Text("Used: $used")),
          Expanded(
            child: Text(
              "Remaining: $remaining",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: remaining > 0
                    ? context.appColors.successForeground
                    : context.appColors.errorForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
