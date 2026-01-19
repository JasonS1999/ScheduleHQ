import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/employee.dart';
import '../models/job_code_settings.dart';
import '../models/shift_runner.dart';
import '../models/shift_type.dart';
import '../models/schedule_note.dart';
import '../widgets/schedule/schedule_view.dart';

class SchedulePdfService {
  /// Build store info header for PDFs
  static pw.Widget _buildStoreHeader(String title, {String? storeName, String? storeNsn}) {
    // Build store info text inline
    String storeInfoText = '';
    if (storeName?.isNotEmpty ?? false) {
      storeInfoText = storeName!;
    }
    if (storeNsn?.isNotEmpty ?? false) {
      if (storeInfoText.isNotEmpty) {
        storeInfoText += ' $storeNsn';
      } else {
        storeInfoText = storeNsn!;
      }
    }
    
    // Build full header: "Title | Store Info"
    String fullTitle = title;
    if (storeInfoText.isNotEmpty) {
      fullTitle += ' | $storeInfoText';
    }
    
    return pw.Text(
      fullTitle,
      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
    );
  }

  /// Generate a PDF for the weekly schedule
  static Future<Uint8List> generateWeeklyPdf({
    required DateTime weekStart,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
    List<ShiftRunner> shiftRunners = const [],
    List<ShiftType> shiftTypes = const [],
    String? storeName,
    String? storeNsn,
  }) async {
    final pdf = pw.Document();

    // Calculate week end
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekTitle =
        'Manager Schedule | Week of ${_formatDate(weekStart)} - ${_formatDate(weekEnd)}';

    // Generate days for the week (Sun..Sat)
    final week = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildStoreHeader(weekTitle, storeName: storeName, storeNsn: storeNsn),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: _buildWeekTable(
                  employees: sortedEmployees,
                  week: week,
                  targetMonth: null,
                  shifts: shifts,
                  shiftRunners: shiftRunners,
                  shiftTypes: shiftTypes,
                  jobCodeSettings: jobCodeSettings,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Generate a PDF for the monthly schedule
  static Future<Uint8List> generateMonthlyPdf({
    required int year,
    required int month,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
    List<ShiftRunner> shiftRunners = const [],
    List<ShiftType> shiftTypes = const [],
    String? storeName,
    String? storeNsn,
  }) async {
    final pdf = pw.Document();

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
    final managerTitle = 'Manager Schedule | ${monthNames[month - 1]} $year';

    // Get first and last day of month
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);

    // Find Sunday before or on first day
    final startDate = firstDay.subtract(Duration(days: firstDay.weekday % 7));

    // Build weeks
    final weeks = <List<DateTime>>[];
    var currentDate = startDate;
    while (currentDate.isBefore(lastDay) || currentDate.month == month) {
      final week = List.generate(7, (i) => currentDate.add(Duration(days: i)));
      weeks.add(week);
      currentDate = currentDate.add(const Duration(days: 7));
      if (weeks.length >= 6) break;
    }

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    // Stack week tables vertically on a single page with scaling
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildStoreHeader(managerTitle, storeName: storeName, storeNsn: storeNsn),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: _buildMonthlyStackedWeekWidgets(
                    employees: sortedEmployees,
                    weeks: weeks,
                    targetMonth: month,
                    shifts: shifts,
                    shiftRunners: shiftRunners,
                    shiftTypes: shiftTypes,
                    jobCodeSettings: jobCodeSettings,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Generate a manager-style PDF for the weekly schedule (based on Excel format)
  /// Employees across the top, days down the left side, landscape orientation
  static Future<Uint8List> generateManagerWeeklyPdf({
    required DateTime weekStart,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
    List<ShiftRunner> shiftRunners = const [],
    List<ShiftType> shiftTypes = const [],
    Map<DateTime, ScheduleNote> notes = const {},
    String? storeName,
    String? storeNsn,
  }) async {
    final pdf = pw.Document();

    // Calculate week end
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekTitle =
        'Manager Schedule | Week of ${_formatDate(weekStart)} - ${_formatDate(weekEnd)}';

    // Generate days for the week (Sun..Sat)
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(12),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildStoreHeader(weekTitle, storeName: storeName, storeNsn: storeNsn),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: _buildManagerTable(
                  employees: sortedEmployees,
                  days: days,
                  shifts: shifts,
                  shiftRunners: shiftRunners,
                  shiftTypes: shiftTypes,
                  jobCodeSettings: jobCodeSettings,
                  notes: notes,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Generate a manager-style PDF for the monthly schedule (based on Excel format)
  /// Single continuous table with all days, employees across the top
  static Future<Uint8List> generateManagerMonthlyPdf({
    required int year,
    required int month,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
    List<ShiftRunner> shiftRunners = const [],
    List<ShiftType> shiftTypes = const [],
    Map<DateTime, ScheduleNote> notes = const {},
    String? storeName,
    String? storeNsn,
  }) async {
    final pdf = pw.Document();

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
    final managerTitle = 'Manager Schedule | ${monthNames[month - 1]} $year';

    // Get first and last day of month
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);

    // Find Sunday before or on first day
    final startDate = firstDay.subtract(Duration(days: firstDay.weekday % 7));

    // Build all days to display - only include weeks that contain at least one day in the target month
    final days = <DateTime>[];
    var currentDate = startDate;
    
    while (true) {
      // Build a week (Sunday to Saturday)
      final weekDays = List.generate(7, (i) => currentDate.add(Duration(days: i)));
      
      // Check if this week contains any days in the target month
      final hasTargetMonthDay = weekDays.any((d) => d.month == month);
      
      if (!hasTargetMonthDay) {
        // This week has no days in the target month, stop
        break;
      }
      
      // Add all days from this week
      days.addAll(weekDays);
      
      // Move to next week
      currentDate = currentDate.add(const Duration(days: 7));
      
      if (days.length > 42) break; // Safety limit (6 weeks)
    }

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(12),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildStoreHeader(managerTitle, storeName: storeName, storeNsn: storeNsn),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: _buildManagerTable(
                  employees: sortedEmployees,
                  days: days,
                  shifts: shifts,
                  shiftRunners: shiftRunners,
                  shiftTypes: shiftTypes,
                  jobCodeSettings: jobCodeSettings,
                  notes: notes,
                  targetMonth: month,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static List<pw.Widget> _buildMonthlyStackedWeekWidgets({
    required List<Employee> employees,
    required List<List<DateTime>> weeks,
    required int targetMonth,
    required List<ShiftPlaceholder> shifts,
    required List<ShiftRunner> shiftRunners,
    required List<ShiftType> shiftTypes,
    required List<JobCodeSettings> jobCodeSettings,
  }) {
    final children = <pw.Widget>[];

    for (final week in weeks) {
      // Skip weeks that are completely outside the target month
      final hasAnyTargetMonthDay = week.any((d) => d.month == targetMonth);
      if (!hasAnyTargetMonthDay) continue;

      children.add(
        _buildWeekTable(
          employees: employees,
          week: week,
          targetMonth: targetMonth,
          shifts: shifts,
          shiftRunners: shiftRunners,
          shiftTypes: shiftTypes,
          jobCodeSettings: jobCodeSettings,
        ),
      );
    }

    return children;
  }

  static pw.Widget _buildWeekTable({
    required List<Employee> employees,
    required List<DateTime> week,
    required int? targetMonth,
    required List<ShiftPlaceholder> shifts,
    required List<ShiftRunner> shiftRunners,
    required List<ShiftType> shiftTypes,
    required List<JobCodeSettings> jobCodeSettings,
  }) {
    final dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'];

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 8,
    );
    final cellStyle = const pw.TextStyle(fontSize: 8);

    // Build shift type color map
    final shiftTypeColorMap = <String, PdfColor>{};
    for (final st in shiftTypes) {
      shiftTypeColorMap[st.key] = _hexToPdfColor(st.colorHex);
    }

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(70), // Name
      1: const pw.FixedColumnWidth(70), // Position (job code)
      9: const pw.FixedColumnWidth(24), // HRS
    };
    // Day columns - use fixed width so FittedBox can scale properly
    for (int i = 0; i < 7; i++) {
      colWidths[2 + i] = const pw.FixedColumnWidth(60);
    }

    final rows = <pw.TableRow>[];

    // Header row - YELLOW background
    final headerColor = PdfColor.fromHex('#FFEB3B'); // Material Yellow 500
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerColor),
        children: [
          _padCell(
            pw.Text('Name', style: headerStyle),
            align: pw.Alignment.centerLeft,
            bgColor: headerColor,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
          _padCell(
            pw.Text('Position', style: headerStyle),
            align: pw.Alignment.centerLeft,
            bgColor: headerColor,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
          ...List.generate(7, (i) {
            final d = week[i];
            final label = '${dayNames[i]} ${d.month}/${d.day}';
            return _padCell(
              pw.Text(label, style: headerStyle),
              align: pw.Alignment.center,
              bgColor: headerColor,
              border: pw.Border.all(color: PdfColors.black, width: 1),
            );
          }),
          _padCell(
            pw.Text('HRS', style: headerStyle),
            align: pw.Alignment.center,
            bgColor: headerColor,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
        ],
      ),
    );

    // Build job code group map for determining when to add spacers
    final jobCodeGroupMap = <String, String?>{};
    for (final jc in jobCodeSettings) {
      jobCodeGroupMap[jc.code.toLowerCase()] = jc.sortGroup;
    }

    // Helper to get effective group key
    String getGroupKey(String jobCode) {
      final group = jobCodeGroupMap[jobCode.toLowerCase()];
      return group ?? '__ungrouped_$jobCode'; // Ungrouped codes are their own group
    }

    String? lastGroupKey;
    for (final emp in employees) {
      final jobCode = emp.jobCode;
      final currentGroupKey = getGroupKey(jobCode);

      // Only add spacer when the group changes (not just the job code)
      if (lastGroupKey != null && currentGroupKey != lastGroupKey) {
        // Spacer row between groups
        rows.add(
          pw.TableRow(
            children: List.generate(10, (_) => pw.SizedBox(height: 6)),
          ),
        );
      }
      lastGroupKey = currentGroupKey;

      final hours = _computeWeekHours(
        employeeId: emp.id,
        week: week,
        shifts: shifts,
      );

      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _padCell(
              pw.Text(emp.name, style: cellStyle),
              align: pw.Alignment.centerLeft,
            ),
            _padCell(
              pw.Text(jobCode, style: cellStyle),
              align: pw.Alignment.centerLeft,
            ),
            ...week.map((day) {
              final dayText = _formatEmployeeDayCell(
                employeeId: emp.id,
                day: day,
                shifts: shifts,
              );

              // Check if this employee is a shift runner for this day
              PdfColor? cellBgColor;
              final runnerColor = _getShiftRunnerColor(
                employeeName: emp.name,
                day: day,
                shiftRunners: shiftRunners,
                shiftTypeColorMap: shiftTypeColorMap,
              );

              if (runnerColor != null) {
                // Use a lighter version of the shift runner color for readability
                cellBgColor = _lightenPdfColor(runnerColor, 0.5);
              } else if (targetMonth != null && day.month != targetMonth) {
                cellBgColor = PdfColors.grey100;
              }

              return _padCell(
                pw.Text(dayText, style: cellStyle, maxLines: 2),
                align: pw.Alignment.center,
                bgColor: cellBgColor,
              );
            }),
            _padCell(
              pw.Text(hours == 0 ? '' : hours.toString(), style: cellStyle),
              align: pw.Alignment.center,
            ),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.5),
      ),
      child: pw.Table(
        columnWidths: colWidths,
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }

  /// Get shift runner color for an employee on a specific day
  static PdfColor? _getShiftRunnerColor({
    required String employeeName,
    required DateTime day,
    required List<ShiftRunner> shiftRunners,
    required Map<String, PdfColor> shiftTypeColorMap,
  }) {
    // Find if this employee is running any shift on this day
    final runner = shiftRunners
        .where(
          (r) =>
              r.date.year == day.year &&
              r.date.month == day.month &&
              r.date.day == day.day &&
              r.runnerName.toLowerCase() == employeeName.toLowerCase(),
        )
        .toList();

    if (runner.isEmpty) return null;

    // Return the first shift type's color (typically they'd only run one shift per day)
    return shiftTypeColorMap[runner.first.shiftType];
  }

  /// Convert hex color string to PdfColor
  static PdfColor _hexToPdfColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Add full opacity
    }
    final int value = int.parse(hex, radix: 16);
    return PdfColor(
      ((value >> 16) & 0xFF) / 255.0,
      ((value >> 8) & 0xFF) / 255.0,
      (value & 0xFF) / 255.0,
    );
  }

  /// Lighten a PdfColor by blending with white
  static PdfColor _lightenPdfColor(PdfColor color, double amount) {
    return PdfColor(
      color.red + (1.0 - color.red) * amount,
      color.green + (1.0 - color.green) * amount,
      color.blue + (1.0 - color.blue) * amount,
    );
  }

  static pw.Widget _padCell(
    pw.Widget child, {
    pw.Alignment align = pw.Alignment.center,
    PdfColor? bgColor,
    pw.Border? border,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: pw.BoxDecoration(color: bgColor, border: border),
      child: child,
    );
  }

  static pw.Widget _padCellManager(
    pw.Widget child, {
    pw.Alignment align = pw.Alignment.center,
    PdfColor? bgColor,
    pw.Border? border,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      constraints: const pw.BoxConstraints(minHeight: 18),
      decoration: pw.BoxDecoration(color: bgColor, border: border),
      child: child,
    );
  }

  static String _formatEmployeeDayCell({
    required int? employeeId,
    required DateTime day,
    required List<ShiftPlaceholder> shifts,
  }) {
    if (employeeId == null) return '';
    final dayShifts = shifts
        .where(
          (s) =>
              s.employeeId == employeeId &&
              s.start.year == day.year &&
              s.start.month == day.month &&
              s.start.day == day.day,
        )
        .toList();

    if (dayShifts.isEmpty) return '';
    return dayShifts.map((s) => _formatShiftCell(s)).join('\n');
  }

  static String _formatShiftCell(ShiftPlaceholder s) {
    if (_isLabelOnly(s.text)) {
      // For label-only shifts (OFF, PTO, VAC), include notes if present
      final label = s.text.toUpperCase();
      if (s.notes != null && s.notes!.isNotEmpty) {
        return '$label ${s.notes}';
      }
      return label;
    }

    // Special formatting for opener (4:30 AM start) and closer (1 AM end)
    final isOpener = s.start.hour == 4 && s.start.minute == 30;
    final isCloser = s.end.hour == 1 && s.end.minute == 0;

    String range;
    if (isOpener && isCloser) {
      range = 'Op-CL';
    } else if (isOpener) {
      range = 'Op-${_formatHourMinCompact(s.end)}';
    } else if (isCloser) {
      range = '${_formatHourMinCompact(s.start)}-CL';
    } else {
      range =
          '${_formatHourMinCompact(s.start)}-${_formatHourMinCompact(s.end)}';
    }

    // Append notes if present
    if (s.notes != null && s.notes!.isNotEmpty) {
      range = '$range ${s.notes}';
    }

    final label = s.text.trim();
    if (label.isEmpty) return range;

    // The UI uses "Shift" as a placeholder when creating/editing shifts.
    // In the PDF we omit this generic label and show only the time range.
    if (label.toLowerCase() == 'shift') return range;

    return '$range $label';
  }

  static int _computeWeekHours({
    required int? employeeId,
    required List<DateTime> week,
    required List<ShiftPlaceholder> shifts,
  }) {
    if (employeeId == null) return 0;
    double total = 0;
    for (final day in week) {
      final dayShifts = shifts
          .where(
            (s) =>
                s.employeeId == employeeId &&
                s.start.year == day.year &&
                s.start.month == day.month &&
                s.start.day == day.day,
          )
          .toList();
      for (final s in dayShifts) {
        if (_isLabelOnly(s.text)) continue;
        total += s.end.difference(s.start).inMinutes / 60.0;
      }
    }
    return total.round();
  }

  static List<Employee> _sortEmployees(
    List<Employee> employees,
    List<JobCodeSettings> jobCodeSettings,
  ) {
    // Build lookup maps
    final orderByCode = <String, int>{};
    final groupByCode = <String, String?>{};
    final groupOrder = <String, int>{};
    
    for (final s in jobCodeSettings) {
      orderByCode[s.code.toLowerCase()] = s.sortOrder;
      groupByCode[s.code.toLowerCase()] = s.sortGroup;
    }
    
    // Calculate group order based on the minimum sortOrder of job codes in each group
    final groupMinOrder = <String, int>{};
    for (final s in jobCodeSettings) {
      if (s.sortGroup != null) {
        final current = groupMinOrder[s.sortGroup!];
        if (current == null || s.sortOrder < current) {
          groupMinOrder[s.sortGroup!] = s.sortOrder;
        }
      }
    }
    for (final entry in groupMinOrder.entries) {
      groupOrder[entry.key] = entry.value;
    }

    final list = [...employees];
    list.sort((a, b) {
      final aCode = a.jobCode.toLowerCase();
      final bCode = b.jobCode.toLowerCase();
      final aGroup = groupByCode[aCode];
      final bGroup = groupByCode[bCode];
      final aOrder = orderByCode[aCode] ?? 999999;
      final bOrder = orderByCode[bCode] ?? 999999;
      
      // If both are in the same group (or both ungrouped), sort by job code order then name
      if (aGroup == bGroup) {
        final byOrder = aOrder.compareTo(bOrder);
        if (byOrder != 0) return byOrder;
        final byCode = aCode.compareTo(bCode);
        if (byCode != 0) return byCode;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      
      // If one is grouped and one isn't, use the group's min order vs the ungrouped order
      final aEffectiveOrder = aGroup != null ? (groupOrder[aGroup] ?? aOrder) : aOrder;
      final bEffectiveOrder = bGroup != null ? (groupOrder[bGroup] ?? bOrder) : bOrder;
      
      // Sort by effective order
      final byEffective = aEffectiveOrder.compareTo(bEffectiveOrder);
      if (byEffective != 0) return byEffective;
      
      // If same effective order, grouped items come after ungrouped at that position
      if (aGroup != null && bGroup == null) return 1;
      if (aGroup == null && bGroup != null) return -1;
      
      // Both are in different groups with same min order - use individual order
      final byOrder = aOrder.compareTo(bOrder);
      if (byOrder != 0) return byOrder;
      
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }
  
  /// Helper to determine which "super group" a job code belongs to
  /// Returns the group name if in a group, or the job code itself if ungrouped
  static String _getGroupKey(String jobCode, Map<String, String?> groupByCode) {
    final group = groupByCode[jobCode.toLowerCase()];
    return group ?? '__ungrouped__$jobCode';
  }

  static bool _isLabelOnly(String text) {
    final t = text.toLowerCase();
    return t == 'off' || t == 'pto' || t == 'vac' || t == 'req off';
  }

  static String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  static String _formatHourMinCompact(DateTime d) {
    final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    if (d.minute == 0) return '$hour';
    return '$hour:${d.minute.toString().padLeft(2, '0')}';
  }

  // ====================
  // MANAGER FORMAT METHODS
  // ====================

  /// Build a manager-style table with:
  /// - Job code header row with colors spanning employee columns
  /// - Employee names in second header row
  /// - Days down the left side
  /// - Reminders column on the right
  static pw.Widget _buildManagerTable({
    required List<Employee> employees,
    required List<DateTime> days,
    required List<ShiftPlaceholder> shifts,
    required List<ShiftRunner> shiftRunners,
    required List<ShiftType> shiftTypes,
    required List<JobCodeSettings> jobCodeSettings,
    required Map<DateTime, ScheduleNote> notes,
    int? targetMonth,
  }) {
    final dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'];
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
    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 7,
      color: PdfColors.white,
    );
    final headerStyleDark = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 7,
      color: PdfColors.black,
    );
    final cellStyle = const pw.TextStyle(fontSize: 6);
    final reminderStyle = pw.TextStyle(
      fontSize: 5,
      fontStyle: pw.FontStyle.italic,
    );

    // Build shift type color map
    final shiftTypeColorMap = <String, PdfColor>{};
    for (final st in shiftTypes) {
      shiftTypeColorMap[st.key] = _hexToPdfColor(st.colorHex);
    }

    // Build job code color map and group map
    final jobCodeColorMap = <String, PdfColor>{};
    final jobCodeGroupMap = <String, String?>{};
    for (final jc in jobCodeSettings) {
      jobCodeColorMap[jc.code.toLowerCase()] = _hexToPdfColor(jc.colorHex);
      jobCodeGroupMap[jc.code.toLowerCase()] = jc.sortGroup;
    }

    // Group employees by job code (maintaining sort order)
    final jobCodeGroups = <String, List<Employee>>{};
    final jobCodeOrder = <String>[];
    for (final emp in employees) {
      final jobCode = emp.jobCode;
      if (!jobCodeGroups.containsKey(jobCode)) {
        jobCodeGroups[jobCode] = [];
        jobCodeOrder.add(jobCode);
      }
      jobCodeGroups[jobCode]!.add(emp);
    }
    
    // Determine where gaps should go (between different super groups)
    // A super group is defined by sortGroup, or if ungrouped, the job code itself
    final gapAfterJobCode = <String, bool>{};
    for (int i = 0; i < jobCodeOrder.length - 1; i++) {
      final currentCode = jobCodeOrder[i];
      final nextCode = jobCodeOrder[i + 1];
      final currentGroup = jobCodeGroupMap[currentCode.toLowerCase()];
      final nextGroup = jobCodeGroupMap[nextCode.toLowerCase()];
      
      // Add gap if:
      // 1. Current is ungrouped (any ungrouped code gets a gap after)
      // 2. Next is ungrouped (gap before ungrouped)
      // 3. They're in different groups
      final needsGap = currentGroup == null || nextGroup == null || currentGroup != nextGroup;
      gapAfterJobCode[currentCode] = needsGap;
    }
    
    // Count actual gaps needed
    final numGaps = gapAfterJobCode.values.where((v) => v).length;

    // Calculate fixed widths for all columns
    // Page: Letter landscape = 792 points, margins = 12 each side
    // Available width = 792 - 24 = 768 points
    final availableWidth = 768.0;
    final dayColWidth = 45.0;
    final reminderColWidth = 80.0;
    final gapWidth = 3.0;
    final totalGapWidth = numGaps * gapWidth;
    final employeeAreaWidth =
        availableWidth - dayColWidth - reminderColWidth - totalGapWidth;
    final employeeColWidth = employeeAreaWidth / employees.length;

    // Build column widths using fixed widths
    final colWidths = <int, pw.TableColumnWidth>{};
    colWidths[0] = pw.FixedColumnWidth(dayColWidth);
    int colIdx = 1;
    for (int i = 0; i < jobCodeOrder.length; i++) {
      final jobCode = jobCodeOrder[i];
      final groupSize = jobCodeGroups[jobCode]!.length;
      for (int j = 0; j < groupSize; j++) {
        colWidths[colIdx++] = pw.FixedColumnWidth(employeeColWidth);
      }
      // Only add gap if gapAfterJobCode[jobCode] is true
      if (gapAfterJobCode[jobCode] == true) {
        colWidths[colIdx++] = pw.FixedColumnWidth(gapWidth);
      }
    }
    colWidths[colIdx] = pw.FixedColumnWidth(reminderColWidth);

    final rows = <pw.TableRow>[];

    // ===== ROW 1: Job Code Headers =====
    final jobCodeHeaderCells = <pw.Widget>[];
    // Empty cell for Day column (invisible)
    jobCodeHeaderCells.add(
      pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Text(''),
      ),
    );

    for (int i = 0; i < jobCodeOrder.length; i++) {
      final jobCode = jobCodeOrder[i];
      final groupSize = jobCodeGroups[jobCode]!.length;
      final jobCodeColor =
          jobCodeColorMap[jobCode.toLowerCase()] ?? PdfColors.grey400;
      final useDarkText = _isLightColor(jobCodeColor);

      final jobCodeStyle = pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontStyle: pw.FontStyle.italic,
        fontSize: 6, // Reduced by 2
        color: useDarkText ? PdfColors.black : PdfColors.white,
      );

      // Determine if this job code is at the edge of a super group
      // First in super group: either i == 0 OR the previous job code has a gap after it
      final isFirstJobCodeInSuperGroup = i == 0 || gapAfterJobCode[jobCodeOrder[i - 1]] == true;
      // Last in super group: there's a gap after this job code (or it's the last one)
      final isLastJobCodeInSuperGroup = gapAfterJobCode[jobCode] == true || i == jobCodeOrder.length - 1;

      // Create a cell for each employee with the job code text
      for (int j = 0; j < groupSize; j++) {
        final isFirstInJobCode = j == 0;
        final isLastInJobCode = j == groupSize - 1;
        
        // Thick left border only on the very first cell of the super group
        final needsThickLeft = isFirstJobCodeInSuperGroup && isFirstInJobCode;
        // Thick right border only on the very last cell of the super group
        final needsThickRight = isLastJobCodeInSuperGroup && isLastInJobCode;

        // Thick borders only on left/right edges of each super group
        final jobCodeCellBorder = pw.Border(
          left: pw.BorderSide(
            color: PdfColors.black,
            width: needsThickLeft ? 2.0 : 0,
          ),
          right: pw.BorderSide(
            color: PdfColors.black,
            width: needsThickRight ? 2.0 : 0,
          ),
          top: const pw.BorderSide(color: PdfColors.black, width: 2.0),
          bottom: const pw.BorderSide(color: PdfColors.black, width: 0.5),
        );

        jobCodeHeaderCells.add(
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            decoration: pw.BoxDecoration(
              color: jobCodeColor,
              border: jobCodeCellBorder,
            ),
            child: pw.Text(
              jobCode,
              style: jobCodeStyle,
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }

      // Gap between job code groups (only if gapAfterJobCode says so)
      if (gapAfterJobCode[jobCode] == true) {
        jobCodeHeaderCells.add(pw.Container(width: gapWidth));
      }
    }

    // Empty cell for Reminders (invisible)
    jobCodeHeaderCells.add(
      pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Text(''),
      ),
    );
    rows.add(pw.TableRow(children: jobCodeHeaderCells));

    // ===== ROW 2: Employee Names =====
    final employeeHeaderCells = <pw.Widget>[];
    // Month name in first cell of employee row
    employeeHeaderCells.add(
      _padCellManager(
        pw.Text(
          targetMonth != null ? monthNames[targetMonth - 1] : '',
          style: headerStyleDark,
        ),
        align: pw.Alignment.center,
        bgColor: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
    );

    for (int i = 0; i < jobCodeOrder.length; i++) {
      final jobCode = jobCodeOrder[i];
      final emps = jobCodeGroups[jobCode]!;
      final jobCodeColor =
          jobCodeColorMap[jobCode.toLowerCase()] ?? PdfColors.grey400;
      final useDarkText = _isLightColor(jobCodeColor);

      // Determine if this job code is at the edge of a super group
      final isFirstJobCodeInSuperGroup = i == 0 || gapAfterJobCode[jobCodeOrder[i - 1]] == true;
      final isLastJobCodeInSuperGroup = gapAfterJobCode[jobCode] == true || i == jobCodeOrder.length - 1;

      for (int j = 0; j < emps.length; j++) {
        final emp = emps[j];
        final isFirstInJobCode = j == 0;
        final isLastInJobCode = j == emps.length - 1;
        
        // Thick left border only on the very first cell of the super group
        final needsThickLeft = isFirstJobCodeInSuperGroup && isFirstInJobCode;
        // Thick right border only on the very last cell of the super group
        final needsThickRight = isLastJobCodeInSuperGroup && isLastInJobCode;

        // Thick borders only on left/right edges of each super group
        final empCellBorder = pw.Border(
          left: pw.BorderSide(
            color: PdfColors.black,
            width: needsThickLeft ? 2.0 : 0,
          ),
          right: pw.BorderSide(
            color: PdfColors.black,
            width: needsThickRight ? 2.0 : 0,
          ),
          top: const pw.BorderSide(color: PdfColors.black, width: 0.5),
          bottom: const pw.BorderSide(color: PdfColors.black, width: 0.5),
        );

        // Get just the first name
        final firstName = emp.name.split(' ').first;
        employeeHeaderCells.add(
          _padCellManager(
            pw.Text(
              firstName,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 7,
                color: useDarkText ? PdfColors.black : PdfColors.white,
              ),
              textAlign: pw.TextAlign.center,
            ),
            align: pw.Alignment.center,
            bgColor: jobCodeColor,
            border: empCellBorder,
          ),
        );
      }

      // Gap between job code groups (only if gapAfterJobCode says so)
      if (gapAfterJobCode[jobCode] == true) {
        employeeHeaderCells.add(pw.Container(width: gapWidth));
      }
    }

    employeeHeaderCells.add(
      _padCellManager(
        pw.Text(
          'Reminders',
          style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 7),
        ),
        align: pw.Alignment.center,
        bgColor: PdfColors.grey300,
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
    );
    rows.add(pw.TableRow(children: employeeHeaderCells));

    // ===== DATA ROWS: One per day =====
    for (int dayIdx = 0; dayIdx < days.length; dayIdx++) {
      final day = days[dayIdx];
      final isOutOfMonth = targetMonth != null && day.month != targetMonth;

      // Determine if this is a week boundary (Saturday = end of week)
      final isSaturday = day.weekday == 6;
      final isSunday = day.weekday == 0;
      final weekBorderWidth = 2.0;
      final normalBorderWidth = 0.5;

      final rowCells = <pw.Widget>[];

      // Day column with special coloring for weekends
      PdfColor dayBgColor;
      if (isOutOfMonth) {
        dayBgColor = PdfColors.grey300;
      } else if (day.weekday == 0) {
        // Sunday - light orange/peach
        dayBgColor = PdfColor.fromHex('#FFDAB9'); // Peach
      } else if (day.weekday == 6) {
        // Saturday - light yellow
        dayBgColor = PdfColor.fromHex('#FFFFE0'); // Light yellow
      } else {
        dayBgColor = PdfColors.white;
      }

      // Build border for day cell with thick borders at week boundaries
      final dayBorder = pw.Border(
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        top: pw.BorderSide(
          color: PdfColors.black,
          width: isSunday ? weekBorderWidth : normalBorderWidth,
        ),
        bottom: pw.BorderSide(
          color: PdfColors.black,
          width: isSaturday ? weekBorderWidth : normalBorderWidth,
        ),
      );

      rowCells.add(
        _padCellManager(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                dayNames[day.weekday % 7],
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6),
              ),
              pw.Text(
                '${day.day}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6),
              ),
            ],
          ),
          align: pw.Alignment.centerLeft,
          bgColor: dayBgColor,
          border: dayBorder,
        ),
      );

