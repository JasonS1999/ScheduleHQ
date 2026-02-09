import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/employee_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/time_off_provider.dart';
import '../providers/approval_provider.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';

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
      final employeeProvider = Provider.of<EmployeeProvider>(context, listen: false);
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final timeOffProvider = Provider.of<TimeOffProvider>(context, listen: false);
      final approvalProvider = Provider.of<ApprovalProvider>(context, listen: false);

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
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approval Queue'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending Requests'),
            Tab(text: 'Approved Entries'),
          ],
        ),
      ),
      body: Consumer4<EmployeeProvider, SettingsProvider, TimeOffProvider, ApprovalProvider>(
        builder: (context, employeeProvider, settingsProvider, timeOffProvider, approvalProvider, child) {
          if (isLoading || employeeProvider.isLoading || settingsProvider.isLoading || 
              timeOffProvider.isLoading || approvalProvider.isLoading) {
            return const LoadingIndicator();
          }

          if (employeeProvider.errorMessage != null || 
              settingsProvider.errorMessage != null || timeOffProvider.errorMessage != null ||
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
              _buildPendingRequestsTab(approvalProvider, settings),
              _buildApprovedEntriesTab(approvalProvider),
            ],
          );
        },
      ),
    );
  }

  // Placeholder methods - these need full implementation
  Widget _buildPendingRequestsTab(dynamic approvalProvider, dynamic settings) {
    return const Center(
      child: Text('Pending Requests Tab - To be implemented'),
    );
  }

  Widget _buildApprovedEntriesTab(dynamic approvalProvider) {
    return const Center(
      child: Text('Approved Entries Tab - To be implemented'),
    );
  }

}
