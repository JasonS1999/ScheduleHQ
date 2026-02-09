import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/employee_availability.dart';
import '../database/employee_availability_dao.dart';
import '../services/app_colors.dart';

class EmployeeAvailabilityPage extends StatefulWidget {
  final Employee employee;

  const EmployeeAvailabilityPage({super.key, required this.employee});

  @override
  State<EmployeeAvailabilityPage> createState() =>
      _EmployeeAvailabilityPageState();
}

class _EmployeeAvailabilityPageState extends State<EmployeeAvailabilityPage> {
  final EmployeeAvailabilityDao _dao = EmployeeAvailabilityDao();

  List<EmployeeAvailability> _genericAvailability = [];
  List<EmployeeAvailability> _biweeklyAvailability = [];
  List<EmployeeAvailability> _monthlyOverrides = [];

  String _selectedPatternType = 'generic'; // 'generic', 'biweekly', 'monthly'
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final generic = await _dao.getGenericAvailability(widget.employee.id!);
    final biweekly = await _dao.getBiweeklyAvailability(widget.employee.id!);
    final monthly = await _dao.getMonthlyOverrides(widget.employee.id!);

    // Determine which pattern type is active based on what has data
    String patternType = 'generic';
    if (monthly.isNotEmpty) {
      patternType = 'monthly';
    } else if (biweekly.isNotEmpty) {
      patternType = 'biweekly';
    } else if (generic.isNotEmpty) {
      patternType = 'generic';
    }

