import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/employee_provider.dart';
import '../services/app_colors.dart';
import '../providers/time_off_provider.dart';
import '../providers/analytics_provider.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with LoadingStateMixin<AnalyticsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
    });
  }

  Future<void> _loadAllData() async {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    final timeOffProvider = Provider.of<TimeOffProvider>(
      context,
      listen: false,
    );
    final analyticsProvider = Provider.of<AnalyticsProvider>(
      context,
      listen: false,
    );

    // Load all required data - each provider handles its own loading state
    await Future.wait([
      employeeProvider.loadEmployees(),
      timeOffProvider.loadData(),
      analyticsProvider.loadData(),
    ]);
  }

  void _onSearchChanged(String query) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(
      context,
      listen: false,
    );
    analyticsProvider.setSearchQuery(query);
  }

  void _onJobCodeChanged(String? jobCode) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(
      context,
      listen: false,
    );
    analyticsProvider.setSelectedJobCode(jobCode);
  }

  void _onMonthChanged(DateTime month) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(
      context,
      listen: false,
    );
    analyticsProvider.setSelectedMonth(month);
  }

  String _formatMonth(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Analytics")),
      body:
          Consumer3<
            EmployeeProvider,
            TimeOffProvider,
            AnalyticsProvider
          >(
            builder:
                (
                  context,
                  employeeProvider,
                  timeOffProvider,
                  analyticsProvider,
                  child,
                ) {
                  if (employeeProvider.isLoading ||
                      timeOffProvider.isLoading ||
                      analyticsProvider.isLoading) {
                    return const LoadingIndicator();
                  }

                  if (employeeProvider.errorMessage != null ||
                      timeOffProvider.errorMessage != null ||
                      analyticsProvider.errorMessage != null) {
                    return ErrorMessage(
                      message:
                          employeeProvider.errorMessage ??
                          timeOffProvider.errorMessage ??
                          analyticsProvider.errorMessage!,
                      onRetry: _loadAllData,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _loadAllData,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFiltersSection(
                            analyticsProvider,
                            employeeProvider,
                          ),
                          const SizedBox(height: 24),
                          _buildAnalyticsTable(
                            employeeProvider,
                            timeOffProvider,
                            analyticsProvider,
                          ),
                        ],
                      ),
                    ),
                  );
                },
          ),
    );
  }

  Widget _buildFiltersSection(
    AnalyticsProvider analyticsProvider,
    EmployeeProvider employeeProvider,
  ) {
    final jobCodes = analyticsProvider.getAvailableJobCodes(
      employeeProvider.employees,
    );
    final selected = analyticsProvider.selectedMonth;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Filters",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Month Selection with arrow navigation
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Month:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.appColors.borderMedium,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () {
                                final prev = DateTime(selected.year, selected.month - 1, 1);
                                _onMonthChanged(prev);
                              },
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'Previous month',
                            ),
                            Text(
                              _formatMonth(selected),
                              style: const TextStyle(fontSize: 16),
                            ),
                            IconButton(
                              onPressed: () {
                                final next = DateTime(selected.year, selected.month + 1, 1);
                                _onMonthChanged(next);
                              },
                              icon: const Icon(Icons.chevron_right),
                              tooltip: 'Next month',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Job Code Filter
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Job Code:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: analyticsProvider.selectedJobCode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("All Job Codes"),
                          ),
                          ...jobCodes.map(
                            (code) => DropdownMenuItem<String>(
                              value: code,
                              child: Text(code),
                            ),
                          ),
                        ],
                        onChanged: _onJobCodeChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Search Filter
            TextField(
              decoration: const InputDecoration(
                labelText: "Search employees",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTable(
    EmployeeProvider employeeProvider,
    TimeOffProvider timeOffProvider,
    AnalyticsProvider analyticsProvider,
  ) {
    final shiftTypes = analyticsProvider.shiftTypes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Employee Analytics - ${_formatMonth(analyticsProvider.selectedMonth)}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<EmployeeAnalytics>>(
              future: analyticsProvider.getEmployeeAnalytics(
                employeeProvider.employees,
                timeOffProvider.jobCodeSettings,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingIndicator();
                }

                if (snapshot.hasError) {
                  return ErrorMessage(
                    message: 'Failed to load analytics: ${snapshot.error}',
                  );
                }

                final analytics = snapshot.data ?? [];

                if (analytics.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        "No employees found matching the current filters.",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 64,
                    ),
                    child: DataTable(
                      columnSpacing: 24,
                      columns: [
                        const DataColumn(label: Text("Employee")),
                        const DataColumn(label: Text("Job Code")),
                        const DataColumn(label: Text("Total Shifts")),
                        const DataColumn(label: Text("Total Runners")),
                        const DataColumn(label: Text("Avg Hours/Week")),
                        ...shiftTypes.map(
                          (st) => DataColumn(label: Text(st.label)),
                        ),
                      ],
                      rows: analytics.map((data) {
                        return DataRow(
                          cells: [
                            DataCell(Text(data.employee.displayName)),
                            DataCell(Text(data.employee.jobCode)),
                            DataCell(Text(data.totalShifts.toString())),
                            DataCell(Text(data.totalRunnerCount.toString())),
                            DataCell(Text(data.avgHoursPerWeek.toStringAsFixed(1))),
                            ...shiftTypes.map(
                              (st) => DataCell(
                                Text(
                                  (data.runnerCountsByShiftType[st.key] ?? 0).toString(),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
