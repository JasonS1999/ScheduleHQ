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
import '../utils/app_constants.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
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
          tabs: const [
            Tab(text: "PTO Rules"),
            Tab(text: "Job Codes"),
            Tab(text: "Shift Templates"),
            Tab(text: "Shift Runner"),
            Tab(text: "Store Settings"),
            Tab(text: "Schedule"),
            Tab(text: "Cloud Sync"),
            Tab(text: "Account"),
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
