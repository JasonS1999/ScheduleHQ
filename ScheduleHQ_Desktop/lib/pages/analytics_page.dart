import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/employee_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/time_off_provider.dart';
import '../providers/analytics_provider.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';

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
    final employeeProvider = Provider.of<EmployeeProvider>(context, listen: false);
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final timeOffProvider = Provider.of<TimeOffProvider>(context, listen: false);
    final analyticsProvider = Provider.of<AnalyticsProvider>(context, listen: false);
    
    // Load all required data - each provider handles its own loading state
    await Future.wait([
      employeeProvider.loadEmployees(),
      scheduleProvider.loadSchedule(),
      timeOffProvider.loadData(),
      analyticsProvider.loadData(),
    ]);
  }

  void _onSearchChanged(String query) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(context, listen: false);
    analyticsProvider.setSearchQuery(query);
  }

  void _onJobCodeChanged(String? jobCode) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(context, listen: false);
    analyticsProvider.setSelectedJobCode(jobCode);
  }

  void _onMonthChanged(DateTime month) {
    final analyticsProvider = Provider.of<AnalyticsProvider>(context, listen: false);
    analyticsProvider.setSelectedMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Analytics")),
      body: Consumer4<EmployeeProvider, ScheduleProvider, TimeOffProvider, AnalyticsProvider>(
        builder: (context, employeeProvider, scheduleProvider, timeOffProvider, analyticsProvider, child) {
          if (employeeProvider.isLoading || scheduleProvider.isLoading || 
              timeOffProvider.isLoading || analyticsProvider.isLoading) {
            return const LoadingIndicator();
          }

          if (employeeProvider.errorMessage != null || 
              scheduleProvider.errorMessage != null || timeOffProvider.errorMessage != null ||
              analyticsProvider.errorMessage != null) {
            return ErrorMessage(
              message: employeeProvider.errorMessage ?? 
                       scheduleProvider.errorMessage ?? 
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
                  _buildFiltersSection(analyticsProvider, employeeProvider),
                  const SizedBox(height: 24),
                  _buildAnalyticsTable(
                    employeeProvider, 
                    scheduleProvider, 
                    timeOffProvider, 
                    analyticsProvider
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFiltersSection(AnalyticsProvider analyticsProvider, EmployeeProvider employeeProvider) {
    final jobCodes = analyticsProvider.getAvailableJobCodes(employeeProvider.employees);

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
                // Month Selection
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Month:", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final selectedMonth = await showDatePicker(
                            context: context,
                            initialDate: analyticsProvider.selectedMonth,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (selectedMonth != null) {
                            _onMonthChanged(selectedMonth);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "${analyticsProvider.selectedMonth.month}/${analyticsProvider.selectedMonth.year}",
                                style: const TextStyle(fontSize: 16),
                              ),
                              const Icon(Icons.calendar_today),
                            ],
                          ),
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
                      const Text("Job Code:", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: analyticsProvider.selectedJobCode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("All Job Codes"),
                          ),
                          ...jobCodes.map((code) => DropdownMenuItem<String>(
                            value: code,
                            child: Text(code),
                          )),
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
    ScheduleProvider scheduleProvider,
    TimeOffProvider timeOffProvider,
    AnalyticsProvider analyticsProvider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Employee Analytics - ${analyticsProvider.selectedMonth.month}/${analyticsProvider.selectedMonth.year}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<EmployeeAnalytics>>(
              future: analyticsProvider.getEmployeeAnalytics(
                employeeProvider.employees,
                scheduleProvider.shifts,
                scheduleProvider.shiftRunners,
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
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text("Employee")),
                      DataColumn(label: Text("Job Code")),
                      DataColumn(label: Text("Total Hours")),
                      DataColumn(label: Text("Shift Count")),
                      DataColumn(label: Text("Avg Hours/Shift")),
                      DataColumn(label: Text("Mid Shift %")),
                    ],
                    rows: analytics.map((data) {
                      return DataRow(
                        cells: [
                          DataCell(Text(data.employee.displayName)),
                          DataCell(Text(data.employee.jobCode)),
                          DataCell(Text(data.totalHours.toStringAsFixed(1))),
                          DataCell(Text(data.shiftCount.toString())),
                          DataCell(Text(data.averageHoursPerShift.toStringAsFixed(1))),
                          DataCell(Text("${data.midShiftPercentage.toStringAsFixed(0)}%")),
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
}
