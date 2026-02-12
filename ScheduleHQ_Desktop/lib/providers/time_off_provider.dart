import 'package:flutter/foundation.dart';
import '../database/time_off_dao.dart';
import '../database/pto_history_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/employee.dart';
import '../models/time_off_entry.dart';
import '../models/job_code_settings.dart';
import '../models/settings.dart';
import 'base_provider.dart';

class TimeOffProvider extends BaseProvider {
  final TimeOffDao _timeOffDao = TimeOffDao();
  final PtoHistoryDao _ptoHistoryDao = PtoHistoryDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();

  List<TimeOffEntry> _allEntries = [];
  List<TimeOffEntry> _rawEntries = [];
  List<JobCodeSettings> _jobCodeSettings = [];

  List<TimeOffEntry> get allEntries => List.unmodifiable(_allEntries);
  List<TimeOffEntry> get rawEntries => List.unmodifiable(_rawEntries);
  List<JobCodeSettings> get jobCodeSettings => List.unmodifiable(_jobCodeSettings);

  /// Load all time-off data
  Future<void> loadData() async {
    await executeWithLoading(() async {
      final entries = await _timeOffDao.getAllTimeOff();
      final rawEntries = await _timeOffDao.getAllTimeOffRaw();
      final jobCodeSettings = await _jobCodeSettingsDao.getAll();

      _allEntries = entries;
      _rawEntries = rawEntries;
      _jobCodeSettings = jobCodeSettings;
    });
  }

  /// Check if an employee's job code has PTO enabled
  bool hasPtoEnabled(Employee employee) {
    final jobCodeLower = employee.jobCode.toLowerCase();
    final setting = _jobCodeSettings.firstWhere(
      (jc) => jc.code.toLowerCase() == jobCodeLower,
      orElse: () => JobCodeSettings(
        code: employee.jobCode,
        hasPTO: false,
        colorHex: '#808080',
      ),
    );
    return setting.hasPTO;
  }

  /// Get employees with PTO enabled
  List<Employee> getPtoEnabledEmployees(List<Employee> employees) {
    final ptoEnabledCodes = _jobCodeSettings
        .where((jc) => jc.hasPTO)
        .map((jc) => jc.code.toLowerCase())
        .toSet();
    
    return employees
        .where((e) => ptoEnabledCodes.contains(e.jobCode.toLowerCase()))
        .toList();
  }

  /// Calculate trimester start date
  DateTime getTrimesterStart(DateTime date) {
    final y = date.year;
    final m = date.month;

    if (m >= 1 && m <= 4) return DateTime(y, 1, 1);
    if (m >= 5 && m <= 8) return DateTime(y, 5, 1);
    return DateTime(y, 9, 1);
  }

  /// Get trimester date ranges for a year
  List<Map<String, dynamic>> getTrimesterRanges(int year) {
    return [
      {
        "label": "Trimester 1",
        "start": DateTime(year, 1, 1),
        "end": DateTime(year, 4, 30),
      },
      {
        "label": "Trimester 2",
        "start": DateTime(year, 5, 1),
        "end": DateTime(year, 8, 31),
      },
      {
        "label": "Trimester 3",
        "start": DateTime(year, 9, 1),
        "end": DateTime(year, 12, 31),
      },
    ];
  }

  /// Calculate PTO summary for an employee
  Future<Map<String, dynamic>> calculatePto(Employee employee, Settings settings) async {
    try {
      final now = DateTime.now();
      final trimesterStart = getTrimesterStart(now);

      final history = await _ptoHistoryDao.ensureHistoryRecord(
        employeeId: employee.id ?? 0,
        trimesterStart: trimesterStart,
      );

      // PTO entries using new schema - sum actual hours
      final usedHours = _allEntries
          .where((entry) {
            if (entry.employeeId != employee.id) return false;
            if (entry.timeOffType != "pto") return false;
            return getTrimesterStart(entry.date) == trimesterStart;
          })
          .fold(0, (sum, entry) => sum + entry.hours);

      final isFirstTrimester =
          trimesterStart.month == 1 && trimesterStart.day == 1;

      int carryover;
      if (isFirstTrimester) {
        carryover = 0;
      } else {
        final unused =
            (settings.ptoHoursPerTrimester + history.carryoverHours) -
            usedHours;

        carryover = unused > 0
            ? unused.clamp(0, settings.maxCarryoverHours)
            : 0;
      }

      final remaining = (settings.ptoHoursPerTrimester + carryover) - usedHours;

      return {
        'allowance': settings.ptoHoursPerTrimester,
        'carryover': carryover,
        'used': usedHours,
        'remaining': remaining,
      };
    } catch (e) {
      debugPrint("PTO calc error: $e");
      return {'allowance': 0, 'carryover': 0, 'used': 0, 'remaining': 0};
    }
  }

