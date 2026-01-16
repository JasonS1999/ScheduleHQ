import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/employee_dao.dart';
import '../../database/time_off_dao.dart';
import '../../database/employee_availability_dao.dart';
import '../../database/shift_template_dao.dart';
import '../../database/job_code_settings_dao.dart';
import '../../database/shift_dao.dart';
import '../../database/schedule_note_dao.dart';
import '../../models/employee.dart';
import '../../models/time_off_entry.dart';
import '../../models/shift_template.dart';
import '../../models/shift.dart';
import '../../models/schedule_note.dart';
import '../../models/job_code_settings.dart';
import '../../services/schedule_pdf_service.dart';
import '../../services/schedule_undo_manager.dart';

// Custom intents for keyboard shortcuts
class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

enum ScheduleMode { daily, weekly, monthly }

bool _isLabelOnly(String text) {
  final t = text.toLowerCase();
  return t == 'off' || t == 'pto' || t == 'vac' || t == 'req off';
}

String _labelText(String text) {
  final t = text.toLowerCase();
  if (t == 'off') return 'OFF';
  if (t == 'pto') return 'PTO';
  if (t == 'vac') return 'VAC';
  if (t == 'req off') return 'REQ OFF';
  return text;
}

class ScheduleView extends StatefulWidget {
  final DateTime initialDate;
  final ScheduleMode initialMode;

  ScheduleView({super.key, DateTime? date, this.initialMode = ScheduleMode.weekly})
      : initialDate = date ?? DateTime.now();

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  late DateTime _date;
  late ScheduleMode _mode;
  final EmployeeDao _employeeDao = EmployeeDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final ShiftDao _shiftDao = ShiftDao();
  final ScheduleNoteDao _noteDao = ScheduleNoteDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();
  List<Employee> _employees = [];
  List<Employee> _filteredEmployees = [];
  List<ShiftPlaceholder> _shifts = [];
  Map<DateTime, ScheduleNote> _notes = {};
  List<JobCodeSettings> _jobCodeSettings = [];

  // Filter state
  String _filterType = 'all'; // 'all', 'jobCode', 'employee'
  String? _selectedJobCode;
  int? _selectedEmployeeId;

  // simple in-memory clipboard for copy/paste: stores start TimeOfDay, duration, and text
  Map<String, Object?>? _clipboard;

