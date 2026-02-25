import 'package:flutter/material.dart';
import '../widgets/settings/pto_rules_tab.dart';
import '../widgets/settings/job_codes_tab.dart';
import '../widgets/settings/shift_runner_colors_tab.dart';
import '../widgets/settings/schedule_settings_tab.dart';
import '../widgets/settings/shift_templates_tab.dart';
import '../widgets/settings/store_hours_tab.dart';
import '../widgets/settings/cloud_sync_tab.dart';
import '../widgets/settings/account_tab.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/onboarding_provider.dart';
import '../utils/app_constants.dart';
import '../widgets/onboarding/coach_mark_controller.dart';
import '../widgets/onboarding/coach_mark_overlay.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CoachMarkController? _coachMarkController;

  // Coach mark target keys
  final GlobalKey _storeSettingsTabKey = GlobalKey(debugLabel: 'storeSettingsTab');
  final GlobalKey _jobCodesTabKey = GlobalKey(debugLabel: 'jobCodesTab');
  final GlobalKey _ptoRulesTabKey = GlobalKey(debugLabel: 'ptoRulesTab');
  final GlobalKey _shiftTemplatesTabKey = GlobalKey(debugLabel: 'shiftTemplatesTab');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
      if (onboarding.shouldShowSettingsCoach) {
        _startSettingsCoachMarks();
      }
    });
  }

  void _startSettingsCoachMarks() {
    _coachMarkController = CoachMarkController(
      steps: [
        CoachMarkStep(
          targetKey: _storeSettingsTabKey,
          title: 'Configure Your Store',
          description: 'Start here! Set your store name and operating hours for each day of the week.',
          preferredPosition: TooltipPosition.below,
          onShow: () => _tabController.animateTo(4),
        ),
        CoachMarkStep(
          targetKey: _jobCodesTabKey,
          title: 'Set Up Job Codes',
          description: 'Define job codes like Assistant, Swing, or Supervisor. Assign colors and configure hours for each role.',
          preferredPosition: TooltipPosition.below,
          onShow: () => _tabController.animateTo(1),
        ),
        CoachMarkStep(
          targetKey: _ptoRulesTabKey,
          title: 'Configure PTO Rules',
          description: 'Set PTO hours per trimester and maximum carryover hours for your team.',
          preferredPosition: TooltipPosition.below,
          onShow: () => _tabController.animateTo(0),
        ),
        CoachMarkStep(
          targetKey: _shiftTemplatesTabKey,
          title: 'Create Shift Templates',
          description: 'Define reusable shift templates (e.g. 9-5, 2-10) to speed up scheduling.',
          preferredPosition: TooltipPosition.below,
          onShow: () => _tabController.animateTo(2),
        ),
      ],
      onComplete: () {
        final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
        onboarding.markSettingsCoachCompleted();
      },
      onSkip: () {
        final onboarding = Provider.of<OnboardingProvider>(context, listen: false);
        onboarding.markSettingsCoachCompleted();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        actions: [
          // Theme mode selector
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              IconData icon;
              if (settings.isDarkTheme) {
                icon = Icons.dark_mode;
              } else if (settings.isLightTheme) {
                icon = Icons.light_mode;
              } else {
                icon = Icons.brightness_auto;
              }

              return PopupMenuButton<String>(
                icon: Icon(icon),
                onSelected: (m) => settings.setThemeMode(m),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: AppConstants.systemThemeKey, child: Text('System')),
                  PopupMenuItem(value: AppConstants.lightThemeKey, child: Text('Light')),
                  PopupMenuItem(value: AppConstants.darkThemeKey, child: Text('Dark')),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(key: _ptoRulesTabKey, text: "PTO Rules"),
            Tab(key: _jobCodesTabKey, text: "Job Codes"),
            Tab(key: _shiftTemplatesTabKey, text: "Shift Templates"),
            const Tab(text: "Shift Runner"),
            Tab(key: _storeSettingsTabKey, text: "Store Settings"),
            const Tab(text: "Schedule"),
            const Tab(text: "Cloud Sync"),
            const Tab(text: "Account"),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PtoRulesTab(),
                JobCodesTab(),
                ShiftTemplatesTab(),
                ShiftRunnerColorsTab(),
                StoreHoursTab(),
                ScheduleSettingsTab(),
                CloudSyncTab(),
                AccountTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