      // Employee cells
      for (int i = 0; i < jobCodeOrder.length; i++) {
        final jobCode = jobCodeOrder[i];
        final emps = jobCodeGroups[jobCode]!;
        
        // Determine if this job code is at the edge of a super group
        final isFirstJobCodeInSuperGroup = i == 0 || gapAfterJobCode[jobCodeOrder[i - 1]] == true;
        final isLastJobCodeInSuperGroup = gapAfterJobCode[jobCode] == true || i == jobCodeOrder.length - 1;

        for (int empIdx = 0; empIdx < emps.length; empIdx++) {
          final emp = emps[empIdx];
          final isFirstInJobCode = empIdx == 0;
          final isLastInJobCode = empIdx == emps.length - 1;
          
          // Thick left border only on the very first cell of the super group
          final needsThickLeft = isFirstJobCodeInSuperGroup && isFirstInJobCode;
          // Thick right border only on the very last cell of the super group
          final needsThickRight = isLastJobCodeInSuperGroup && isLastInJobCode;

          final dayText = _formatEmployeeDayCell(
            employeeId: emp.id,
            day: day,
            shifts: shifts,
          );

          // Default to white background
          PdfColor? cellBgColor = PdfColors.white;

          // Check if this employee is a shift runner for this day
          final runnerColor = _getShiftRunnerColor(
            employeeName: emp.name,
            day: day,
            shiftRunners: shiftRunners,
            shiftTypeColorMap: shiftTypeColorMap,
          );

          if (runnerColor != null) {
            cellBgColor = _lightenPdfColor(runnerColor, 0.4);
          } else if (isOutOfMonth) {
            cellBgColor = PdfColors.grey200;
          }

          // Format display text - convert OFF to "-"
          String displayText = dayText;
          if (dayText.toUpperCase() == 'OFF') {
            displayText = '-';
            // No color fill for OFF (keep white background)
          } else if (dayText.toUpperCase() == 'VAC') {
            cellBgColor = PdfColor.fromHex('#F4B183'); // Orange like Excel
          } else if (dayText.toUpperCase() == 'PTO') {
            cellBgColor = PdfColor.fromHex('#A9D08E'); // Light green
          } else if (dayText.toUpperCase() == 'ETO') {
            cellBgColor = PdfColor.fromHex('#D9D9D9'); // Light grey for ETO
          }

          // Build border with thick borders around each week's cells per super group
          // Thick left/right on super group edges, thick top on Sunday, thick bottom on Saturday
          final cellBorder = pw.Border(
            left: pw.BorderSide(
              color: PdfColors.black,
              width: needsThickLeft ? weekBorderWidth : 0,
            ),
            right: pw.BorderSide(
              color: PdfColors.black,
              width: needsThickRight ? weekBorderWidth : 0,
            ),
            top: pw.BorderSide(
              color: PdfColors.black,
              width: isSunday ? weekBorderWidth : 0,
            ),
            bottom: pw.BorderSide(
              color: PdfColors.black,
              width: isSaturday ? weekBorderWidth : 0,
            ),
          );

          rowCells.add(
            _padCellManager(
              pw.Text(
                displayText,
                style: cellStyle,
                maxLines: 2,
                textAlign: pw.TextAlign.center,
              ),
              align: pw.Alignment.center,
              bgColor: cellBgColor,
              border: cellBorder,
            ),
          );
        }

        // Gap between job code groups (only if gapAfterJobCode says so)
        if (gapAfterJobCode[jobCode] == true) {
          rowCells.add(pw.Container(width: gapWidth));
        }
      }