  // Undo/Redo manager
  final ScheduleUndoManager _undoManager = ScheduleUndoManager();

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _mode = widget.initialMode;
    _undoManager.addListener(_onUndoRedoChange);
    _loadEmployees();
  }

  @override
  void dispose() {
    _undoManager.removeListener(_onUndoRedoChange);
    super.dispose();
  }

  void _onUndoRedoChange() {
    if (mounted) {
      setState(() {});
    }
  }

  List<ShiftPlaceholder> _timeOffToShifts(List<TimeOffEntry> entries) {
    return entries.map((e) {
      String label;
      switch (e.timeOffType.toLowerCase()) {
        case 'vac':
          label = 'VAC';
          break;
        case 'pto':
          label = 'PTO';
          break;
        default:
          label = 'REQ OFF';
      }
      return ShiftPlaceholder(
        employeeId: e.employeeId,
        start: DateTime(e.date.year, e.date.month, e.date.day, 0, 0),
        end: DateTime(e.date.year, e.date.month, e.date.day, 23, 59),
        text: label,
      );
    }).toList();
  }

  List<ShiftPlaceholder> _shiftsToPlaceholders(List<Shift> shifts) {
    return shifts.map((s) => ShiftPlaceholder(
      id: s.id,
      employeeId: s.employeeId,
      start: s.startTime,
      end: s.endTime,
      text: s.label ?? '',
    )).toList();
  }

  Future<void> _refreshShifts() async {
    // Load time-off entries
    final timeOffEntries = await _timeOffDao.getAllTimeOff();
    final timeOffShifts = _timeOffToShifts(timeOffEntries);
    
    // Load actual shifts from database based on current view
    List<Shift> dbShifts;
    if (_mode == ScheduleMode.monthly) {
      dbShifts = await _shiftDao.getByMonth(_date.year, _date.month);
    } else if (_mode == ScheduleMode.weekly) {
      dbShifts = await _shiftDao.getByWeek(_date);
    } else {
      dbShifts = await _shiftDao.getByDate(_date);
    }
    final workShifts = _shiftsToPlaceholders(dbShifts);
    
    // Load notes based on current view
    Map<DateTime, ScheduleNote> notes;
    if (_mode == ScheduleMode.monthly) {
      notes = await _noteDao.getByMonth(_date.year, _date.month);
    } else {
      notes = await _noteDao.getByWeek(_date);
    }
    
    if (!mounted) return;
    setState(() {
      // Combine database time-off shifts with work shifts from database
      _shifts = [...timeOffShifts, ...workShifts];
      _notes = notes;
    });
  }

  Future<void> _loadEmployees() async {
    // Load job code settings first for proper sorting
    _jobCodeSettings = await _jobCodeSettingsDao.getAll();
    final list = await _employeeDao.getEmployees();
    debugPrint('ScheduleView: loaded ${list.length} employee(s) from DB');
    if (!mounted) return;

    setState(() {
      _employees = _sortEmployeesByJobCode(list);
      _applyFilter();
    });

    await _refreshShifts();
  }

  void _applyFilter() {
    if (_filterType == 'all') {
      _filteredEmployees = List.from(_employees);
    } else if (_filterType == 'jobCode' && _selectedJobCode != null) {
      _filteredEmployees = _employees.where((e) => 
        e.jobCode.toLowerCase() == _selectedJobCode!.toLowerCase()
      ).toList();
    } else if (_filterType == 'employee' && _selectedEmployeeId != null) {
      _filteredEmployees = _employees.where((e) => 
        e.id == _selectedEmployeeId
      ).toList();
    } else {
      _filteredEmployees = List.from(_employees);
    }
  }

  List<String> get _uniqueJobCodes {
    final codes = _employees.map((e) => e.jobCode).toSet().toList();
    codes.sort();
    return codes;
  }

  List<Employee> _sortEmployeesByJobCode(List<Employee> employees) {
    // Build hierarchy from job code settings (sorted by sortOrder)
    final hierarchy = <String, int>{};
    for (int i = 0; i < _jobCodeSettings.length; i++) {
      hierarchy[_jobCodeSettings[i].code.toLowerCase()] = _jobCodeSettings[i].sortOrder;
    }

    final sorted = List<Employee>.from(employees);
    sorted.sort((a, b) {
      final aOrder = hierarchy[a.jobCode.toLowerCase()] ?? 999;
      final bOrder = hierarchy[b.jobCode.toLowerCase()] ?? 999;
      if (aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      // If same job code, sort by name
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  void _prev() {
    setState(() {
      if (_mode == ScheduleMode.daily) {
        _date = _date.subtract(const Duration(days: 1));
      } else if (_mode == ScheduleMode.weekly) {
        _date = _date.subtract(const Duration(days: 7));
      } else {
        _date = DateTime(_date.year, _date.month - 1, 1);
      }
    });
    _refreshShifts();
  }

  void _next() {
    setState(() {
      if (_mode == ScheduleMode.daily) {
        _date = _date.add(const Duration(days: 1));
      } else if (_mode == ScheduleMode.weekly) {
        _date = _date.add(const Duration(days: 7));
      } else {
        _date = DateTime(_date.year, _date.month + 1, 1);
      }
    });
    _refreshShifts();
  }

  Future<void> _handleUndo() async {
    await _undoManager.undo();
    await _refreshShifts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Undo successful'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handleRedo() async {
    await _undoManager.redo();
    await _refreshShifts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Redo successful'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // Undo-aware shift operations
  Future<int> _insertShiftWithUndo(Shift shift) async {
    final action = CreateShiftAction(
      shift: shift,
      insertFn: (s) => _shiftDao.insert(s),
      deleteFn: (id) => _shiftDao.delete(id),
    );
    await _undoManager.executeAction(action);
    return shift.id ?? 0;
  }

  Future<void> _updateShiftWithUndo(Shift oldShift, Shift newShift) async {
    final action = UpdateShiftAction(
      oldShift: oldShift,
      newShift: newShift,
      updateFn: (s) => _shiftDao.update(s),
    );
    await _undoManager.executeAction(action);
  }

  Future<void> _deleteShiftWithUndo(Shift shift) async {
    final action = DeleteShiftAction(
      shift: shift,
      insertFn: (s) => _shiftDao.insert(s),
      deleteFn: (id) => _shiftDao.delete(id),
    );
    await _undoManager.executeAction(action);
  }

  Future<void> _moveShiftWithUndo(Shift oldShift, Shift newShift) async {
    final action = MoveShiftAction(
      oldShift: oldShift,
      newShift: newShift,
      updateFn: (s) => _shiftDao.update(s),
    );
    await _undoManager.executeAction(action);
  }

  Future<void> _handlePrintExport(String action) async {
    try {
      late final Uint8List pdfBytes;
      late final String title;
      late final String filename;

      if (_mode == ScheduleMode.weekly || _mode == ScheduleMode.daily) {
        // Get week start (Sunday)
        final weekStart = _date.subtract(Duration(days: _date.weekday % 7));
        pdfBytes = await SchedulePdfService.generateWeeklyPdf(
          weekStart: weekStart,
          employees: _employees,
          shifts: _shifts,
          jobCodeSettings: _jobCodeSettings,
        );
        title = 'Schedule - Week of ${weekStart.month}/${weekStart.day}/${weekStart.year}';
        filename = 'schedule_${weekStart.year}_${weekStart.month}_${weekStart.day}.pdf';
      } else {
        pdfBytes = await SchedulePdfService.generateMonthlyPdf(
          year: _date.year,
          month: _date.month,
          employees: _employees,
          shifts: _shifts,
          jobCodeSettings: _jobCodeSettings,
        );
        final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        title = 'Schedule - ${monthNames[_date.month - 1]} ${_date.year}';
        filename = 'schedule_${_date.year}_${_date.month}.pdf';
      }

      if (action == 'print') {
        await SchedulePdfService.printSchedule(pdfBytes, title);
      } else {
        await SchedulePdfService.sharePdf(pdfBytes, filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  Future<void> _handleWeekAction(String action) async {
    // Get current week start (Sunday)
    final weekStart = _date.subtract(Duration(days: _date.weekday % 7));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
    
    if (action == 'copyWeekToNext') {
      final nextWeekStart = weekStartDate.add(const Duration(days: 7));
      await _copyWeekTo(weekStartDate, nextWeekStart);
    } else if (action == 'copyWeekToDate') {
      final targetDate = await _showWeekPicker(context, weekStartDate);
      if (targetDate != null) {
        await _copyWeekTo(weekStartDate, targetDate);
      }
    } else if (action == 'clearWeek') {
      await _clearWeek(weekStartDate);
    } else if (action == 'autoFillFromTemplates') {
      await _autoFillFromTemplates(weekStartDate);
    }
  }

  Future<void> _copyWeekTo(DateTime sourceWeekStart, DateTime targetWeekStart) async {
    // Get all shifts from source week
    final sourceShifts = await _shiftDao.getByWeek(sourceWeekStart);
    
    if (sourceShifts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No shifts to copy from this week')),
        );
      }
      return;
    }
    
    // Confirm the copy
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy Week'),
        content: Text(
          'Copy ${sourceShifts.length} shift(s) from week of '
          '${sourceWeekStart.month}/${sourceWeekStart.day} '
          'to week of ${targetWeekStart.month}/${targetWeekStart.day}?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    // Calculate the offset between weeks
    final dayOffset = targetWeekStart.difference(sourceWeekStart).inDays;
    
    // Create new shifts for the target week
    final newShifts = sourceShifts.map((s) {
      return Shift(
        employeeId: s.employeeId,
        startTime: s.startTime.add(Duration(days: dayOffset)),
        endTime: s.endTime.add(Duration(days: dayOffset)),
        label: s.label,
        notes: s.notes,
      );
    }).toList();
    
    // Insert all new shifts
    await _shiftDao.insertAll(newShifts);
    
    // Navigate to target week and refresh
    setState(() {
      _date = targetWeekStart;
    });
    await _refreshShifts();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${newShifts.length} shift(s) to new week')),
      );
    }
  }

  Future<void> _clearWeek(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    
    // Count shifts to clear
    final shifts = await _shiftDao.getByWeek(weekStart);
    
    if (shifts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No shifts to clear in this week')),
        );
      }
      return;
    }
    
    // Confirm the clear
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Week'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${shifts.length} shift(s) from this week?\n\n'
          'This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    // Delete all shifts in the week
    await _shiftDao.deleteByDateRange(weekStart, weekEnd);
    await _refreshShifts();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared ${shifts.length} shift(s) from this week')),
      );
    }
  }

  Future<DateTime?> _showWeekPicker(BuildContext context, DateTime currentWeek) async {
    return showDatePicker(
      context: context,
      initialDate: currentWeek.add(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select the start of the target week (any day in the week)',
    ).then((selected) {
      if (selected != null) {
        // Normalize to Sunday of that week
        return selected.subtract(Duration(days: selected.weekday % 7));
      }
      return null;
    });
  }

  final ShiftTemplateDao _templateDao = ShiftTemplateDao();

  Future<void> _autoFillFromTemplates(DateTime weekStart) async {
    // Get all templates
    final templates = await _templateDao.getAllTemplates();
    
    if (templates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shift templates defined. Go to Settings > Shift Templates to create some.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Get job code settings for default hours
    final jobCodeSettings = await _jobCodeSettingsDao.getAll();
    final defaultHoursMap = <String, int>{};
    for (final setting in jobCodeSettings) {
      defaultHoursMap[setting.code.toLowerCase()] = setting.defaultDailyHours;
    }

    // Show dialog to select days and options
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final selectedDays = <int>{1, 2, 3, 4, 5}; // Mon-Fri default (1=Mon, 5=Fri in this context)
        bool skipExisting = true;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
            
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.auto_fix_high, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Auto-Fill from Templates'),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found ${templates.length} template(s) and ${_employees.length} employee(s).',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select days to fill:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: List.generate(7, (i) {
                        return FilterChip(
                          label: Text(dayNames[i]),
                          selected: selectedDays.contains(i),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedDays.add(i);
                              } else {
                                selectedDays.remove(i);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Skip employees with existing shifts'),
                      value: skipExisting,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => skipExisting = v ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Auto-Fill'),
                  onPressed: () => Navigator.pop(ctx, {
                    'days': selectedDays.toList(),
                    'skipExisting': skipExisting,
                  }),
                ),
              ],
            );
          },
        );
      },
    );
    
    if (result == null) return;
    
    final selectedDays = result['days'] as List<int>;
    final skipExisting = result['skipExisting'] as bool;
    
    if (selectedDays.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one day')),
        );
      }
      return;
    }
    
    // Generate shifts
    int shiftsCreated = 0;
    final newShifts = <Shift>[];
    
    for (final employee in _employees) {
      // Find templates matching this employee's job code
      final matchingTemplates = templates.where(
        (t) => t.jobCode.toLowerCase() == employee.jobCode.toLowerCase()
      ).toList();
      
      if (matchingTemplates.isEmpty) continue;
      
      // Use the first matching template
      final template = matchingTemplates.first;
      
      // Parse template start time (e.g., "9:00 AM")
      final startTimeParts = template.startTime.replaceAll(RegExp(r'[APMapm]'), '').trim().split(':');
      var startHour = int.parse(startTimeParts[0]);
      final startMinute = startTimeParts.length > 1 ? int.parse(startTimeParts[1].trim()) : 0;
      
      if (template.startTime.toLowerCase().contains('pm') && startHour != 12) {
        startHour += 12;
      } else if (template.startTime.toLowerCase().contains('am') && startHour == 12) {
        startHour = 0;
      }
      
      // Get default hours for this job code
      final defaultHours = defaultHoursMap[employee.jobCode.toLowerCase()] ?? 8;
      
      for (final dayIndex in selectedDays) {
        final day = weekStart.add(Duration(days: dayIndex));
        
        // Check if employee already has a shift this day
        if (skipExisting) {
          final existingShifts = _shifts.where((s) =>
            s.employeeId == employee.id &&
            s.start.year == day.year &&
            s.start.month == day.month &&
            s.start.day == day.day
          ).toList();
          
          if (existingShifts.isNotEmpty) continue;
        }
        
        final shiftStart = DateTime(day.year, day.month, day.day, startHour, startMinute);
        final shiftEnd = shiftStart.add(Duration(hours: defaultHours));
        
        newShifts.add(Shift(
          employeeId: employee.id!,
          startTime: shiftStart,
          endTime: shiftEnd,
          label: template.templateName,
        ));
        shiftsCreated++;
      }
    }
    
    if (newShifts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No shifts were created (all slots already filled or no matching templates)')),
        );
      }
      return;
    }
    
    // Insert all shifts
    await _shiftDao.insertAll(newShifts);
    await _refreshShifts();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $shiftsCreated shift(s) from templates')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildControls(context),
        _buildFilterRow(context),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20),
          const SizedBox(width: 8),
          const Text('Filter:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          // Filter type selector
          DropdownButton<String>(
            value: _filterType,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Employees')),
              DropdownMenuItem(value: 'jobCode', child: Text('By Job Code')),
              DropdownMenuItem(value: 'employee', child: Text('By Employee')),
            ],
            onChanged: (value) {
              setState(() {
                _filterType = value ?? 'all';
                _selectedJobCode = null;
                _selectedEmployeeId = null;
                _applyFilter();
              });
            },
          ),
          const SizedBox(width: 12),
          // Secondary selector based on filter type
          if (_filterType == 'jobCode')
            DropdownButton<String>(
              value: _selectedJobCode,
              hint: const Text('Select Job Code'),
              underline: const SizedBox(),
              items: _uniqueJobCodes.map((code) => 
                DropdownMenuItem(value: code, child: Text(code))
              ).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedJobCode = value;
                  _applyFilter();
                });
              },
            ),
          if (_filterType == 'employee')
            DropdownButton<int>(
              value: _selectedEmployeeId,
              hint: const Text('Select Employee'),
              underline: const SizedBox(),
              items: _employees.map((emp) => 
                DropdownMenuItem(value: emp.id, child: Text(emp.name))
              ).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedEmployeeId = value;
                  _applyFilter();
                });
              },
            ),
          const Spacer(),
          if (_filterType != 'all')
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Clear Filter'),
              onPressed: () {
                setState(() {
                  _filterType = 'all';
                  _selectedJobCode = null;
                  _selectedEmployeeId = null;
                  _applyFilter();
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _prev, 
                  icon: const Icon(Icons.chevron_left),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(
                  _mode == ScheduleMode.monthly
                      ? "${_monthName(_date.month)} ${_date.year}"
                      : _mode == ScheduleMode.weekly
                          ? "Week of ${_date.month}/${_date.day}/${_date.year}"
                          : "${_dayOfWeekAbbr(_date)}, ${_monthName(_date.month)} ${_date.day}, ${_date.year}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _next, 
                  icon: const Icon(Icons.chevron_right),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ToggleButtons(
          isSelected: [
            _mode == ScheduleMode.daily,
            _mode == ScheduleMode.weekly,
            _mode == ScheduleMode.monthly,
          ],
          onPressed: (i) {
            setState(() {
              _mode = ScheduleMode.values[i];
            });
            _refreshShifts();
          },
          children: const [
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Daily')),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Weekly')),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Monthly')),
          ],
        ),
        const SizedBox(width: 8),
        // Undo button
        Tooltip(
          message: _undoManager.canUndo 
              ? 'Undo ${_undoManager.undoDescription ?? ''}' 
              : 'Nothing to undo',
          child: IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoManager.canUndo ? _handleUndo : null,
          ),
        ),
        // Redo button
        Tooltip(
          message: _undoManager.canRedo 
              ? 'Redo ${_undoManager.redoDescription ?? ''}' 
              : 'Nothing to redo',
          child: IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _undoManager.canRedo ? _handleRedo : null,
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: const Icon(Icons.print),
          tooltip: 'Print/Export Schedule',
          onSelected: (value) => _handlePrintExport(value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'print',
              child: Row(
                children: [
                  Icon(Icons.print, size: 20),
                  SizedBox(width: 8),
                  Text('Print Schedule'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 8),
                  Text('Export/Share PDF'),
                ],
              ),
            ),
          ],
        ),
        if (_mode == ScheduleMode.weekly)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More Options',
            onSelected: (value) => _handleWeekAction(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'autoFillFromTemplates',
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high, size: 20, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Auto-Fill from Templates'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'copyWeekToNext',
                child: Row(
                  children: [
                    Icon(Icons.content_copy, size: 20),
                    SizedBox(width: 8),
                    Text('Copy Week to Next Week'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copyWeekToDate',
                child: Row(
                  children: [
                    Icon(Icons.date_range, size: 20),
                    SizedBox(width: 8),
                    Text('Copy Week to Date...'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clearWeek',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear This Week', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_mode == ScheduleMode.daily) {
      return DailyScheduleView(date: _date, employees: _filteredEmployees, shifts: _shifts);
    }
    if (_mode == ScheduleMode.weekly) {
      return WeeklyScheduleView(
      date: _date,
      employees: _filteredEmployees,
      shifts: _shifts,
      notes: _notes,
      jobCodeSettings: _jobCodeSettings,
      clipboardAvailable: _clipboard != null,
      onCopyShift: (s) {
        setState(() {
          _clipboard = {'start': TimeOfDay(hour: s.start.hour, minute: s.start.minute), 'duration': s.end.difference(s.start), 'text': s.text};
        });
      },
      onSaveNote: (day, note) async {
        final scheduleNote = ScheduleNote(date: day, note: note);
        await _noteDao.upsert(scheduleNote);
        await _refreshShifts();
      },
      onDeleteNote: (day) async {
        await _noteDao.deleteByDate(day);
        await _refreshShifts();
      },
      onPasteTarget: (day, employeeId) async {
        if (_clipboard == null) {
          return;
        }
        final tod = _clipboard!['start'] as TimeOfDay;
        final dur = _clipboard!['duration'] as Duration;
        DateTime start = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
        // times with hour 0 or 1 are next-day
        if (tod.hour == 0 || tod.hour == 1) start = start.add(const Duration(days: 1));
        final end = start.add(dur);
        
        // Check for conflicts
        final hasConflict = await _shiftDao.hasConflict(employeeId, start, end);
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(context, employeeId, start, end);
          if (!proceed) return;
        }
        
        // Save to database with undo support
        final shift = Shift(
          employeeId: employeeId,
          startTime: start,
          endTime: end,
          label: _clipboard!['text'] as String,
        );
        await _insertShiftWithUndo(shift);
        _clipboard = null;
        await _refreshShifts();
      },
      onUpdateShift: (oldShift, newStart, newEnd) async {
        if (newStart == newEnd) {
          // Delete with undo support
          if (oldShift.id != null) {
            final shiftToDelete = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
            );
            await _deleteShiftWithUndo(shiftToDelete);
          }
        } else {
          // Check for conflicts (exclude current shift if editing)
          final hasConflict = await _shiftDao.hasConflict(
            oldShift.employeeId, newStart, newEnd, 
            excludeId: oldShift.id,
          );
          if (hasConflict && mounted) {
            final proceed = await _showConflictWarning(context, oldShift.employeeId, newStart, newEnd, excludeId: oldShift.id);
            if (!proceed) return;
          }
          
          // Update or add with undo support
          if (oldShift.id != null) {
            // Update existing
            final oldShiftModel = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
            );
            final updated = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
            );
            await _updateShiftWithUndo(oldShiftModel, updated);
          } else {
            // Insert new
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
            );
            await _insertShiftWithUndo(newShift);
          }
        }
        await _refreshShifts();
      },
      onMoveShift: (shift, newDay, newEmployeeId) async {
        // Move shift to a new day and/or employee
        // Calculate the shift duration to preserve time
        final duration = shift.end.difference(shift.start);
        final newStart = DateTime(
          newDay.year, newDay.month, newDay.day,
          shift.start.hour, shift.start.minute,
        );
        final newEnd = newStart.add(duration);
        
        // Check for conflicts
        final hasConflict = await _shiftDao.hasConflict(
          newEmployeeId, newStart, newEnd,
          excludeId: shift.id,
        );
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(context, newEmployeeId, newStart, newEnd, excludeId: shift.id);
          if (!proceed) return;
        }
        
        if (shift.id != null) {
          // Update existing shift with new employee and times with undo support
          final oldShiftModel = Shift(
            id: shift.id,
            employeeId: shift.employeeId,
            startTime: shift.start,
            endTime: shift.end,
            label: shift.text,
          );
          final updated = Shift(
            id: shift.id,
            employeeId: newEmployeeId,
            startTime: newStart,
            endTime: newEnd,
            label: shift.text,
          );
          await _moveShiftWithUndo(oldShiftModel, updated);
        } else {
          // Insert as new (shouldn't happen for drag, but handle it)
          final newShift = Shift(
            employeeId: newEmployeeId,
            startTime: newStart,
            endTime: newEnd,
            label: shift.text,
          );
          await _insertShiftWithUndo(newShift);
        }
        await _refreshShifts();
      },
      );
    }

    return MonthlyScheduleView(
      date: _date,
      employees: _filteredEmployees,
      shifts: _shifts,
      notes: _notes,
      clipboardAvailable: _clipboard != null,
      onCopyShift: (s) {
        setState(() {
          _clipboard = {'start': TimeOfDay(hour: s.start.hour, minute: s.start.minute), 'duration': s.end.difference(s.start), 'text': s.text};
        });
      },
      onSaveNote: (day, note) async {
        final scheduleNote = ScheduleNote(date: day, note: note);
        await _noteDao.upsert(scheduleNote);
        await _refreshShifts();
      },
      onDeleteNote: (day) async {
        await _noteDao.deleteByDate(day);
        await _refreshShifts();
      },
      onPasteTarget: (day, employeeId) async {
        if (_clipboard == null) return;
        final tod = _clipboard!['start'] as TimeOfDay;
        final dur = _clipboard!['duration'] as Duration;
        DateTime start = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
        if (tod.hour == 0 || tod.hour == 1) start = start.add(const Duration(days: 1));
        final end = start.add(dur);
        
        final hasConflict = await _shiftDao.hasConflict(employeeId, start, end);
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(context, employeeId, start, end);
          if (!proceed) return;
        }
        
        final shift = Shift(
          employeeId: employeeId,
          startTime: start,
          endTime: end,
          label: _clipboard!['text'] as String,
        );
        await _insertShiftWithUndo(shift);
        _clipboard = null;
        await _refreshShifts();
      },
      onUpdateShift: (oldShift, newStart, newEnd) async {
        if (newStart == newEnd) {
          // Delete with undo
          if (oldShift.id != null) {
            final shiftToDelete = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
            );
            await _deleteShiftWithUndo(shiftToDelete);
          }
        } else {
          // Update or add with undo
          if (oldShift.id != null) {
            final oldShiftModel = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
            );
            final updated = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
            );
            await _updateShiftWithUndo(oldShiftModel, updated);
          } else {
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
            );
            await _insertShiftWithUndo(newShift);
          }
        }
        await _refreshShifts();
      },
      onMoveShift: (shift, newDay, newEmployeeId) async {
        final duration = shift.end.difference(shift.start);
        final newStart = DateTime(newDay.year, newDay.month, newDay.day, shift.start.hour, shift.start.minute);
        final newEnd = newStart.add(duration);
        
        final hasConflict = await _shiftDao.hasConflict(newEmployeeId, newStart, newEnd, excludeId: shift.id);
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(context, newEmployeeId, newStart, newEnd, excludeId: shift.id);
          if (!proceed) return;
        }
        
        if (shift.id != null) {
          final oldShiftModel = Shift(
            id: shift.id,
            employeeId: shift.employeeId,
            startTime: shift.start,
            endTime: shift.end,
            label: shift.text,
          );
          final updated = Shift(
            id: shift.id,
            employeeId: newEmployeeId,
            startTime: newStart,
            endTime: newEnd,
            label: shift.text,
          );
          await _moveShiftWithUndo(oldShiftModel, updated);
        } else {
          final newShift = Shift(
            employeeId: newEmployeeId,
            startTime: newStart,
            endTime: newEnd,
            label: shift.text,
          );
          await _insertShiftWithUndo(newShift);
        }
        await _refreshShifts();
      },
    );
  }

  String _monthName(int month) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[month - 1];
  }

  String _dayOfWeekAbbr(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  /// Show a warning dialog when there's a scheduling conflict
  Future<bool> _showConflictWarning(
    BuildContext context, 
    int employeeId, 
    DateTime start, 
    DateTime end, 
    {int? excludeId}
  ) async {
    final conflicts = await _shiftDao.getConflicts(employeeId, start, end, excludeId: excludeId);
    final employee = _employees.firstWhere(
      (e) => e.id == employeeId, 
      orElse: () => Employee(id: employeeId, name: 'Unknown', jobCode: ''),
    );
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('Scheduling Conflict'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${employee.name} already has a shift that overlaps with this time:',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New shift: ${_formatTimeRange(start, end)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    const Text('Conflicting shift(s):', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    ...conflicts.map((c) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• ${_formatTimeRange(c.startTime, c.endTime)}'),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Do you want to proceed anyway?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed Anyway'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  String _formatTimeRange(DateTime start, DateTime end) {
    String formatTime(DateTime dt) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$h:$mm $suffix';
    }
    final dateStr = '${start.month}/${start.day}/${start.year}';
    return '$dateStr ${formatTime(start)} - ${formatTime(end)}';
  }

}

