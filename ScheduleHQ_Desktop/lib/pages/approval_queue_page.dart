import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/employee_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/time_off_provider.dart';
import '../providers/approval_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/firestore_sync_service.dart';
import '../utils/loading_state_mixin.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';
import '../widgets/time_off/requests_management_tab.dart';
import '../widgets/time_off/time_off_calendar_tab.dart';
import '../widgets/onboarding/coach_mark_controller.dart';
import '../widgets/onboarding/coach_mark_overlay.dart';

class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({super.key});

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage>
    with SingleTickerProviderStateMixin, LoadingStateMixin<ApprovalQueuePage> {
  late TabController _tabController;
  CoachMarkController? _coachMarkController;

  // Coach mark target keys
  final GlobalKey _requestsTabKey = GlobalKey(debugLabel: 'requestsTab');
  final GlobalKey _calendarTabKey = GlobalKey(debugLabel: 'calendarTab');
  final GlobalKey _appBarKey = GlobalKey(debugLabel: 'timeOffAppBar');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData().then((_) {
        if (!mounted) return;
        final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
        if (onboarding.shouldShowTimeOffCoach) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _startTimeOffCoachMarks();
          });
        }
      });
    });
  }

  void _startTimeOffCoachMarks() {
    _coachMarkController = CoachMarkController(
      steps: [
        CoachMarkStep(
          targetKey: _appBarKey,
          title: 'Time Off Management',
          description:
              'This is where you manage all time-off requests. Employees can submit PTO, vacation, and requested days off through the mobile app, and they\'ll appear here for your review.',
          preferredPosition: TooltipPosition.below,
        ),
        CoachMarkStep(
          targetKey: _requestsTabKey,
          title: 'Requests & Management',
          description:
              "View, approve, or deny time-off requests here. Use the 'Add Entry' button to manually create entries. Filter by employee, type, or search by name.",
          preferredPosition: TooltipPosition.below,
        ),
        CoachMarkStep(
          targetKey: _calendarTabKey,
          title: 'Time Off Calendar',
          description:
              'Switch to Calendar view to see all approved time off laid out visually. Great for spotting coverage gaps before finalizing schedules.',
          preferredPosition: TooltipPosition.below,
        ),
      ],
      onComplete: () {
        final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
        onboarding.markTimeOffCoachCompleted();
      },
      onSkip: () {
        final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
        onboarding.markTimeOffCoachCompleted();
      },
    );
    _coachMarkController!.start(context);
  }

  @override
  void dispose() {
    _coachMarkController?.dispose();
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
        key: _appBarKey,
        title: const Text('Time Off'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              key: _requestsTabKey,
              icon: const Icon(Icons.inbox, size: 18),
              text: 'Requests & Management',
            ),
            Tab(
              key: _calendarTabKey,
              icon: const Icon(Icons.calendar_month, size: 18),
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