      // Reminders column with week border
      final normalizedDay = DateTime(day.year, day.month, day.day);
      final note = notes[normalizedDay];
      final reminderBorder = pw.Border(
        left: pw.BorderSide(color: PdfColors.grey400, width: normalBorderWidth),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        top: pw.BorderSide(
          color: PdfColors.black,
          width: isSunday ? weekBorderWidth : normalBorderWidth,
        ),
        bottom: pw.BorderSide(
          color: PdfColors.black,
          width: isSaturday ? weekBorderWidth : normalBorderWidth,
        ),
      );
      rowCells.add(
        _padCellManager(
          pw.Text(note?.note ?? '', style: reminderStyle, maxLines: 2),
          align: pw.Alignment.centerLeft,
          bgColor: isOutOfMonth ? PdfColors.grey200 : null,
          border: reminderBorder,
        ),
      );

      rows.add(pw.TableRow(children: rowCells));
    }

    return pw.Table(
      columnWidths: colWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  static String _monthNameShort(int month) {
    const names = [
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
    return names[month - 1];
  }

  static bool _isLightColor(PdfColor color) {
    // Calculate relative luminance
    final luminance =
        0.299 * color.red + 0.587 * color.green + 0.114 * color.blue;
    return luminance > 0.5;
  }

  /// Print the schedule directly
  static Future<void> printSchedule(Uint8List pdfBytes, String title) async {
    await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: title);
  }

  /// Share/save the PDF
  static Future<void> sharePdf(Uint8List pdfBytes, String filename) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }
}
