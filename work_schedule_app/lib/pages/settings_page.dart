import 'package:flutter/material.dart';
import '../widgets/settings/pto_rules_tab.dart';
import '../widgets/settings/job_codes_tab.dart';
import '../widgets/settings/shift_runner_colors_tab.dart';
import '../widgets/settings/schedule_settings_tab.dart';
import '../widgets/settings/shift_templates_tab.dart';
import '../widgets/settings/store_hours_tab.dart';
import '../services/theme_service.dart';

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
    _tabController = TabController(length: 6, vsync: this);
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
          ValueListenableBuilder(
            valueListenable: appThemeMode,
            builder: (context, ThemeMode mode, _) {
              IconData icon;
              if (mode == ThemeMode.dark) {
                icon = Icons.dark_mode;
              } else if (mode == ThemeMode.light) {
                icon = Icons.light_mode;
              } else {
                icon = Icons.brightness_auto;
              }

              return PopupMenuButton<ThemeMode>(
                icon: Icon(icon),
                onSelected: (m) => appThemeMode.value = m,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: ThemeMode.system, child: Text('System')),
                  PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
                  PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
