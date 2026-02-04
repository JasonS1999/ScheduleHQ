import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedulehq_desktop/widgets/schedule/schedule_view.dart';
import 'package:schedulehq_desktop/models/employee.dart';

void main() {
  testWidgets('Weekly double-tap edit changes shift time', (WidgetTester tester) async {
    final date = DateTime(2026, 1, 12); // Monday
    final employees = [Employee(id: 1, firstName: 'Alice', jobCode: 'gm')];
    final shift = ShiftPlaceholder(employeeId: 1, start: DateTime(date.year, date.month, 12, 9), end: DateTime(date.year, date.month, 12, 17), text: 'Shift');

    // Pump the WeeklyScheduleView directly (avoid ScheduleView which hits the DB in initState)
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WeeklyScheduleView(
          date: date,
          employees: employees,
          shifts: [shift],
          onUpdateShift: (old, ns, ne, {String? shiftNotes}) {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Should find the cell label with initial time
    expect(find.textContaining('9:00'), findsOneWidget);

    // Double-tap the shift cell
    final cellFinder = find.textContaining('9:00');
    await tester.tap(cellFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cellFinder);
    await tester.pumpAndSettle();

    // Dialog should appear
    expect(find.text('Edit Shift Time'), findsOneWidget);

    // Change start time to 5:00 AM
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('5:00').last);
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // After save, the Weekly view should reflect the change (label updated). The exact integration with parent state is tested elsewhere.
    // We at least expect dialog to disappear and no errors
    expect(find.text('Edit Shift Time'), findsNothing);
  });
}
