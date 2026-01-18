import 'package:flutter/material.dart';
import 'pages/schedule_page.dart';
import 'pages/time_off_page.dart';
import 'pages/roster_page.dart';
import 'package:work_schedule_app/pages/settings_page.dart';
import 'pages/pto_vac_tracker_page.dart';
import 'pages/analytics_page.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    SchedulePage(),
    TimeOffPage(),
    RosterPage(),
    PtoVacTrackerPage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  final List<String> _titles = const [
    "Schedule",
    "Time Off",
    "Roster",
    "PTO / VAC Tracker",
    "Analytics",
    "Settings",
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.calendar_month),
                  label: Text("Schedule"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.beach_access),
                  label: Text("Time Off"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people),
                  label: Text("Roster"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.track_changes),
                  label: Text("PTO / VAC"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.analytics),
                  label: Text("Analytics"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text("Settings"),
                ),
              ],
            ),

          Expanded(
            child: _pages[_index],
          ),
        ],
      ),

      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month),
                  label: "Schedule",
                ),
                NavigationDestination(
                  icon: Icon(Icons.beach_access),
                  label: "Time Off",
                ),
                NavigationDestination(
                  icon: Icon(Icons.people),
                  label: "Roster",
                ),
                NavigationDestination(
                  icon: Icon(Icons.track_changes),
                  label: "PTO / VAC",
                ),
                NavigationDestination(
                  icon: Icon(Icons.analytics),
                  label: "Analytics",
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: "Settings",
                ),
              ],
            ),
    );
  }
}
