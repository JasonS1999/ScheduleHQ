import 'package:flutter/material.dart';
import '../../database/settings_dao.dart';
import '../../database/employee_dao.dart';
import '../../database/tracked_employee_dao.dart';
import '../../database/job_code_settings_dao.dart';
import '../../models/settings.dart';
import '../../models/employee.dart';
import '../../models/job_code_settings.dart';

class ScheduleSettingsTab extends StatefulWidget {
  const ScheduleSettingsTab({super.key});

  @override
  State<ScheduleSettingsTab> createState() => _ScheduleSettingsTabState();
}

class _ScheduleSettingsTabState extends State<ScheduleSettingsTab> {
  final SettingsDao _settingsDao = SettingsDao();
  final EmployeeDao _employeeDao = EmployeeDao();
  final TrackedEmployeeDao _trackedEmployeeDao = TrackedEmployeeDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();

  Settings? _settings;
  List<Employee> _allEmployees = [];
  List<int> _trackedEmployeeIds = [];
  List<JobCodeSettings> _jobCodeSettings = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = await _settingsDao.getSettings();
    final employees = await _employeeDao.getEmployees();
    final trackedIds = await _trackedEmployeeDao.getTrackedEmployeeIds();
    final jobCodeSettings = await _jobCodeSettingsDao.getAll();

