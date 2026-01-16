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
    
    // Day names
    final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    
    // Generate days for the week
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final sortedEmployees = _sortEmployees(employees, jobCodeSettings);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              weekTitle,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${_formatDateTime(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          _buildScheduleTable(sortedEmployees, days, dayNames, shifts),
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
    final monthTitle = '${monthNames[month - 1]} $year Schedule';
    
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              monthTitle,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${_formatDateTime(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          _buildMonthlyStackedWeeks(
            employees: sortedEmployees,
            weeks: weeks,
            targetMonth: month,
            shifts: shifts,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildScheduleTable(
    List<Employee> employees,
    List<DateTime> days,
    List<String> dayNames,
    List<ShiftPlaceholder> shifts,
  ) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 40,
      headers: [
        'Employee',
        ...days.map((d) => '${dayNames[d.weekday % 7]}\n${d.month}/${d.day}'),
      ],
      data: employees.map((emp) {
        return [
          emp.name,
          ...days.map((day) {
            final dayShifts = shifts.where((s) =>
              s.employeeId == emp.id &&
              s.start.year == day.year &&
              s.start.month == day.month &&
              s.start.day == day.day
            ).toList();
            
            if (dayShifts.isEmpty) return '';
            
            return dayShifts.map((s) => _formatShiftCell(s)).join('\n');
          }),
        ];
      }).toList(),
    );
  }

  static pw.Widget _buildMonthlyStackedWeeks({
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

      final weekStart = week.first;
      final weekEnd = week.last;
      children.add(
        pw.Text(
          '${_formatDate(weekStart)} - ${_formatDate(weekEnd)}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      );
      children.add(pw.SizedBox(height: 4));
      children.add(
        _buildWeekTable(
          employees: employees,
          week: week,
          targetMonth: targetMonth,
          shifts: shifts,
        ),
      );
      children.add(pw.SizedBox(height: 12));
    }

    return pw.Column(children: children);
  }

  static pw.Widget _buildWeekTable({
    required List<Employee> employees,
    required List<DateTime> week,
    required int targetMonth,
    required List<ShiftPlaceholder> shifts,
  }) {
    final dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'];

    final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7);
    final cellStyle = const pw.TextStyle(fontSize: 7);

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(80), // Name
      1: const pw.FixedColumnWidth(90), // Position (job code)
      9: const pw.FixedColumnWidth(28), // HRS
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
          _padCell(pw.Text('Name', style: headerStyle), align: pw.Alignment.centerLeft),
          _padCell(pw.Text('Position', style: headerStyle), align: pw.Alignment.centerLeft),
          ...List.generate(7, (i) {
            final d = week[i];
            final label = '${dayNames[i]} ${d.month}/${d.day}';
            return _padCell(pw.Text(label, style: headerStyle), align: pw.Alignment.center);
          }),
          _padCell(pw.Text('HRS', style: headerStyle), align: pw.Alignment.center),
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
                targetMonth: targetMonth,
                shifts: shifts,
              );
              return _padCell(
                pw.Text(dayText, style: cellStyle, maxLines: 2),
                align: pw.Alignment.center,
                bgColor: day.month != targetMonth ? PdfColors.grey100 : null,
              );
            }),
            _padCell(pw.Text(hours == 0 ? '' : hours.toString(), style: cellStyle), align: pw.Alignment.center),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  static pw.Widget _padCell(
    pw.Widget child, {
    pw.Alignment align = pw.Alignment.center,
    PdfColor? bgColor,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      color: bgColor,
      child: child,
    );
  }

  static String _formatEmployeeDayCell({
    required int? employeeId,
    required DateTime day,
    required int targetMonth,
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
  
  static String _formatDateTime(DateTime d) => 
    '${d.month}/${d.day}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

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
