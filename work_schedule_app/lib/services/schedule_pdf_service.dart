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
  /// Generate a PDF for the weekly schedule
  static Future<Uint8List> generateWeeklyPdf({
    required DateTime weekStart,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
    List<ShiftRunner> shiftRunners = const [],
    List<ShiftType> shiftTypes = const [],
  }) async {
    final pdf = pw.Document();

    // Calculate week end
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekTitle =
        'Week of ${_formatDate(weekStart)} - ${_formatDate(weekEnd)}';

    // Generate days for the week (Sun..Sat)
    final week = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              weekTitle,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          _buildWeekTable(
            employees: sortedEmployees,
            week: week,
            targetMonth: null,
            shifts: shifts,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
          ),
        ],
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
    final managerTitle = '${monthNames[month - 1]} $year Manager Schedule';

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

    // Stack week tables vertically; allow MultiPage to paginate naturally.
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(16),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              managerTitle,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => _buildMonthlyStackedWeekWidgets(
          employees: sortedEmployees,
          weeks: weeks,
          targetMonth: month,
          shifts: shifts,
          shiftRunners: shiftRunners,
          shiftTypes: shiftTypes,
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
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(12),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              weekTitle,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) => [
          _buildManagerTable(
            employees: sortedEmployees,
            days: days,
            shifts: shifts,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            jobCodeSettings: jobCodeSettings,
            notes: notes,
          ),
        ],
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
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(12),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              managerTitle,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) => [
          _buildManagerTable(
            employees: sortedEmployees,
            days: days,
            shifts: shifts,
            shiftRunners: shiftRunners,
            shiftTypes: shiftTypes,
            jobCodeSettings: jobCodeSettings,
            notes: notes,
            targetMonth: month,
          ),
        ],
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
    // Day columns
    for (int i = 0; i < 7; i++) {
      colWidths[2 + i] = const pw.FlexColumnWidth(1);
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

    String? lastJobCode;
    for (final emp in employees) {
      final jobCode = emp.jobCode;

      if (lastJobCode != null &&
          jobCode.toLowerCase() != lastJobCode.toLowerCase()) {
        // Spacer row between job codes
        rows.add(
          pw.TableRow(
            children: List.generate(10, (_) => pw.SizedBox(height: 6)),
          ),
        );
      }
      lastJobCode = jobCode;

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
    final orderByCode = <String, int>{};
    for (final s in jobCodeSettings) {
      orderByCode[s.code.toLowerCase()] = s.sortOrder;
    }

    final list = [...employees];
    list.sort((a, b) {
      final ao = orderByCode[a.jobCode.toLowerCase()] ?? 999999;
      final bo = orderByCode[b.jobCode.toLowerCase()] ?? 999999;
      final byOrder = ao.compareTo(bo);
      if (byOrder != 0) return byOrder;

      final byCode = a.jobCode.toLowerCase().compareTo(b.jobCode.toLowerCase());
      if (byCode != 0) return byCode;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
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

    // Build job code color map
    final jobCodeColorMap = <String, PdfColor>{};
    for (final jc in jobCodeSettings) {
      jobCodeColorMap[jc.code.toLowerCase()] = _hexToPdfColor(jc.colorHex);
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

    // Calculate fixed widths for all columns
    // Page: Letter landscape = 792 points, margins = 12 each side
    // Available width = 792 - 24 = 768 points
    final availableWidth = 768.0;
    final dayColWidth = 45.0;
    final reminderColWidth = 80.0;
    final gapWidth = 3.0;
    final numGaps = jobCodeOrder.length - 1;
    final totalGapWidth = numGaps * gapWidth;
    final employeeAreaWidth =
        availableWidth - dayColWidth - reminderColWidth - totalGapWidth;
    final employeeColWidth = employeeAreaWidth / employees.length;

    // Build column widths using fixed widths
    final colWidths = <int, pw.TableColumnWidth>{};
    colWidths[0] = pw.FixedColumnWidth(dayColWidth);
    int colIdx = 1;
    for (int i = 0; i < jobCodeOrder.length; i++) {
      final groupSize = jobCodeGroups[jobCodeOrder[i]]!.length;
      for (int j = 0; j < groupSize; j++) {
        colWidths[colIdx++] = pw.FixedColumnWidth(employeeColWidth);
      }
      if (i < jobCodeOrder.length - 1) {
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

      // Create a cell for each employee with the job code text
      for (int j = 0; j < groupSize; j++) {
        final isFirstInGroup = j == 0;
        final isLastInGroup = j == groupSize - 1;

        // Thick borders only on left/right edges of each job code group
        final jobCodeCellBorder = pw.Border(
          left: pw.BorderSide(
            color: PdfColors.black,
            width: isFirstInGroup ? 2.0 : 0,
          ),
          right: pw.BorderSide(
            color: PdfColors.black,
            width: isLastInGroup ? 2.0 : 0,
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

      // Gap between job code groups
      if (i < jobCodeOrder.length - 1) {
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

      for (int j = 0; j < emps.length; j++) {
        final emp = emps[j];
        final isFirstInGroup = j == 0;
        final isLastInGroup = j == emps.length - 1;

        // Thick borders only on left/right edges of each job code group
        final empCellBorder = pw.Border(
          left: pw.BorderSide(
            color: PdfColors.black,
            width: isFirstInGroup ? 2.0 : 0,
          ),
          right: pw.BorderSide(
            color: PdfColors.black,
            width: isLastInGroup ? 2.0 : 0,
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

      if (i < jobCodeOrder.length - 1) {
        employeeHeaderCells.add(pw.Container(width: 3));
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

        for (int empIdx = 0; empIdx < emps.length; empIdx++) {
          final emp = emps[empIdx];
          final isFirstInGroup = empIdx == 0;
          final isLastInGroup = empIdx == emps.length - 1;

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

          // Build border with thick borders around each week's cells per job code group
          // Thick left/right on job code group edges, thick top on Sunday, thick bottom on Saturday
          final cellBorder = pw.Border(
            left: pw.BorderSide(
              color: PdfColors.black,
              width: isFirstInGroup ? weekBorderWidth : 0,
            ),
            right: pw.BorderSide(
              color: PdfColors.black,
              width: isLastInGroup ? weekBorderWidth : 0,
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

        if (i < jobCodeOrder.length - 1) {
          rowCells.add(pw.Container(width: 3));
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