// ------------------------------------------------------------
// DAILY VIEW - list-only view: show shifts for a single day sorted by start time
// ------------------------------------------------------------
class DailyScheduleView extends StatelessWidget {
  final DateTime date;
  final List<Employee> employees;
  final List<ShiftPlaceholder> shifts;

  const DailyScheduleView({super.key, required this.date, required this.employees, this.shifts = const []});

  List<ShiftPlaceholder> _shiftsForDate() {
    final d = DateTime(date.year, date.month, date.day);
    final list = shifts.where((s) {
      return s.start.year == d.year && s.start.month == d.month && s.start.day == d.day;
    }).toList();
    list.sort((a, b) => a.start.compareTo(b.start)); // earlier first
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = _shiftsForDate();

    if (items.isEmpty) {
      return Center(child: Text('No shifts for ${date.month}/${date.day}/${date.year}'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      separatorBuilder: (context, idx) => const Divider(height: 12),
      itemBuilder: (context, idx) {
        final s = items[idx];
        final emp = employees.firstWhere((e) => e.id == s.employeeId, orElse: () => Employee(id: s.employeeId, name: 'Employee', jobCode: ''));
        final time = _formatTimeOfDay(TimeOfDay(hour: s.start.hour, minute: s.start.minute));
        return ListTile(
          key: ValueKey('daily-shift-${s.employeeId}-${s.start.toIso8601String()}'),
          leading: CircleAvatar(child: Text(emp.name.isNotEmpty ? emp.name[0] : '?')),
          title: Text(emp.name),
          subtitle: Text('$time — ${_formatTimeOfDay(TimeOfDay(hour: s.end.hour, minute: s.end.minute))}'),
          trailing: Text(s.text),
        );
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$mm $suffix';
  }
}

// ------------------------------------------------------------
// WEEKLY VIEW - days on Y axis (Mon..Sun or starting with date's week), employees on X axis
// ------------------------------------------------------------
class WeeklyScheduleView extends StatefulWidget {
  final DateTime date;
  final List<Employee> employees;
  final List<ShiftPlaceholder> shifts;
  final Map<DateTime, ScheduleNote> notes;
  final List<JobCodeSettings> jobCodeSettings;
  final void Function(ShiftPlaceholder oldShift, DateTime newStart, DateTime newEnd)? onUpdateShift;
  final void Function(ShiftPlaceholder shift)? onCopyShift;
  final void Function(DateTime day, int employeeId)? onPasteTarget;
  final void Function(ShiftPlaceholder shift, DateTime newDay, int newEmployeeId)? onMoveShift;
  final void Function(DateTime day, String note)? onSaveNote;
  final void Function(DateTime day)? onDeleteNote;
  final bool clipboardAvailable;

  const WeeklyScheduleView({
    super.key,
    required this.date,
    required this.employees,
    this.shifts = const [],
    this.notes = const {},
    this.jobCodeSettings = const [],
    this.onUpdateShift,
    this.onCopyShift,
    this.onPasteTarget,
    this.onMoveShift,
    this.onSaveNote,
    this.onDeleteNote,
    this.clipboardAvailable = false,
  });

  @override
  State<WeeklyScheduleView> createState() => _WeeklyScheduleViewState();
}

class _WeeklyScheduleViewState extends State<WeeklyScheduleView> {
  ShiftPlaceholder? _selectedShift;
  DateTime? _selectedTargetDay;
  int? _selectedTargetEmployeeId;
  // Drag & drop state
  DateTime? _dragHoverDay;
  int? _dragHoverEmployeeId;
  late ScrollController _scrollController;
  final EmployeeAvailabilityDao _availabilityDao = EmployeeAvailabilityDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final ShiftTemplateDao _shiftTemplateDao = ShiftTemplateDao();
  final JobCodeSettingsDao _jobCodeDao = JobCodeSettingsDao();
  final Map<String, Map<String, dynamic>> _availabilityCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Calculate total hours for an employee in the given week
  int _calculateWeeklyHours(int employeeId, List<DateTime> weekDays) {
    int totalMinutes = 0;
    for (final day in weekDays) {
      final shiftsForDay = widget.shifts.where((s) =>
        s.employeeId == employeeId &&
        s.start.year == day.year &&
        s.start.month == day.month &&
        s.start.day == day.day &&
        !['VAC', 'PTO', 'REQ OFF'].contains(s.text.toUpperCase())
      );
      for (final shift in shiftsForDay) {
        totalMinutes += shift.end.difference(shift.start).inMinutes;
      }
    }
    return (totalMinutes / 60).round();
  }

  // Get max hours per week for an employee based on their job code
  int _getMaxHoursForEmployee(Employee employee) {
    final settings = widget.jobCodeSettings.firstWhere(
      (s) => s.code.toLowerCase() == employee.jobCode.toLowerCase(),
      orElse: () => JobCodeSettings(
        code: employee.jobCode,
        hasPTO: false,
        defaultDailyHours: 8,
        maxHoursPerWeek: 40,
        colorHex: '#4285F4',
      ),
    );
    return settings.maxHoursPerWeek;
  }

  Widget _buildTemplateDialog({
    required DateTime day,
    required int employeeId,
    required List<ShiftTemplate> templates,
    required int defaultHours,
    required Color bannerColor,
    required String reason,
    required String type,
    required bool isAvailable,
  }) {
    final times = _allowedTimes();
    int selStart = 0;
    int selEnd = 16;
    ShiftTemplate? selectedTemplate;

    return StatefulBuilder(builder: (context, setDialogState) {
      return AlertDialog(
        title: const Text('Add Shift'),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (templates.isNotEmpty)
              Container(
                width: 140,
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Templates:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    ...templates.map((template) {
                      final parts = template.startTime.split(':');
                      final startHour = int.parse(parts[0]);
                      final startMin = int.parse(parts[1]);
                      final endTime = DateTime(2000, 1, 1, startHour, startMin)
                          .add(Duration(hours: defaultHours));
                      final endTimeStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selectedTemplate == template ? Colors.blue.withOpacity(0.1) : null,
                            side: BorderSide(
                              color: selectedTemplate == template ? Colors.blue : Colors.grey,
                              width: selectedTemplate == template ? 2 : 1,
                            ),
                          ),
                          onPressed: () {
                            int startIdx = times.indexWhere((t) => t.hour == startHour && t.minute == startMin);
                            if (startIdx == -1) startIdx = 0;
                            
                            int endIdx = startIdx + (defaultHours * 4);
                            if (endIdx >= times.length) endIdx = times.length - 1;

                            setDialogState(() {
                              selectedTemplate = template;
                              selStart = startIdx;
                              selEnd = endIdx;
                            });
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(template.templateName, style: const TextStyle(fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                '${template.startTime}-$endTimeStr',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bannerColor.withOpacity(0.2),
                      border: Border.all(color: bannerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          type == 'time-off' ? Icons.event_busy : (isAvailable ? Icons.check_circle : Icons.warning),
                          color: bannerColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reason,
                            style: TextStyle(color: bannerColor.withOpacity(0.9), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<int>(
                    value: selStart,
                    isExpanded: true,
                    items: List.generate(times.length, (i) => DropdownMenuItem(value: i, child: Text(_formatTimeOfDay(times[i])))),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selStart = v;
                        if (selEnd < selStart) selEnd = selStart;
                        selectedTemplate = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selEnd,
                    isExpanded: true,
                    items: List.generate(times.length, (i) => DropdownMenuItem(value: i, child: Text(_formatTimeOfDay(times[i])))),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selEnd = v;
                        selectedTemplate = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final newStart = _timeOfDayToDateTime(day, times[selStart]);
              final newEnd = _timeOfDayToDateTime(day, times[selEnd]);
              if (!newEnd.isAfter(newStart)) {
                Navigator.pop(context, [newStart, newStart.add(const Duration(hours: 1))]);
              } else {
                Navigator.pop(context, [newStart, newEnd]);
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC): const CopyIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV): const PasteIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            CopyIntent: CallbackAction<CopyIntent>(onInvoke: (intent) {
              if (_selectedShift != null && widget.onCopyShift != null) {
                widget.onCopyShift!(_selectedShift!);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Shift copied'), duration: Duration(seconds: 1)),
                );
              }
              return null;
            }),
            PasteIntent: CallbackAction<PasteIntent>(onInvoke: (intent) {
              if (widget.onPasteTarget != null && _selectedTargetDay != null && _selectedTargetEmployeeId != null) {
                if (widget.clipboardAvailable) {
                  widget.onPasteTarget!(_selectedTargetDay!, _selectedTargetEmployeeId!);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No shift copied to paste')),
                  );
                }
              }
              return null;
            })
          },
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final days = _weekDays();

    // Calculate cell width based on available space
    return LayoutBuilder(
      builder: (context, constraints) {
        final employeeColumnWidth = 160.0;
        final availableWidth = constraints.maxWidth - employeeColumnWidth;
        final cellWidth = (availableWidth / days.length).clamp(80.0, 150.0);

        // Header row for days with notes indicator
        final dayHeaders = Row(
          children: days.map((d) {
            final dateKey = DateTime(d.year, d.month, d.day);
            final hasNote = widget.notes.containsKey(dateKey);
            final note = widget.notes[dateKey];
            
            return SizedBox(
              width: cellWidth, 
              height: 40, 
              child: InkWell(
                onTap: () => _showNoteDialog(context, d, note?.note),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${_dayOfWeekAbbr(d)} ${d.month}/${d.day}'),
                    if (hasNote)
                      Tooltip(
                        message: note?.note ?? '',
                        child: Icon(Icons.sticky_note_2, size: 14, color: Colors.amber.shade700),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

        return Column(
          children: [
            Row(children: [
              SizedBox(width: employeeColumnWidth, height: 40), 
              Expanded(child: dayHeaders)
            ]),
            Expanded(
              child: Row(
                children: [
                  // Scrollable content (employee list + grid together)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.vertical,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fixed employee column
                          SizedBox(
                            width: employeeColumnWidth,
                            child: Column(
                              children: widget.employees.map((e) {
                                // Calculate weekly hours for this employee
                                final weeklyHours = _calculateWeeklyHours(e.id!, days);
                                final maxHours = _getMaxHoursForEmployee(e);
                                final isOverLimit = weeklyHours > maxHours;
                                
                                return SizedBox(
                                  height: 60,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            child: Text(
                                              e.name.isNotEmpty ? e.name[0] : '?',
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(e.name, overflow: TextOverflow.ellipsis),
                                                Row(
                                                  children: [
                                                    Text(
                                                      '${weeklyHours}h',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isOverLimit ? Colors.red : Colors.grey,
                                                        fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
                                                      ),
                                                    ),
                                                    if (isOverLimit) ...[
                                                      const SizedBox(width: 4),
                                                      Tooltip(
                                                        message: 'Over max ${maxHours}h/week limit',
                                                        child: const Icon(Icons.warning, size: 14, color: Colors.red),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Grid columns
                          ...days.map((d) {
                            return SizedBox(
                              width: cellWidth,
                              child: Column(
                              children: widget.employees.map((e) {
                                final shiftsForCell = widget.shifts.where((s) => 
                                  s.employeeId == e.id && 
                                  s.start.year == d.year && 
                                  s.start.month == d.month && 
                                  s.start.day == d.day
                                ).toList();
                                
                                final has = shiftsForCell.isNotEmpty;
                                
                                if (!has) {
                                  final isTargetSelected = _selectedTargetDay != null && 
                                      _selectedTargetDay == d && 
                                      _selectedTargetEmployeeId == e.id;
                                  final clipboardAvailable = widget.clipboardAvailable;
                                  final isDragHover = _dragHoverDay != null &&
                                      _dragHoverDay == d &&
                                      _dragHoverEmployeeId == e.id;

                                  return DragTarget<ShiftPlaceholder>(
                                    onWillAcceptWithDetails: (details) {
                                      // Accept drops from other cells (not the same cell)
                                      final draggedShift = details.data;
                                      final isSameCell = draggedShift.employeeId == e.id &&
                                          draggedShift.start.year == d.year &&
                                          draggedShift.start.month == d.month &&
                                          draggedShift.start.day == d.day;
                                      return !isSameCell;
                                    },
                                    onAcceptWithDetails: (details) {
                                      setState(() {
                                        _dragHoverDay = null;
                                        _dragHoverEmployeeId = null;
                                      });
                                      if (widget.onMoveShift != null) {
                                        widget.onMoveShift!(details.data, d, e.id!);
                                      }
                                    },
                                    onMove: (details) {
                                      setState(() {
                                        _dragHoverDay = d;
                                        _dragHoverEmployeeId = e.id;
                                      });
                                    },
                                    onLeave: (data) {
                                      setState(() {
                                        _dragHoverDay = null;
                                        _dragHoverEmployeeId = null;
                                      });
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      return GestureDetector(
                                        onTap: () {
                                          if (widget.clipboardAvailable && widget.onPasteTarget != null) {
                                            // Paste if clipboard has data
                                            widget.onPasteTarget!(d, e.id!);
                                          } else {
                                            // Otherwise just select the cell
                                            setState(() {
                                              _selectedTargetDay = d;
                                              _selectedTargetEmployeeId = e.id;
                                              _selectedShift = null;
                                            });
                                          }
                                        },
                                        onDoubleTap: () async {
                                          // Create a new shift on double-click with availability check
                                          await _showAddShiftDialogWithAvailability(context, d, e.id!);
                                        },
                                        onLongPress: () {
                                          if (widget.clipboardAvailable && widget.onPasteTarget != null) {
                                            widget.onPasteTarget!(d, e.id!);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('No shift copied to paste')),
                                            );
                                          }
                                        },
                                        onSecondaryTapDown: (details) {
                                          _showEmptyCellContextMenu(context, d, e.id!, position: details.globalPosition);
                                        },
                                        child: FutureBuilder<Map<String, dynamic>>(
                                          future: _checkAvailability(e.id!, d),
                                          builder: (context, snapshot) {
                                            bool showDash = false;
                                            if (snapshot.hasData) {
                                              final type = snapshot.data!['type'] as String;
                                              final available = snapshot.data!['available'] as bool;
                                              if (type == 'time-off' || !available) {
                                                showDash = true;
                                              }
                                            }

                                            return Container(
                                              height: 60,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isDragHover
                                                    ? Colors.green
                                                    : isTargetSelected 
                                                      ? Colors.blue 
                                                      : Theme.of(context).dividerColor,
                                                  width: isDragHover ? 3 : (isTargetSelected ? 2.5 : 1),
                                                ),
                                                color: isDragHover
                                                  ? Colors.green.withAlpha(30)
                                                  : isTargetSelected 
                                                    ? Colors.blue.withAlpha(13) 
                                                    : null,
                                              ),
                                              child: isDragHover
                                                ? const Icon(Icons.add_circle_outline, color: Colors.green, size: 24)
                                                : clipboardAvailable && isTargetSelected 
                                                  ? Icon(Icons.content_paste, color: Colors.blue.withAlpha(128), size: 20)
                                                  : showDash
                                                    ? const Text('-', style: TextStyle(fontSize: 24, color: Colors.grey))
                                                    : null,
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  );
                                }

                                final s = shiftsForCell.first;
                                final startLabel = _formatTimeOfDay(TimeOfDay(hour: s.start.hour, minute: s.start.minute));
                                final endLabel = _formatTimeOfDay(TimeOfDay(hour: s.end.hour, minute: s.end.minute));
                                final isShiftSelected = _selectedShift != null && 
                                    _selectedShift!.employeeId == s.employeeId && 
                                    _selectedShift!.start == s.start;

                                // Wrap in Draggable for drag & drop support
                                return Draggable<ShiftPlaceholder>(
                                  data: s,
                                  feedback: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: cellWidth - 4,
                                      height: 56,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue, width: 2),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _isLabelOnly(s.text)
                                            ? _labelText(s.text)
                                            : '$startLabel - $endLabel',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Container(
                                    height: 60,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                        style: BorderStyle.solid,
                                      ),
                                      color: Colors.grey.shade200,
                                    ),
                                    child: const Text(
                                      'Moving...',
                                      style: TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedShift = s;
                                        _selectedTargetDay = null;
                                        _selectedTargetEmployeeId = null;
                                      });
                                    },
                                    onDoubleTap: () async {
                                      final res = await _showEditDialog(context, d, s);
                                      if (res != null && widget.onUpdateShift != null) {
                                        widget.onUpdateShift!(s, res[0], res[1]);
                                      }
                                    },
                                    onLongPress: () {
                                      setState(() {
                                        _selectedShift = s;
                                        _selectedTargetDay = null;
                                        _selectedTargetEmployeeId = null;
                                      });
                                      _showShiftContextMenu(context, s);
                                    },
                                    onSecondaryTapDown: (details) {
                                      setState(() {
                                        _selectedShift = s;
                                        _selectedTargetDay = null;
                                        _selectedTargetEmployeeId = null;
                                      });
                                      _showShiftContextMenu(context, s, position: details.globalPosition);
                                    },
                                    child: Container(
                                      height: 60,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isShiftSelected ? Colors.blue : Theme.of(context).dividerColor,
                                          width: isShiftSelected ? 2.5 : 1,
                                        ),
                                        color: isShiftSelected ? Colors.blue.withAlpha(38) : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          _isLabelOnly(s.text)
                                            ? _labelText(s.text)
                                            : '$startLabel - $endLabel',
                                          style: TextStyle(
                                            fontWeight: isShiftSelected ? FontWeight.bold : FontWeight.normal,
                                            color: Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.white 
                                              : Colors.black87,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<DateTime> _weekDays() {
    // Start from Sunday: weekday % 7 gives us Sunday=0, Monday=1, etc.
    final sunday = widget.date.subtract(Duration(days: widget.date.weekday % 7));
    return List.generate(7, (i) => DateTime(sunday.year, sunday.month, sunday.day + i));
  }

  List<TimeOfDay> _allowedTimes() {
    // 4:30 AM is allowed, then every whole hour from 5:00 through 23:00, and 0:00 and 1:00 (next day)
    final List<TimeOfDay> list = [];
    list.add(const TimeOfDay(hour: 4, minute: 30));
    for (int h = 5; h <= 23; h++) {
      list.add(TimeOfDay(hour: h, minute: 0));
    }
    list.add(const TimeOfDay(hour: 0, minute: 0));
    list.add(const TimeOfDay(hour: 1, minute: 0));
    return list;
  }

  void _showShiftContextMenu(BuildContext context, ShiftPlaceholder shift, {Offset? position}) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null 
        ? RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy)
        : RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'copy' && widget.onCopyShift != null) {
      widget.onCopyShift!(shift);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift copied'), duration: Duration(seconds: 1)),
      );
    } else if (result == 'delete') {
      if (widget.onUpdateShift != null) {
        widget.onUpdateShift!(shift, shift.start, shift.start);
      }
    }
  }

  void _showEmptyCellContextMenu(BuildContext context, DateTime day, int employeeId, {Offset? position}) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null 
        ? RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy)
        : RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        const PopupMenuItem(value: 'off', child: Text('Mark as Off')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'off' && widget.onUpdateShift != null) {
      // Create an OFF shift that spans from midnight to 11:59pm so it's a valid shift
      final offShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 0, 0),
        end: DateTime(day.year, day.month, day.day, 23, 59),
        text: 'Off',
      );
      // Use a temporary placeholder (start==end) to signal this is a new shift
      final tempShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 0, 0),
        end: DateTime(day.year, day.month, day.day, 0, 0),
        text: 'Off',
      );
      widget.onUpdateShift!(tempShift, offShift.start, offShift.end);
    }
  }

  DateTime _timeOfDayToDateTime(DateTime day, TimeOfDay tod) {
    // Times with hour 0 or 1 are considered next-day times
    if (tod.hour == 0 || tod.hour == 1) {
      return DateTime(day.year, day.month, day.day, tod.hour, tod.minute).add(const Duration(days: 1));
    }
    return DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    if (t.minute == 0) {
      return '$h $suffix';
    }
    final mm = t.minute.toString().padLeft(2, '0');
    return '$h:$mm $suffix';
  }

  String _dayOfWeekAbbr(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  void _showNoteDialog(BuildContext context, DateTime day, String? existingNote) {
    final controller = TextEditingController(text: existingNote ?? '');
    final dateStr = '${_dayOfWeekAbbr(day)}, ${day.month}/${day.day}/${day.year}';
    
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.sticky_note_2, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text('Note for $dateStr'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Enter a note for this day...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
          actions: [
            if (existingNote != null && existingNote.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (widget.onDeleteNote != null) {
                    widget.onDeleteNote!(day);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete Note'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                Navigator.pop(ctx);
                if (text.isNotEmpty && widget.onSaveNote != null) {
                  widget.onSaveNote!(day, text);
                } else if (text.isEmpty && widget.onDeleteNote != null) {
                  widget.onDeleteNote!(day);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _checkAvailability(int employeeId, DateTime date) async {
    final cacheKey = '$employeeId-${date.year}-${date.month}-${date.day}';
    if (_availabilityCache.containsKey(cacheKey)) {
      return _availabilityCache[cacheKey]!;
    }

    // Priority 1: Check time-off first
    final timeOffList = await _timeOffDao.getAllTimeOff();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeOffEntry = timeOffList.cast<TimeOffEntry?>().firstWhere(
      (t) => t != null &&
        t.employeeId == employeeId &&
        '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}' == dateStr,
      orElse: () => null,
    );
    
    if (timeOffEntry != null) {
      final timeRange = timeOffEntry.isAllDay 
          ? 'All Day' 
          : '${timeOffEntry.startTime ?? ''} - ${timeOffEntry.endTime ?? ''}';
      final result = {
        'available': false, 
        'reason': 'Time off scheduled ($timeRange)', 
        'type': 'time-off',
        'isAllDay': timeOffEntry.isAllDay,
        'startTime': timeOffEntry.startTime,
        'endTime': timeOffEntry.endTime,
        'timeOffEntry': timeOffEntry,
      };
      _availabilityCache[cacheKey] = result;
      return result;
    }

    // Priority 2: Check availability patterns
    final result = await _availabilityDao.isAvailable(employeeId, date, null, null);
    _availabilityCache[cacheKey] = result;
    return result;
  }

  Future<void> _showAddShiftDialogWithAvailability(BuildContext context, DateTime day, int employeeId) async {
    // Get employee job code
    final employee = widget.employees.firstWhere((e) => e.id == employeeId);
    final jobCode = employee.jobCode;

    // Load templates for this job code
    await _shiftTemplateDao.insertDefaultTemplatesIfMissing(jobCode);
    final templates = await _shiftTemplateDao.getTemplatesForJobCode(jobCode);

    // Load job code settings for duration
    final jobCodeSettings = await _jobCodeDao.getByCode(jobCode);
    final defaultHours = jobCodeSettings?.defaultDailyHours ?? 8;

    // Check availability
    final availability = await _checkAvailability(employeeId, day);
    final isAvailable = availability['available'] as bool;
    final reason = availability['reason'] as String;
    final type = availability['type'] as String;

    Color bannerColor = Colors.green;
    if (type == 'time-off') {
      bannerColor = Colors.red;
    } else if (!isAvailable) {
      bannerColor = Colors.orange;
    }

    if (!context.mounted) return;

    final res = await showDialog<List<DateTime>>(
      context: context,
      builder: (context) => _buildTemplateDialog(
        day: day,
        employeeId: employeeId,
        templates: templates,
        defaultHours: defaultHours,
        bannerColor: bannerColor,
        reason: reason,
        type: type,
        isAvailable: isAvailable,
      ),
    );

    if (res != null && widget.onUpdateShift != null) {
      final tempShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 0, 0),
        end: DateTime(day.year, day.month, day.day, 0, 0),
        text: 'Shift',
      );
      widget.onUpdateShift!(tempShift, res[0], res[1]);
    }
  }

  Future<List<DateTime>?> _showEditDialog(BuildContext context, DateTime day, ShiftPlaceholder shift) async {
    final times = _allowedTimes();
    int startIdx = 0;
    int endIdx = 0;
    for (int i = 0; i < times.length; i++) {
      final t = times[i];
      final dt = _timeOfDayToDateTime(day, t);
      if (dt.hour == shift.start.hour && dt.minute == shift.start.minute && dt.day == shift.start.day) startIdx = i;
      if (dt.hour == shift.end.hour && dt.minute == shift.end.minute && dt.day == shift.end.day) endIdx = i;
    }

    int selStart = startIdx;
    int selEnd = endIdx;

    final result = await showDialog<List<DateTime>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Shift Time'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  value: selStart,
                  items: List.generate(times.length, (i) => DropdownMenuItem(value: i, child: Text(_formatTimeOfDay(times[i])))),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => selStart = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButton<int>(
                  value: selEnd,
                  items: List.generate(times.length, (i) => DropdownMenuItem(value: i, child: Text(_formatTimeOfDay(times[i])))),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => selEnd = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  final newStart = _timeOfDayToDateTime(day, times[selStart]);
                  final newEnd = _timeOfDayToDateTime(day, times[selEnd]);
                  Navigator.pop(context, [newStart, newEnd]);
                },
                child: const Text('OK'),
              ),
            ],
          );
        });
      },
    );

    return result;
  }
}

// ====================
// MONTHLY SCHEDULE VIEW
// ====================

class MonthlyScheduleView extends StatefulWidget {
  final DateTime date;
  final List<Employee> employees;
  final List<ShiftPlaceholder> shifts;
  final Map<DateTime, ScheduleNote> notes;
  final void Function(ShiftPlaceholder oldShift, DateTime newStart, DateTime newEnd)? onUpdateShift;
  final void Function(ShiftPlaceholder shift)? onCopyShift;
  final void Function(DateTime day, int employeeId)? onPasteTarget;
  final void Function(ShiftPlaceholder shift, DateTime newDay, int newEmployeeId)? onMoveShift;
  final void Function(DateTime day, String note)? onSaveNote;
  final void Function(DateTime day)? onDeleteNote;
  final bool clipboardAvailable;

  const MonthlyScheduleView({
    super.key,
    required this.date,
    required this.employees,
    this.shifts = const [],
    this.notes = const {},
    this.onUpdateShift,
    this.onCopyShift,
    this.onPasteTarget,
    this.onMoveShift,
    this.onSaveNote,
    this.onDeleteNote,
    this.clipboardAvailable = false,
  });

  @override
  State<MonthlyScheduleView> createState() => _MonthlyScheduleViewState();
}

class _MonthlyScheduleViewState extends State<MonthlyScheduleView> {
  ShiftPlaceholder? _selectedShift;
  // Drag & drop state
  DateTime? _dragHoverDay;
  int? _dragHoverEmployeeId;
  final ShiftTemplateDao _shiftTemplateDao = ShiftTemplateDao();
  final JobCodeSettingsDao _jobCodeDao = JobCodeSettingsDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final EmployeeAvailabilityDao _availabilityDao = EmployeeAvailabilityDao();
  final Map<String, Map<String, dynamic>> _availabilityCache = {};

  @override
  void initState() {
    super.initState();
    print('MonthlyScheduleView initState: ${widget.shifts.length} shifts loaded');
  }

  @override
  void didUpdateWidget(MonthlyScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shifts.length != widget.shifts.length) {
      print('MonthlyScheduleView didUpdateWidget: shifts changed from ${oldWidget.shifts.length} to ${widget.shifts.length}');
      for (var shift in widget.shifts) {
        print('  Shift: employee=${shift.employeeId}, date=${shift.start.year}-${shift.start.month}-${shift.start.day} ${shift.start.hour}:${shift.start.minute}, text=${shift.text}');
      }
    }
  }

  Future<Map<String, dynamic>> _checkAvailability(int employeeId, DateTime date) async {
    final cacheKey = '$employeeId-${date.year}-${date.month}-${date.day}';
    if (_availabilityCache.containsKey(cacheKey)) {
      return _availabilityCache[cacheKey]!;
    }

    // Priority 1: Check time-off first
    final timeOffList = await _timeOffDao.getAllTimeOff();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeOffEntry = timeOffList.cast<TimeOffEntry?>().firstWhere(
      (t) => t != null &&
        t.employeeId == employeeId &&
        '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}' == dateStr,
      orElse: () => null,
    );
    
    if (timeOffEntry != null) {
      final timeRange = timeOffEntry.isAllDay 
          ? 'All Day' 
          : '${timeOffEntry.startTime ?? ''} - ${timeOffEntry.endTime ?? ''}';
      final result = {
        'available': false, 
        'reason': 'Time off scheduled ($timeRange)', 
        'type': 'time-off',
        'isAllDay': timeOffEntry.isAllDay,
        'startTime': timeOffEntry.startTime,
        'endTime': timeOffEntry.endTime,
        'timeOffEntry': timeOffEntry,
      };
      _availabilityCache[cacheKey] = result;
      return result;
    }

    // Priority 2: Check availability patterns
    final result = await _availabilityDao.isAvailable(employeeId, date, null, null);
    _availabilityCache[cacheKey] = result;
    return result;
  }

  bool _hasNoteForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return widget.notes.containsKey(normalizedDay);
  }

  String _getNoteForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return widget.notes[normalizedDay]?.note ?? '';
  }

  Future<void> _showNoteDialog(BuildContext context, DateTime day) async {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final existingNote = widget.notes[normalizedDay];
    final controller = TextEditingController(text: existingNote?.note ?? '');

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note for ${day.month}/${day.day}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter note (leave empty to delete)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          if (existingNote != null)
            TextButton(
              onPressed: () {
                widget.onDeleteNote?.call(normalizedDay);
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      widget.onSaveNote?.call(normalizedDay, result);
    }
  }

  void _showEmptyCellContextMenu(BuildContext context, DateTime day, int employeeId, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(value: 'add', child: Text('Add Shift')),
        if (widget.clipboardAvailable)
          const PopupMenuItem(value: 'paste', child: Text('Paste Shift')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'add') {
      _showEditDialog(context, ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 9, 0),
        end: DateTime(day.year, day.month, day.day, 17, 0),
        text: '',
      ));
    } else if (result == 'paste') {
      widget.onPasteTarget?.call(day, employeeId);
    }
  }

  List<List<DateTime?>> _buildCalendarWeeks() {
    // Get first and last day of month
    final firstDayOfMonth = DateTime(widget.date.year, widget.date.month, 1);
    final lastDayOfMonth = DateTime(widget.date.year, widget.date.month + 1, 0);
    
    // Find the Sunday before or on the first day
    final startDate = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday % 7));
    
    // Build weeks (5 or 6 weeks to cover the month)
    final weeks = <List<DateTime?>>[];
    DateTime currentDate = startDate;
    
    while (currentDate.isBefore(lastDayOfMonth) || currentDate.month == lastDayOfMonth.month) {
      final week = <DateTime?>[];
      for (int i = 0; i < 7; i++) {
        week.add(currentDate);
        currentDate = currentDate.add(const Duration(days: 1));
      }
      weeks.add(week);
      
      // Stop after we've passed the last day of the month
      if (weeks.length >= 6 || (currentDate.month != widget.date.month && weeks.length >= 5)) {
        break;
      }
    }
    
    return weeks;
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$mm $suffix';
  }

  void _showShiftContextMenu(BuildContext context, ShiftPlaceholder shift, Offset? position) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null 
        ? RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy)
        : const RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('Edit Shift')),
        const PopupMenuItem(value: 'copy', child: Text('Copy Shift')),
        const PopupMenuItem(value: 'delete', child: Text('Delete Shift')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'edit') {
      _showEditDialog(context, shift);
    } else if (result == 'copy') {
      widget.onCopyShift?.call(shift);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift copied'), duration: Duration(seconds: 1)),
      );
    } else if (result == 'delete') {
      if (widget.onUpdateShift != null) {
        widget.onUpdateShift!(shift, shift.start, shift.start);
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, ShiftPlaceholder shift) async {
    // Find employee for this shift
    final employee = widget.employees.firstWhere(
      (e) => e.id == shift.employeeId,
      orElse: () => widget.employees.first,
    );
    final jobCode = employee.jobCode;
    final day = DateTime(shift.start.year, shift.start.month, shift.start.day);

    // Load templates
    await _shiftTemplateDao.insertDefaultTemplatesIfMissing(jobCode);
    final templates = await _shiftTemplateDao.getTemplatesForJobCode(jobCode);

    // Load job code settings for duration
    final jobCodeSettings = await _jobCodeDao.getByCode(jobCode);
    final defaultHours = jobCodeSettings?.defaultDailyHours ?? 8;

    // Check availability
    final availability = await _checkAvailability(shift.employeeId, day);
    final isAvailable = availability['available'] as bool;
    final reason = availability['reason'] as String;
    final type = availability['type'] as String;

    Color bannerColor = Colors.green;
    if (type == 'time-off') {
      bannerColor = Colors.red;
    } else if (!isAvailable) {
      bannerColor = Colors.orange;
    }

    if (!context.mounted) return;

    final times = _allowedTimes();
    int selStart = times.indexWhere((t) => t.hour == shift.start.hour && t.minute == shift.start.minute);
    int selEnd = times.indexWhere((t) => t.hour == shift.end.hour && t.minute == shift.end.minute);
    if (selStart == -1) selStart = 0;
    if (selEnd == -1) selEnd = times.length - 1;

    ShiftTemplate? selectedTemplate;
    final result = await showDialog<List<DateTime>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Shift'),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (templates.isNotEmpty)
                  Container(
                    width: 140,
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Templates:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        ...templates.map((template) {
                          final parts = template.startTime.split(':');
                          final startHour = int.parse(parts[0]);
                          final startMin = int.parse(parts[1]);
                          final endTime = DateTime(2000, 1, 1, startHour, startMin)
                              .add(Duration(hours: defaultHours));
                          final endTimeStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: selectedTemplate == template ? Colors.blue.withOpacity(0.1) : null,
                                side: BorderSide(
                                  color: selectedTemplate == template ? Colors.blue : Colors.grey,
                                  width: selectedTemplate == template ? 2 : 1,
                                ),
                              ),
                              onPressed: () {
                                int startIdx = times.indexWhere((t) => t.hour == startHour && t.minute == startMin);
                                if (startIdx == -1) startIdx = 0;
                                
                                int endIdx = startIdx + (defaultHours * 4);
                                if (endIdx >= times.length) endIdx = times.length - 1;

                                setDialogState(() {
                                  selectedTemplate = template;
                                  selStart = startIdx;
                                  selEnd = endIdx;
                                });
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(template.templateName, style: const TextStyle(fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${template.startTime}-$endTimeStr',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: bannerColor.withOpacity(0.2),
                          border: Border.all(color: bannerColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              type == 'time-off' ? Icons.event_busy : (isAvailable ? Icons.check_circle : Icons.warning),
                              color: bannerColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                reason,
                                style: TextStyle(color: bannerColor.withOpacity(0.9), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButton<int>(
                        value: selStart,
                        isExpanded: true,
                        items: times.asMap().entries.map((e) {
                          return DropdownMenuItem(value: e.key, child: Text(_formatTimeOfDay(e.value)));
                        }).toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            selStart = v!;
                            if (selStart >= selEnd) selEnd = (selStart + 1).clamp(0, times.length - 1);
                            selectedTemplate = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: selEnd,
                        isExpanded: true,
                        items: times.asMap().entries.map((e) {
                          return DropdownMenuItem(value: e.key, child: Text(_formatTimeOfDay(e.value)));
                        }).toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            selEnd = v!;
                            if (selEnd <= selStart) selStart = (selEnd - 1).clamp(0, times.length - 1);
                            selectedTemplate = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  final newStart = _timeOfDayToDateTime(day, times[selStart]);
                  final newEnd = _timeOfDayToDateTime(day, times[selEnd]);
                  if (!newEnd.isAfter(newStart)) {
                    Navigator.pop(context, [newStart, newStart.add(const Duration(hours: 1))]);
                  } else {
                    Navigator.pop(context, [newStart, newEnd]);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );

    if (result != null && widget.onUpdateShift != null) {
      widget.onUpdateShift!(shift, result[0], result[1]);
    }
  }

  List<TimeOfDay> _allowedTimes() {
    final List<TimeOfDay> list = [];
    list.add(const TimeOfDay(hour: 4, minute: 30));
    for (int h = 5; h <= 23; h++) {
      list.add(TimeOfDay(hour: h, minute: 0));
    }
    list.add(const TimeOfDay(hour: 0, minute: 0));
    list.add(const TimeOfDay(hour: 1, minute: 0));
    return list;
  }

  DateTime _timeOfDayToDateTime(DateTime day, TimeOfDay tod) {
    DateTime result = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
    if (tod.hour == 0 || tod.hour == 1) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  Widget _buildShiftChip(ShiftPlaceholder shift, bool isSelected, String startLabel, String endLabel, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected 
            ? Colors.blue.withAlpha(128)
            : Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
        borderRadius: BorderRadius.circular(4),
        border: isSelected 
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isLabelOnly(shift.text))
            Text(
              _labelText(shift.text),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
              textAlign: TextAlign.center,
            )
          else ...[
            Text(
              '$startLabel-',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              endLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (shift.text.isNotEmpty)
              Text(
                shift.text,
                style: const TextStyle(fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildCalendarWeeks();
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayColumnWidth = 120.0;
        final availableWidth = constraints.maxWidth - dayColumnWidth;
        final cellWidth = widget.employees.isNotEmpty 
            ? (availableWidth / widget.employees.length).clamp(80.0, 200.0)
            : 100.0;

        // Account for borders (2px on each side = 4px total)
        final totalWidth = dayColumnWidth + (cellWidth * widget.employees.length) + 4;

        return Column(
          children: [
            // Header row with employee names - horizontally scrollable
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                width: totalWidth,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  border: Border.all(color: Theme.of(context).dividerColor, width: 2),
                ),
                child: Row(
                  children: [
                    // Empty corner cell
                    SizedBox(
                      width: dayColumnWidth,
                      height: 60,
                      child: const Center(
                        child: Text('Day', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                    // Employee headers
                    ...widget.employees.map((employee) => Container(
                      width: cellWidth,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            child: Text(
                              employee.name.isNotEmpty ? employee.name[0] : '?',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            employee.name,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Weeks with days and employee cells
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: weeks.length,
                itemBuilder: (context, weekIndex) {
                  final week = weeks[weekIndex];
                  
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      width: totalWidth,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: week.asMap().entries.map((entry) {
                          final dayIndex = entry.key;
                          final day = entry.value;
                          
                          if (day == null) {
                            return const SizedBox.shrink();
                          }

                          final isCurrentMonth = day.month == widget.date.month;
                          final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
                          final dayName = dayNames[day.weekday % 7];
                          
                          return Container(
                            decoration: BoxDecoration(
                              border: dayIndex < 6 
                                  ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor))
                                  : null,
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Day label column with notes
                                  GestureDetector(
                                    onTap: () => _showNoteDialog(context, day),
                                    child: Container(
                                    width: dayColumnWidth,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      border: Border(right: BorderSide(color: Theme.of(context).dividerColor, width: 2)),
                                      color: isWeekend
                                          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(51)
                                          : !isCurrentMonth
                                              ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(25)
                                            : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            dayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (_hasNoteForDay(day))
                                            const Icon(Icons.note, size: 14, color: Colors.amber),
                                        ],
                                      ),
                                      Text(
                                        '${day.month}/${day.day}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: !isCurrentMonth
                                              ? Colors.grey
                                              : day.day == DateTime.now().day && 
                                                day.month == DateTime.now().month && 
                                                day.year == DateTime.now().year
                                                  ? Theme.of(context).colorScheme.primary
                                                  : null,
                                        ),
                                      ),
                                      if (_hasNoteForDay(day))
                                        Text(
                                          _getNoteForDay(day),
                                          style: const TextStyle(fontSize: 9, color: Colors.amber),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                  ),
                                // Employee cells for this day
                                ...widget.employees.map((employee) {
                                  final shiftsForCell = widget.shifts.where((s) {
                                    final match = s.employeeId == employee.id &&
                                      s.start.year == day.year &&
                                      s.start.month == day.month &&
                                      s.start.day == day.day;
                                    return match;
                                  }).toList();

                                  final isDragHover = _dragHoverDay?.year == day.year &&
                                      _dragHoverDay?.month == day.month &&
                                      _dragHoverDay?.day == day.day &&
                                      _dragHoverEmployeeId == employee.id;

                                  // Wrap in DragTarget for drop support
                                  return DragTarget<ShiftPlaceholder>(
                                    onWillAcceptWithDetails: (details) {
                                      setState(() {
                                        _dragHoverDay = day;
                                        _dragHoverEmployeeId = employee.id;
                                      });
                                      return true;
                                    },
                                    onLeave: (_) {
                                      setState(() {
                                        _dragHoverDay = null;
                                        _dragHoverEmployeeId = null;
                                      });
                                    },
                                    onAcceptWithDetails: (details) {
                                      setState(() {
                                        _dragHoverDay = null;
                                        _dragHoverEmployeeId = null;
                                      });
                                      widget.onMoveShift?.call(details.data, day, employee.id!);
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      return GestureDetector(
                                        onTap: shiftsForCell.isEmpty ? () {
                                          // If clipboard has data, paste on single click
                                          if (widget.clipboardAvailable && widget.onPasteTarget != null) {
                                            widget.onPasteTarget!(day, employee.id!);
                                          } else {
                                            // Otherwise show add shift dialog
                                            _showEditDialog(context, ShiftPlaceholder(
                                              employeeId: employee.id!,
                                              start: DateTime(day.year, day.month, day.day, 9, 0),
                                              end: DateTime(day.year, day.month, day.day, 17, 0),
                                              text: '',
                                            ));
                                          }
                                        } : null,
                                        onSecondaryTapDown: shiftsForCell.isEmpty ? (details) {
                                          _showEmptyCellContextMenu(context, day, employee.id!, details.globalPosition);
                                        } : null,
                                        child: Container(
                                          width: cellWidth,
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                                            color: isDragHover
                                                ? Colors.blue.withAlpha(50)
                                                : !isCurrentMonth
                                                    ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(25)
                                                    : isWeekend
                                                        ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(51)
                                                        : null,
                                          ),
                                          child: shiftsForCell.isEmpty
                                              ? (isDragHover 
                                                  ? const Center(child: Icon(Icons.add, color: Colors.blue, size: 20))
                                                  : const SizedBox.shrink())
                                              : Column(
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: shiftsForCell.map((shift) {
                                                    final isSelected = _selectedShift == shift;
                                                    final startLabel = _formatTimeOfDay(TimeOfDay(hour: shift.start.hour, minute: shift.start.minute));
                                                    final endLabel = _formatTimeOfDay(TimeOfDay(hour: shift.end.hour, minute: shift.end.minute));

                                                    // Wrap shift in Draggable
                                                    return Draggable<ShiftPlaceholder>(
                                                      data: shift,
                                                      feedback: Material(
                                                        elevation: 4,
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Container(
                                                          padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue.withAlpha(200),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            _isLabelOnly(shift.text) ? _labelText(shift.text) : '$startLabel-$endLabel',
                                                            style: const TextStyle(color: Colors.white, fontSize: 10),
                                                          ),
                                                        ),
                                                      ),
                                                      childWhenDragging: Opacity(
                                                        opacity: 0.3,
                                                        child: _buildShiftChip(shift, isSelected, startLabel, endLabel, context),
                                                      ),
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          setState(() {
                                                            _selectedShift = isSelected ? null : shift;
                                                          });
                                                        },
                                                        onDoubleTap: () {
                                                          _showEditDialog(context, shift);
                                                        },
                                                        onSecondaryTapDown: (details) {
                                                          setState(() {
                                                            _selectedShift = shift;
                                                          });
                                                          _showShiftContextMenu(context, shift, details.globalPosition);
                                                        },
                                                        child: _buildShiftChip(shift, isSelected, startLabel, endLabel, context),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// Public simple shift placeholder for rendering
class ShiftPlaceholder {
  final int? id;  // Database ID (null for time-off entries)
  final int employeeId;
  final DateTime start;
  final DateTime end;
  final String text;

  ShiftPlaceholder({
    this.id,
    required this.employeeId,
    required this.start,
    required this.end,
    required this.text,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShiftPlaceholder &&
        other.id == id &&
        other.employeeId == employeeId &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => id.hashCode ^ employeeId.hashCode ^ start.hashCode ^ end.hashCode;
}

