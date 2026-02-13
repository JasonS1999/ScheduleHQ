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
import '../../database/tracked_employee_dao.dart';
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
import '../../utils/color_helpers.dart';
import '../../services/schedule_pdf_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/notification_sender_service.dart';
import '../../utils/dialog_helper.dart';
import 'time_off_cell_dialog.dart';

// Custom intents for keyboard shortcuts
class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

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
    // Primary check: exact 4AM-3:59AM pattern (DST-safe with new component storage)
    final hasCorrectTimes =
        (s.start.hour == 4 &&
        s.start.minute == 0 &&
        s.end.hour == 3 &&
        s.end.minute == 59);
    // Defensive fallback: show as label if times are within 2 hours (handles legacy DST-shifted data)
    final seemsLikeOffShift =
        (s.start.hour >= 2 && s.start.hour <= 6) &&
        (s.end.hour >= 2 && s.end.hour <= 6) &&
        s.start.minute == 0 &&
        s.end.minute == 59;
    return hasCorrectTimes || seemsLikeOffShift;
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

  ScheduleView({super.key, DateTime? date})
    : initialDate = date ?? DateTime.now();

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  late DateTime _date;
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

  // Counter to trigger shift runner refresh in child views
  int _shiftRunnerRefreshKey = 0;
  bool _showRunners = true;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _loadEmployees();
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<ShiftPlaceholder> _timeOffToShifts(List<TimeOffEntry> entries) {
    return entries
        .where((e) {
          // Skip partial day time off entries (requested type with specific hours)
          // These should not show "REQ OFF" in the cell - only show a warning in the dialog
          if (e.timeOffType.toLowerCase() == 'requested' && !e.isAllDay) {
            return false;
          }
          return true;
        })
        .map((e) {
          String label;
          switch (e.timeOffType.toLowerCase()) {
            case 'vac':
            case 'vacation':
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
            timeOffEntryId: e.id,
            vacationGroupId: e.vacationGroupId,
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
    // Use calendar month to include visible overlapping days from adjacent months
    dbShifts = await _shiftDao.getByCalendarMonth(_date.year, _date.month);
    final workShifts = _shiftsToPlaceholders(dbShifts);

    // Load notes for calendar month
    final notes = await _noteDao.getByCalendarMonth(_date.year, _date.month);

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
      _date = DateTime(_date.year, _date.month - 1, 1);
    });
    _refreshShifts();
  }

  void _next() {
    setState(() {
      _date = DateTime(_date.year, _date.month + 1, 1);
    });
    _refreshShifts();
  }

  // Direct shift operations (no undo)
  Future<int> _insertShift(Shift shift) async {
    return await _shiftDao.insert(shift);
  }

  Future<void> _updateShift(Shift newShift) async {
    await _shiftDao.update(newShift);
  }

  Future<void> _deleteShift(Shift shift) async {
    // Check if there's a runner assigned for this shift's employee, date, and shift type
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

      final runner = await _shiftRunnerDao.getForDateAndShift(
        shiftDate,
        shiftType,
      );

      if (runner != null) {
        final employee = await _employeeDao.getById(shift.employeeId);
        if (employee != null && runner.runnerName == employee.name) {
          await _shiftRunnerDao.delete(shiftDate, shiftType);
          setState(() {
            _shiftRunnerRefreshKey++;
          });
        }
      }
    }

    if (shift.id != null) {
      await _shiftDao.delete(shift.id!);
    }
  }

  Future<void> _moveShift(Shift newShift) async {
    await _shiftDao.update(newShift);
  }

  Future<void> _handlePrintExport(String action) async {
    try {
      late final Uint8List fileBytes;
      late final String title;
      late final String filename;
      late final String fileType;

      // Load shift types
      final shiftTypes = await _shiftTypeDao.getAll();

      // Get first and last day of month for shift runners
      final firstDay = DateTime(_date.year, _date.month, 1);
      final lastDay = DateTime(_date.year, _date.month + 1, 0);

      // Check if this month results in only 4 weeks (need to extend range for 5-week export)
      // Find Sunday before or on first day
      final startDate = firstDay.subtract(Duration(days: firstDay.weekday % 7));
      // Count weeks
      var weekCount = 0;
      var currentDate = startDate;
      while (currentDate.isBefore(lastDay) ||
          currentDate.month == _date.month) {
        weekCount++;
        currentDate = currentDate.add(const Duration(days: 7));
        if (weekCount >= 6) break;
      }

      // Determine the actual start date for data loading
      final dataStartDate = weekCount == 4
          ? startDate.subtract(const Duration(days: 7)) // Include previous week
          : startDate;

      // Load shift runners for extended range if needed
      final shiftRunners = await _shiftRunnerDao.getForDateRange(
        dataStartDate,
        lastDay,
      );

      // Load shifts for the extended range if this is a 4-week month
      List<ShiftPlaceholder> shiftsForPdf = _shifts;
      if (weekCount == 4) {
        // Load additional shifts from previous week
        final previousWeekEnd = startDate; // Exclusive end date
        final previousWeekStart = startDate.subtract(const Duration(days: 7));
        final previousWeekShifts = await _shiftDao.getByDateRange(
          previousWeekStart,
          previousWeekEnd,
        );
        final previousWeekPlaceholders = _shiftsToPlaceholders(
          previousWeekShifts,
        );

        // Combine previous week shifts with current shifts
        // Note: _shifts already contains all time-off entries, so don't add them again
        shiftsForPdf = [...previousWeekPlaceholders, ..._shifts];
      }

      // Load tracked employees for stats table
      final trackedEmployeeDao = TrackedEmployeeDao();
      final trackedEmployees = await trackedEmployeeDao.getTrackedEmployees(
        _employees,
      );

      if (action == 'pdf_manager') {
        fileBytes = await SchedulePdfService.generateManagerMonthlyPdf(
          year: _date.year,
          month: _date.month,
          employees: _employees,
          shifts: shiftsForPdf,
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
        // Load time off entries for stats calculation
        final timeOffEntries = await _timeOffDao.getAllTimeOff();

        fileBytes = await SchedulePdfService.generateMonthlyPdf(
          year: _date.year,
          month: _date.month,
          employees: _employees,
          shifts: shiftsForPdf,
          jobCodeSettings: _jobCodeSettings,
          shiftRunners: shiftRunners,
          shiftTypes: shiftTypes,
          storeHours: StoreHours.cached,
          storeName: StoreHours.cached.storeName,
          storeNsn: StoreHours.cached.storeNsn,
          trackedEmployees: trackedEmployees,
          timeOffEntries: timeOffEntries,
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

  Future<void> _handleMonthAction(String action) async {
    final monthStart = DateTime(_date.year, _date.month, 1);

    if (action == 'copyMonthToNext') {
      final nextMonthStart = DateTime(_date.year, _date.month + 1, 1);
      await _copyMonthTo(monthStart, nextMonthStart);
    } else if (action == 'copyMonthToDate') {
      final targetMonth = await _showMonthPicker(context, monthStart);
      if (targetMonth != null) {
        await _copyMonthTo(monthStart, targetMonth);
      }
    } else if (action == 'clearMonth') {
      await _clearMonth(monthStart);
    } else if (action == 'autoFillFromTemplates') {
      await _autoFillFromTemplates(monthStart);
    }
  }

  Future<void> _showPublishDialog(BuildContext context) async {
    // Calculate date range for current month
    final startDate = DateTime(_date.year, _date.month, 1);
    final endDate = DateTime(_date.year, _date.month + 1, 0);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PublishScheduleDialog(
        startDate: startDate,
        endDate: endDate,
        employees: _employees,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Schedule published to employees'),
          backgroundColor: context.appColors.successBackground,
        ),
      );
    }
  }

  Future<void> _copyMonthTo(
    DateTime sourceMonthStart,
    DateTime targetMonthStart,
  ) async {
    final sourceMonthEnd = DateTime(
      sourceMonthStart.year,
      sourceMonthStart.month + 1,
      0,
    );
    final targetMonthEnd = DateTime(
      targetMonthStart.year,
      targetMonthStart.month + 1,
      0,
    );

    // Get all shifts from source month
    final sourceShifts = await _shiftDao.getByDateRange(
      sourceMonthStart,
      sourceMonthEnd.add(const Duration(days: 1)),
    );

    if (sourceShifts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No shifts to copy from this month')),
        );
      }
      return;
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
    final sourceName =
        '${monthNames[sourceMonthStart.month - 1]} ${sourceMonthStart.year}';
    final targetName =
        '${monthNames[targetMonthStart.month - 1]} ${targetMonthStart.year}';

    // Confirm the copy
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy Month'),
        content: Text(
          'Copy ${sourceShifts.length} shift(s) from $sourceName to $targetName?\n\n'
          'Shifts on days that don\'t exist in the target month will be skipped.',
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

    // Create new shifts for the target month
    final newShifts = <Shift>[];
    for (final s in sourceShifts) {
      final sourceDay = s.startTime.day;
      // Skip if the target month doesn't have this day
      if (sourceDay > targetMonthEnd.day) continue;

      final dayOffset =
          DateTime(targetMonthStart.year, targetMonthStart.month, sourceDay)
              .difference(
                DateTime(
                  sourceMonthStart.year,
                  sourceMonthStart.month,
                  sourceDay,
                ),
              )
              .inDays;

      newShifts.add(
        Shift(
          employeeId: s.employeeId,
          startTime: s.startTime.add(Duration(days: dayOffset)),
          endTime: s.endTime.add(Duration(days: dayOffset)),
          label: s.label,
          notes: s.notes,
        ),
      );
    }

    // Insert all new shifts
    await _shiftDao.insertAll(newShifts);

    // Navigate to target month and refresh
    setState(() {
      _date = targetMonthStart;
    });
    await _refreshShifts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${newShifts.length} shift(s) to $targetName'),
        ),
      );
    }
  }

  Future<void> _clearMonth(DateTime monthStart) async {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final monthEndExclusive = monthEnd.add(const Duration(days: 1));

    // Count shifts to clear
    final shifts = await _shiftDao.getByDateRange(
      monthStart,
      monthEndExclusive,
    );

    if (shifts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No shifts to clear in this month')),
        );
      }
      return;
    }

    // Confirm the clear
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning,
              color: Theme.of(ctx).extension<AppColors>()!.errorIcon,
            ),
            const SizedBox(width: 8),
            const Text('Clear Month'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${shifts.length} shift(s) from this month?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(
                ctx,
              ).extension<AppColors>()!.destructive,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Delete all shifts in the month
    await _shiftDao.deleteByDateRange(monthStart, monthEndExclusive);
    await _refreshShifts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleared ${shifts.length} shift(s) from this month'),
        ),
      );
    }
  }

  Future<DateTime?> _showMonthPicker(
    BuildContext context,
    DateTime currentMonth,
  ) async {
    final monthNames = [
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
    int selectedYear = currentMonth.year;
    int selectedMonth = currentMonth.month;

    // Move to next month as default
    selectedMonth++;
    if (selectedMonth > 12) {
      selectedMonth = 1;
      selectedYear++;
    }

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select Target Month'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setDialogState(() => selectedYear--),
                      ),
                      Text(
                        '$selectedYear',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setDialogState(() => selectedYear++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(12, (i) {
                      final month = i + 1;
                      final isSelected = month == selectedMonth;
                      return ChoiceChip(
                        label: Text(monthNames[i].substring(0, 3)),
                        selected: isSelected,
                        onSelected: (_) =>
                            setDialogState(() => selectedMonth = month),
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    DateTime(selectedYear, selectedMonth, 1),
                  ),
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  final WeeklyTemplateDao _weeklyTemplateDao = WeeklyTemplateDao();

  Future<void> _autoFillFromTemplates(DateTime monthStart) async {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);

    // Get employees who have weekly templates
    final employeeIdsWithTemplates = await _weeklyTemplateDao
        .getEmployeeIdsWithTemplates();

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
            content: Text(
              'No employees with weekly templates found in the current filter.',
            ),
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
        weekStart: monthStart,
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
    final templates = await _weeklyTemplateDao.getTemplatesForEmployees(
      selectedEmployeeIds,
    );

    // Generate shifts
    int shiftsCreated = 0;
    int shiftsDeleted = 0;
    final newShifts = <Shift>[];
    final shiftsToDelete = <int>[];

    for (final employeeId in selectedEmployeeIds) {
      final employeeTemplates = templates[employeeId] ?? [];

      // Iterate every day in the month and apply the matching template entry
      for (
        var day = monthStart;
        !day.isAfter(monthEnd);
        day = day.add(const Duration(days: 1))
      ) {
        final dayOfWeek = day.weekday % 7; // 0=Sun, 1=Mon, ..., 6=Sat
        final template = employeeTemplates
            .cast<WeeklyTemplateEntry?>()
            .firstWhere((t) => t!.dayOfWeek == dayOfWeek, orElse: () => null);
        if (template == null || template.isBlank) continue;

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
        final startMinute = startTimeParts.length > 1
            ? int.parse(startTimeParts[1])
            : 0;

        final endTimeParts = template.endTime!.split(':');
        final endHour = int.parse(endTimeParts[0]);
        final endMinute = endTimeParts.length > 1
            ? int.parse(endTimeParts[1])
            : 0;

        final shiftStart = DateTime(
          day.year,
          day.month,
          day.day,
          startHour,
          startMinute,
        );
        var shiftEnd = DateTime(
          day.year,
          day.month,
          day.day,
          endHour,
          endMinute,
        );

        // Handle overnight shifts
        if (shiftEnd.isBefore(shiftStart) ||
            shiftEnd.isAtSameMomentAs(shiftStart)) {
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
            content: Text(
              'No shifts were created (all slots already filled or no shifts in templates)',
            ),
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
      String message = 'Created $shiftsCreated shift(s) from templates';
      if (shiftsDeleted > 0) {
        message += ', replaced $shiftsDeleted existing shift(s)';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
                    (emp) => DropdownMenuItem(
                      value: emp.id,
                      child: Text(emp.displayName),
                    ),
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
                  "${_monthName(_date.month)} ${_date.year}",
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
        // Publish to Employees button
        Tooltip(
          message: 'Publish schedule to employee app',
          child: IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () => _showPublishDialog(context),
          ),
        ),
        Tooltip(
          message: _showRunners ? 'Hide Runners' : 'Show Runners',
          child: IconButton(
            icon: Icon(
              _showRunners ? Icons.groups : Icons.groups_outlined,
              color: _showRunners
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => setState(() => _showRunners = !_showRunners),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'More Options',
          onSelected: (value) => _handleMonthAction(value),
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
              value: 'copyMonthToNext',
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 20),
                  SizedBox(width: 8),
                  Text('Copy Month to Next Month'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'copyMonthToDate',
              child: Row(
                children: [
                  Icon(Icons.date_range, size: 20),
                  SizedBox(width: 8),
                  Text('Copy Month to Date...'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clearMonth',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_sweep,
                    size: 20,
                    color: context.appColors.destructive,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Clear This Month',
                    style: TextStyle(color: context.appColors.destructive),
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
    return MonthlyScheduleView(
      date: _date,
      employees: _filteredEmployees,
      shifts: _shifts,
      notes: _notes,
      jobCodeSettings: _jobCodeSettings,
      clipboardAvailable: _clipboard != null,
      shiftRunnerRefreshKey: _shiftRunnerRefreshKey,
      showRunners: _showRunners,
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
        await _insertShift(shift);
        _clipboard = null;
        await _refreshShifts();
      },
      onUpdateShift: (oldShift, newStart, newEnd, {String? shiftNotes}) async {
        // Handle "OFF" button - create an OFF label shift (4AM-3:59AM)
        if (shiftNotes == 'OFF') {
          // Calculate 4:00 AM start and 3:59 AM next day end
          final day = oldShift.id != null ? oldShift.start : newStart;
          final offStart = DateTime(day.year, day.month, day.day, 4, 0);
          final offEnd = DateTime(
            day.year,
            day.month,
            day.day,
            3,
            59,
          ).add(const Duration(days: 1));

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
            await _updateShift(updated);
          } else {
            // Create new OFF shift
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: offStart,
              endTime: offEnd,
              label: 'OFF',
              notes: null,
            );
            await _insertShift(newShift);
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
            await _deleteShift(shiftToDelete);
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
            await _updateShift(updated);
          } else {
            final newShift = Shift(
              employeeId: oldShift.employeeId,
              startTime: newStart,
              endTime: newEnd,
              label: oldShift.text,
              notes: shiftNotes,
            );
            await _insertShift(newShift);
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
          await _moveShift(updated);
        } else {
          final newShift = Shift(
            employeeId: newEmployeeId,
            startTime: newStart,
            endTime: newEnd,
            label: shift.text,
          );
          await _insertShift(newShift);
        }
        await _refreshShifts();
      },
      onAddTimeOff: (employeeId, day) async {
        final employee = _employees.cast<Employee?>().firstWhere(
          (e) => e?.id == employeeId,
          orElse: () => null,
        );
        if (employee == null || !mounted) return;

        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => TimeOffCellDialog(
            employeeName: employee.displayName,
            date: day,
          ),
        );
        if (result == null || !mounted) return;

        final type = result['timeOffType'] as String;

        if (type == 'vacation') {
          // Vacation: insert a row per day using date range
          final startDate = result['startDate'] as DateTime;
          final endDate = result['endDate'] as DateTime;
          final groupId = 'vac_${employeeId}_${startDate.millisecondsSinceEpoch}';

          // Check for existing time off in range
          final existing = await _timeOffDao.getTimeOffInRange(employeeId, startDate, endDate);
          if (existing.isNotEmpty && mounted) {
            final proceed = await DialogHelper.showConfirmDialog(
              context,
              title: 'Time Off Conflict',
              message: '${employee.displayName} already has time off during this period. Add anyway?',
              confirmText: 'Add',
              icon: Icons.warning_amber_rounded,
            );
            if (!proceed) return;
          }

          final ids = await _timeOffDao.insertTimeOffRange(
            employeeId: employeeId,
            startDate: startDate,
            endDate: endDate,
            timeOffType: type,
            totalHours: (endDate.difference(startDate).inDays + 1) * 8,
            vacationGroupId: groupId,
          );

          // Sync each entry
          for (final id in ids) {
            final entry = await _timeOffDao.getById(id);
            if (entry != null) {
              try {
                await FirestoreSyncService.instance.syncTimeOffEntry(entry, employee);
              } catch (e) {
                debugPrint('Failed to sync vacation entry to Firestore: $e');
              }
            }
          }
        } else {
          // PTO or Requested: single-day insert
          final existing = await _timeOffDao.getTimeOffInRange(employeeId, day, day);
          if (existing.isNotEmpty && mounted) {
            final proceed = await DialogHelper.showConfirmDialog(
              context,
              title: 'Time Off Conflict',
              message: '${employee.displayName} already has time off on this date. Add anyway?',
              confirmText: 'Add',
              icon: Icons.warning_amber_rounded,
            );
            if (!proceed) return;
          }

          final entry = TimeOffEntry(
            id: null,
            employeeId: employeeId,
            date: day,
            timeOffType: type,
            hours: result['hours'] as int,
            isAllDay: result['isAllDay'] as bool,
            startTime: result['startTime'] as String?,
            endTime: result['endTime'] as String?,
          );

          final localId = await _timeOffDao.insertTimeOff(entry);
          try {
            await FirestoreSyncService.instance.syncTimeOffEntry(
              entry.copyWith(id: localId),
              employee,
            );
          } catch (e) {
            debugPrint('Failed to sync time-off to Firestore: $e');
          }
        }

        await _refreshShifts();
      },
      onEditTimeOff: (timeOffEntryId) async {
        final entry = await _timeOffDao.getById(timeOffEntryId);
        if (entry == null || !mounted) return;

        final employee = _employees.cast<Employee?>().firstWhere(
          (e) => e?.id == entry.employeeId,
          orElse: () => null,
        );
        if (employee == null || !mounted) return;

        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => TimeOffCellDialog(
            employeeName: employee.displayName,
            date: entry.date,
            existingEntry: entry,
          ),
        );
        if (result == null || !mounted) return;

        final updated = entry.copyWith(
          timeOffType: result['timeOffType'] as String,
          hours: result['hours'] as int,
          isAllDay: result['isAllDay'] as bool,
          startTime: result['startTime'] as String?,
          endTime: result['endTime'] as String?,
        );

        await _timeOffDao.updateTimeOff(updated);
        try {
          await FirestoreSyncService.instance.syncTimeOffEntry(updated, employee);
        } catch (e) {
          debugPrint('Failed to sync time-off update to Firestore: $e');
        }
        await _refreshShifts();
      },
      onDeleteTimeOff: (timeOffEntryId, vacationGroupId) async {
        if (!mounted) return;

        if (vacationGroupId != null) {
          // Multi-day vacation — ask user what to delete
          final choice = await DialogHelper.showChoiceDialog(
            context,
            title: 'Delete Time Off',
            message: 'This is part of a multi-day vacation block.',
            options: ['Delete this day only', 'Delete entire vacation block'],
            icon: Icons.delete,
          );

          if (choice == null || !mounted) return;

          if (choice == 0) {
            // Delete single day
            final entry = await _timeOffDao.getById(timeOffEntryId);
            if (entry != null) {
              try {
                await FirestoreSyncService.instance.deleteTimeOffEntry(
                  entry.employeeId,
                  timeOffEntryId,
                );
              } catch (e) {
                debugPrint('Failed to sync time-off delete to Firestore: $e');
              }
              await _timeOffDao.deleteTimeOff(timeOffEntryId);
            }
          } else if (choice == 1) {
            // Delete entire group
            final groupEntries = await _timeOffDao.getEntriesByGroup(vacationGroupId);
            for (final e in groupEntries) {
              try {
                await FirestoreSyncService.instance.deleteTimeOffEntry(
                  e.employeeId,
                  e.id!,
                );
              } catch (err) {
                debugPrint('Failed to sync group entry delete to Firestore: $err');
              }
            }
            await _timeOffDao.deleteVacationGroup(vacationGroupId);
          }
        } else {
          // Single-day time off — confirm delete
          final confirmed = await DialogHelper.showDeleteConfirmDialog(
            context,
            title: 'Delete Time Off',
            message: 'Are you sure you want to delete this time off entry?',
          );
          if (!confirmed || !mounted) return;

          final entry = await _timeOffDao.getById(timeOffEntryId);
          if (entry != null) {
            try {
              await FirestoreSyncService.instance.deleteTimeOffEntry(
                entry.employeeId,
                timeOffEntryId,
              );
            } catch (e) {
              debugPrint('Failed to sync time-off delete to Firestore: $e');
            }
            await _timeOffDao.deleteTimeOff(timeOffEntryId);
          }
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
      orElse: () => Employee(id: employeeId, firstName: 'Unknown', jobCode: ''),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(ctx).extension<AppColors>()!.warningIcon,
              ),
              const SizedBox(width: 8),
              const Text('Scheduling Conflict'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${employee.displayName} already has a shift that overlaps with this time:',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    ctx,
                  ).extension<AppColors>()!.warningBackground,
                  border: Border.all(
                    color: Theme.of(ctx).extension<AppColors>()!.warningBorder,
                  ),
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
                          'â€¢ ${_formatTimeRange(c.startTime, c.endTime)}',
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
                backgroundColor: Theme.of(
                  ctx,
                ).extension<AppColors>()!.warningForeground,
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
  final bool showRunners;
  final void Function(int employeeId, DateTime date)? onAddTimeOff;
  final void Function(int timeOffEntryId)? onEditTimeOff;
  final void Function(int timeOffEntryId, String? vacationGroupId)?
      onDeleteTimeOff;

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
    this.showRunners = true,
    this.onAddTimeOff,
    this.onEditTimeOff,
    this.onDeleteTimeOff,
  });

  @override
  State<MonthlyScheduleView> createState() => _MonthlyScheduleViewState();
}

class _MonthlyScheduleViewState extends State<MonthlyScheduleView> {
  final ValueNotifier<ShiftPlaceholder?> _selectedShift = ValueNotifier(null);
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
  final Map<String, Future<Map<String, dynamic>>> _availabilityCache = {};
  List<ShiftType> _shiftTypes = [];
  List<ShiftRunner> _shiftRunners = [];

  /// Return a cached availability future keyed on employeeId + date.
  Future<Map<String, dynamic>> _cachedCheckAvailability(
    int employeeId,
    DateTime date,
  ) {
    final key = '$employeeId-${date.year}-${date.month}-${date.day}';
    return _availabilityCache.putIfAbsent(
      key,
      () => _checkAvailability(employeeId, date),
    );
  }

  /// Invalidate the availability cache.
  void _invalidateAvailabilityCache() => _availabilityCache.clear();

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
    _selectedShift.dispose();
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
      _invalidateAvailabilityCache();
    } else if (oldWidget.shifts != widget.shifts) {
      _invalidateAvailabilityCache();
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

    final runners = await _shiftRunnerDao.getForDateRange(
      calendarStart,
      calendarEnd,
    );
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
    final runnersForDay = _shiftRunners
        .where(
          (r) =>
              r.date.year == day.year &&
              r.date.month == day.month &&
              r.date.day == day.day,
        )
        .toList();

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

  Future<void> _editMonthlyRunner(
    DateTime day,
    String shiftType,
    String? currentRunner,
  ) async {
    // Get shift type info
    final shiftTypeObj = _shiftTypes.cast<ShiftType?>().firstWhere(
      (st) => st?.key == shiftType,
      orElse: () => null,
    );
    final startTime = shiftTypeObj?.defaultShiftStart ?? '09:00';
    final endTime = shiftTypeObj?.defaultShiftEnd ?? '17:00';

    // Load available employees for this shift
    final availableEmployees = await _getAvailableEmployeesForRunner(
      day,
      shiftType,
    );

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
              day.year,
              day.month,
              day.day,
              int.parse(startParts[0]),
              int.parse(startParts[1]),
            );
            var shiftEnd = DateTime(
              day.year,
              day.month,
              day.day,
              int.parse(endParts[0]),
              int.parse(endParts[1]),
            );
            // Handle overnight shifts (end time before start time)
            if (shiftEnd.isBefore(shiftStart) ||
                shiftEnd.isAtSameMomentAs(shiftStart)) {
              shiftEnd = shiftEnd.add(const Duration(days: 1));
            }

            await _shiftDao.insert(
              Shift(
                employeeId: employee.id!,
                startTime: shiftStart,
                endTime: shiftEnd,
              ),
            );
          }
        }

        // Set the runner
        await _shiftRunnerDao.upsert(
          ShiftRunner(date: day, shiftType: shiftType, runnerName: result),
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
      String reason;
      if (!timeOffEntry.isAllDay && timeOffEntry.timeOffType.toLowerCase() == 'requested') {
        // Partial-day requested: times represent availability window
        reason = 'Employee Is Available (${timeOffEntry.startTime ?? ''} - ${timeOffEntry.endTime ?? ''})';
      } else {
        final timeRange = timeOffEntry.isAllDay
            ? 'All Day'
            : '${timeOffEntry.startTime ?? ''} - ${timeOffEntry.endTime ?? ''}';
        reason = 'Time off scheduled ($timeRange)';
      }
      return {
        'available': false,
        'reason': reason,
        'type': 'time-off',
        'isAllDay': timeOffEntry.isAllDay,
        'startTime': timeOffEntry.startTime,
        'endTime': timeOffEntry.endTime,
        'timeOffEntry': timeOffEntry,
      };
    }

    // Priority 2: Check availability patterns
    return await _availabilityDao.isAvailable(employeeId, date, null, null);
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
              child: Text(
                'Delete',
                style: TextStyle(color: context.appColors.destructive),
              ),
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
        const PopupMenuItem(
          value: 'addTimeOff',
          child: Text('Add Time Off'),
        ),
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
        end: DateTime(
          day.year,
          day.month,
          day.day,
          3,
          59,
        ).add(const Duration(days: 1)),
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
    } else if (result == 'addTimeOff') {
      widget.onAddTimeOff?.call(employeeId, day);
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

  void _showTimeOffContextMenu(
    BuildContext context,
    ShiftPlaceholder shift,
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
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit Time Off')),
        PopupMenuItem(value: 'delete', child: Text('Delete Time Off')),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'edit') {
      widget.onEditTimeOff?.call(shift.timeOffEntryId!);
    } else if (result == 'delete') {
      widget.onDeleteTimeOff?.call(
        shift.timeOffEntryId!,
        shift.vacationGroupId,
      );
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

    Color bannerColor = context.appColors.successForeground;
    if (type == 'time-off') {
      final isAllDay = availability['isAllDay'] as bool? ?? true;
      bannerColor = isAllDay
          ? context.appColors.errorForeground
          : context.appColors.warningForeground;
    } else if (!isAvailable) {
      bannerColor = context.appColors.warningForeground;
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

    // Helper to check if the selected shift conflicts with time off
    bool shiftOverlapsTimeOff(int startIndex, int endIndex) {
      if (timeOffEntry == null) return false;
      final shiftStart = times[startIndex];
      final shiftEnd = times[endIndex];
      final shiftStartDt = _timeOfDayToDateTime(day, shiftStart);
      final shiftEndDt = _timeOfDayToDateTime(day, shiftEnd);
      final overlaps = timeOffEntry.overlapsWithShift(shiftStartDt, shiftEndDt);

      // For partial-day "requested" entries, times represent availability window
      // Conflict exists when shift is OUTSIDE the availability window (no overlap)
      if (!timeOffEntry.isAllDay && timeOffEntry.timeOffType.toLowerCase() == 'requested') {
        return !overlaps;
      }

      return overlaps;
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
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primary.softBg
                                      : null,
                                  side: BorderSide(
                                    color: selectedTemplate == template
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                              .extension<AppColors>()!
                                              .borderMedium,
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
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).extension<AppColors>()!.textSecondary,
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
                            color: bannerColor.softBg,
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
                                    color: bannerColor,
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
                                      ? _getShiftTypeColor(shiftType).softBorder
                                      : _getShiftTypeColor(shiftType).subtle,
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
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).extension<AppColors>()!.disabledForeground,
                  ),
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
            ? Theme.of(context).colorScheme.primary.softBg
            : runnerColor?.softBg,
        border: isSelected
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
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
                color: context.appColors.errorForeground,
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
                  ? Theme.of(context).colorScheme.primary.subtle
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
                    future: _cachedCheckAvailability(employee.id!, day),
                    builder: (context, snapshot) {
                      bool showDash = false;
                      if (snapshot.hasData) {
                        final type = snapshot.data!['type'] as String;
                        final available = snapshot.data!['available'] as bool;
                        final isAllDay =
                            snapshot.data!['isAllDay'] as bool? ?? true;
                        // Only show dash for all-day time-off or unavailability
                        // Partial day time-off should allow scheduling (with warning)
                        if (type == 'time-off' && isAllDay) {
                          showDash = true;
                        } else if (type != 'time-off' && !available) {
                          showDash = true;
                        }
                      }

                      if (isDragHover) {
                        return Center(
                          child: Icon(
                            Icons.add,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        );
                      }
                      if (showDash) {
                        return Center(
                          child: Text(
                            '-',
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(
                                context,
                              ).extension<AppColors>()!.disabledForeground,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: shiftsForCell.map((shift) {
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

                      // Use ValueListenableBuilder to only rebuild
                      // this cell when selection changes, not the
                      // entire grid.
                      return ValueListenableBuilder<ShiftPlaceholder?>(
                        valueListenable: _selectedShift,
                        builder: (context, selectedShift, _) {
                          final isSelected = selectedShift == shift;

                          // Build the shift chip widget
                          Widget shiftChip = GestureDetector(
                            onTap: isTimeOffLabel
                                ? null
                                : () {
                                    _selectedShift.value =
                                        isSelected ? null : shift;
                                  },
                            onDoubleTap: isTimeOffLabel
                                ? null
                                : () {
                                    _showEditDialog(context, shift);
                                  },
                            onSecondaryTapDown: isTimeOffLabel
                                ? (shift.timeOffEntryId != null
                                    ? (details) {
                                        _showTimeOffContextMenu(
                                          context,
                                          shift,
                                          details.globalPosition,
                                        );
                                      }
                                    : null)
                                : (details) {
                                    _selectedShift.value = shift;
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
                            return SizedBox(height: 50, child: shiftChip);
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
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$startLabel-$endLabel',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
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
                        },
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

    // --- Helper functions for shift runners & Mgr # inline columns ---

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

    int getEmployeeCountForDay(DateTime day) {
      final employeeIds = widget.shifts
          .where(
            (s) =>
                s.start.year == day.year &&
                s.start.month == day.month &&
                s.start.day == day.day &&
                ![
                  'VAC',
                  'PTO',
                  'REQ OFF',
                  'OFF',
                ].contains(s.text.toUpperCase()),
          )
          .map((s) => s.employeeId)
          .toSet();
      return employeeIds.length;
    }

    Future<void> showRunnerContextMenu(
      Offset position,
      DateTime day,
      String shiftType,
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
          PopupMenuItem<String>(
            value: 'clear',
            child: Row(
              children: [
                Icon(
                  Icons.clear,
                  size: 18,
                  color: context.appColors.destructive,
                ),
                const SizedBox(width: 8),
                Text(
                  'Clear Runner',
                  style: TextStyle(color: context.appColors.destructive),
                ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayColumnWidth = 120.0;
        const mgrColumnWidth = 40.0;
        const runnerColumnWidth = 55.0;
        final runnerColumnsTotal = widget.showRunners
            ? runnerColumnWidth * _shiftTypes.length
            : 0.0;
        const tablePadding = 40.0; // Extra padding to prevent edge overhang

        final availableWidth =
            constraints.maxWidth -
            dayColumnWidth -
            mgrColumnWidth -
            runnerColumnsTotal -
            tablePadding;
        final cellWidth = widget.employees.isNotEmpty
            ? (availableWidth / widget.employees.length).clamp(80.0, 200.0)
            : 100.0;

        // Account for borders (2px on each side = 4px total)
        final totalWidth =
            dayColumnWidth +
            mgrColumnWidth +
            (cellWidth * widget.employees.length) +
            runnerColumnsTotal +
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
                    employee.displayName,
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
                          // Mgr # header
                          Container(
                            width: mgrColumnWidth,
                            height: 60,
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Mgr\n#',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          ...buildEmployeeHeaderCells(),
                          // Shift runner headers
                          if (widget.showRunners)
                            ..._shiftTypes.map((shiftType) {
                              return Container(
                                width: runnerColumnWidth,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: getShiftColor(
                                    shiftType.key,
                                  ).softBorder,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    ShiftRunner.getLabelForType(shiftType.key),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      color: context.appColors.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            }),
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
                                            constraints: const BoxConstraints(
                                              minHeight: 50,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
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
                                                        .softBg
                                                  : !isCurrentMonth
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .subtle
                                                  : null,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                // Day name and date
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      dayName,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${day.month}/${day.day}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: !isCurrentMonth
                                                            ? context
                                                                  .appColors
                                                                  .textTertiary
                                                            : day.day ==
                                                                      DateTime.now()
                                                                          .day &&
                                                                  day.month ==
                                                                      DateTime.now()
                                                                          .month &&
                                                                  day.year ==
                                                                      DateTime.now()
                                                                          .year
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
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
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: context
                                                            .appColors
                                                            .warningIcon,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.note,
                                                    size: 14,
                                                    color: context
                                                        .appColors
                                                        .warningIcon,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Mgr # cell
                                        Container(
                                          width: mgrColumnWidth,
                                          constraints: const BoxConstraints(
                                            minHeight: 50,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              right: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              getEmployeeCountForDay(
                                                day,
                                              ).toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
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

                                        // Shift runner cells
                                        if (widget.showRunners)
                                          ..._shiftTypes.map((shiftType) {
                                            final runner = getRunnerForCell(
                                              day,
                                              shiftType.key,
                                            );
                                            final hasRunner =
                                                runner != null &&
                                                runner.isNotEmpty;
                                            return GestureDetector(
                                              onSecondaryTapDown: hasRunner
                                                  ? (
                                                      details,
                                                    ) => showRunnerContextMenu(
                                                      details.globalPosition,
                                                      day,
                                                      shiftType.key,
                                                    )
                                                  : null,
                                              child: InkWell(
                                                onTap: () => _editMonthlyRunner(
                                                  day,
                                                  shiftType.key,
                                                  runner,
                                                ),
                                                child: Container(
                                                  width: runnerColumnWidth,
                                                  constraints:
                                                      const BoxConstraints(
                                                        minHeight: 50,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: hasRunner
                                                        ? getShiftColor(
                                                            shiftType.key,
                                                          ).subtle
                                                        : null,
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        width:
                                                            shiftType ==
                                                                _shiftTypes
                                                                    .first
                                                            ? 2
                                                            : 1,
                                                      ),
                                                      right:
                                                          shiftType ==
                                                              _shiftTypes.last
                                                          ? BorderSide(
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              width: 2,
                                                            )
                                                          : BorderSide.none,
                                                      top: dayIndex == 0
                                                          ? BorderSide(
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              width: 2,
                                                            )
                                                          : BorderSide.none,
                                                      bottom:
                                                          dayIndex ==
                                                              week
                                                                      .where(
                                                                        (d) =>
                                                                            d !=
                                                                            null,
                                                                      )
                                                                      .length -
                                                                  1
                                                          ? BorderSide(
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                              width: 2,
                                                            )
                                                          : BorderSide.none,
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      runner ?? '',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: hasRunner
                                                            ? context
                                                                  .appColors
                                                                  .textPrimary
                                                            : context
                                                                  .appColors
                                                                  .disabledForeground,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
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
  final int? timeOffEntryId; // Database ID of the TimeOffEntry (null for shifts)
  final String? vacationGroupId; // Links multi-day vacation blocks

  ShiftPlaceholder({
    this.id,
    required this.employeeId,
    required this.start,
    required this.end,
    required this.text,
    this.notes,
    this.timeOffEntryId,
    this.vacationGroupId,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShiftPlaceholder &&
        other.id == id &&
        other.employeeId == employeeId &&
        other.start == start &&
        other.end == end &&
        other.timeOffEntryId == timeOffEntryId;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      employeeId.hashCode ^
      start.hashCode ^
      end.hashCode ^
      timeOffEntryId.hashCode;
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

class _MonthlyRunnerSearchDialogState
    extends State<_MonthlyRunnerSearchDialog> {
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
              (emp) =>
                  emp.displayName.toLowerCase().contains(query.toLowerCase()),
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
                  '${widget.day.month}/${widget.day.day} â€¢ ${widget.startTime} - ${widget.endTime}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).extension<AppColors>()!.textSecondary,
                  ),
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
                fillColor: Theme.of(
                  context,
                ).extension<AppColors>()!.surfaceVariant,
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
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).extension<AppColors>()!.textTertiary,
                          fontSize: 13,
                        ),
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
                              ? widget.shiftColor.subtle
                              : null,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: widget.shiftColor.softBg,
                            child: Text(
                              emp.displayName.isNotEmpty
                                  ? emp.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.shiftColor,
                              ),
                            ),
                          ),
                          title: Text(
                            emp.displayName,
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
            child: Text(
              'Clear',
              style: TextStyle(color: context.appColors.destructive),
            ),
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
  State<_AutoFillFromWeeklyTemplatesDialog> createState() =>
      _AutoFillFromWeeklyTemplatesDialogState();
}

class _AutoFillFromWeeklyTemplatesDialogState
    extends State<_AutoFillFromWeeklyTemplatesDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<int> _selectedEmployeeIds = {};
  bool _skipExisting = true;
  bool _overrideExisting = false;
  Map<int, List<WeeklyTemplateEntry>> _employeeTemplates = {};
  bool _isLoading = true;

  static const List<String> _dayAbbreviations = [
    'S',
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
  ];

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
    final templates = await widget.weeklyTemplateDao.getTemplatesForEmployees(
      employeeIds,
    );
    setState(() {
      _employeeTemplates = templates;
      _isLoading = false;
    });
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return widget.employees;
    final query = _searchQuery.toLowerCase();
    return widget.employees
        .where(
          (e) =>
              e.name.toLowerCase().contains(query) ||
              e.jobCode.toLowerCase().contains(query),
        )
        .toList();
  }

  String _getTemplatePreview(int employeeId) {
    final templates = _employeeTemplates[employeeId] ?? [];
    if (templates.isEmpty) return 'No template';

    final parts = <String>[];
    for (final entry in templates) {
      if (entry.hasShift) {
        parts.add(
          '${_dayAbbreviations[entry.dayOfWeek]}: ${entry.startTime}-${entry.endTime}',
        );
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                              final isSelected = _selectedEmployeeIds.contains(
                                employee.id,
                              );
                              final templatePreview = _getTemplatePreview(
                                employee.id!,
                              );

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
                                title: Text(employee.displayName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employee.jobCode,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).extension<AppColors>()!.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      templatePreview,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .extension<AppColors>()!
                                            .infoForeground,
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
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            },
                          ),
                  ),

                  const Divider(),

                  // Options
                  CheckboxListTile(
                    title: const Text('Skip employees with existing shifts'),
                    subtitle: const Text(
                      'Don\'t create shifts for days that already have one',
                    ),
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
                        subtitle: const Text(
                          'Delete existing shifts and replace with template',
                        ),
                        value: _overrideExisting,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (v) =>
                            setState(() => _overrideExisting = v ?? false),
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

/// Dialog for publishing schedules to employee app
class _PublishScheduleDialog extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<Employee> employees;

  const _PublishScheduleDialog({
    required this.startDate,
    required this.endDate,
    required this.employees,
  });

  @override
  State<_PublishScheduleDialog> createState() => _PublishScheduleDialogState();
}

class _PublishScheduleDialogState extends State<_PublishScheduleDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _publishAll = true;
  final Set<int> _selectedEmployeeIds = {};
  bool _publishing = false;
  bool _unpublishing = false;
  String? _lastPublishInfo;

  @override
  void initState() {
    super.initState();
    _startDate = widget.startDate;
    _endDate = widget.endDate;
    _loadLastPublishInfo();
  }

  Future<void> _loadLastPublishInfo() async {
    final info = await FirestoreSyncService.instance.getLastPublishInfo(
      startDate: _startDate,
      endDate: _endDate,
    );
    if (info != null && mounted) {
      final publishedAt = info['publishedAt'];
      if (publishedAt != null) {
        setState(() {
          _lastPublishInfo = 'Last published: ${_formatTimestamp(publishedAt)}';
        });
      }
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is DateTime) {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year} at ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return 'Unknown';
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);

    try {
      final result = await FirestoreSyncService.instance.publishSchedule(
        startDate: _startDate,
        endDate: _endDate,
        employeeIds: _publishAll ? null : _selectedEmployeeIds.toList(),
      );

      if (mounted) {
        if (result.success) {
          // Send push notifications to employees
          if (result.publishedEmployeeUids.isNotEmpty) {
            final weekOf = '${_startDate.month}/${_startDate.day}';
            NotificationSenderService.instance
                .notifySchedulePublished(
                  employeeUids: result.publishedEmployeeUids,
                  weekOf: weekOf,
                )
                .then((notifyResult) {
                  if (notifyResult.success) {
                    debugPrint(
                      'Sent ${notifyResult.sent} schedule notifications',
                    );
                  } else {
                    debugPrint(
                      'Failed to send notifications: ${notifyResult.reason ?? notifyResult.error}',
                    );
                  }
                })
                .catchError((e) {
                  debugPrint('Error sending notifications: $e');
                });
          }
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: context.appColors.errorBackground,
            ),
          );
          setState(() => _publishing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error publishing: $e'),
            backgroundColor: context.appColors.errorBackground,
          ),
        );
        setState(() => _publishing = false);
      }
    }
  }

  Future<void> _unpublish() async {
    // Confirm before unpublishing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Unpublish'),
        content: const Text(
          'This will hide the schedule from employees in the app. '
          'The shifts will remain in the system and can be republished later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(
                ctx,
              ).extension<AppColors>()!.warningForeground,
              foregroundColor: Theme.of(
                ctx,
              ).extension<AppColors>()!.textOnError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _unpublishing = true);

    try {
      final result = await FirestoreSyncService.instance.unpublishSchedule(
        startDate: _startDate,
        endDate: _endDate,
        employeeIds: _publishAll ? null : _selectedEmployeeIds.toList(),
      );

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: context.appColors.successBackground,
            ),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: context.appColors.errorBackground,
            ),
          );
          setState(() => _unpublishing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unpublishing: $e'),
            backgroundColor: context.appColors.errorBackground,
          ),
        );
        setState(() => _unpublishing = false);
      }
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _startDate = _endDate;
          }
        }
      });
      _loadLastPublishInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud_upload, color: context.appColors.infoIcon),
          const SizedBox(width: 8),
          const Text('Publish Schedule'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Publish the schedule to make it visible in the employee app.',
              style: TextStyle(color: context.appColors.textSecondary),
            ),
            const SizedBox(height: 16),

            // Date range selector
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'From',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        '${_startDate.month}/${_startDate.day}/${_startDate.year}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'To',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        '${_endDate.month}/${_endDate.day}/${_endDate.year}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Employee selection
            CheckboxListTile(
              title: const Text('Publish for all employees'),
              value: _publishAll,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _publishAll = v ?? true),
            ),

            if (!_publishAll) ...[
              const Divider(),
              const Text(
                'Select employees:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: widget.employees.length,
                  itemBuilder: (ctx, i) {
                    final emp = widget.employees[i];
                    return CheckboxListTile(
                      title: Text(emp.displayName),
                      subtitle: Text(emp.jobCode),
                      value: _selectedEmployeeIds.contains(emp.id),
                      dense: true,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedEmployeeIds.add(emp.id!);
                          } else {
                            _selectedEmployeeIds.remove(emp.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],

            if (_lastPublishInfo != null) ...[
              const Divider(),
              Text(
                _lastPublishInfo!,
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _publishing || _unpublishing
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed:
              _publishing ||
                  _unpublishing ||
                  (!_publishAll && _selectedEmployeeIds.isEmpty)
              ? null
              : _unpublish,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.appColors.warningForeground,
          ),
          icon: _unpublishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_off),
          label: Text(_unpublishing ? 'Unpublishing...' : 'Unpublish'),
        ),
        ElevatedButton.icon(
          onPressed:
              _publishing ||
                  _unpublishing ||
                  (!_publishAll && _selectedEmployeeIds.isEmpty)
              ? null
              : _publish,
          icon: _publishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(_publishing ? 'Publishing...' : 'Publish'),
        ),
      ],
    );
  }
}
