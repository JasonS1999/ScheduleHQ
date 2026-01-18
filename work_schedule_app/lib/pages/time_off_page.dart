import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/employee_dao.dart';
import '../database/time_off_dao.dart';
import '../database/settings_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/employee.dart';
import '../models/time_off_entry.dart';
import '../models/settings.dart';
import '../services/pto_trimester_service.dart';

class TimeOffPage extends StatefulWidget {
  const TimeOffPage({super.key});

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage> {
  final EmployeeDao _employeeDao = EmployeeDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final SettingsDao _settingsDao = SettingsDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();
  late final PtoTrimesterService _ptoService;

  List<Employee> _employees = [];
  Map<int, Employee> _employeeById = {};
  Settings? _settings;

  DateTime _focusedMonth = DateTime.now();
  List<TimeOffEntry> _monthEntries = [];

  DateTime? _selectedDay;
  bool _detailsVisible = false;

  // jobCode -> Color
  final Map<String, Color> _jobCodeColorCache = {};

  @override
  void initState() {
    super.initState();
    _ptoService = PtoTrimesterService(timeOffDao: _timeOffDao);
    _loadSettingsAndData();
  }

  Future<void> _loadSettingsAndData() async {
    final settings = await _settingsDao.getSettings();
    final employees = await _employeeDao.getEmployees();

    setState(() {
      _settings = settings;
      _employees = employees;
      _employeeById = {for (var e in employees) e.id!: e};
    });

    await _preloadJobCodeColors();
    await _loadMonthEntries();
  }

  Future<void> _preloadJobCodeColors() async {
    for (final e in _employees) {
      final code = e.jobCode;
      if (_jobCodeColorCache.containsKey(code)) continue;

      final hex = await _jobCodeSettingsDao.getColorForJobCode(code);
      _jobCodeColorCache[code] = _colorFromHex(hex);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMonthEntries() async {
    final entries = await _timeOffDao.getAllTimeOffForMonth(
      _focusedMonth.year,
      _focusedMonth.month,
    );
    setState(() => _monthEntries = entries);
  }

  Map<int, Employee> get _employeeByIdSafe =>
      _employeeById.isEmpty ? {for (var e in _employees) e.id!: e} : _employeeById;

  List<List<DateTime>> _generateMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday;
    final daysToSubtract = weekday % 7;
    final start = first.subtract(Duration(days: daysToSubtract));
    final last = DateTime(month.year, month.month + 1, 0);

    List<List<DateTime>> weeks = [];
    DateTime current = start;

    while (current.isBefore(last) || current.weekday != DateTime.sunday) {
      List<DateTime> week = [];
      for (int i = 0; i < 7; i++) {
        week.add(current);
        current = current.add(const Duration(days: 1));
      }
      weeks.add(week);
    }
    return weeks;
  }

  int _countForDay(DateTime day) {
    final ids = _monthEntries.where((e) =>
        e.date.year == day.year &&
        e.date.month == day.month &&
        e.date.day == day.day).map((e) => e.employeeId).toSet();
    return ids.length;
  }

  List<TimeOffEntry> _entriesForSelectedDay() {
    if (_selectedDay == null) return [];
    final d = _selectedDay!;
    return _monthEntries.where((e) =>
        e.date.year == d.year &&
        e.date.month == d.month &&
        e.date.day == d.day).toList();
  }

  void _changeMonth(int delta) async {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + delta,
        1,
      );
      _selectedDay = null;
      _detailsVisible = false;
    });
    await _loadMonthEntries();
  }

  void _onDayTapped(DateTime day) {
    if (day.month != _focusedMonth.month) return;
    setState(() {
      _selectedDay = day;
      _detailsVisible = true;
    });
  }

  String _monthName(int month) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[month - 1];
  }

  Color _colorFromHex(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      clean = 'FF$clean';
    }
    final value = int.tryParse(clean, radix: 16) ?? 0xFF4285F4;
    return Color(value);
  }

  Color _colorForEntry(TimeOffEntry entry) {
    final emp = _employeeByIdSafe[entry.employeeId];
    final code = emp?.jobCode;
    if (code == null) return Colors.grey;

    final cached = _jobCodeColorCache[code];
    if (cached != null) return cached;

    return Colors.grey;
  }

  String _timeOffLabel(TimeOffEntry e) {
    final emp = _employeeByIdSafe[e.employeeId];
    final name = emp?.name ?? 'Unknown';
    if (e.timeOffType == 'vac') {
      final days = (e.hours / 8).round();
      return '$name – Vacation ${days}d';
    } else if (e.timeOffType == 'sick') {
      final days = (e.hours / 8).round();
      return '$name – Requested ${days}d';
    } else if (e.timeOffType == 'pto') {
      final perDay = _settings?.ptoHoursPerRequest ?? 8;
      final days = (e.hours / perDay).round();
      return '$name – PTO ${days}d';
    } else {
      final type = e.timeOffType.toUpperCase();
      final days = (e.hours / 8).round();
      return '$name – $type ${days}d';
    }
  }

  Future<void> _addTimeOff(DateTime day) async {
    if (_employees.isEmpty) return;

    final employee = await _selectEmployee();
    if (employee == null) return;

    final type = await _selectTimeOffType();
    if (type == null) return;

    if (type == 'vac') {
      final days = await _selectVacationDays();
      if (days == null) return;

      final start = day;
      final end = day.add(Duration(days: days - 1));

      // Check for overlaps and gather conflicting entries
      final conflicts = await _timeOffDao.getTimeOffInRange(employee.id!, start, end);
      if (conflicts.isNotEmpty) {
        if (_settings?.blockOverlaps == true) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Overlap Blocked'),
                content: SizedBox(
                  width: 360,
                  height: 160,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()}')).toList(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              );
            },
          );
          return;
        }

        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Overlap Detected'),
              content: SizedBox(
                width: 360,
                height: 160,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This employee already has time off overlapping the selected dates:'),
                      const SizedBox(height: 8),
                      ...conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()}')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
              ],
            );
          },
        );
        if (proceed != true) return;
      }

      final groupId = const Uuid().v4();

      for (int i = 0; i < days; i++) {
        final entry = TimeOffEntry(
          id: null,
          employeeId: employee.id!,
          date: day.add(Duration(days: i)),
          timeOffType: 'vac',
          hours: 8, // 1 day = 8 hours
          vacationGroupId: groupId,
        );
        await _timeOffDao.insertTimeOff(entry);
      }
    } else if (type == 'pto') {
      // PTO requests: ask for hours (per-day) via dropdown (linked to settings) and number of days.
      final ptoInput = await _selectPtoHoursAndDays();
      if (ptoInput == null) return;

      final hoursPerDay = ptoInput['hours']!;
      final days = ptoInput['days']!;

      final start = day;
      final end = day.add(Duration(days: days - 1));

      final requestedHours = hoursPerDay * days;

      // Check PTO remaining for the trimester
      final remaining = await _ptoService.getRemainingForDate(employee.id!, start);
      if (requestedHours > remaining) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Insufficient PTO'),
              content: Text('This employee has only $remaining hour(s) remaining in the trimester, which is less than the requested $requestedHours hour(s).'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            );
          },
        );
        return;
      }

      // Check for overlaps across the full range and show details
      final conflicts = await _timeOffDao.getTimeOffInRange(employee.id!, start, end);
      if (conflicts.isNotEmpty) {
        if (_settings?.blockOverlaps == true) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Overlap Blocked'),
                content: SizedBox(
                  width: 360,
                  height: 160,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()}')).toList(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              );
            },
          );
          return;
        }

        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Overlap Detected'),
              content: SizedBox(
                width: 360,
                height: 160,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This employee already has time off overlapping the selected dates:'),
                      const SizedBox(height: 8),
                      ...conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()}')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
              ],
            );
          },
        );
        if (proceed != true) return;
      }

      final groupId = const Uuid().v4();
      for (int i = 0; i < days; i++) {
        final entry = TimeOffEntry(
          id: null,
          employeeId: employee.id!,
          date: day.add(Duration(days: i)),
          timeOffType: 'pto',
          hours: hoursPerDay,
          vacationGroupId: groupId,
        );
        await _timeOffDao.insertTimeOff(entry);
      }
    } else if (type == 'sick') {
      // Sick/requested time off - can be full day or partial
      final timeRange = await _selectTimeRange();
      if (timeRange == null) return;
      
      final isAllDay = timeRange['isAllDay'] as bool;
      final hours = timeRange['hours'] as int;
      final startTimeStr = isAllDay ? null : timeRange['startTime'] as String;
      final endTimeStr = isAllDay ? null : timeRange['endTime'] as String;

      // Check for overlap (single-day) and show details
      final conflicts = await _timeOffDao.getTimeOffInRange(employee.id!, day, day);
      if (conflicts.isNotEmpty) {
        if (_settings?.blockOverlaps == true) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Overlap Blocked'),
                content: SizedBox(
                  width: 360,
                  height: 160,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()} (${c.timeRangeDisplay})')).toList(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              );
            },
          );
          return;
        }

        // Ask the user if they'd still like to proceed
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Overlap Detected'),
              content: SizedBox(
                width: 360,
                height: 160,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('This employee already has time off on this date:'),
                      const SizedBox(height: 8),
                      ...conflicts.map((c) => Text('${c.date.toIso8601String().split('T').first} — ${c.timeOffType.toUpperCase()} (${c.timeRangeDisplay})')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
              ],
            );
          },
        );
        if (proceed != true) return;
      }

      final entry = TimeOffEntry(
        id: null,
        employeeId: employee.id!,
        date: day,
        timeOffType: type,
        hours: hours,
        vacationGroupId: null,
        isAllDay: isAllDay,
        startTime: startTimeStr,
        endTime: endTimeStr,
      );

      await _timeOffDao.insertTimeOff(entry);
    } else {
      final h = await _selectHours();
      if (h == null) return;

      final entry = TimeOffEntry(
        id: null,
        employeeId: employee.id!,
        date: day,
        timeOffType: type,
        hours: h,
        vacationGroupId: null,
      );

      await _timeOffDao.insertTimeOff(entry);
    }

    await _loadMonthEntries();
  }

  Future<Employee?> _selectEmployee() async {
    if (!mounted) return null;
    return showDialog<Employee>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Employee'),
          content: SizedBox(
            width: 300,
            height: 300,
            child: ListView(
              children: _employees.map((e) {
                return ListTile(
                  title: Text(e.name),
                  onTap: () => Navigator.of(context).pop(e),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _selectTimeOffType() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select Time Off Type'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'pto'),
              child: const Text('PTO'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'vac'),
              child: const Text('Vacation'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'sick'),
              child: const Text('Requested'),
            ),
          ],
        );
      },
    );
  }

  Future<int?> _selectHours() async {
    final controller = TextEditingController(text: '8');
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hours'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Hours',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final h = int.tryParse(controller.text);
                Navigator.pop(context, h);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<int?> _selectVacationDays() async {
    final controller = TextEditingController(text: '1');
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Days'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final d = int.tryParse(controller.text);
                Navigator.pop(context, d);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Shows a dialog to select time range for partial day time off
  /// Returns a map with 'isAllDay', 'startTime', 'endTime', and 'hours'
  Future<Map<String, dynamic>?> _selectTimeRange() async {
    bool isAllDay = true;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    final defaultHours = _settings?.ptoHoursPerRequest ?? 8;

    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Calculate hours from time range
            int calculatedHours = defaultHours;
            if (!isAllDay) {
              final startMinutes = startTime.hour * 60 + startTime.minute;
              final endMinutes = endTime.hour * 60 + endTime.minute;
              calculatedHours = ((endMinutes - startMinutes) / 60).round().clamp(1, 24);
            }

            String formatTime(TimeOfDay t) {
              final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
              final mm = t.minute.toString().padLeft(2, '0');
              final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
              return '$h:$mm $suffix';
            }

            return AlertDialog(
              title: const Text('Time Off Duration'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    title: const Text('All Day'),
                    value: isAllDay,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        isAllDay = value ?? true;
                      });
                    },
                  ),
                  if (!isAllDay) ...[
                    const SizedBox(height: 8),
                    const Text('Unavailable from:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: startTime,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startTime = picked;
                                  // Ensure end time is after start time
                                  if (picked.hour * 60 + picked.minute >= endTime.hour * 60 + endTime.minute) {
                                    endTime = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
                                  }
                                });
                              }
                            },
                            child: Text(formatTime(startTime)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('to'),
                        ),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: endTime,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  endTime = picked;
                                });
                              }
                            },
                            child: Text(formatTime(endTime)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Hours: $calculatedHours', style: const TextStyle(color: Colors.grey)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                    final endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
                    Navigator.pop(context, {
                      'isAllDay': isAllDay,
                      'startTime': startStr,
                      'endTime': endStr,
                      'hours': isAllDay ? defaultHours : calculatedHours,
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows a dialog that collects the PTO hours-per-day (via text input)
  /// and number of days for the request. The returned map contains keys
  /// 'hours' and 'days'. Returns null if canceled.
  Future<Map<String,int>?> _selectPtoHoursAndDays() async {
    final daysController = TextEditingController(text: '1');
    final hoursController = TextEditingController(text: (_settings?.ptoHoursPerRequest ?? 8).toString());

    if (!mounted) return null;
    final result = await showDialog<Map<String,int>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('PTO Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hoursController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Hours per day'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () {
              final h = int.tryParse(hoursController.text) ?? (_settings?.ptoHoursPerRequest ?? 8);
              final d = int.tryParse(daysController.text) ?? 1;
              Navigator.pop(context, {'hours': h, 'days': d});
            }, child: const Text('OK')),
          ],
        );
      },
    );

    return result;
  }

  Future<void> _deleteEntry(TimeOffEntry entry) async {
    if (entry.id == null) return;
    if (entry.vacationGroupId != null) {
      // Deleting any entry that is part of a vacation group deletes the whole group
      await _deleteVacationGroup(entry.vacationGroupId!);
      return;
    }

    await _timeOffDao.deleteTimeOff(entry.id!);
    await _loadMonthEntries();
  }

  Future<void> _deleteVacationGroup(String groupId) async {
    // Confirm deletion and show details
    final entries = await _timeOffDao.getEntriesByGroup(groupId);
    if (entries.isEmpty) return;

    final employeeId = entries.first.employeeId;
    final employeeName = _employeeByIdSafe[employeeId]?.name ?? 'Employee';
    final count = entries.length;

    final type = entries.first.timeOffType;
    final typeLabel = type == 'vac' ? 'vacation' : type == 'pto' ? 'PTO' : 'requested';

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Group'),
          content: Text('Delete $typeLabel for $employeeName covering $count day(s)? This will remove all days in the group.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        );
      },
    );

    // Re-check mounted after awaiting the dialog to avoid operating on an unmounted
    // widget (linter: use_build_context_synchronously).
    if (!mounted) return;

    if (confirm == true) {
      await _timeOffDao.deleteVacationGroup(groupId);
      if (!mounted) return;
      await _loadMonthEntries();
    }
  }

  Future<void> _showBulkAddDialog() async {
    Employee? selectedEmployee;
    final entries = <_BulkTimeOffEntry>[];
    
    // Cache job code settings for PTO eligibility check
    final jobCodeSettings = await _jobCodeSettingsDao.getAll();
    final jobCodeMap = {for (var jc in jobCodeSettings) jc.code.toLowerCase(): jc};
    
    bool hasPtoEnabled(Employee? emp) {
      if (emp == null) return false;
      final setting = jobCodeMap[emp.jobCode.toLowerCase()];
      return setting?.hasPTO ?? false;
    }
    
    int vacationWeeksRemaining(Employee? emp) {
      if (emp == null) return 0;
      return emp.vacationWeeksAllowed - emp.vacationWeeksUsed;
    }
    
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canAddPto = hasPtoEnabled(selectedEmployee);
            final vacWeeksLeft = vacationWeeksRemaining(selectedEmployee);
            final canAddVacation = vacWeeksLeft > 0;
            
            // Determine default type based on eligibility
            String getDefaultType() {
              if (canAddPto) return 'pto';
              if (canAddVacation) return 'vac';
              return 'sick';
            }
            
            // Get available type options for this employee
            List<DropdownMenuItem<String>> getTypeOptions() {
              final items = <DropdownMenuItem<String>>[];
              if (canAddPto) {
                items.add(const DropdownMenuItem(value: 'pto', child: Text('PTO')));
              }
              if (canAddVacation) {
                items.add(const DropdownMenuItem(value: 'vac', child: Text('Vacation')));
              }
              items.add(const DropdownMenuItem(value: 'sick', child: Text('Requested')));
              return items;
            }
            
            String formatTime(String? time) {
              if (time == null) return '';
              final parts = time.split(':');
              if (parts.length != 2) return time;
              final hour = int.tryParse(parts[0]) ?? 0;
              final minute = parts[1];
              final h = hour % 12 == 0 ? 12 : hour % 12;
              final suffix = hour < 12 ? 'AM' : 'PM';
              return '$h:$minute $suffix';
            }
            
            return AlertDialog(
              title: const Text('Bulk Add Time Off'),
              content: SizedBox(
                width: 550,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee search/select
                    const Text('Select Employee:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Autocomplete<Employee>(
                      displayStringForOption: (e) => e.name,
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _employees;
                        }
                        return _employees.where((e) =>
                            e.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      onSelected: (employee) {
                        setDialogState(() {
                          selectedEmployee = employee;
                          // Clear entries when employee changes since eligibility may differ
                          entries.clear();
                        });
                      },
                      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            hintText: 'Search by name...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        );
                      },
                    ),
                    if (selectedEmployee != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            avatar: CircleAvatar(
                              backgroundColor: _jobCodeColorCache[selectedEmployee!.jobCode] ?? Colors.grey,
                              child: Text(selectedEmployee!.name[0], style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            label: Text('${selectedEmployee!.name} (${selectedEmployee!.jobCode})'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setDialogState(() {
                              selectedEmployee = null;
                              entries.clear();
                            }),
                          ),
                          const SizedBox(width: 12),
                          // Show eligibility info
                          Text(
                            canAddPto ? '✓ PTO' : '✗ No PTO',
                            style: TextStyle(
                              fontSize: 12,
                              color: canAddPto ? Colors.green : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            canAddVacation ? '✓ $vacWeeksLeft vac wks' : '✗ No vacation',
                            style: TextStyle(
                              fontSize: 12,
                              color: canAddVacation ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    
                    // Entries list
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Time Off Entries:', style: TextStyle(fontWeight: FontWeight.w500)),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Entry'),
                          onPressed: selectedEmployee == null
                              ? null
                              : () {
                                  setDialogState(() {
                                    entries.add(_BulkTimeOffEntry(
                                      date: DateTime.now(),
                                      type: getDefaultType(),
                                      hours: _settings?.ptoHoursPerRequest ?? 8,
                                      days: 1,
                                    ));
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    Expanded(
                      child: entries.isEmpty
                          ? Center(
                              child: Text(
                                selectedEmployee == null
                                    ? 'Select an employee first'
                                    : 'No entries added yet.\nClick "Add Entry" to start.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                
                                // Validate entry type - if employee became ineligible, switch to allowed type
                                if (entry.type == 'pto' && !canAddPto) {
                                  entry.type = canAddVacation ? 'vac' : 'sick';
                                }
                                if (entry.type == 'vac' && !canAddVacation) {
                                  entry.type = canAddPto ? 'pto' : 'sick';
                                }
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            // Date picker
                                            Expanded(
                                              flex: 2,
                                              child: InkWell(
                                                onTap: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: entry.date,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime(2030),
                                                  );
                                                  if (picked != null) {
                                                    setDialogState(() => entry.date = picked);
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.grey),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                                                    style: const TextStyle(fontSize: 13),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            
                                            // Type dropdown
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButtonFormField<String>(
                                                value: entry.type,
                                                isDense: true,
                                                isExpanded: true,
                                                decoration: const InputDecoration(
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  border: OutlineInputBorder(),
                                                ),
                                                items: getTypeOptions(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setDialogState(() {
                                                      entry.type = v;
                                                      // Reset values when type changes
                                                      if (v == 'vac') {
                                                        entry.days = 1;
                                                      } else if (v == 'pto') {
                                                        entry.hours = _settings?.ptoHoursPerRequest ?? 8;
                                                      } else if (v == 'sick') {
                                                        entry.isAllDay = true;
                                                        entry.hours = _settings?.ptoHoursPerRequest ?? 8;
                                                      }
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            
                                            // Hours/Days input based on type
                                            if (entry.type == 'vac') ...[
                                              // Vacation: days input
                                              Expanded(
                                                flex: 1,
                                                child: TextField(
                                                  controller: TextEditingController(text: entry.days.toString()),
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Days',
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    border: OutlineInputBorder(),
                                                  ),
                                                  onChanged: (v) {
                                                    entry.days = int.tryParse(v) ?? entry.days;
                                                  },
                                                ),
                                              ),
                                            ] else if (entry.type == 'pto') ...[
                                              // PTO: hours input
                                              Expanded(
                                                flex: 1,
                                                child: TextField(
                                                  controller: TextEditingController(text: entry.hours.toString()),
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Hrs',
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    border: OutlineInputBorder(),
                                                  ),
                                                  onChanged: (v) {
                                                    entry.hours = int.tryParse(v) ?? entry.hours;
                                                  },
                                                ),
                                              ),
                                            ] else ...[
                                              // Requested: show time info
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.grey.shade300),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    entry.isAllDay ? 'All Day' : '${entry.hours}h',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            
                                            // Delete button
                                            IconButton(
                                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                              onPressed: () {
                                                setDialogState(() => entries.removeAt(index));
                                              },
                                            ),
                                          ],
                                        ),
                                        
                                        // Time range options for "Requested" type
                                        if (entry.type == 'sick') ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Checkbox(
                                                value: entry.isAllDay,
                                                onChanged: (v) {
                                                  setDialogState(() {
                                                    entry.isAllDay = v ?? true;
                                                    if (!entry.isAllDay) {
                                                      entry.startTime = '09:00';
                                                      entry.endTime = '17:00';
                                                      entry.hours = 8;
                                                    } else {
                                                      entry.hours = _settings?.ptoHoursPerRequest ?? 8;
                                                    }
                                                  });
                                                },
                                              ),
                                              const Text('All Day', style: TextStyle(fontSize: 13)),
                                              if (!entry.isAllDay) ...[
                                                const SizedBox(width: 16),
                                                const Text('From:', style: TextStyle(fontSize: 13)),
                                                const SizedBox(width: 4),
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  onPressed: () async {
                                                    final parts = (entry.startTime ?? '09:00').split(':');
                                                    final initial = TimeOfDay(
                                                      hour: int.tryParse(parts[0]) ?? 9,
                                                      minute: int.tryParse(parts[1]) ?? 0,
                                                    );
                                                    final picked = await showTimePicker(
                                                      context: context,
                                                      initialTime: initial,
                                                    );
                                                    if (picked != null) {
                                                      setDialogState(() {
                                                        entry.startTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                        // Recalculate hours
                                                        final endParts = (entry.endTime ?? '17:00').split(':');
                                                        final endMins = (int.tryParse(endParts[0]) ?? 17) * 60 + (int.tryParse(endParts[1]) ?? 0);
                                                        final startMins = picked.hour * 60 + picked.minute;
                                                        entry.hours = ((endMins - startMins) / 60).round().clamp(1, 24);
                                                      });
                                                    }
                                                  },
                                                  child: Text(formatTime(entry.startTime ?? '09:00'), style: const TextStyle(fontSize: 12)),
                                                ),
                                                const SizedBox(width: 8),
                                                const Text('To:', style: TextStyle(fontSize: 13)),
                                                const SizedBox(width: 4),
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  onPressed: () async {
                                                    final parts = (entry.endTime ?? '17:00').split(':');
                                                    final initial = TimeOfDay(
                                                      hour: int.tryParse(parts[0]) ?? 17,
                                                      minute: int.tryParse(parts[1]) ?? 0,
                                                    );
                                                    final picked = await showTimePicker(
                                                      context: context,
                                                      initialTime: initial,
                                                    );
                                                    if (picked != null) {
                                                      setDialogState(() {
                                                        entry.endTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                        // Recalculate hours
                                                        final startParts = (entry.startTime ?? '09:00').split(':');
                                                        final startMins = (int.tryParse(startParts[0]) ?? 9) * 60 + (int.tryParse(startParts[1]) ?? 0);
                                                        final endMins = picked.hour * 60 + picked.minute;
                                                        entry.hours = ((endMins - startMins) / 60).round().clamp(1, 24);
                                                      });
                                                    }
                                                  },
                                                  child: Text(formatTime(entry.endTime ?? '17:00'), style: const TextStyle(fontSize: 12)),
                                                ),
                                                const SizedBox(width: 8),
                                                Text('(${entry.hours}h)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (selectedEmployee == null || entries.isEmpty)
                      ? null
                      : () async {
                          // Save all entries
                          for (final entry in entries) {
                            final groupId = const Uuid().v4();
                            
                            if (entry.type == 'vac') {
                              // For vacation, create multiple days based on entry.days
                              // Each "day" is 8 hours
                              for (int d = 0; d < entry.days; d++) {
                                final dayDate = entry.date.add(Duration(days: d));
                                final timeOffEntry = TimeOffEntry(
                                  id: null,
                                  employeeId: selectedEmployee!.id!,
                                  date: dayDate,
                                  timeOffType: 'vac',
                                  hours: 8, // Full day
                                  vacationGroupId: groupId,
                                  isAllDay: true,
                                );
                                await _timeOffDao.insertTimeOff(timeOffEntry);
                              }
                            } else {
                              // PTO or Requested
                              final timeOffEntry = TimeOffEntry(
                                id: null,
                                employeeId: selectedEmployee!.id!,
                                date: entry.date,
                                timeOffType: entry.type,
                                hours: entry.hours,
                                vacationGroupId: groupId,
                                isAllDay: entry.type == 'sick' ? entry.isAllDay : true,
                                startTime: entry.type == 'sick' && !entry.isAllDay ? entry.startTime : null,
                                endTime: entry.type == 'sick' && !entry.isAllDay ? entry.endTime : null,
                              );
                              await _timeOffDao.insertTimeOff(timeOffEntry);
                            }
                          }
                          if (!mounted) return;
                          Navigator.pop(context);
                          await _loadMonthEntries();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added ${entries.length} time off entries for ${selectedEmployee!.name}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                  child: Text('Save ${entries.length} Entries'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final weeks = _generateMonth(_focusedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Time Off"),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Bulk Add Time Off',
            onPressed: _showBulkAddDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _loadSettingsAndData();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegend(),
                  const SizedBox(height: 16),
                  _buildMonthHeader(),
                  const SizedBox(height: 8),
                  _buildWeekdayHeader(),
                  const SizedBox(height: 8),
                  _buildCalendarGrid(weeks),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Dim overlay when the details panel is visible. Tapping dismisses it.
          if (_detailsVisible && _selectedDay != null && _entriesForSelectedDay().isNotEmpty)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() {
                  _detailsVisible = false;
                  _selectedDay = null;
                }),
                child: Container(
                  color: const Color.fromRGBO(0, 0, 0, 0.35),
                ),
              ),
            ),

          // Sliding right-hand details panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            right: (_detailsVisible && _selectedDay != null && _entriesForSelectedDay().isNotEmpty) ? 0 : -360,
            top: 0,
            bottom: 0,
            width: 360,
            child: Material(
              elevation: 12,
              color: Theme.of(context).cardColor,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDay == null ? '' : "${_monthName(_selectedDay!.month)} ${_selectedDay!.day}, ${_selectedDay!.year}",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _detailsVisible = false;
                              _selectedDay = null;
                            }),
                          ),
                        ],
                      ),
                      const Divider(),
                      _buildDayDetails(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton(
              onPressed: () => _addTimeOff(_selectedDay!),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildLegend() {
    final entries = <Widget>[];

    void addLegendItem(String label, String codeKey) {
      final color = _jobCodeColorCache[codeKey] ?? Colors.grey;
      entries.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Text(label),
          const SizedBox(width: 16),
        ],
      ));
    }

    addLegendItem('Assistant', 'assistant');
    addLegendItem('Swing', 'swing');
    addLegendItem('GM', 'gm');
    addLegendItem('MIT', 'mit');
    addLegendItem('Breakfast Mgr', 'breakfast mgr');

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: entries,
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          "${_monthName(_focusedMonth.month)} ${_focusedMonth.year}",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final labelStyle = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: labelStyle,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCalendarGrid(List<List<DateTime>> weeks) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: weeks.asMap().entries.map((entry) {
          final weekIndex = entry.key;
          final week = entry.value;
          final isLastWeek = weekIndex == weeks.length - 1;
          
          return Container(
            decoration: BoxDecoration(
              border: isLastWeek
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
            ),
            child: Row(
              children: week.map((day) {
                final isCurrentMonth = day.month == _focusedMonth.month;
                final isToday = DateTime.now().year == day.year &&
                    DateTime.now().month == day.month &&
                    DateTime.now().day == day.day;
                final isSelected = _selectedDay != null &&
                    _selectedDay!.year == day.year &&
                    _selectedDay!.month == day.month &&
                    _selectedDay!.day == day.day;

                final count = _countForDay(day);

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onDayTapped(day),
                    onDoubleTap: () {
                      if (day.month != _focusedMonth.month) return;
                      _addTimeOff(day);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.shade100
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: isToday
                            ? Border.all(color: Colors.blue, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            "${day.day}",
                            style: TextStyle(
                              color: isCurrentMonth
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).disabledColor,
                              fontWeight:
                                  count > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (count > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "$count",
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
      ),
    );
  }

  Widget _buildDayDetails() {
    final entries = _entriesForSelectedDay();
    if (entries.isEmpty || _selectedDay == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries.map((e) {
            final color = _colorForEntry(e);
            final label = _timeOffLabel(e);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: color,
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              title: Text(label),
              subtitle: Text(
                "Group: ${e.vacationGroupId ?? 'N/A'}",
                style: const TextStyle(fontSize: 12),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    await _deleteEntry(e);
                  } else if (value == 'delete_group' &&
                      e.vacationGroupId != null) {
                    await _deleteVacationGroup(e.vacationGroupId!);
                  }
                },
                itemBuilder: (context) {
                  return <PopupMenuEntry<String>>[
                    if (e.vacationGroupId == null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete Entry'),
                      ),
                    if (e.vacationGroupId != null)
                      PopupMenuItem(
                        value: 'delete_group',
                        child: Text('Delete Group (entire ${e.timeOffType.toUpperCase()})'),
                      ),
                  ];
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Helper class for bulk time off entry
class _BulkTimeOffEntry {
  DateTime date;
  String type;
  int hours;
  int days; // For vacation entries
  bool isAllDay; // For requested entries
  String? startTime; // For partial day requested entries
  String? endTime;

  _BulkTimeOffEntry({
    required this.date,
    required this.type,
    this.hours = 8,
    this.days = 1,
    this.isAllDay = true,
    this.startTime,
    this.endTime,
  });
}
