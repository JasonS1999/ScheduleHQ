import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/employee.dart';
import '../models/job_code_settings.dart';
import '../widgets/schedule/schedule_view.dart';

class SchedulePdfService {
  /// Generate a PDF for the weekly schedule
  static Future<Uint8List> generateWeeklyPdf({
    required DateTime weekStart,
    required List<Employee> employees,
    required List<ShiftPlaceholder> shifts,
    List<JobCodeSettings> jobCodeSettings = const [],
  }) async {
    final pdf = pw.Document();
    
    // Calculate week end
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekTitle = 'Week of ${_formatDate(weekStart)} - ${_formatDate(weekEnd)}';
    
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
  }) async {
    final pdf = pw.Document();
    
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
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
  }) {
    final dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'];

    final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8);
    final cellStyle = const pw.TextStyle(fontSize: 8);

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

    // Header row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _padCell(
            pw.Text('Name', style: headerStyle),
            align: pw.Alignment.centerLeft,
            bgColor: PdfColors.grey300,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
          _padCell(
            pw.Text('Position', style: headerStyle),
            align: pw.Alignment.centerLeft,
            bgColor: PdfColors.grey300,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
          ...List.generate(7, (i) {
            final d = week[i];
            final label = '${dayNames[i]} ${d.month}/${d.day}';
            return _padCell(
              pw.Text(label, style: headerStyle),
              align: pw.Alignment.center,
              bgColor: PdfColors.grey300,
              border: pw.Border.all(color: PdfColors.black, width: 1),
            );
          }),
          _padCell(
            pw.Text('HRS', style: headerStyle),
            align: pw.Alignment.center,
            bgColor: PdfColors.grey300,
            border: pw.Border.all(color: PdfColors.black, width: 1),
          ),
        ],
      ),
    );

    String? lastJobCode;
    for (final emp in employees) {
      final jobCode = emp.jobCode;

      if (lastJobCode != null && jobCode.toLowerCase() != lastJobCode.toLowerCase()) {
        // Spacer row between job codes
        rows.add(
          pw.TableRow(
            children: List.generate(10, (_) => pw.SizedBox(height: 6)),
          ),
        );
      }
      lastJobCode = jobCode;

      final hours = _computeWeekHours(employeeId: emp.id, week: week, shifts: shifts);

      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _padCell(pw.Text(emp.name, style: cellStyle), align: pw.Alignment.centerLeft),
            _padCell(pw.Text(jobCode, style: cellStyle), align: pw.Alignment.centerLeft),
            ...week.map((day) {
              final dayText = _formatEmployeeDayCell(
                employeeId: emp.id,
                day: day,
                shifts: shifts,
              );
              return _padCell(
                pw.Text(dayText, style: cellStyle, maxLines: 2),
                align: pw.Alignment.center,
                bgColor: (targetMonth != null && day.month != targetMonth) ? PdfColors.grey100 : null,
              );
            }),
            _padCell(pw.Text(hours == 0 ? '' : hours.toString(), style: cellStyle), align: pw.Alignment.center),
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

  static pw.Widget _padCell(
    pw.Widget child, {
    pw.Alignment align = pw.Alignment.center,
    PdfColor? bgColor,
    pw.Border? border,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: pw.BoxDecoration(
        color: bgColor,
        border: border,
      ),
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
        .where((s) =>
            s.employeeId == employeeId &&
            s.start.year == day.year &&
            s.start.month == day.month &&
            s.start.day == day.day)
        .toList();

    if (dayShifts.isEmpty) return '';
    return dayShifts.map((s) => _formatShiftCell(s)).join('\n');
  }

  static String _formatShiftCell(ShiftPlaceholder s) {
    if (_isLabelOnly(s.text)) {
      return s.text.toUpperCase();
    }

    final range = '${_formatHourMinCompact(s.start)}-${_formatHourMinCompact(s.end)}';
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
          .where((s) =>
              s.employeeId == employeeId &&
              s.start.year == day.year &&
              s.start.month == day.month &&
              s.start.day == day.day)
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

  /// Print the schedule directly
  static Future<void> printSchedule(Uint8List pdfBytes, String title) async {
    await Printing.layoutPdf(
      onLayout: (_) => pdfBytes,
      name: title,
    );
  }

  /// Share/save the PDF
  static Future<void> sharePdf(Uint8List pdfBytes, String filename) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }
}