    setState(() {
      _settings = settings;
      _allEmployees = employees;
      _trackedEmployeeIds = trackedIds;
      _jobCodeSettings = jobCodeSettings;
    });
  }

  Future<void> _save() async {
    if (_settings == null) return;
    await _settingsDao.updateSettings(_settings!);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Schedule settings saved")));
  }

  Future<void> _saveTrackedEmployees() async {
    // Sort tracked employees by job code before saving
    final sortedIds = _getSortedTrackedEmployeeIds();
    await _trackedEmployeeDao.setTrackedEmployees(sortedIds);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Tracked employees saved")));
  }

  List<int> _getSortedTrackedEmployeeIds() {
    // Get tracked employees and sort them by job code
    final trackedEmployees = _allEmployees
        .where((e) => e.id != null && _trackedEmployeeIds.contains(e.id))
        .toList();

    // Sort by job code order
    final jobCodeOrder = <String, int>{};
    for (int i = 0; i < _jobCodeSettings.length; i++) {
      jobCodeOrder[_jobCodeSettings[i].code.toLowerCase()] = i;
    }

    trackedEmployees.sort((a, b) {
      final aOrder = jobCodeOrder[a.jobCode.toLowerCase()] ?? 999;
      final bOrder = jobCodeOrder[b.jobCode.toLowerCase()] ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.name.compareTo(b.name);
    });

    return trackedEmployees.map((e) => e.id!).toList();
  }

  List<Employee> _getFilteredEmployees() {
    if (_searchQuery.isEmpty) return _allEmployees;
    final query = _searchQuery.toLowerCase();
    return _allEmployees.where((e) {
      return e.name.toLowerCase().contains(query) ||
          e.jobCode.toLowerCase().contains(query);
    }).toList();
  }

  List<Employee> _getTrackedEmployeesSorted() {
    final tracked = _allEmployees
        .where((e) => e.id != null && _trackedEmployeeIds.contains(e.id))
        .toList();

    // Sort by job code order
    final jobCodeOrder = <String, int>{};
    for (int i = 0; i < _jobCodeSettings.length; i++) {
      jobCodeOrder[_jobCodeSettings[i].code.toLowerCase()] = i;
    }

    tracked.sort((a, b) {
      final aOrder = jobCodeOrder[a.jobCode.toLowerCase()] ?? 999;
      final bOrder = jobCodeOrder[b.jobCode.toLowerCase()] ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.name.compareTo(b.name);
    });

    return tracked;
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            "Schedule Settings",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Minimum Hours Between Shifts
          TextField(
            decoration: const InputDecoration(
              labelText: "Minimum Hours Between Shifts",
            ),
            keyboardType: TextInputType.number,
            controller: TextEditingController(
              text: _settings!.minimumHoursBetweenShifts.toString(),
            ),
            onChanged: (v) {
              final value = int.tryParse(v) ?? 8;
              setState(() {
                _settings = _settings!.copyWith(
                  minimumHoursBetweenShifts: value,
                );
              });
            },
          ),

          const SizedBox(height: 16),

          // Inventory Day
          DropdownButtonFormField<int>(
            value: _settings!.inventoryDay,
            decoration: const InputDecoration(labelText: "Inventory Day"),
            items: const [
              DropdownMenuItem(value: 1, child: Text("Monday")),
              DropdownMenuItem(value: 2, child: Text("Tuesday")),
              DropdownMenuItem(value: 3, child: Text("Wednesday")),
              DropdownMenuItem(value: 4, child: Text("Thursday")),
              DropdownMenuItem(value: 5, child: Text("Friday")),
              DropdownMenuItem(value: 6, child: Text("Saturday")),
              DropdownMenuItem(value: 7, child: Text("Sunday")),
            ],
            onChanged: (v) {
              setState(() {
                _settings = _settings!.copyWith(inventoryDay: v);
              });
            },
          ),

          const SizedBox(height: 16),

          // Schedule Start Day
          DropdownButtonFormField<int>(
            value: _settings!.scheduleStartDay,
            decoration: const InputDecoration(labelText: "Schedule Start Day"),
            items: const [
              DropdownMenuItem(value: 1, child: Text("Monday")),
              DropdownMenuItem(value: 2, child: Text("Tuesday")),
              DropdownMenuItem(value: 3, child: Text("Wednesday")),
              DropdownMenuItem(value: 4, child: Text("Thursday")),
              DropdownMenuItem(value: 5, child: Text("Friday")),
              DropdownMenuItem(value: 6, child: Text("Saturday")),
              DropdownMenuItem(value: 7, child: Text("Sunday")),
            ],
            onChanged: (v) {
              setState(() {
                _settings = _settings!.copyWith(scheduleStartDay: v);
              });
            },
          ),

          const SizedBox(height: 16),

          // Block overlapping vacations toggle
          SwitchListTile(
            title: const Text('Block overlapping vacations'),
            subtitle: const Text(
              'Prevent creating vacations that overlap existing time off',
            ),
            value: _settings!.blockOverlaps,
            onChanged: (v) {
              setState(() {
                _settings = _settings!.copyWith(blockOverlaps: v);
              });
            },
          ),

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _save,
            child: const Text("Save Schedule Settings"),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Tracked Employees Section
          const Text(
            "PDF Stats Tracking",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Select employees to show in the statistics table at the bottom of monthly PDF exports. "
            "Stats include Opens, Mids, Closes, PTO hours, and Vacation days.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Currently tracked employees (sorted by job code)
          if (_trackedEmployeeIds.isNotEmpty) ...[
            const Text(
              "Currently Tracked (sorted by job code):",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _getTrackedEmployeesSorted().map((emp) {
                return Chip(
                  label: Text('${emp.displayName} (${emp.jobCode})'),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      _trackedEmployeeIds.remove(emp.id);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Search and add employees
          TextField(
            decoration: const InputDecoration(
              labelText: "Search employees to add",
              prefixIcon: Icon(Icons.search),
              hintText: "Type to search by name or job code...",
            ),
            onChanged: (v) {
              setState(() {
                _searchQuery = v;
              });
            },
          ),
          const SizedBox(height: 8),

          // Employee list (filtered)
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _getFilteredEmployees().length,
              itemBuilder: (context, index) {
                final emp = _getFilteredEmployees()[index];
                final isTracked =
                    emp.id != null && _trackedEmployeeIds.contains(emp.id);

                return CheckboxListTile(
                  title: Text(emp.displayName),
                  subtitle: Text(emp.jobCode),
                  value: isTracked,
                  onChanged: (checked) {
                    if (emp.id == null) return;
                    setState(() {
                      if (checked == true) {
                        _trackedEmployeeIds.add(emp.id!);
                      } else {
                        _trackedEmployeeIds.remove(emp.id);
                      }
                    });
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              ElevatedButton(
                onPressed: _saveTrackedEmployees,
                child: const Text("Save Tracked Employees"),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _trackedEmployeeIds.clear();
                  });
                },
                child: const Text("Clear All"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