    setState(() {
      _genericAvailability = generic;
      _biweeklyAvailability = biweekly;
      _monthlyOverrides = monthly;
      _selectedPatternType = patternType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employee.displayName} - Availability'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text(
                  'Pattern Type: ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedPatternType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'generic',
                        child: Text('Generic (repeats weekly)'),
                      ),
                      DropdownMenuItem(
                        value: 'biweekly',
                        child: Text('2-Week Pattern (alternating weeks)'),
                      ),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly Override (specific dates)'),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value != null && value != _selectedPatternType) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Switch Pattern Type'),
                            content: const Text(
                              'Switching pattern types will clear any existing availability settings for the other patterns. Continue?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Switch'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          // Clear other pattern types
                          if (value != 'generic') {
                            for (var avail in _genericAvailability) {
                              if (avail.id != null)
                                await _dao.deleteAvailability(avail.id!);
                            }
                            _genericAvailability = [];
                          }
                          if (value != 'biweekly') {
                            for (var avail in _biweeklyAvailability) {
                              if (avail.id != null)
                                await _dao.deleteAvailability(avail.id!);
                            }
                            _biweeklyAvailability = [];
                          }
                          if (value != 'monthly') {
                            for (var avail in _monthlyOverrides) {
                              if (avail.id != null)
                                await _dao.deleteAvailability(avail.id!);
                            }
                            _monthlyOverrides = [];
                          }

                          setState(() {
                            _selectedPatternType = value;
                          });
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _buildSelectedPatternView()),
        ],
      ),
    );
  }

  Widget _buildSelectedPatternView() {
    switch (_selectedPatternType) {
      case 'generic':
        return _buildGenericTab();
      case 'biweekly':
        return _buildBiweeklyTab();
      case 'monthly':
        return _buildMonthlyTab();
      default:
        return _buildGenericTab();
    }
  }

  Widget _buildGenericTab() {
    const daysOfWeek = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 7,
      itemBuilder: (context, index) {
        final availability = _genericAvailability.firstWhere(
          (a) => a.dayOfWeek == index,
          orElse: () => EmployeeAvailability(
            employeeId: widget.employee.id!,
            availabilityType: 'generic',
            dayOfWeek: index,
            allDay: true,
            available: true,
          ),
        );

        return Card(
          child: ListTile(
            title: Text(daysOfWeek[index]),
            subtitle: _buildAvailabilitySubtitle(availability),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () =>
                  _editAvailability(availability, 'generic', index),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBiweeklyTab() {
    const daysOfWeek = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Week 1',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...List.generate(7, (index) {
          final availability = _biweeklyAvailability.firstWhere(
            (a) => a.dayOfWeek == index && a.weekNumber == 1,
            orElse: () => EmployeeAvailability(
              employeeId: widget.employee.id!,
              availabilityType: 'biweekly',
              dayOfWeek: index,
              weekNumber: 1,
              allDay: true,
              available: true,
            ),
          );

          return Card(
            child: ListTile(
              title: Text(daysOfWeek[index]),
              subtitle: _buildAvailabilitySubtitle(availability),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    _editAvailability(availability, 'biweekly', index, 1),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text(
          'Week 2',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...List.generate(7, (index) {
          final availability = _biweeklyAvailability.firstWhere(
            (a) => a.dayOfWeek == index && a.weekNumber == 2,
            orElse: () => EmployeeAvailability(
              employeeId: widget.employee.id!,
              availabilityType: 'biweekly',
              dayOfWeek: index,
              weekNumber: 2,
              allDay: true,
              available: true,
            ),
          );

          return Card(
            child: ListTile(
              title: Text(daysOfWeek[index]),
              subtitle: _buildAvailabilitySubtitle(availability),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    _editAvailability(availability, 'biweekly', index, 2),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMonthlyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(child: _buildMonthlyCalendar()),
      ],
    );
  }

  Widget _buildMonthlyCalendar() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // 0 = Sunday

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: startWeekday + lastDay.day + 7, // Add header row
      itemBuilder: (context, index) {
        // Header row
        if (index < 7) {
          const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
          return Center(
            child: Text(
              days[index],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }

        final adjustedIndex = index - 7;
        if (adjustedIndex < startWeekday) {
          return Container(); // Empty space before month starts
        }

        final day = adjustedIndex - startWeekday + 1;
        if (day > lastDay.day) {
          return Container(); // Empty space after month ends
        }

        final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        final override = _monthlyOverrides.firstWhere(
          (o) => o.specificDate == dateStr,
          orElse: () => EmployeeAvailability(
            employeeId: widget.employee.id!,
            availabilityType: 'monthly',
            specificDate: dateStr,
            allDay: true,
            available: true,
          ),
        );

        final hasOverride = override.id != null;

        return GestureDetector(
          onTap: () => _editAvailability(override, 'monthly', null, null, date),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: context.appColors.borderLight),
              color: hasOverride
                  ? (override.available
                        ? context.appColors.successBackground
                        : context.appColors.errorBackground)
                  : null,
            ),
            child: Center(child: Text('$day')),
          ),
        );
      },
    );
  }

  Widget _buildAvailabilitySubtitle(EmployeeAvailability availability) {
    if (!availability.available) {
      return Text(
        'Unavailable',
        style: TextStyle(color: context.appColors.errorForeground),
      );
    }
    if (availability.allDay) {
      return const Text('Available all day');
    }
    return Text('${availability.startTime} - ${availability.endTime}');
  }

  Future<void> _editAvailability(
    EmployeeAvailability availability,
    String type,
    int? dayOfWeek, [
    int? weekNumber,
    DateTime? specificDate,
  ]) async {
    bool available = availability.available;
    bool allDay = availability.allDay;
    TimeOfDay startTime = availability.startTime != null
        ? TimeOfDay(
            hour: int.parse(availability.startTime!.split(':')[0]),
            minute: int.parse(availability.startTime!.split(':')[1]),
          )
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = availability.endTime != null
        ? TimeOfDay(
            hour: int.parse(availability.endTime!.split(':')[0]),
            minute: int.parse(availability.endTime!.split(':')[1]),
          )
        : const TimeOfDay(hour: 17, minute: 0);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Availability'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Available'),
                value: available,
                onChanged: (value) {
                  setDialogState(() {
                    available = value;
                  });
                },
              ),
              if (available)
                SwitchListTile(
                  title: const Text('All Day'),
                  value: allDay,
                  onChanged: (value) {
                    setDialogState(() {
                      allDay = value;
                    });
                  },
                ),
              if (available && !allDay) ...[
                ListTile(
                  title: const Text('Start Time'),
                  trailing: Text(
                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: startTime,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        startTime = picked;
                      });
                    }
                  },
                ),
                ListTile(
                  title: const Text('End Time'),
                  trailing: Text(
                    '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
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
                ),
              ],
            ],
          ),
          actions: [
            if (availability.id != null)
              TextButton(
                onPressed: () async {
                  await _dao.deleteAvailability(availability.id!);
                  Navigator.pop(context);
                  _loadAvailability();
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newAvailability = EmployeeAvailability(
                  id: availability.id,
                  employeeId: widget.employee.id!,
                  availabilityType: type,
                  dayOfWeek: dayOfWeek,
                  weekNumber: weekNumber,
                  specificDate: specificDate != null
                      ? '${specificDate.year}-${specificDate.month.toString().padLeft(2, '0')}-${specificDate.day.toString().padLeft(2, '0')}'
                      : null,
                  startTime: !allDay && available
                      ? '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
                      : null,
                  endTime: !allDay && available
                      ? '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}'
                      : null,
                  allDay: allDay,
                  available: available,
                );

                if (availability.id != null) {
                  await _dao.updateAvailability(newAvailability);
                } else {
                  await _dao.insertAvailability(newAvailability);
                }

                Navigator.pop(context);
                _loadAvailability();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}
