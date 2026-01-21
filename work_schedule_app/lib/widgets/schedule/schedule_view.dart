import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/employee_dao.dart';
import '../../database/time_off_dao.dart';
import '../../database/employee_availability_dao.dart';
import '../../database/shift_template_dao.dart';
import '../../database/weekly_template_dao.dart';
import '../../database/job_code_settings_dao.dart';
import '../../database/shift_dao.dart';
import '../../database/schedule_note_dao.dart';
import '../../database/shift_runner_dao.dart';
import '../../database/shift_type_dao.dart';
import '../../database/store_hours_dao.dart';
import '../../models/employee.dart';
import '../../models/time_off_entry.dart';
import '../../models/shift_template.dart';
import '../../models/weekly_template.dart';
import '../../models/shift.dart';
import '../../models/schedule_note.dart';
import '../../models/job_code_settings.dart';
import '../../models/shift_runner.dart';
import '../../models/shift_type.dart';
import '../../models/store_hours.dart';
import '../../services/app_colors.dart';
import '../../services/schedule_pdf_service.dart';
import '../../services/schedule_undo_manager.dart';
import 'shift_runner_table.dart';

// Custom intents for keyboard shortcuts
class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

enum ScheduleMode { weekly, monthly }

bool _isLabelOnly(String text) {
  final t = text.toLowerCase();
  // Only time-off system labels are non-editable (not manual "OFF")
  return t == 'pto' || t == 'vac' || t == 'req off';
}