  /// Calculate trimester summaries for PTO breakdown
  List<TrimesterSummary> calculateTrimesterSummaries(Employee employee, Settings settings, {int? year}) {
    if (employee.id == null) {
      return [];
    }

    final int earnedPerTrimester = settings.ptoHoursPerTrimester; // should be 30
    const int maxCap = 40; // hard cap per your rule
    final int maxCarryover = settings.maxCarryoverHours; // should be 10

    final yr = year ?? DateTime.now().year;
    final trimesters = getTrimesterRanges(yr);

    int carryover = 0;
    final List<TrimesterSummary> summaries = [];

    for (final t in trimesters) {
      final label = t['label'] as String;
      final start = t['start'] as DateTime;
      final end = t['end'] as DateTime;

      // Sum actual PTO hours in this trimester
      final usedHours = _allEntries
          .where((entry) {
            if (entry.employeeId != employee.id) return false;
            if (entry.timeOffType != "pto") return false;
            final d = entry.date;
            return !d.isBefore(start) && !d.isAfter(end);
          })
          .fold(0, (sum, entry) => sum + entry.hours);

      // Available = earned + carryover, capped at 40
      int available = earnedPerTrimester + carryover;
      if (available > maxCap) available = maxCap;

      final remaining = available - usedHours;

      int carryoverOut = 0;
      if (remaining > 0) {
        carryoverOut = remaining;
        if (carryoverOut > maxCarryover) {
          carryoverOut = maxCarryover;
        }
      }

      summaries.add(
        TrimesterSummary(
          label: label,
          start: start,
          end: end,
          earned: earnedPerTrimester,
          carryoverIn: carryover,
          available: available,
          used: usedHours,
          remaining: remaining,
          carryoverOut: carryoverOut,
        ),
      );

      carryover = carryoverOut;
    }

    return summaries;
  }

  /// Calculate vacation weeks used for an employee
  int getVacationWeeksUsed(Employee employee) {
    try {
      final vacationEntries = _allEntries
          .where((e) => e.employeeId == employee.id && e.timeOffType == 'vacation')
          .toList();

      // Group by vacationGroupId, count days per group
      final groups = <String, int>{};
      for (final entry in vacationEntries) {
        final groupId = entry.vacationGroupId;
        if (groupId != null) {
          groups[groupId] = (groups[groupId] ?? 0) + 1;
        }
      }

      int vacationWeeks = 0;
      for (final dayCount in groups.values) {
        if (dayCount >= 5) {
          vacationWeeks += (dayCount / 5).floor();
        }
      }
      return vacationWeeks;
    } catch (e) {
      debugPrint("Vacation weeks calculation error: $e");
      return 0;
    }
  }

  /// Calculate remaining vacation weeks for an employee
  int getVacationWeeksRemaining(Employee employee) {
    final used = getVacationWeeksUsed(employee);
    final allowed = employee.vacationWeeksAllowed;
    return (allowed - used).clamp(0, allowed);
  }

  @override
  Future<void> refresh() async {
    await loadData();
  }
}

/// Data class for trimester summary information
class TrimesterSummary {
  final String label;
  final DateTime start;
  final DateTime end;
  final int earned; // typically 30
  final int carryoverIn; // from previous trimester
  final int available; // earned + carryoverIn, capped at 40
  final int used; // PTO used in this trimester (hours)
  final int remaining; // available - used
  final int carryoverOut; // min(remaining, maxCarryover)

  TrimesterSummary({
    required this.label,
    required this.start,
    required this.end,
    required this.earned,
    required this.carryoverIn,
    required this.available,
    required this.used,
    required this.remaining,
    required this.carryoverOut,
  });
}