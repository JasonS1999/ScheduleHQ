import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedulehq_desktop/widgets/schedule/schedule_view.dart';
import 'package:schedulehq_desktop/models/employee.dart';

class TestHost extends StatefulWidget {
  final DateTime date;
  final List<Employee> employees;
  final ShiftPlaceholder seed;

  const TestHost({super.key, required this.date, required this.employees, required this.seed});

  @override
  State<TestHost> createState() => _TestHostState();
}

class _TestHostState extends State<TestHost> {
  late List<ShiftPlaceholder> shifts;
  Map<String, Object?>? clipboard;

  void pasteTo(int employeeId, DateTime day) {
    if (clipboard == null) return;
    final tod = clipboard!['start'] as TimeOfDay;
    final dur = clipboard!['duration'] as Duration;
    var start = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
    if (tod.hour == 0 || tod.hour == 1) start = start.add(const Duration(days: 1));
    final end = start.add(dur);
    setState(() {
      shifts.add(ShiftPlaceholder(employeeId: employeeId, start: start, end: end, text: clipboard!['text'] as String));
    });
  }

  @override
  void initState() {
    super.initState();
    shifts = [widget.seed];
  }

  @override
  Widget build(BuildContext context) {
    return WeeklyScheduleView(
      date: widget.date,
      employees: widget.employees,
      shifts: shifts,
      onCopyShift: (s) {
        clipboard = {
          'start': TimeOfDay(hour: s.start.hour, minute: s.start.minute),
          'duration': s.end.difference(s.start),
          'text': s.text,
        };
      },
      onPasteTarget: (day, employeeId) {
        if (clipboard == null) return;
        final tod = clipboard!['start'] as TimeOfDay;
        final dur = clipboard!['duration'] as Duration;
        var start = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
        if (tod.hour == 0 || tod.hour == 1) start = start.add(const Duration(days: 1));
        final end = start.add(dur);
        setState(() {
          shifts.add(ShiftPlaceholder(employeeId: employeeId, start: start, end: end, text: clipboard!['text'] as String));
        });
      },
    );
  }
}

void main() {
  testWidgets('Copy a shift and paste into another employee same time', (WidgetTester tester) async {
    final date = DateTime(2026, 1, 12); // Monday
    final employees = [Employee(id: 1, firstName: 'Alice', jobCode: 'gm'), Employee(id: 2, firstName: 'Bob', jobCode: 'assistant')];
    final shift = ShiftPlaceholder(employeeId: 1, start: DateTime(date.year, date.month, 12, 9), end: DateTime(date.year, date.month, 12, 17), text: 'Shift');

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TestHost(date: date, employees: employees, seed: shift))));
    await tester.pumpAndSettle();

    // Verify initial shift is rendered
    expect(find.textContaining('9:00'), findsOneWidget);

    // Get the TestHost state to invoke copy/paste directly
    final testHostState = tester.state<_TestHostState>(find.byType(TestHost));
    
    // Simulate copy: directly set clipboard
    testHostState.clipboard = {
      'start': TimeOfDay(hour: shift.start.hour, minute: shift.start.minute),
      'duration': shift.end.difference(shift.start),
      'text': shift.text,
    };

    // Simulate paste to Bob (employeeId: 2) on the same day
    testHostState.pasteTo(2, date);

    await tester.pumpAndSettle();

    // After paste, there should now be TWO shifts at 9:00 (one for Alice, one for Bob)
    expect(find.textContaining('9:00'), findsNWidgets(2));
  });
}