/// Check if a shift should display as a label instead of time range
/// Returns true for time-off labels OR if it's an OFF shift (4AM-3:59AM)
bool _shouldShowAsLabel(ShiftPlaceholder s) {
  if (_isLabelOnly(s.text)) return true;
  // Check for OFF shift format: 4:00 AM to 3:59 AM (next day)
  final t = s.text.toLowerCase();
  if (t == 'off') {
    return (s.start.hour == 4 && s.start.minute == 0 &&
            s.end.hour == 3 && s.end.minute == 59);
  }
  return false;
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

  ScheduleView({
    super.key,
    DateTime? date,
    this.initialMode = ScheduleMode.weekly,
  }) : initialDate = date ?? DateTime.now();

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
  final ShiftRunnerDao _shiftRunnerDao = ShiftRunnerDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
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

  // Counter to trigger shift runner refresh in child views
  int _shiftRunnerRefreshKey = 0;

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
    return entries
        .where((e) {
          // Skip partial day time off entries (sick/requested type with specific hours)
          // These should not show "REQ OFF" in the cell - only show a warning in the dialog
          if (e.timeOffType.toLowerCase() == 'sick' && !e.isAllDay) {
            return false;
          }
          return true;
        })
        .map((e) {
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
        })
        .toList();
  }

  List<ShiftPlaceholder> _shiftsToPlaceholders(List<Shift> shifts) {
    return shifts
        .map(
          (s) => ShiftPlaceholder(
            id: s.id,
            employeeId: s.employeeId,
            start: s.startTime,
            end: s.endTime,
            text: s.label ?? '',
            notes: s.notes,
          ),
        )
        .toList();
  }

  Future<void> _refreshShifts() async {
    // Load time-off entries
    final timeOffEntries = await _timeOffDao.getAllTimeOff();
    final timeOffShifts = _timeOffToShifts(timeOffEntries);

    // Load actual shifts from database based on current view
    List<Shift> dbShifts;
    if (_mode == ScheduleMode.monthly) {
      // Use calendar month to include visible overlapping days from adjacent months
      dbShifts = await _shiftDao.getByCalendarMonth(_date.year, _date.month);
    } else if (_mode == ScheduleMode.weekly) {
      dbShifts = await _shiftDao.getByWeek(_date);
    } else {
      dbShifts = await _shiftDao.getByDate(_date);
    }
    final workShifts = _shiftsToPlaceholders(dbShifts);

    // Load notes based on current view
    Map<DateTime, ScheduleNote> notes;
    if (_mode == ScheduleMode.monthly) {
      // Use calendar month to include visible overlapping days from adjacent months
      notes = await _noteDao.getByCalendarMonth(_date.year, _date.month);
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

    // Load store hours into cache
    final storeHoursDao = StoreHoursDao();
    final storeHours = await storeHoursDao.getStoreHours();
    StoreHours.setCache(storeHours);

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
      _filteredEmployees = _employees
          .where(
            (e) => e.jobCode.toLowerCase() == _selectedJobCode!.toLowerCase(),
          )
          .toList();
    } else if (_filterType == 'employee' && _selectedEmployeeId != null) {
      _filteredEmployees = _employees
          .where((e) => e.id == _selectedEmployeeId)
          .toList();
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
      hierarchy[_jobCodeSettings[i].code.toLowerCase()] =
          _jobCodeSettings[i].sortOrder;
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
      if (_mode == ScheduleMode.weekly) {
        _date = _date.subtract(const Duration(days: 7));
      } else {
        _date = DateTime(_date.year, _date.month - 1, 1);
      }
    });
    _refreshShifts();
  }

  void _next() {
    setState(() {
      if (_mode == ScheduleMode.weekly) {
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
    // Check if there's a runner assigned for this shift's employee, date, and shift type
    ShiftRunner? deletedRunner;
    
    // Determine the shift type from the shift's start time
    final shiftType = ShiftRunner.getShiftTypeForTime(
      shift.startTime.hour,
      shift.startTime.minute,
    );
    
    if (shiftType != null) {
      final shiftDate = DateTime(
        shift.startTime.year,
        shift.startTime.month,
        shift.startTime.day,
      );
      
      // Get the runner for this date and shift type
      final runner = await _shiftRunnerDao.getForDateAndShift(shiftDate, shiftType);
      
      // Check if the runner is the employee being deleted
      if (runner != null) {
        final employee = await _employeeDao.getById(shift.employeeId);
        if (employee != null && runner.runnerName == employee.name) {
          deletedRunner = runner;
        }
      }
    }
    
    final action = DeleteShiftAction(
      shift: shift,
      insertFn: (s) => _shiftDao.insert(s),
      deleteFn: (id) => _shiftDao.delete(id),
      deletedRunner: deletedRunner,
      upsertRunnerFn: deletedRunner != null ? (r) => _shiftRunnerDao.upsert(r) : null,
      deleteRunnerFn: deletedRunner != null ? (date, type) => _shiftRunnerDao.delete(date, type) : null,
    );
    await _undoManager.executeAction(action);
    
    // If a runner was deleted, trigger runner table refresh
    if (deletedRunner != null) {
      setState(() {
        _shiftRunnerRefreshKey++;
      });
    }
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
      late final Uint8List fileBytes;
      late final String title;
      late final String filename;
      late final String fileType;

      // Load shift types
      final shiftTypes = await _shiftTypeDao.getAll();

      if (_mode == ScheduleMode.weekly) {
        // Get week start (Sunday)
        final weekStart = _date.subtract(Duration(days: _date.weekday % 7));
        final weekEnd = weekStart.add(const Duration(days: 6));

        // Load shift runners for this week
        final shiftRunners = await _shiftRunnerDao.getForDateRange(
          weekStart,
          weekEnd,
        );

        if (action == 'pdf_manager') {
          fileBytes = await SchedulePdfService.generateManagerWeeklyPdf(
            weekStart: weekStart,
            employees: _employees,
            shifts: _shifts,
            jobCodeSettings: _jobCodeSettings,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            notes: _notes,
            storeName: StoreHours.cached.storeName,
            storeNsn: StoreHours.cached.storeNsn,
          );
          fileType = 'Manager PDF';
          filename =
              'manager_schedule_${weekStart.year}_${weekStart.month}_${weekStart.day}.pdf';
        } else {
          fileBytes = await SchedulePdfService.generateWeeklyPdf(
            weekStart: weekStart,
            employees: _employees,
            shifts: _shifts,
            jobCodeSettings: _jobCodeSettings,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            storeHours: StoreHours.cached,
            storeName: StoreHours.cached.storeName,
            storeNsn: StoreHours.cached.storeNsn,
          );
          fileType = 'PDF';
          filename =
              'schedule_${weekStart.year}_${weekStart.month}_${weekStart.day}.pdf';
        }
        title =
            'Schedule - Week of ${weekStart.month}/${weekStart.day}/${weekStart.year}';
      } else {
        // Get first and last day of month for shift runners
        final firstDay = DateTime(_date.year, _date.month, 1);
        final lastDay = DateTime(_date.year, _date.month + 1, 0);

        // Load shift runners for this month
        final shiftRunners = await _shiftRunnerDao.getForDateRange(
          firstDay,
          lastDay,
        );

        if (action == 'pdf_manager') {
          fileBytes = await SchedulePdfService.generateManagerMonthlyPdf(
            year: _date.year,
            month: _date.month,
            employees: _employees,
            shifts: _shifts,
            jobCodeSettings: _jobCodeSettings,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            notes: _notes,
            storeName: StoreHours.cached.storeName,
            storeNsn: StoreHours.cached.storeNsn,
          );
          fileType = 'Manager PDF';
          filename = 'manager_schedule_${_date.year}_${_date.month}.pdf';
        } else {
          fileBytes = await SchedulePdfService.generateMonthlyPdf(
            year: _date.year,
            month: _date.month,
            employees: _employees,
            shifts: _shifts,
            jobCodeSettings: _jobCodeSettings,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            storeHours: StoreHours.cached,
            storeName: StoreHours.cached.storeName,
            storeNsn: StoreHours.cached.storeNsn,
          );
          fileType = 'PDF';
          filename = 'schedule_${_date.year}_${_date.month}.pdf';
        }
        final monthNames = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        title = 'Schedule - ${monthNames[_date.month - 1]} ${_date.year}';
      }

      if (action == 'print') {
        await SchedulePdfService.printSchedule(fileBytes, title);
      } else {
        await SchedulePdfService.sharePdf(fileBytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$fileType exported successfully: $filename'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate file: $e')));
      }
    }
  }

  Future<void> _handleWeekAction(String action) async {
    // Get current week start (Sunday)
    final weekStart = _date.subtract(Duration(days: _date.weekday % 7));
    final weekStartDate = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );

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

  Future<void> _copyWeekTo(
    DateTime sourceWeekStart,
    DateTime targetWeekStart,
  ) async {
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
          'to week of ${targetWeekStart.month}/${targetWeekStart.day}?',
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
        SnackBar(
          content: Text('Copied ${newShifts.length} shift(s) to new week'),
        ),
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
          'This action cannot be undone.',
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
        SnackBar(
          content: Text('Cleared ${shifts.length} shift(s) from this week'),
        ),
      );
    }
  }

  Future<DateTime?> _showWeekPicker(
    BuildContext context,
    DateTime currentWeek,
  ) async {
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

  final WeeklyTemplateDao _weeklyTemplateDao = WeeklyTemplateDao();

  Future<void> _autoFillFromTemplates(DateTime weekStart) async {
    // Get employees who have weekly templates
    final employeeIdsWithTemplates = await _weeklyTemplateDao.getEmployeeIdsWithTemplates();
    
    if (employeeIdsWithTemplates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No employees have weekly templates defined. Go to Roster and set up Weekly Templates for employees.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Filter employees who have templates
    final employeesWithTemplates = _employees
        .where((e) => employeeIdsWithTemplates.contains(e.id))
        .toList();

    if (employeesWithTemplates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No employees with weekly templates found in the current filter.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Show dialog with employee selection
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AutoFillFromWeeklyTemplatesDialog(
        employees: employeesWithTemplates,
        weeklyTemplateDao: _weeklyTemplateDao,
        weekStart: weekStart,
      ),
    );

    if (result == null) return;

    final selectedEmployeeIds = result['selectedEmployees'] as List<int>;
    final skipExisting = result['skipExisting'] as bool;
    final overrideExisting = result['overrideExisting'] as bool;

    if (selectedEmployeeIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one employee')),
        );
      }
      return;
    }

    // Get templates for selected employees
    final templates = await _weeklyTemplateDao.getTemplatesForEmployees(selectedEmployeeIds);

    // Generate shifts
    int shiftsCreated = 0;
    int shiftsDeleted = 0;
    final newShifts = <Shift>[];
    final shiftsToDelete = <int>[];

    for (final employeeId in selectedEmployeeIds) {
      final employeeTemplates = templates[employeeId] ?? [];
      
      for (final template in employeeTemplates) {
        // Skip blank days (no shift and not marked as OFF)
        if (template.isBlank) continue;
        
        final dayIndex = template.dayOfWeek;
        final day = weekStart.add(Duration(days: dayIndex));

        // Check if employee already has a shift this day
        final existingShifts = _shifts
            .where(
              (s) =>
                  s.employeeId == employeeId &&
                  s.start.year == day.year &&
                  s.start.month == day.month &&
                  s.start.day == day.day,
            )
            .toList();

        if (existingShifts.isNotEmpty) {
          if (skipExisting) {
            continue;
          } else if (overrideExisting) {
            // Mark existing shifts for deletion
            for (final shift in existingShifts) {
              if (shift.id != null) {
                shiftsToDelete.add(shift.id!);
                shiftsDeleted++;
              }
            }
          } else {
            // Don't skip but don't override either - skip this day
            continue;
          }
        }

        // Handle OFF days - create a shift with "OFF" label
        if (template.isOff) {
          newShifts.add(
            Shift(
              employeeId: employeeId,
              startTime: DateTime(day.year, day.month, day.day, 0, 0),
              endTime: DateTime(day.year, day.month, day.day, 23, 59),
              label: 'OFF',
            ),
          );
          shiftsCreated++;
          continue;
        }

        // Parse template times for regular shifts
        final startTimeParts = template.startTime!.split(':');
        final startHour = int.parse(startTimeParts[0]);
        final startMinute = startTimeParts.length > 1 ? int.parse(startTimeParts[1]) : 0;

        final endTimeParts = template.endTime!.split(':');
        final endHour = int.parse(endTimeParts[0]);
        final endMinute = endTimeParts.length > 1 ? int.parse(endTimeParts[1]) : 0;

        final shiftStart = DateTime(day.year, day.month, day.day, startHour, startMinute);
        var shiftEnd = DateTime(day.year, day.month, day.day, endHour, endMinute);

        // Handle overnight shifts
        if (shiftEnd.isBefore(shiftStart) || shiftEnd.isAtSameMomentAs(shiftStart)) {
          shiftEnd = shiftEnd.add(const Duration(days: 1));
        }

        newShifts.add(
          Shift(
            employeeId: employeeId,
            startTime: shiftStart,
            endTime: shiftEnd,
          ),
        );
        shiftsCreated++;
      }
    }

    if (newShifts.isEmpty && shiftsToDelete.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No shifts were created (all slots already filled or no shifts in templates)'),
          ),
        );
      }
      return;
    }

    // Delete existing shifts if override is enabled
    for (final shiftId in shiftsToDelete) {
      await _shiftDao.delete(shiftId);
    }

    // Insert new shifts
    if (newShifts.isNotEmpty) {
      await _shiftDao.insertAll(newShifts);
    }
    await _refreshShifts();

    if (mounted) {
      String message = 'Created $shiftsCreated shift(s) from weekly templates';
      if (shiftsDeleted > 0) {
        message += ', replaced $shiftsDeleted existing shift(s)';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
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
              items: _uniqueJobCodes
                  .map(
                    (code) => DropdownMenuItem(value: code, child: Text(code)),
                  )
                  .toList(),
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
              items: _employees
                  .map(
                    (emp) =>
                        DropdownMenuItem(value: emp.id, child: Text(emp.name)),
                  )
                  .toList(),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Weekly'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Monthly'),
            ),
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
              value: 'pdf_standard',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, size: 20),
                  SizedBox(width: 8),
                  Text('Export Standard PDF'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pdf_manager',
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, size: 20),
                  SizedBox(width: 8),
                  Text('Export Manager PDF'),
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
                    Text(
                      'Clear This Week',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_mode == ScheduleMode.weekly) {
      // Calculate week start (Sunday)
      final weekStart = _date.subtract(Duration(days: _date.weekday % 7));
      final normalizedWeekStart = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Weekly schedule on the left
          Expanded(
            child: WeeklyScheduleView(
              date: _date,
              employees: _filteredEmployees,
              shifts: _shifts,
              notes: _notes,
              jobCodeSettings: _jobCodeSettings,
              clipboardAvailable: _clipboard != null,
              shiftRunnerRefreshKey: _shiftRunnerRefreshKey,
              onShiftRunnerChanged: () {
                setState(() {
                  _shiftRunnerRefreshKey++;
                });
                _refreshShifts(); // Reload schedule in case a shift was auto-created
              },
              onCopyShift: (s) {
                setState(() {
                  _clipboard = {
                    'start': TimeOfDay(
                      hour: s.start.hour,
                      minute: s.start.minute,
                    ),
                    'duration': s.end.difference(s.start),
                    'text': s.text,
                  };
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
                DateTime start = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  tod.hour,
                  tod.minute,
                );
                // times with hour 0 or 1 are next-day
                if (tod.hour == 0 || tod.hour == 1)
                  start = start.add(const Duration(days: 1));
                final end = start.add(dur);

                // Check for conflicts
                final hasConflict = await _shiftDao.hasConflict(
                  employeeId,
                  start,
                  end,
                );
                if (hasConflict && mounted) {
                  final proceed = await _showConflictWarning(
                    context,
                    employeeId,
                    start,
                    end,
                  );
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
              onUpdateShift:
                  (oldShift, newStart, newEnd, {String? shiftNotes}) async {
                    // Handle "OFF" button - create an OFF label shift (4AM-3:59AM)
                    if (shiftNotes == 'OFF') {
                      // Calculate 4:00 AM start and 3:59 AM next day end
                      final day = oldShift.id != null ? oldShift.start : newStart;
                      final offStart = DateTime(day.year, day.month, day.day, 4, 0);
                      final offEnd = DateTime(day.year, day.month, day.day, 3, 59).add(const Duration(days: 1));
                      
                      if (oldShift.id != null) {
                        // Update existing shift to OFF
                        final oldShiftModel = Shift(
                          id: oldShift.id,
                          employeeId: oldShift.employeeId,
                          startTime: oldShift.start,
                          endTime: oldShift.end,
                          label: oldShift.text,
                          notes: oldShift.notes,
                        );
                        final updated = Shift(
                          id: oldShift.id,
                          employeeId: oldShift.employeeId,
                          startTime: offStart,
                          endTime: offEnd,
                          label: 'OFF',
                          notes: null,
                        );
                        await _updateShiftWithUndo(oldShiftModel, updated);
                      } else {
                        // Create new OFF shift
                        final newShift = Shift(
                          employeeId: oldShift.employeeId,
                          startTime: offStart,
                          endTime: offEnd,
                          label: 'OFF',
                          notes: null,
                        );
                        await _insertShiftWithUndo(newShift);
                      }
                      await _refreshShifts();
                      return;
                    }

                    if (newStart == newEnd) {
                      // Delete with undo support
                      if (oldShift.id != null) {
                        final shiftToDelete = Shift(
                          id: oldShift.id,
                          employeeId: oldShift.employeeId,
                          startTime: oldShift.start,
                          endTime: oldShift.end,
                          label: oldShift.text,
                          notes: oldShift.notes,
                        );
                        await _deleteShiftWithUndo(shiftToDelete);
                      }
                    } else {
                      // Check for conflicts (exclude current shift if editing)
                      final hasConflict = await _shiftDao.hasConflict(
                        oldShift.employeeId,
                        newStart,
                        newEnd,
                        excludeId: oldShift.id,
                      );
                      if (hasConflict && mounted) {
                        final proceed = await _showConflictWarning(
                          context,
                          oldShift.employeeId,
                          newStart,
                          newEnd,
                          excludeId: oldShift.id,
                        );
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
                          notes: oldShift.notes,
                        );
                        final updated = Shift(
                          id: oldShift.id,
                          employeeId: oldShift.employeeId,
                          startTime: newStart,
                          endTime: newEnd,
                          label: oldShift.text,
                          notes: shiftNotes ?? oldShift.notes,
                        );
                        await _updateShiftWithUndo(oldShiftModel, updated);
                      } else {
                        // Insert new
                        final newShift = Shift(
                          employeeId: oldShift.employeeId,
                          startTime: newStart,
                          endTime: newEnd,
                          label: oldShift.text,
                          notes: shiftNotes,
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
                  newDay.year,
                  newDay.month,
                  newDay.day,
                  shift.start.hour,
                  shift.start.minute,
                );
                final newEnd = newStart.add(duration);

                // Check for conflicts
                final hasConflict = await _shiftDao.hasConflict(
                  newEmployeeId,
                  newStart,
                  newEnd,
                  excludeId: shift.id,
                );
                if (hasConflict && mounted) {
                  final proceed = await _showConflictWarning(
                    context,
                    newEmployeeId,
                    newStart,
                    newEnd,
                    excludeId: shift.id,
                  );
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
            ),
          ),
          // Shift Runner table on the right side
          ShiftRunnerTable(
            weekStart: normalizedWeekStart,
            refreshKey: _shiftRunnerRefreshKey,
            onChanged: () async {
              await _refreshShifts();
              setState(() {
                _shiftRunnerRefreshKey++;
              });
            },
          ),
        ],
      );
    }

    return MonthlyScheduleView(
      date: _date,
      employees: _filteredEmployees,
      shifts: _shifts,
      notes: _notes,
      jobCodeSettings: _jobCodeSettings,
      clipboardAvailable: _clipboard != null,
      shiftRunnerRefreshKey: _shiftRunnerRefreshKey,
      onShiftRunnerChanged: () {
        setState(() {
          _shiftRunnerRefreshKey++;
        });
        _refreshShifts(); // Reload schedule in case a shift was auto-created
      },
      onCopyShift: (s) {
        setState(() {
          _clipboard = {
            'start': TimeOfDay(hour: s.start.hour, minute: s.start.minute),
            'duration': s.end.difference(s.start),
            'text': s.text,
          };
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
        DateTime start = DateTime(
          day.year,
          day.month,
          day.day,
          tod.hour,
          tod.minute,
        );
        if (tod.hour == 0 || tod.hour == 1)
          start = start.add(const Duration(days: 1));
        final end = start.add(dur);

        final hasConflict = await _shiftDao.hasConflict(employeeId, start, end);
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(
            context,
            employeeId,
            start,
            end,
          );
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
      onUpdateShift: (oldShift, newStart, newEnd, {String? shiftNotes}) async {
        // Handle "OFF" button - create an OFF label shift (4AM-3:59AM)
        if (shiftNotes == 'OFF') {
          // Calculate 4:00 AM start and 3:59 AM next day end
          final day = oldShift.id != null ? oldShift.start : newStart;
          final offStart = DateTime(day.year, day.month, day.day, 4, 0);
          final offEnd = DateTime(day.year, day.month, day.day, 3, 59).add(const Duration(days: 1));
          
          if (oldShift.id != null) {
            // Update existing shift to OFF
            final oldShiftModel = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
              notes: oldShift.notes,
            );
            final updated = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: offStart,
              endTime: offEnd,
              label: 'OFF',
              notes: null,
            );
            await _updateShiftWithUndo(oldShiftModel, updated);
          } else {
            // Create new OFF shift
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: offStart,
              endTime: offEnd,
              label: 'OFF',
              notes: null,
            );
            await _insertShiftWithUndo(newShift);
          }
          await _refreshShifts();
          return;
        }

        if (newStart == newEnd) {
          // Delete with undo
          if (oldShift.id != null) {
            final shiftToDelete = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: oldShift.start,
              endTime: oldShift.end,
              label: oldShift.text,
              notes: oldShift.notes,
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
              notes: oldShift.notes,
            );
            final updated = Shift(
              id: oldShift.id,
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
              notes: shiftNotes ?? oldShift.notes,
            );
            await _updateShiftWithUndo(oldShiftModel, updated);
          } else {
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
              notes: shiftNotes,
            );
            await _insertShiftWithUndo(newShift);
          }
        }
        await _refreshShifts();
      },
      onMoveShift: (shift, newDay, newEmployeeId) async {
        final duration = shift.end.difference(shift.start);
        final newStart = DateTime(
          newDay.year,
          newDay.month,
          newDay.day,
          shift.start.hour,
          shift.start.minute,
        );
        final newEnd = newStart.add(duration);

        final hasConflict = await _shiftDao.hasConflict(
          newEmployeeId,
          newStart,
          newEnd,
          excludeId: shift.id,
        );
        if (hasConflict && mounted) {
          final proceed = await _showConflictWarning(
            context,
            newEmployeeId,
            newStart,
            newEnd,
            excludeId: shift.id,
          );
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

  String _dayOfWeekAbbr(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  /// Show a warning dialog when there's a scheduling conflict
  Future<bool> _showConflictWarning(
    BuildContext context,
    int employeeId,
    DateTime start,
    DateTime end, {
    int? excludeId,
  }) async {
    final conflicts = await _shiftDao.getConflicts(
      employeeId,
      start,
      end,
      excludeId: excludeId,
    );
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
                  color: Theme.of(ctx).extension<AppColors>()!.warningBackground,
                  border: Border.all(color: Theme.of(ctx).extension<AppColors>()!.warningBorder),
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
                    const Text(
                      'Conflicting shift(s):',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    ...conflicts.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(
                          '• ${_formatTimeRange(c.startTime, c.endTime)}',
                        ),
                      ),
                    ),
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
                foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
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
// WEEKLY VIEW - days on Y axis (Mon..Sun or starting with date's week), employees on X axis
// ------------------------------------------------------------
class WeeklyScheduleView extends StatefulWidget {
  final DateTime date;
  final List<Employee> employees;
  final List<ShiftPlaceholder> shifts;
  final Map<DateTime, ScheduleNote> notes;
  final List<JobCodeSettings> jobCodeSettings;
  final void Function(
    ShiftPlaceholder oldShift,
    DateTime newStart,
    DateTime newEnd, {
    String? shiftNotes,
  })?
  onUpdateShift;
  final void Function(ShiftPlaceholder shift)? onCopyShift;
  final void Function(DateTime day, int employeeId)? onPasteTarget;
  final void Function(
    ShiftPlaceholder shift,
    DateTime newDay,
    int newEmployeeId,
  )?
  onMoveShift;
  final void Function(DateTime day, String note)? onSaveNote;
  final void Function(DateTime day)? onDeleteNote;
  final VoidCallback? onShiftRunnerChanged;
  final bool clipboardAvailable;
  final int shiftRunnerRefreshKey;

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
    this.onShiftRunnerChanged,
    this.clipboardAvailable = false,
    this.shiftRunnerRefreshKey = 0,
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
  final ShiftRunnerDao _shiftRunnerDao = ShiftRunnerDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final Map<String, Map<String, dynamic>> _availabilityCache = {};
  List<ShiftType> _shiftTypes = [];
  List<ShiftRunner> _shiftRunners = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadShiftRunnerData();
  }

  @override
  void didUpdateWidget(WeeklyScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date ||
        oldWidget.shiftRunnerRefreshKey != widget.shiftRunnerRefreshKey) {
      _loadShiftRunnerData();
    }
  }

  Future<void> _loadShiftRunnerData() async {
    final shiftTypes = await _shiftTypeDao.getAll();
    ShiftRunner.setShiftTypes(shiftTypes);
    final weekStart = _normalizeToWeekStart(widget.date);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final runners = await _shiftRunnerDao.getForDateRange(weekStart, weekEnd);
    if (mounted) {
      setState(() {
        _shiftTypes = shiftTypes;
        _shiftRunners = runners;
      });
    }
  }

  DateTime _normalizeToWeekStart(DateTime date) {
    final daysSinceSunday = date.weekday % 7;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: daysSinceSunday));
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
      final shiftsForDay = widget.shifts.where(
        (s) =>
            s.employeeId == employeeId &&
            s.start.year == day.year &&
            s.start.month == day.month &&
            s.start.day == day.day &&
            !['VAC', 'PTO', 'REQ OFF', 'OFF'].contains(s.text.toUpperCase()),
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
    required Color bannerColor,
    required String reason,
    required String type,
    required bool isAvailable,
    TimeOffEntry? timeOffEntry,
  }) {
    final times = _allowedTimes();
    int selStart = 0;
    int selEnd = 16;
    ShiftTemplate? selectedTemplate;
    String? selectedRunnerShift; // Track which shift runner button is selected

    return StatefulBuilder(
      builder: (context, setDialogState) {
        // Helper to check if the selected shift times overlap with time off
        bool shiftOverlapsTimeOff() {
          if (timeOffEntry == null) return false;
          final shiftStart = times[selStart];
          final shiftEnd = times[selEnd];
          final shiftStartDt = _timeOfDayToDateTime(day, shiftStart);
          final shiftEndDt = _timeOfDayToDateTime(day, shiftEnd);
          return timeOffEntry.overlapsWithShift(shiftStartDt, shiftEndDt);
        }

        return AlertDialog(
          title: const Text('Add Shift'),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Templates column (left)
              if (templates.isNotEmpty)
                Container(
                  width: 140,
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Templates:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...templates.map((template) {
                        final startParts = template.startTime.split(':');
                        final startHour = int.parse(startParts[0]);
                        final startMin = int.parse(startParts[1]);
                        final endParts = template.endTime.split(':');
                        final endHour = int.parse(endParts[0]);
                        final endMin = int.parse(endParts[1]);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selectedTemplate == template
                                  ? Colors.blue.withOpacity(0.1)
                                  : null,
                              side: BorderSide(
                                color: selectedTemplate == template
                                    ? Colors.blue
                                    : Colors.grey,
                                width: selectedTemplate == template ? 2 : 1,
                              ),
                            ),
                            onPressed: () {
                              int startIdx = times.indexWhere(
                                (t) =>
                                    t.hour == startHour && t.minute == startMin,
                              );
                              if (startIdx == -1) startIdx = 0;

                              int endIdx = times.indexWhere(
                                (t) => t.hour == endHour && t.minute == endMin,
                              );
                              if (endIdx == -1) endIdx = times.length - 1;

                              setDialogState(() {
                                selectedTemplate = template;
                                selStart = startIdx;
                                selEnd = endIdx;
                              });
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  template.templateName,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${template.startTime}-${template.endTime}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              // Time selection column (center)
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
                            type == 'time-off'
                                ? Icons.event_busy
                                : (isAvailable
                                      ? Icons.check_circle
                                      : Icons.warning),
                            color: bannerColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                color: bannerColor.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButton<int>(
                      value: selStart,
                      isExpanded: true,
                      items: List.generate(
                        times.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(_formatTimeOfDay(times[i])),
                        ),
                      ),
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
                      items: List.generate(
                        times.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(_formatTimeOfDay(times[i])),
                        ),
                      ),
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
              // Shift Runner column (right)
              Container(
                width: 100,
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Shift Runner:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...ShiftRunner.shiftOrder.map((shiftType) {
                      final isSelected = selectedRunnerShift == shiftType;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              if (selectedRunnerShift == shiftType) {
                                selectedRunnerShift =
                                    null; // Deselect if already selected
                              } else {
                                selectedRunnerShift = shiftType;
                                // Update time selection to match shift type defaults
                                final shiftTypeObj = _shiftTypes
                                    .cast<ShiftType?>()
                                    .firstWhere(
                                      (st) => st?.key == shiftType,
                                      orElse: () => null,
                                    );
                                if (shiftTypeObj != null) {
                                  selStart = _findTimeIndex(
                                    times,
                                    shiftTypeObj.defaultShiftStart,
                                  );
                                  selEnd = _findTimeIndex(
                                    times,
                                    shiftTypeObj.defaultShiftEnd,
                                  );
                                }
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _getShiftTypeColor(
                                      shiftType,
                                    ).withOpacity(0.3)
                                  : _getShiftTypeColor(
                                      shiftType,
                                    ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getShiftTypeColor(shiftType),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              ShiftRunner.getLabelForType(shiftType),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _getShiftTypeColor(shiftType),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {'off': true}),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              child: const Text('OFF'),
            ),
            TextButton(
              onPressed: () async {
                final newStart = _timeOfDayToDateTime(day, times[selStart]);
                final newEnd = _timeOfDayToDateTime(day, times[selEnd]);

                // Check if shift overlaps with time off and confirm
                if (shiftOverlapsTimeOff()) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Scheduling Conflict'),
                      content: const Text(
                        'The employee is not available for this time. Are you sure?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('No'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Yes'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }

                // Return the data including runner selection - runner will be saved by caller
                if (!newEnd.isAfter(newStart)) {
                  Navigator.pop(context, {
                    'start': newStart,
                    'end': newStart.add(const Duration(hours: 1)),
                    'runnerShift': selectedRunnerShift,
                  });
                } else {
                  Navigator.pop(context, {
                    'start': newStart,
                    'end': newEnd,
                    'runnerShift': selectedRunnerShift,
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Color _getShiftTypeColor(String shiftType) {
    final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
      (st) => st?.key == shiftType,
      orElse: () => null,
    );
    final hex =
        shiftTypeObj?.colorHex ??
        ShiftType.defaultShiftTypes
            .firstWhere(
              (st) => st.key == shiftType,
              orElse: () => ShiftType.defaultShiftTypes.first,
            )
            .colorHex;
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  // Get shift runner for a given day and shift type
  ShiftRunner? _getShiftRunner(DateTime day, String shiftType) {
    return _shiftRunners.cast<ShiftRunner?>().firstWhere(
      (r) =>
          r != null &&
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day &&
          r.shiftType == shiftType,
      orElse: () => null,
    );
  }

  // Check if an employee is a shift runner for a given shift on a given day
  String? _getShiftRunnerTypeForEmployee(DateTime day, int employeeId) {
    final employee = widget.employees.firstWhere(
      (e) => e.id == employeeId,
      orElse: () => widget.employees.first,
    );
    for (final shiftType in ShiftRunner.shiftOrder) {
      final runner = _getShiftRunner(day, shiftType);
      if (runner != null && runner.runnerName == employee.name) {
        return shiftType;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
              const CopyIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV):
              const PasteIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            CopyIntent: CallbackAction<CopyIntent>(
              onInvoke: (intent) {
                if (_selectedShift != null && widget.onCopyShift != null) {
                  widget.onCopyShift!(_selectedShift!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Shift copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
                return null;
              },
            ),
            PasteIntent: CallbackAction<PasteIntent>(
              onInvoke: (intent) {
                if (widget.onPasteTarget != null &&
                    _selectedTargetDay != null &&
                    _selectedTargetEmployeeId != null) {
                  if (widget.clipboardAvailable) {
                    widget.onPasteTarget!(
                      _selectedTargetDay!,
                      _selectedTargetEmployeeId!,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No shift copied to paste')),
                    );
                  }
                }
                return null;
              },
            ),
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
                        child: Icon(
                          Icons.sticky_note_2,
                          size: 14,
                          color: Colors.amber.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

        return Column(
          children: [
            Row(
              children: [
                SizedBox(width: employeeColumnWidth, height: 40),
                Expanded(child: dayHeaders),
              ],
            ),
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
                                final weeklyHours = _calculateWeeklyHours(
                                  e.id!,
                                  days,
                                );
                                final maxHours = _getMaxHoursForEmployee(e);
                                final isOverLimit = weeklyHours > maxHours;

                                return SizedBox(
                                  height: 60,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            e.name,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${weeklyHours}h',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isOverLimit
                                                      ? Colors.red
                                                      : Colors.grey,
                                                  fontWeight: isOverLimit
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                              if (isOverLimit) ...[
                                                const SizedBox(width: 4),
                                                Tooltip(
                                                  message:
                                                      'Over max ${maxHours}h/week limit',
                                                  child: const Icon(
                                                    Icons.warning,
                                                    size: 14,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ],
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
                                  final shiftsForCell = widget.shifts
                                      .where(
                                        (s) =>
                                            s.employeeId == e.id &&
                                            s.start.year == d.year &&
                                            s.start.month == d.month &&
                                            s.start.day == d.day,
                                      )
                                      .toList();

                                  final has = shiftsForCell.isNotEmpty;

                                  if (!has) {
                                    final isTargetSelected =
                                        _selectedTargetDay != null &&
                                        _selectedTargetDay == d &&
                                        _selectedTargetEmployeeId == e.id;
                                    final clipboardAvailable =
                                        widget.clipboardAvailable;
                                    final isDragHover =
                                        _dragHoverDay != null &&
                                        _dragHoverDay == d &&
                                        _dragHoverEmployeeId == e.id;

                                    return DragTarget<ShiftPlaceholder>(
                                      onWillAcceptWithDetails: (details) {
                                        // Accept drops from other cells (not the same cell)
                                        final draggedShift = details.data;
                                        final isSameCell =
                                            draggedShift.employeeId == e.id &&
                                            draggedShift.start.year == d.year &&
                                            draggedShift.start.month ==
                                                d.month &&
                                            draggedShift.start.day == d.day;
                                        return !isSameCell;
                                      },
                                      onAcceptWithDetails: (details) {
                                        setState(() {
                                          _dragHoverDay = null;
                                          _dragHoverEmployeeId = null;
                                        });
                                        if (widget.onMoveShift != null) {
                                          widget.onMoveShift!(
                                            details.data,
                                            d,
                                            e.id!,
                                          );
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
                                            if (widget.clipboardAvailable &&
                                                widget.onPasteTarget != null) {
                                              // Paste if clipboard has data
                                              widget.onPasteTarget!(d, e.id!);
                                            } else {
                                              // Otherwise just select the cell
                                              setState(() {
                                                _selectedTargetDay = d;
                                                _selectedTargetEmployeeId =
                                                    e.id;
                                                _selectedShift = null;
                                              });
                                            }
                                          },
                                          onDoubleTap: () async {
                                            // Create a new shift on double-click with availability check
                                            await _showAddShiftDialogWithAvailability(
                                              context,
                                              d,
                                              e.id!,
                                            );
                                          },
                                          onLongPress: () {
                                            if (widget.clipboardAvailable &&
                                                widget.onPasteTarget != null) {
                                              widget.onPasteTarget!(d, e.id!);
                                            } else {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'No shift copied to paste',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          onSecondaryTapDown: (details) {
                                            _showEmptyCellContextMenu(
                                              context,
                                              d,
                                              e.id!,
                                              position: details.globalPosition,
                                            );
                                          },
                                          child: FutureBuilder<Map<String, dynamic>>(
                                            future: _checkAvailability(
                                              e.id!,
                                              d,
                                            ),
                                            builder: (context, snapshot) {
                                              bool showDash = false;
                                              if (snapshot.hasData) {
                                                final type =
                                                    snapshot.data!['type']
                                                        as String;
                                                final available =
                                                    snapshot.data!['available']
                                                        as bool;
                                                if (type == 'time-off' ||
                                                    !available) {
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
                                                        : Theme.of(
                                                            context,
                                                          ).dividerColor,
                                                    width: isDragHover
                                                        ? 3
                                                        : (isTargetSelected
                                                              ? 2.5
                                                              : 1),
                                                  ),
                                                  color: isDragHover
                                                      ? Colors.green.withAlpha(
                                                          30,
                                                        )
                                                      : isTargetSelected
                                                      ? Colors.blue.withAlpha(
                                                          13,
                                                        )
                                                      : null,
                                                ),
                                                child: isDragHover
                                                    ? const Icon(
                                                        Icons
                                                            .add_circle_outline,
                                                        color: Colors.green,
                                                        size: 24,
                                                      )
                                                    : clipboardAvailable &&
                                                          isTargetSelected
                                                    ? Icon(
                                                        Icons.content_paste,
                                                        color: Colors.blue
                                                            .withAlpha(128),
                                                        size: 20,
                                                      )
                                                    : showDash
                                                    ? const Text(
                                                        '-',
                                                        style: TextStyle(
                                                          fontSize: 24,
                                                          color: Colors.grey,
                                                        ),
                                                      )
                                                    : null,
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    );
                                  }

                                  final s = shiftsForCell.first;
                                  final startLabel = _formatTimeOfDay(
                                    TimeOfDay(
                                      hour: s.start.hour,
                                      minute: s.start.minute,
                                    ),
                                    forCell: true,
                                    dayOfWeek: d.weekday,
                                  );
                                  final endLabel = _formatTimeOfDay(
                                    TimeOfDay(
                                      hour: s.end.hour,
                                      minute: s.end.minute,
                                    ),
                                    forCell: true,
                                    dayOfWeek: d.weekday,
                                  );
                                  final isShiftSelected =
                                      _selectedShift != null &&
                                      _selectedShift!.employeeId ==
                                          s.employeeId &&
                                      _selectedShift!.start == s.start;

                                  // Check if this is a time-off label (not editable/draggable)
                                  final isTimeOffLabel = _isLabelOnly(s.text);

                                  // Build the shift cell widget
                                  Widget shiftCell = GestureDetector(
                                    onTap: isTimeOffLabel
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedShift = s;
                                              _selectedTargetDay = null;
                                              _selectedTargetEmployeeId = null;
                                            });
                                          },
                                    onDoubleTap: isTimeOffLabel
                                        ? null
                                        : () async {
                                            final res = await _showEditDialog(
                                              context,
                                              d,
                                              s,
                                            );
                                            if (res != null &&
                                                widget.onUpdateShift != null) {
                                              // Handle "OFF" button
                                              if (res['off'] == true) {
                                                widget.onUpdateShift!(
                                                  s,
                                                  s.start,
                                                  s.start,
                                                  shiftNotes: 'OFF',
                                                );
                                                return;
                                              }
                                              widget.onUpdateShift!(
                                                s,
                                                res['start'] as DateTime,
                                                res['end'] as DateTime,
                                                shiftNotes: res['notes'] as String?,
                                              );
                                            }
                                          },
                                    onLongPress: isTimeOffLabel
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedShift = s;
                                              _selectedTargetDay = null;
                                              _selectedTargetEmployeeId = null;
                                            });
                                            _showShiftContextMenu(context, s);
                                          },
                                    onSecondaryTapDown: isTimeOffLabel
                                        ? null
                                        : (details) {
                                            setState(() {
                                              _selectedShift = s;
                                              _selectedTargetDay = null;
                                              _selectedTargetEmployeeId = null;
                                            });
                                            _showShiftContextMenu(
                                              context,
                                              s,
                                              position: details.globalPosition,
                                            );
                                          },
                                    child: Container(
                                      height: 60,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: Builder(
                                        builder: (context) {
                                          // Check if this employee is a shift runner for this day
                                          final runnerShiftType =
                                              _getShiftRunnerTypeForEmployee(
                                                d,
                                                e.id!,
                                              );
                                          final runnerColor =
                                              runnerShiftType != null
                                              ? _getShiftTypeColor(
                                                  runnerShiftType,
                                                )
                                              : null;
                                          final isDark = Theme.of(context).brightness == Brightness.dark;

                                          return Container(
                                            decoration: BoxDecoration(
                                              border: isShiftSelected && !isTimeOffLabel
                                                  ? Border.all(color: Colors.blue, width: 2)
                                                  : runnerColor != null
                                                      ? Border.all(color: runnerColor, width: 1.5)
                                                      : null,
                                              color: isShiftSelected && !isTimeOffLabel
                                                  ? Colors.blue.withAlpha(38)
                                                  : runnerColor?.withOpacity(0.15),
                                            ),
                                            child: Center(
                                              child: Text(
                                                _shouldShowAsLabel(s)
                                                    ? _labelText(s.text)
                                                    : '$startLabel - $endLabel',
                                                style: TextStyle(
                                                  fontWeight:
                                                      isShiftSelected && !isTimeOffLabel
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isDark
                                                      ? Theme.of(context).colorScheme.onSurface
                                                      : Theme.of(context).colorScheme.onSurface,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );

                                  // Only wrap in Draggable if not a time-off label
                                  if (isTimeOffLabel) {
                                    return shiftCell;
                                  }

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
                                          color: context.appColors.selectionBackground,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.primary,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$startLabel - $endLabel',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
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
                                          color: context.appColors.borderLight,
                                          width: 1,
                                          style: BorderStyle.solid,
                                        ),
                                        color: context.appColors.surfaceVariant,
                                      ),
                                      child: Text(
                                        'Moving...',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: context.appColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    child: shiftCell,
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
    final sunday = widget.date.subtract(
      Duration(days: widget.date.weekday % 7),
    );
    return List.generate(
      7,
      (i) => DateTime(sunday.year, sunday.month, sunday.day + i),
    );
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

  /// Find the index in _allowedTimes() for a time string like "08:00"
  int _findTimeIndex(List<TimeOfDay> times, String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    for (int i = 0; i < times.length; i++) {
      if (times[i].hour == hour && times[i].minute == minute) {
        return i;
      }
    }
    // Return a reasonable default if not found
    return 0;
  }

  void _showShiftContextMenu(
    BuildContext context,
    ShiftPlaceholder shift, {
    Offset? position,
  }) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null
          ? RelativeRect.fromLTRB(
              position.dx,
              position.dy,
              position.dx,
              position.dy,
            )
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
        const SnackBar(
          content: Text('Shift copied'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (result == 'delete') {
      if (widget.onUpdateShift != null) {
        widget.onUpdateShift!(shift, shift.start, shift.start);
      }
    }
  }

  void _showEmptyCellContextMenu(
    BuildContext context,
    DateTime day,
    int employeeId, {
    Offset? position,
  }) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null
          ? RelativeRect.fromLTRB(
              position.dx,
              position.dy,
              position.dx,
              position.dy,
            )
          : RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [const PopupMenuItem(value: 'off', child: Text('Mark as Off'))],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'off' && widget.onUpdateShift != null) {
      // Create an OFF shift that spans from 4:00 AM to 3:59 AM next day
      final offShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 4, 0),
        end: DateTime(day.year, day.month, day.day, 3, 59).add(const Duration(days: 1)),
        text: 'OFF',
      );
      // Use a temporary placeholder to signal this is a new shift
      final tempShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 4, 0),
        end: DateTime(day.year, day.month, day.day, 4, 0),
        text: 'OFF',
      );
      widget.onUpdateShift!(tempShift, offShift.start, offShift.end);
    }
  }

  DateTime _timeOfDayToDateTime(DateTime day, TimeOfDay tod) {
    // Times with hour 0 or 1 are considered next-day times
    if (tod.hour == 0 || tod.hour == 1) {
      return DateTime(
        day.year,
        day.month,
        day.day,
        tod.hour,
        tod.minute,
      ).add(const Duration(days: 1));
    }
    return DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
  }

  String _formatTimeOfDay(TimeOfDay t, {bool forCell = false, int? dayOfWeek}) {
    // Special cases for cell display
    if (forCell) {
      final storeHours = StoreHours.cached;
      if (storeHours.isOpenTime(t.hour, t.minute, dayOfWeek: dayOfWeek))
        return 'Op';
      if (storeHours.isCloseTime(t.hour, t.minute, dayOfWeek: dayOfWeek))
        return 'CL';
      // Show just hour, or hour:minute if not on the hour
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      if (t.minute == 0) return '$h';
      return '$h:${t.minute.toString().padLeft(2, '0')}';
    }
    // Full format for dropdowns/dialogs
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

  void _showNoteDialog(
    BuildContext context,
    DateTime day,
    String? existingNote,
  ) {
    final controller = TextEditingController(text: existingNote ?? '');
    final dateStr =
        '${_dayOfWeekAbbr(day)}, ${day.month}/${day.day}/${day.year}';

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

  Future<Map<String, dynamic>> _checkAvailability(
    int employeeId,
    DateTime date,
  ) async {
    final cacheKey = '$employeeId-${date.year}-${date.month}-${date.day}';
    if (_availabilityCache.containsKey(cacheKey)) {
      return _availabilityCache[cacheKey]!;
    }

    // Priority 1: Check time-off first
    final timeOffList = await _timeOffDao.getAllTimeOff();
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeOffEntry = timeOffList.cast<TimeOffEntry?>().firstWhere(
      (t) =>
          t != null &&
          t.employeeId == employeeId &&
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}' ==
              dateStr,
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
    final result = await _availabilityDao.isAvailable(
      employeeId,
      date,
      null,
      null,
    );
    _availabilityCache[cacheKey] = result;
    return result;
  }

  Future<void> _showAddShiftDialogWithAvailability(
    BuildContext context,
    DateTime day,
    int employeeId,
  ) async {
    // Get employee job code
    final employee = widget.employees.firstWhere((e) => e.id == employeeId);

    // Load shared templates (not job-code specific)
    await _shiftTemplateDao.insertDefaultTemplatesIfMissing();
    final templates = await _shiftTemplateDao.getAllTemplates();

    // Check availability
    final availability = await _checkAvailability(employeeId, day);
    final isAvailable = availability['available'] as bool;
    final reason = availability['reason'] as String;
    final type = availability['type'] as String;
    final isAllDay = availability['isAllDay'] as bool? ?? true;
    final timeOffEntry = availability['timeOffEntry'] as TimeOffEntry?;

    Color bannerColor = Colors.green;
    if (type == 'time-off') {
      // Red for all-day time off, orange (warning) for partial day
      bannerColor = isAllDay ? Colors.red : Colors.orange;
    } else if (!isAvailable) {
      bannerColor = Colors.orange;
    }

    if (!context.mounted) return;

    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _buildTemplateDialog(
        day: day,
        employeeId: employeeId,
        templates: templates,
        bannerColor: bannerColor,
        reason: reason,
        type: type,
        isAvailable: isAvailable,
        timeOffEntry: timeOffEntry,
      ),
    );

    if (res != null && widget.onUpdateShift != null) {
      // Handle "OFF" button
      if (res['off'] == true) {
        final tempShift = ShiftPlaceholder(
          employeeId: employeeId,
          start: DateTime(day.year, day.month, day.day, 0, 0),
          end: DateTime(day.year, day.month, day.day, 0, 0),
          text: 'OFF',
        );
        widget.onUpdateShift!(tempShift, tempShift.start, tempShift.end, shiftNotes: 'OFF');
        return;
      }

      // Save shift runner if one was selected
      final runnerShift = res['runnerShift'] as String?;
      if (runnerShift != null) {
        await _shiftRunnerDao.upsert(
          ShiftRunner(
            date: day,
            shiftType: runnerShift,
            runnerName: employee.name,
          ),
        );
        // Trigger runner table refresh via callback
        _loadShiftRunnerData();
        widget.onShiftRunnerChanged?.call();
      }

      final tempShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 0, 0),
        end: DateTime(day.year, day.month, day.day, 0, 0),
        text: 'Shift',
      );
      widget.onUpdateShift!(tempShift, res['start'] as DateTime, res['end'] as DateTime);
    }
  }

  Future<Map<String, dynamic>?> _showEditDialog(
    BuildContext context,
    DateTime day,
    ShiftPlaceholder shift,
  ) async {
    final times = _allowedTimes();
    int startIdx = 0;
    int endIdx = 0;
    for (int i = 0; i < times.length; i++) {
      final t = times[i];
      final dt = _timeOfDayToDateTime(day, t);
      if (dt.hour == shift.start.hour &&
          dt.minute == shift.start.minute &&
          dt.day == shift.start.day)
        startIdx = i;
      if (dt.hour == shift.end.hour &&
          dt.minute == shift.end.minute &&
          dt.day == shift.end.day)
        endIdx = i;
    }

    int selStart = startIdx;
    int selEnd = endIdx;
    String? selectedRunnerShift;
    final notesController = TextEditingController(text: shift.notes ?? '');

    // Get the employee for this shift
    final employee = widget.employees.firstWhere(
      (e) => e.id == shift.employeeId,
      orElse: () => widget.employees.first,
    );

    // Check for time off on this day
    final availability = await _checkAvailability(shift.employeeId, day);
    final timeOffEntry = availability['timeOffEntry'] as TimeOffEntry?;

    // Helper to check if the selected shift times overlap with time off
    bool shiftOverlapsTimeOff(int startIndex, int endIndex) {
      if (timeOffEntry == null) return false;
      final shiftStart = times[startIndex];
      final shiftEnd = times[endIndex];
      final shiftStartDt = _timeOfDayToDateTime(day, shiftStart);
      final shiftEndDt = _timeOfDayToDateTime(day, shiftEnd);
      return timeOffEntry.overlapsWithShift(shiftStartDt, shiftEndDt);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Shift Time'),
              content: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time selection
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<int>(
                          value: selStart,
                          isExpanded: true,
                          items: List.generate(
                            times.length,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(_formatTimeOfDay(times[i])),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => selStart = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButton<int>(
                          value: selEnd,
                          isExpanded: true,
                          items: List.generate(
                            times.length,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(_formatTimeOfDay(times[i])),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => selEnd = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Shift Notes
                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'Shift Notes',
                            hintText: 'Add notes...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Shift Runner buttons
                  Container(
                    width: 100,
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Shift Runner:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...ShiftRunner.shiftOrder.map((shiftType) {
                          final isSelected = selectedRunnerShift == shiftType;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (selectedRunnerShift == shiftType) {
                                    selectedRunnerShift = null;
                                  } else {
                                    selectedRunnerShift = shiftType;
                                    // Update time selection to match shift type defaults
                                    final shiftTypeObj = _shiftTypes
                                        .cast<ShiftType?>()
                                        .firstWhere(
                                          (st) => st?.key == shiftType,
                                          orElse: () => null,
                                        );
                                    if (shiftTypeObj != null) {
                                      selStart = _findTimeIndex(
                                        times,
                                        shiftTypeObj.defaultShiftStart,
                                      );
                                      selEnd = _findTimeIndex(
                                        times,
                                        shiftTypeObj.defaultShiftEnd,
                                      );
                                    }
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _getShiftTypeColor(
                                          shiftType,
                                        ).withOpacity(0.3)
                                      : _getShiftTypeColor(
                                          shiftType,
                                        ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _getShiftTypeColor(shiftType),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  ShiftRunner.getLabelForType(shiftType),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _getShiftTypeColor(shiftType),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, {'off': true}),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('OFF'),
                ),
                TextButton(
                  onPressed: () async {
                    // Check if shift overlaps with time off and confirm
                    if (shiftOverlapsTimeOff(selStart, selEnd)) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Scheduling Conflict'),
                          content: const Text(
                            'The employee is not available for this time. Are you sure?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('No'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Yes'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }

                    // Save shift runner if selected
                    if (selectedRunnerShift != null) {
                      await _shiftRunnerDao.upsert(
                        ShiftRunner(
                          date: day,
                          shiftType: selectedRunnerShift!,
                          runnerName: employee.name,
                        ),
                      );
                      _loadShiftRunnerData(); // Reload to update UI
                    }

                    final newStart = _timeOfDayToDateTime(day, times[selStart]);
                    final newEnd = _timeOfDayToDateTime(day, times[selEnd]);
                    final notes = notesController.text.trim();
                    Navigator.pop(context, {
                      'start': newStart,
                      'end': newEnd,
                      'notes': notes.isEmpty ? null : notes,
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

    notesController.dispose();
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
  final List<JobCodeSettings> jobCodeSettings;
  final void Function(
    ShiftPlaceholder oldShift,
    DateTime newStart,
    DateTime newEnd, {
    String? shiftNotes,
  })?
  onUpdateShift;
  final void Function(ShiftPlaceholder shift)? onCopyShift;
  final void Function(DateTime day, int employeeId)? onPasteTarget;
  final void Function(
    ShiftPlaceholder shift,
    DateTime newDay,
    int newEmployeeId,
  )?
  onMoveShift;
  final void Function(DateTime day, String note)? onSaveNote;
  final void Function(DateTime day)? onDeleteNote;
  final VoidCallback? onShiftRunnerChanged;
  final bool clipboardAvailable;
  final int shiftRunnerRefreshKey;

  const MonthlyScheduleView({
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
    this.onShiftRunnerChanged,
    this.clipboardAvailable = false,
    this.shiftRunnerRefreshKey = 0,
  });

  @override
  State<MonthlyScheduleView> createState() => _MonthlyScheduleViewState();
}

class _MonthlyScheduleViewState extends State<MonthlyScheduleView> {
  ShiftPlaceholder? _selectedShift;
  // Drag & drop state
  DateTime? _dragHoverDay;
  int? _dragHoverEmployeeId;
  late final ScrollController _horizontalScrollController;
  final ShiftTemplateDao _shiftTemplateDao = ShiftTemplateDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final EmployeeAvailabilityDao _availabilityDao = EmployeeAvailabilityDao();
  final ShiftRunnerDao _shiftRunnerDao = ShiftRunnerDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final ShiftDao _shiftDao = ShiftDao();
  final Map<String, Map<String, dynamic>> _availabilityCache = {};
  List<ShiftType> _shiftTypes = [];
  List<ShiftRunner> _shiftRunners = [];
  bool _isRunnerPanelExpanded = false; // Start collapsed

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _loadShiftRunnerData();
    print(
      'MonthlyScheduleView initState: ${widget.shifts.length} shifts loaded',
    );
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MonthlyScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date.month != widget.date.month ||
        oldWidget.date.year != widget.date.year ||
        oldWidget.shiftRunnerRefreshKey != widget.shiftRunnerRefreshKey) {
      _loadShiftRunnerData();
    }
    if (oldWidget.shifts.length != widget.shifts.length) {
      print(
        'MonthlyScheduleView didUpdateWidget: shifts changed from ${oldWidget.shifts.length} to ${widget.shifts.length}',
      );
      for (var shift in widget.shifts) {
        print(
          '  Shift: employee=${shift.employeeId}, date=${shift.start.year}-${shift.start.month}-${shift.start.day} ${shift.start.hour}:${shift.start.minute}, text=${shift.text}',
        );
      }
    }
  }

  Future<void> _loadShiftRunnerData() async {
    final shiftTypes = await _shiftTypeDao.getAll();
    ShiftRunner.setShiftTypes(shiftTypes);
    // Load runners for the full calendar view (including visible days from adjacent months)
    final firstDayOfMonth = DateTime(widget.date.year, widget.date.month, 1);
    final lastDayOfMonth = DateTime(widget.date.year, widget.date.month + 1, 0);
    
    // Find the Sunday before or on the first day (start of first visible week)
    final calendarStart = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday % 7),
    );
    
    // Find the Saturday after or on the last day (end of last visible week)
    final daysUntilSaturday = (6 - lastDayOfMonth.weekday % 7) % 7;
    final calendarEnd = lastDayOfMonth.add(Duration(days: daysUntilSaturday));
    
    final runners = await _shiftRunnerDao.getForDateRange(calendarStart, calendarEnd);
    if (mounted) {
      setState(() {
        _shiftTypes = shiftTypes;
        _shiftRunners = runners;
      });
    }
  }

  Future<List<Employee>> _getAvailableEmployeesForRunner(
    DateTime day,
    String shiftType,
  ) async {
    final employeeDao = EmployeeDao();
    final allEmployees = await employeeDao.getEmployees();
    final availableList = <Employee>[];
    final timeOffList = await _timeOffDao.getAllTimeOff();
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    // Get shift type info for availability check
    final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
      (st) => st?.key == shiftType,
      orElse: () => null,
    );
    final startTime = shiftTypeObj?.defaultShiftStart ?? '09:00';
    final endTime = shiftTypeObj?.defaultShiftEnd ?? '17:00';

    // Get all runners for this day to filter out people already running a different shift
    final runnersForDay = _shiftRunners.where(
      (r) =>
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day,
    ).toList();

    for (final employee in allEmployees) {
      // Check if this employee is already running a different shift on this day
      final alreadyRunning = runnersForDay.any(
        (r) => r.runnerName == employee.name && r.shiftType != shiftType,
      );
      if (alreadyRunning) continue;

      // Check time-off
      final hasTimeOff = timeOffList.any(
        (t) =>
            t.employeeId == employee.id &&
            '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}' ==
                dateStr &&
            t.isAllDay,
      );
      if (hasTimeOff) continue;

      // Check availability pattern
      final availability = await _availabilityDao.isAvailable(
        employee.id!,
        day,
        startTime,
        endTime,
      );
      if (availability['available'] == true) {
        availableList.add(employee);
      }
    }

    return availableList;
  }

  Future<void> _editMonthlyRunner(DateTime day, String shiftType, String? currentRunner) async {
    // Get shift type info
    final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
      (st) => st?.key == shiftType,
      orElse: () => null,
    );
    final startTime = shiftTypeObj?.defaultShiftStart ?? '09:00';
    final endTime = shiftTypeObj?.defaultShiftEnd ?? '17:00';

    // Load available employees for this shift
    final availableEmployees = await _getAvailableEmployeesForRunner(day, shiftType);

    if (!mounted) return;

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return _MonthlyRunnerSearchDialog(
          day: day,
          shiftType: shiftType,
          currentName: currentRunner,
          availableEmployees: availableEmployees,
          shiftColor: _getShiftTypeColor(shiftType),
          startTime: startTime,
          endTime: endTime,
        );
      },
    );

    if (result != null) {
      if (result.isEmpty) {
        // Clear the runner
        await _shiftRunnerDao.delete(day, shiftType);
      } else {
        // Find the employee by name
        final employee = widget.employees.cast<Employee?>().firstWhere(
          (e) => e?.name == result,
          orElse: () => null,
        );
        
        // Create shift with default times if employee doesn't have a shift for this day
        if (employee != null) {
          final existingShifts = await _shiftDao.getByEmployeeAndDateRange(
            employee.id!,
            day,
            day.add(const Duration(days: 1)),
          );
          
          if (existingShifts.isEmpty) {
            // Parse the default shift times
            final startParts = startTime.split(':');
            final endParts = endTime.split(':');
            final shiftStart = DateTime(
              day.year, day.month, day.day,
              int.parse(startParts[0]), int.parse(startParts[1]),
            );
            var shiftEnd = DateTime(
              day.year, day.month, day.day,
              int.parse(endParts[0]), int.parse(endParts[1]),
            );
            // Handle overnight shifts (end time before start time)
            if (shiftEnd.isBefore(shiftStart) || shiftEnd.isAtSameMomentAs(shiftStart)) {
              shiftEnd = shiftEnd.add(const Duration(days: 1));
            }
            
            await _shiftDao.insert(Shift(
              employeeId: employee.id!,
              startTime: shiftStart,
              endTime: shiftEnd,
            ));
          }
        }
        
        // Set the runner
        await _shiftRunnerDao.upsert(
          ShiftRunner(
            date: day,
            shiftType: shiftType,
            runnerName: result,
          ),
        );
      }
      await _loadShiftRunnerData();
      widget.onShiftRunnerChanged?.call();
    }
  }

  Color _getShiftTypeColor(String shiftType) {
    final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
      (st) => st?.key == shiftType,
      orElse: () => null,
    );
    final hex =
        shiftTypeObj?.colorHex ??
        ShiftType.defaultShiftTypes
            .firstWhere(
              (st) => st.key == shiftType,
              orElse: () => ShiftType.defaultShiftTypes.first,
            )
            .colorHex;
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  // Get shift runner for a given day and shift type
  ShiftRunner? _getShiftRunner(DateTime day, String shiftType) {
    return _shiftRunners.cast<ShiftRunner?>().firstWhere(
      (r) =>
          r != null &&
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day &&
          r.shiftType == shiftType,
      orElse: () => null,
    );
  }

  // Check if an employee is a shift runner for any shift on a given day
  String? _getShiftRunnerTypeForEmployee(DateTime day, int employeeId) {
    final employee = widget.employees.firstWhere(
      (e) => e.id == employeeId,
      orElse: () => widget.employees.first,
    );
    for (final shiftType in ShiftRunner.shiftOrder) {
      final runner = _getShiftRunner(day, shiftType);
      if (runner != null && runner.runnerName == employee.name) {
        return shiftType;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _checkAvailability(
    int employeeId,
    DateTime date,
  ) async {
    final cacheKey = '$employeeId-${date.year}-${date.month}-${date.day}';
    if (_availabilityCache.containsKey(cacheKey)) {
      return _availabilityCache[cacheKey]!;
    }

    // Priority 1: Check time-off first
    final timeOffList = await _timeOffDao.getAllTimeOff();
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeOffEntry = timeOffList.cast<TimeOffEntry?>().firstWhere(
      (t) =>
          t != null &&
          t.employeeId == employeeId &&
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}' ==
              dateStr,
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
    final result = await _availabilityDao.isAvailable(
      employeeId,
      date,
      null,
      null,
    );
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

  void _showEmptyCellContextMenu(
    BuildContext context,
    DateTime day,
    int employeeId,
    Offset position,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'add', child: Text('Add Shift')),
        const PopupMenuItem(value: 'off', child: Text('Mark as Off')),
        if (widget.clipboardAvailable)
          const PopupMenuItem(value: 'paste', child: Text('Paste Shift')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'add') {
      _showEditDialog(
        context,
        ShiftPlaceholder(
          employeeId: employeeId,
          start: DateTime(day.year, day.month, day.day, 9, 0),
          end: DateTime(day.year, day.month, day.day, 17, 0),
          text: '',
        ),
      );
    } else if (result == 'off' && widget.onUpdateShift != null) {
      // Create an OFF shift that spans from 4:00 AM to 3:59 AM next day
      final offShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 4, 0),
        end: DateTime(day.year, day.month, day.day, 3, 59).add(const Duration(days: 1)),
        text: 'OFF',
      );
      // Use a temporary placeholder to signal this is a new shift
      final tempShift = ShiftPlaceholder(
        employeeId: employeeId,
        start: DateTime(day.year, day.month, day.day, 4, 0),
        end: DateTime(day.year, day.month, day.day, 4, 0),
        text: 'OFF',
      );
      widget.onUpdateShift!(tempShift, offShift.start, offShift.end);
    } else if (result == 'paste') {
      widget.onPasteTarget?.call(day, employeeId);
    }
  }

  List<List<DateTime?>> _buildCalendarWeeks() {
    // Get first and last day of month
    final firstDayOfMonth = DateTime(widget.date.year, widget.date.month, 1);
    final lastDayOfMonth = DateTime(widget.date.year, widget.date.month + 1, 0);

    // Find the Sunday before or on the first day
    final startDate = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday % 7),
    );

    // Build weeks (5 or 6 weeks to cover the month)
    final weeks = <List<DateTime?>>[];
    DateTime currentDate = startDate;

    while (currentDate.isBefore(lastDayOfMonth) ||
        currentDate.month == lastDayOfMonth.month) {
      final week = <DateTime?>[];
      for (int i = 0; i < 7; i++) {
        week.add(currentDate);
        currentDate = currentDate.add(const Duration(days: 1));
      }
      weeks.add(week);

      // Stop after we've passed the last day of the month
      if (weeks.length >= 6 ||
          (currentDate.month != widget.date.month && weeks.length >= 5)) {
        break;
      }
    }

    return weeks;
  }

  String _formatTimeOfDay(TimeOfDay t, {bool forCell = false, int? dayOfWeek}) {
    // Special cases for cell display
    if (forCell) {
      final storeHours = StoreHours.cached;
      if (storeHours.isOpenTime(t.hour, t.minute, dayOfWeek: dayOfWeek))
        return 'Op';
      if (storeHours.isCloseTime(t.hour, t.minute, dayOfWeek: dayOfWeek))
        return 'CL';
      // Show just hour, or hour:minute if not on the hour
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      if (t.minute == 0) return '$h';
      return '$h:${t.minute.toString().padLeft(2, '0')}';
    }
    // Full format for dropdowns/dialogs
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$mm $suffix';
  }

  void _showShiftContextMenu(
    BuildContext context,
    ShiftPlaceholder shift,
    Offset? position,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: position != null
          ? RelativeRect.fromLTRB(
              position.dx,
              position.dy,
              position.dx,
              position.dy,
            )
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
        const SnackBar(
          content: Text('Shift copied'),
          duration: Duration(seconds: 1),
        ),
      );
    } else if (result == 'delete') {
      if (widget.onUpdateShift != null) {
        widget.onUpdateShift!(shift, shift.start, shift.start);
      }
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    ShiftPlaceholder shift,
  ) async {
    // Find employee for this shift
    final employee = widget.employees.firstWhere(
      (e) => e.id == shift.employeeId,
      orElse: () => widget.employees.first,
    );
    final day = DateTime(shift.start.year, shift.start.month, shift.start.day);

    // Load shared templates (not job-code specific)
    await _shiftTemplateDao.insertDefaultTemplatesIfMissing();
    final templates = await _shiftTemplateDao.getAllTemplates();

    // Check availability
    final availability = await _checkAvailability(shift.employeeId, day);
    final isAvailable = availability['available'] as bool;
    final reason = availability['reason'] as String;
    final type = availability['type'] as String;
    final timeOffEntry = availability['timeOffEntry'] as TimeOffEntry?;

    Color bannerColor = Colors.green;
    if (type == 'time-off') {
      final isAllDay = availability['isAllDay'] as bool? ?? true;
      bannerColor = isAllDay ? Colors.red : Colors.orange;
    } else if (!isAvailable) {
      bannerColor = Colors.orange;
    }

    if (!context.mounted) return;

    final times = _allowedTimes();
    int selStart = times.indexWhere(
      (t) => t.hour == shift.start.hour && t.minute == shift.start.minute,
    );
    int selEnd = times.indexWhere(
      (t) => t.hour == shift.end.hour && t.minute == shift.end.minute,
    );
    if (selStart == -1) selStart = 0;
    if (selEnd == -1) selEnd = times.length - 1;

    ShiftTemplate? selectedTemplate;
    String? selectedRunnerShift;
    final notesController = TextEditingController(text: shift.notes ?? '');

    // Helper to check if the selected shift times overlap with time off
    bool shiftOverlapsTimeOff(int startIndex, int endIndex) {
      if (timeOffEntry == null) return false;
      final shiftStart = times[startIndex];
      final shiftEnd = times[endIndex];
      final shiftStartDt = _timeOfDayToDateTime(day, shiftStart);
      final shiftEndDt = _timeOfDayToDateTime(day, shiftEnd);
      return timeOffEntry.overlapsWithShift(shiftStartDt, shiftEndDt);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                          const Text(
                            'Templates:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...templates.map((template) {
                            final startParts = template.startTime.split(':');
                            final startHour = int.parse(startParts[0]);
                            final startMin = int.parse(startParts[1]);
                            final endParts = template.endTime.split(':');
                            final endHour = int.parse(endParts[0]);
                            final endMin = int.parse(endParts[1]);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: selectedTemplate == template
                                      ? Colors.blue.withOpacity(0.1)
                                      : null,
                                  side: BorderSide(
                                    color: selectedTemplate == template
                                        ? Colors.blue
                                        : Colors.grey,
                                    width: selectedTemplate == template ? 2 : 1,
                                  ),
                                ),
                                onPressed: () {
                                  int startIdx = times.indexWhere(
                                    (t) =>
                                        t.hour == startHour &&
                                        t.minute == startMin,
                                  );
                                  if (startIdx == -1) startIdx = 0;

                                  int endIdx = times.indexWhere(
                                    (t) =>
                                        t.hour == endHour && t.minute == endMin,
                                  );
                                  if (endIdx == -1) endIdx = times.length - 1;

                                  setDialogState(() {
                                    selectedTemplate = template;
                                    selStart = startIdx;
                                    selEnd = endIdx;
                                  });
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      template.templateName,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${template.startTime}-${template.endTime}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
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
                                type == 'time-off'
                                    ? Icons.event_busy
                                    : (isAvailable
                                          ? Icons.check_circle
                                          : Icons.warning),
                                color: bannerColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    color: bannerColor.withOpacity(0.9),
                                    fontSize: 12,
                                  ),
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
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(_formatTimeOfDay(e.value)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setDialogState(() {
                              selStart = v!;
                              if (selStart >= selEnd)
                                selEnd = (selStart + 1).clamp(
                                  0,
                                  times.length - 1,
                                );
                              selectedTemplate = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<int>(
                          value: selEnd,
                          isExpanded: true,
                          items: times.asMap().entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(_formatTimeOfDay(e.value)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setDialogState(() {
                              selEnd = v!;
                              if (selEnd <= selStart)
                                selStart = (selEnd - 1).clamp(
                                  0,
                                  times.length - 1,
                                );
                              selectedTemplate = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // Shift Notes
                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'Shift Notes',
                            hintText: 'Add notes for this shift...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Shift Runner buttons
                  Container(
                    width: 100,
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Shift Runner:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...ShiftRunner.shiftOrder.map((shiftType) {
                          final isSelected = selectedRunnerShift == shiftType;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () {
                                setDialogState(() {
                                  if (selectedRunnerShift == shiftType) {
                                    selectedRunnerShift = null;
                                  } else {
                                    selectedRunnerShift = shiftType;
                                    // Update time selection to match shift type defaults
                                    final shiftTypeObj = _shiftTypes
                                        .cast<ShiftType?>()
                                        .firstWhere(
                                          (st) => st?.key == shiftType,
                                          orElse: () => null,
                                        );
                                    if (shiftTypeObj != null) {
                                      selStart = _findTimeIndex(
                                        times,
                                        shiftTypeObj.defaultShiftStart,
                                      );
                                      selEnd = _findTimeIndex(
                                        times,
                                        shiftTypeObj.defaultShiftEnd,
                                      );
                                    }
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _getShiftTypeColor(
                                          shiftType,
                                        ).withOpacity(0.3)
                                      : _getShiftTypeColor(
                                          shiftType,
                                        ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _getShiftTypeColor(shiftType),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  ShiftRunner.getLabelForType(shiftType),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _getShiftTypeColor(shiftType),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, {'off': true}),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('OFF'),
                ),
                TextButton(
                  onPressed: () async {
                    // Check if shift overlaps with time off and confirm
                    if (shiftOverlapsTimeOff(selStart, selEnd)) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Scheduling Conflict'),
                          content: const Text(
                            'The employee is not available for this time. Are you sure?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('No'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Yes'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }

                    // Save shift runner if selected
                    if (selectedRunnerShift != null) {
                      await _shiftRunnerDao.upsert(
                        ShiftRunner(
                          date: day,
                          shiftType: selectedRunnerShift!,
                          runnerName: employee.name,
                        ),
                      );
                      _loadShiftRunnerData(); // Reload to update UI
                    }

                    final newStart = _timeOfDayToDateTime(day, times[selStart]);
                    final newEnd = _timeOfDayToDateTime(day, times[selEnd]);
                    final notes = notesController.text.trim();
                    if (!newEnd.isAfter(newStart)) {
                      Navigator.pop(context, {
                        'start': newStart,
                        'end': newStart.add(const Duration(hours: 1)),
                        'notes': notes.isEmpty ? null : notes,
                      });
                    } else {
                      Navigator.pop(context, {
                        'start': newStart,
                        'end': newEnd,
                        'notes': notes.isEmpty ? null : notes,
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    notesController.dispose();

    if (result != null && widget.onUpdateShift != null) {
      // Handle "OFF" button
      if (result['off'] == true) {
        widget.onUpdateShift!(
          shift,
          shift.start,
          shift.start,
          shiftNotes: 'OFF',
        );
        return;
      }

      widget.onUpdateShift!(
        shift,
        result['start'] as DateTime,
        result['end'] as DateTime,
        shiftNotes: result['notes'] as String?,
      );
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

  /// Find the index in _allowedTimes() for a time string like "08:00"
  int _findTimeIndex(List<TimeOfDay> times, String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    for (int i = 0; i < times.length; i++) {
      if (times[i].hour == hour && times[i].minute == minute) {
        return i;
      }
    }
    // Return a reasonable default if not found
    return 0;
  }

  DateTime _timeOfDayToDateTime(DateTime day, TimeOfDay tod) {
    DateTime result = DateTime(
      day.year,
      day.month,
      day.day,
      tod.hour,
      tod.minute,
    );
    if (tod.hour == 0 || tod.hour == 1) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  Widget _buildShiftChip(
    ShiftPlaceholder shift,
    bool isSelected,
    String startLabel,
    String endLabel,
    BuildContext context,
  ) {
    // Check if this employee is a shift runner for this day
    final day = DateTime(shift.start.year, shift.start.month, shift.start.day);
    final runnerShiftType = _getShiftRunnerTypeForEmployee(
      day,
      shift.employeeId,
    );
    final runnerColor = runnerShiftType != null
        ? _getShiftTypeColor(runnerShiftType)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.withAlpha(128)
            : runnerColor?.withOpacity(0.25),
        border: isSelected
            ? Border.all(color: Colors.blue, width: 2)
            : runnerColor != null
                ? Border.all(color: runnerColor, width: 2)
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_shouldShowAsLabel(shift))
            Text(
              _labelText(shift.text),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
              textAlign: TextAlign.center,
            )
          else ...[
            Text(
              '$startLabel-$endLabel',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Don't show label if it's empty or just "Shift"
            if (shift.text.isNotEmpty && shift.text.toLowerCase() != 'shift')
              Text(
                shift.text,
                style: const TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyEmployeeCell({
    required BuildContext context,
    required DateTime day,
    required bool isCurrentMonth,
    required bool isWeekend,
    required Employee employee,
    required double cellWidth,
  }) {
    final shiftsForCell = widget.shifts.where((s) {
      final match =
          s.employeeId == employee.id &&
          s.start.year == day.year &&
          s.start.month == day.month &&
          s.start.day == day.day;
      return match;
    }).toList();

    final isDragHover =
        _dragHoverDay?.year == day.year &&
        _dragHoverDay?.month == day.month &&
        _dragHoverDay?.day == day.day &&
        _dragHoverEmployeeId == employee.id;

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
          onTap: shiftsForCell.isEmpty
              ? () {
                  // If clipboard has data, paste on single click
                  if (widget.clipboardAvailable &&
                      widget.onPasteTarget != null) {
                    widget.onPasteTarget!(day, employee.id!);
                  } else {
                    // Otherwise show add shift dialog
                    _showEditDialog(
                      context,
                      ShiftPlaceholder(
                        employeeId: employee.id!,
                        start: DateTime(day.year, day.month, day.day, 9, 0),
                        end: DateTime(day.year, day.month, day.day, 17, 0),
                        text: '',
                      ),
                    );
                  }
                }
              : null,
          onSecondaryTapDown: shiftsForCell.isEmpty
              ? (details) {
                  _showEmptyCellContextMenu(
                    context,
                    day,
                    employee.id!,
                    details.globalPosition,
                  );
                }
              : null,
          child: Container(
            width: cellWidth,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Theme.of(context).dividerColor),
              ),
              color: isDragHover
                  ? Colors.blue.withAlpha(50)
                  : !isCurrentMonth
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withAlpha(25)
                  : isWeekend
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withAlpha(51)
                  : null,
            ),
            child: shiftsForCell.isEmpty
                ? FutureBuilder<Map<String, dynamic>>(
                    future: _checkAvailability(employee.id!, day),
                    builder: (context, snapshot) {
                      bool showDash = false;
                      if (snapshot.hasData) {
                        final type = snapshot.data!['type'] as String;
                        final available = snapshot.data!['available'] as bool;
                        final isAllDay = snapshot.data!['isAllDay'] as bool? ?? true;
                        // Only show dash for all-day time-off or unavailability
                        // Partial day time-off should allow scheduling (with warning)
                        if (type == 'time-off' && isAllDay) {
                          showDash = true;
                        } else if (type != 'time-off' && !available) {
                          showDash = true;
                        }
                      }

                      if (isDragHover) {
                        return const Center(
                          child: Icon(Icons.add, color: Colors.blue, size: 20),
                        );
                      }
                      if (showDash) {
                        return const Center(
                          child: Text(
                            '-',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: shiftsForCell.map((shift) {
                      final isSelected = _selectedShift == shift;
                      final startLabel = _formatTimeOfDay(
                        TimeOfDay(
                          hour: shift.start.hour,
                          minute: shift.start.minute,
                        ),
                        forCell: true,
                        dayOfWeek: day.weekday,
                      );
                      final endLabel = _formatTimeOfDay(
                        TimeOfDay(
                          hour: shift.end.hour,
                          minute: shift.end.minute,
                        ),
                        forCell: true,
                        dayOfWeek: day.weekday,
                      );

                      // Check if this is a time-off label (not editable/draggable)
                      final isTimeOffLabel = _isLabelOnly(shift.text);

                      // Build the shift chip widget
                      Widget shiftChip = GestureDetector(
                        onTap: isTimeOffLabel
                            ? null
                            : () {
                                setState(() {
                                  _selectedShift = isSelected ? null : shift;
                                });
                              },
                        onDoubleTap: isTimeOffLabel
                            ? null
                            : () {
                                _showEditDialog(context, shift);
                              },
                        onSecondaryTapDown: isTimeOffLabel
                            ? null
                            : (details) {
                                setState(() {
                                  _selectedShift = shift;
                                });
                                _showShiftContextMenu(
                                  context,
                                  shift,
                                  details.globalPosition,
                                );
                              },
                        child: _buildShiftChip(
                          shift,
                          isSelected && !isTimeOffLabel,
                          startLabel,
                          endLabel,
                          context,
                        ),
                      );

                      // Only wrap in Draggable if not a time-off label
                      if (isTimeOffLabel) {
                        return SizedBox(
                          height: 50,
                          child: shiftChip,
                        );
                      }

                      return SizedBox(
                        height: 50,
                        child: Draggable<ShiftPlaceholder>(
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
                              '$startLabel-$endLabel',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _buildShiftChip(
                            shift,
                            isSelected,
                            startLabel,
                            endLabel,
                            context,
                          ),
                        ),
                        child: shiftChip,
                      ),
                    );
                    }).toList(),
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildCalendarWeeks();
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    Color colorFromHex(String hex) {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
      return Theme.of(context).colorScheme.primary;
    }

    Color jobCodeColorFor(String jobCode) {
      final settings = widget.jobCodeSettings
          .cast<JobCodeSettings?>()
          .firstWhere(
            (s) => s != null && s.code.toLowerCase() == jobCode.toLowerCase(),
            orElse: () => null,
          );
      final hex = settings?.colorHex;
      if (hex == null || hex.trim().isEmpty)
        return Theme.of(context).colorScheme.primary;
      return colorFromHex(hex);
    }

    // Build the runner panel for all weeks in the month (unified table)
    Widget buildRunnerPanel() {
      // Get all days visible in this month view, grouped by week
      final allWeeks = <List<DateTime>>[];
      for (final week in weeks) {
        final weekDays = <DateTime>[];
        for (final day in week) {
          if (day != null) {
            weekDays.add(day);
          }
        }
        if (weekDays.isNotEmpty) {
          allWeeks.add(weekDays);
        }
      }
      
      final shiftTypeKeys = _shiftTypes.map((t) => t.key).toList();

      String dayAbbr(int weekday) {
        const abbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        return abbrs[weekday % 7];
      }

      Color getShiftColor(String shiftType) {
        final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
          (t) => t?.key == shiftType,
          orElse: () => null,
        );
        final hex = shiftTypeObj?.colorHex ?? '#808080';
        final cleanHex = hex.replaceFirst('#', '');
        return Color(int.parse('FF$cleanHex', radix: 16));
      }

      String? getRunnerForCell(DateTime day, String shiftType) {
        final runner = _shiftRunners.cast<ShiftRunner?>().firstWhere(
          (r) =>
              r != null &&
              r.date.year == day.year &&
              r.date.month == day.month &&
              r.date.day == day.day &&
              r.shiftType == shiftType,
          orElse: () => null,
        );
        return runner?.runnerName;
      }

      Widget buildHeaderCell(String text) {
        return Container(
          padding: const EdgeInsets.all(4),
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        );
      }

      Widget buildShiftHeader(String shiftType) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          alignment: Alignment.center,
          color: getShiftColor(shiftType).withOpacity(0.2),
          child: Text(
            ShiftRunner.getLabelForType(shiftType),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: getShiftColor(shiftType),
            ),
          ),
        );
      }

      Widget buildDayCell(DateTime day) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayAbbr(day.weekday),
                style: const TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 9,
                ),
              ),
              Text(
                '${day.month}/${day.day}',
                style: const TextStyle(
                  fontWeight: FontWeight.w500, 
                  fontSize: 9,
                ),
              ),
            ],
          ),
        );
      }

      Future<void> showRunnerContextMenu(Offset position, DateTime day, String shiftType) async {
        final result = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
          items: [
            const PopupMenuItem<String>(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.clear, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Clear Runner', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        );

        if (result == 'clear') {
          await _shiftRunnerDao.delete(day, shiftType);
          await _loadShiftRunnerData();
          widget.onShiftRunnerChanged?.call();
        }
      }

      Widget buildRunnerCell(DateTime day, String shiftType, String? runner) {
        final hasRunner = runner != null && runner.isNotEmpty;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return GestureDetector(
          onSecondaryTapDown: hasRunner
              ? (details) => showRunnerContextMenu(details.globalPosition, day, shiftType)
              : null,
          child: InkWell(
            onTap: () => _editMonthlyRunner(day, shiftType, runner),
            child: Container(
              padding: const EdgeInsets.all(2),
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: 28),
              decoration: BoxDecoration(
                color: hasRunner ? getShiftColor(shiftType).withOpacity(0.1) : null,
              ),
              child: Text(
                runner ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: hasRunner 
                      ? context.appColors.textPrimary
                      : context.appColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      }

      // Build table rows for a single week with thick border
      Widget buildWeekTable(List<DateTime> weekDays, bool isFirst) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
              width: 2,
            ),
          ),
          margin: EdgeInsets.only(top: isFirst ? 0 : 4),
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(55),
            columnWidths: const {
              0: FixedColumnWidth(45), // Day column (narrower now with stacked layout)
            },
            border: TableBorder.all(color: Colors.grey.shade300, width: 1),
            children: weekDays.map((day) {
              return TableRow(
                children: [
                  buildDayCell(day),
                  ...shiftTypeKeys.map((shiftType) {
                    final runner = getRunnerForCell(day, shiftType);
                    return buildRunnerCell(day, shiftType, runner);
                  }),
                ],
              );
            }).toList(),
          ),
        );
      }

      return Container(
        width: _isRunnerPanelExpanded ? 320 : 40,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          children: [
            // Header with toggle button
            InkWell(
              onTap: () {
                setState(() {
                  _isRunnerPanelExpanded = !_isRunnerPanelExpanded;
                });
              },
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: _isRunnerPanelExpanded
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.center,
                  children: [
                    if (_isRunnerPanelExpanded)
                      const Text(
                        'Shift Runners',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    Icon(
                      _isRunnerPanelExpanded
                          ? Icons.chevron_right
                          : Icons.chevron_left,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            // Column headers for shift types
            if (_isRunnerPanelExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 45, child: buildHeaderCell('')), // Match day column width
                      ...shiftTypeKeys.map((shiftType) => SizedBox(
                        width: 55, // Match table column width
                        child: buildShiftHeader(shiftType),
                      )),
                    ],
                  ),
                ),
              ),
            // Weekly tables with thick borders
            if (_isRunnerPanelExpanded)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      for (int i = 0; i < allWeeks.length; i++)
                        buildWeekTable(allWeeks[i], i == 0),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main schedule
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dayColumnWidth = 120.0;
              const tablePadding = 40.0; // Extra padding to prevent edge overhang

              final availableWidth =
                  constraints.maxWidth - dayColumnWidth - tablePadding;
              final cellWidth = widget.employees.isNotEmpty
                  ? (availableWidth / widget.employees.length).clamp(
                      80.0,
                      200.0,
                    )
                  : 100.0;

              // Account for borders (2px on each side = 4px total)
              final totalWidth =
                  dayColumnWidth +
                  (cellWidth * widget.employees.length) +
                  4;

              List<Widget> buildEmployeeHeaderCells() {
                final cells = <Widget>[];
                for (int i = 0; i < widget.employees.length; i++) {
                  final employee = widget.employees[i];

                  final bg = jobCodeColorFor(employee.jobCode);
                  final fg =
                      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.onSurface;

                  cells.add(
                    Container(
                      width: cellWidth,
                      height: 60,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          employee.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: fg,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                return cells;
              }

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: totalWidth,
                      child: Column(
                        children: [
                          Container(
                            width: totalWidth,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: dayColumnWidth,
                                  height: 60,
                                  child: const Center(
                                    child: Text(
                                      'Day',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                ...buildEmployeeHeaderCells(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: weeks.length,
                        itemBuilder: (context, weekIndex) {
                          final week = weeks[weekIndex];

                          return Container(
                            width: totalWidth,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: week.asMap().entries.map((entry) {
                                final dayIndex = entry.key;
                                final day = entry.value;

                                if (day == null) {
                                  return const SizedBox.shrink();
                                }

                                final isCurrentMonth =
                                    day.month == widget.date.month;
                                final isWeekend =
                                    day.weekday == DateTime.saturday ||
                                    day.weekday == DateTime.sunday;
                                final dayName = dayNames[day.weekday % 7];

                                return Container(
                                  decoration: BoxDecoration(
                                    border: dayIndex < 6
                                        ? Border(
                                            bottom: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Day label column with notes
                                        GestureDetector(
                                          onTap: () =>
                                              _showNoteDialog(context, day),
                                          child: Container(
                                            width: dayColumnWidth,
                                            constraints: const BoxConstraints(minHeight: 50),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                right: BorderSide(
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                  width: 2,
                                                ),
                                              ),
                                              color: isWeekend
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer
                                                        .withAlpha(51)
                                                  : !isCurrentMonth
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .withAlpha(25)
                                                  : null,
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                // Day name and date
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      dayName,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
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
                                                  ],
                                                ),
                                                if (_hasNoteForDay(day)) ...[
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      _getNoteForDay(day),
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.amber,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.note,
                                                    size: 14,
                                                    color: Colors.amber,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Employee cells for this day
                                        ...widget.employees.map((employee) {
                                          return _buildMonthlyEmployeeCell(
                                            context: context,
                                            day: day,
                                            isCurrentMonth: isCurrentMonth,
                                            isWeekend: isWeekend,
                                            employee: employee,
                                            cellWidth: cellWidth,
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
            },
          ),
        ),
        // Runner panel on the right
        buildRunnerPanel(),
      ],
    );
  }
}

// Public simple shift placeholder for rendering
class ShiftPlaceholder {
  final int? id; // Database ID (null for time-off entries)
  final int employeeId;
  final DateTime start;
  final DateTime end;
  final String text;
  final String? notes; // Shift-specific notes

  ShiftPlaceholder({
    this.id,
    required this.employeeId,
    required this.start,
    required this.end,
    required this.text,
    this.notes,
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
  int get hashCode =>
      id.hashCode ^ employeeId.hashCode ^ start.hashCode ^ end.hashCode;
}

/// Dialog for selecting a shift runner in monthly view (same as weekly)
class _MonthlyRunnerSearchDialog extends StatefulWidget {
  final DateTime day;
  final String shiftType;
  final String? currentName;
  final List<Employee> availableEmployees;
  final Color shiftColor;
  final String startTime;
  final String endTime;

  const _MonthlyRunnerSearchDialog({
    required this.day,
    required this.shiftType,
    required this.currentName,
    required this.availableEmployees,
    required this.shiftColor,
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_MonthlyRunnerSearchDialog> createState() =>
      _MonthlyRunnerSearchDialogState();
}

class _MonthlyRunnerSearchDialogState extends State<_MonthlyRunnerSearchDialog> {
  late TextEditingController _searchController;
  List<Employee> _filteredEmployees = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredEmployees = widget.availableEmployees;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = widget.availableEmployees;
      } else {
        _filteredEmployees = widget.availableEmployees
            .where(
              (emp) => emp.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: widget.shiftColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ShiftRunner.getLabelForType(widget.shiftType)} Runner',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '${widget.day.month}/${widget.day.day} • ${widget.startTime} - ${widget.endTime}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search employees...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _filterEmployees('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).extension<AppColors>()!.surfaceVariant,
              ),
              onChanged: _filterEmployees,
            ),
            const SizedBox(height: 12),
            Text(
              'Available Employees (${_filteredEmployees.length})',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).extension<AppColors>()!.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            // Employee list
            SizedBox(
              height: 200,
              child: _filteredEmployees.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'No available employees for this shift'
                            : 'No matching employees',
                        style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textTertiary, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredEmployees.length,
                      itemBuilder: (context, index) {
                        final emp = _filteredEmployees[index];
                        final isCurrentRunner = widget.currentName == emp.name;

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          tileColor: isCurrentRunner
                              ? widget.shiftColor.withOpacity(0.1)
                              : null,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: widget.shiftColor.withOpacity(0.2),
                            child: Text(
                              emp.name.isNotEmpty
                                  ? emp.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.shiftColor,
                              ),
                            ),
                          ),
                          title: Text(
                            emp.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrentRunner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            emp.jobCode,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isCurrentRunner
                              ? Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: widget.shiftColor,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, emp.name),
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
        if (widget.currentName != null && widget.currentName!.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}

/// Dialog for auto-filling shifts from weekly templates with employee selection
class _AutoFillFromWeeklyTemplatesDialog extends StatefulWidget {
  final List<Employee> employees;
  final WeeklyTemplateDao weeklyTemplateDao;
  final DateTime weekStart;

  const _AutoFillFromWeeklyTemplatesDialog({
    required this.employees,
    required this.weeklyTemplateDao,
    required this.weekStart,
  });

  @override
  State<_AutoFillFromWeeklyTemplatesDialog> createState() => _AutoFillFromWeeklyTemplatesDialogState();
}

class _AutoFillFromWeeklyTemplatesDialogState extends State<_AutoFillFromWeeklyTemplatesDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<int> _selectedEmployeeIds = {};
  bool _skipExisting = true;
  bool _overrideExisting = false;
  Map<int, List<WeeklyTemplateEntry>> _employeeTemplates = {};
  bool _isLoading = true;

  static const List<String> _dayAbbreviations = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final employeeIds = widget.employees.map((e) => e.id!).toList();
    final templates = await widget.weeklyTemplateDao.getTemplatesForEmployees(employeeIds);
    setState(() {
      _employeeTemplates = templates;
      _isLoading = false;
    });
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return widget.employees;
    final query = _searchQuery.toLowerCase();
    return widget.employees.where((e) => 
      e.name.toLowerCase().contains(query) ||
      e.jobCode.toLowerCase().contains(query)
    ).toList();
  }

  String _getTemplatePreview(int employeeId) {
    final templates = _employeeTemplates[employeeId] ?? [];
    if (templates.isEmpty) return 'No template';
    
    final parts = <String>[];
    for (final entry in templates) {
      if (entry.hasShift) {
        parts.add('${_dayAbbreviations[entry.dayOfWeek]}: ${entry.startTime}-${entry.endTime}');
      } else if (entry.isOff) {
        parts.add('${_dayAbbreviations[entry.dayOfWeek]}: OFF');
      }
    }
    return parts.isEmpty ? 'No shifts defined' : parts.join(', ');
  }

  void _selectAll() {
    setState(() {
      _selectedEmployeeIds = _filteredEmployees.map((e) => e.id!).toSet();
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedEmployeeIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_fix_high, color: Colors.green),
          SizedBox(width: 8),
          Expanded(child: Text('Auto-Fill from Weekly Templates')),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  
                  // Selection controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_selectedEmployeeIds.length} of ${widget.employees.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _selectAll,
                            child: const Text('Select All'),
                          ),
                          TextButton(
                            onPressed: _deselectAll,
                            child: const Text('Deselect All'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  
                  // Employee list
                  Expanded(
                    child: _filteredEmployees.isEmpty
                        ? const Center(child: Text('No employees found'))
                        : ListView.builder(
                            itemCount: _filteredEmployees.length,
                            itemBuilder: (context, index) {
                              final employee = _filteredEmployees[index];
                              final isSelected = _selectedEmployeeIds.contains(employee.id);
                              final templatePreview = _getTemplatePreview(employee.id!);
                              
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedEmployeeIds.add(employee.id!);
                                    } else {
                                      _selectedEmployeeIds.remove(employee.id);
                                    }
                                  });
                                },
                                title: Text(employee.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employee.jobCode,
                                      style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary, fontSize: 12),
                                    ),
                                    Text(
                                      templatePreview,
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            },
                          ),
                  ),
                  
                  const Divider(),
                  
                  // Options
                  CheckboxListTile(
                    title: const Text('Skip employees with existing shifts'),
                    subtitle: const Text('Don\'t create shifts for days that already have one'),
                    value: _skipExisting,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (v) {
                      setState(() {
                        _skipExisting = v ?? true;
                        if (_skipExisting) {
                          _overrideExisting = false;
                        }
                      });
                    },
                  ),
                  if (!_skipExisting)
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: CheckboxListTile(
                        title: const Text('Override existing shifts'),
                        subtitle: const Text('Delete existing shifts and replace with template'),
                        value: _overrideExisting,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (v) => setState(() => _overrideExisting = v ?? false),
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
        ElevatedButton.icon(
          icon: const Icon(Icons.auto_fix_high),
          label: Text('Auto-Fill (${_selectedEmployeeIds.length})'),
          onPressed: _selectedEmployeeIds.isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'selectedEmployees': _selectedEmployeeIds.toList(),
                    'skipExisting': _skipExisting,
                    'overrideExisting': _overrideExisting,
                  }),
        ),
      ],
    );
  }
}
