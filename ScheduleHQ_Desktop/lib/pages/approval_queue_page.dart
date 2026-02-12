import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/employee_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/time_off_provider.dart';
import '../providers/approval_provider.dart';
import '../services/firestore_sync_service.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';
import '../widgets/time_off/requests_management_tab.dart';
import '../widgets/time_off/time_off_calendar_tab.dart';

class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({super.key});

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage>
    with SingleTickerProviderStateMixin, LoadingStateMixin<ApprovalQueuePage> {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await withLoading(() async {
      final employeeProvider =
          Provider.of<EmployeeProvider>(context, listen: false);
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final timeOffProvider =
          Provider.of<TimeOffProvider>(context, listen: false);
      final approvalProvider =
          Provider.of<ApprovalProvider>(context, listen: false);

      // Load all required data
      await Future.wait([
        employeeProvider.loadEmployees(),
        settingsProvider.loadSettings(),
        timeOffProvider.loadData(),
      ]);

      // Initialize approval provider with employee data
      approvalProvider.initializeEmployees(employeeProvider.employees);

      // Load additional approval-specific data
      await Future.wait([
        approvalProvider.loadApprovedEntries(),
        approvalProvider.preloadJobCodeColors(employeeProvider.employees),
        // One-time migration: rename 'sick' to 'requested' in Firestore
        FirestoreSyncService.instance.migrateSickToRequested(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Off'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.inbox, size: 18),
              text: 'Requests & Management',
            ),
            Tab(
              icon: Icon(Icons.calendar_month, size: 18),
              text: 'Calendar',
            ),
          ],
        ),
      ),
      body: Consumer4<EmployeeProvider, SettingsProvider, TimeOffProvider,
          ApprovalProvider>(
        builder: (context, employeeProvider, settingsProvider, timeOffProvider,
            approvalProvider, child) {
          if (isLoading ||
              employeeProvider.isLoading ||
              settingsProvider.isLoading ||
              timeOffProvider.isLoading ||
              approvalProvider.isLoading) {
            return const LoadingIndicator();
          }

          if (employeeProvider.errorMessage != null ||
              settingsProvider.errorMessage != null ||
              timeOffProvider.errorMessage != null ||
              approvalProvider.errorMessage != null) {
            return ErrorMessage(
              message: employeeProvider.errorMessage ??
                  settingsProvider.errorMessage ??
                  timeOffProvider.errorMessage ??
                  approvalProvider.errorMessage!,
              onRetry: _loadAllData,
            );
          }

          final settings = settingsProvider.settings;
          if (settings == null) {
            return const ErrorMessage(
              message: 'Settings not available',
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              RequestsManagementTab(
                approvalProvider: approvalProvider,
                employeeProvider: employeeProvider,
                timeOffProvider: timeOffProvider,
                settings: settings,
              ),
              TimeOffCalendarTab(
                approvalProvider: approvalProvider,
                employeeProvider: employeeProvider,
                timeOffProvider: timeOffProvider,
              ),
            ],
          );
        },
      ),
    );
  }
}
