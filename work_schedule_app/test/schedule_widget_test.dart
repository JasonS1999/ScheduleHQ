import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:work_schedule_app/database/app_database.dart';
import 'package:work_schedule_app/database/employee_dao.dart';
import 'package:work_schedule_app/pages/schedule_page.dart';
import 'package:work_schedule_app/models/employee.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await AppDatabase.instance.init(dbPath: ':memory:');
    final ed = EmployeeDao();
    await ed.insertEmployee(Employee(name: 'Alice', jobCode: 'assistant'));
    await ed.insertEmployee(Employee(name: 'Bob', jobCode: 'gm'));
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  testWidgets('weekly view shows days on Y axis, employees across, and renders shifts', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SchedulePage()));
    await tester.pump();

    await tester.runAsync(() async {
      for (int i = 0; i < 20; i++) {
        if (find.text('Alice').evaluate().isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();

    // Expect day labels like '3/15' (month/day)
    expect(find.byWidgetPredicate((w) => w is Text && RegExp(r"\d{1,2}/\d{1,2}").hasMatch(w.data ?? '')),
        findsWidgets);
    // Employees names should appear
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Bob'), findsWidgets);

    // Weekly shifts render
    expect(find.text('Shift'), findsWidgets);
  });

  testWidgets('monthly view shows day headers on X axis and renders mid-month shifts', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SchedulePage()));
    await tester.pump();

    await tester.runAsync(() async {
      for (int i = 0; i < 20; i++) {
        if (find.text('Alice').evaluate().isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    // day '1' header should be present for monthly
    expect(find.text('1'), findsWidgets);
    expect(find.text('Alice'), findsWidgets);

    // mid-month placeholder shifts should render
    expect(find.text('Shift'), findsWidgets);
  });
}
