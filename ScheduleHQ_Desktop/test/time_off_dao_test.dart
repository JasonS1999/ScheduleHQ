import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedulehq_desktop/database/app_database.dart';
import 'package:schedulehq_desktop/database/time_off_dao.dart';
import 'package:schedulehq_desktop/database/employee_dao.dart';
import 'package:schedulehq_desktop/models/employee.dart';
import 'package:schedulehq_desktop/models/time_off_entry.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late TimeOffDao timeOffDao;
  late EmployeeDao employeeDao;

  setUp(() async {
    // Use in-memory database for tests
    await AppDatabase.instance.init(dbPath: ':memory:');
    timeOffDao = TimeOffDao();
    employeeDao = EmployeeDao();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('insert multi-day vacation and delete group', () async {
    final emp = Employee(firstName: 'Alice', jobCode: 'assistant');
    final id = await employeeDao.insertEmployee(emp);

    final start = DateTime(2026, 1, 10);

    // Insert three-day vacation (manually via dao)
    final groupId = 'group-1';
    for (int i = 0; i < 3; i++) {
      final entry = TimeOffEntry(id: null, employeeId: id, date: start.add(Duration(days: i)), timeOffType: 'vac', hours: 8, vacationGroupId: groupId);
      await timeOffDao.insertTimeOff(entry);
    }

    final monthEntries = await timeOffDao.getAllTimeOffForMonth(2026, 1);
    expect(monthEntries.where((e) => e.vacationGroupId == groupId).length, 3);

    // Deleting the group should remove all 3
    await timeOffDao.deleteVacationGroup(groupId);
    final after = await timeOffDao.getAllTimeOffForMonth(2026, 1);
    expect(after.where((e) => e.vacationGroupId == groupId).isEmpty, true);
  });

  test('hasTimeOffInRange detects overlap', () async {
    final emp = Employee(firstName: 'Bob', jobCode: 'assistant');
    final id = await employeeDao.insertEmployee(emp);

    final start = DateTime(2026, 2, 1);
    final groupId = 'g2';
    for (int i = 0; i < 2; i++) {
      final entry = TimeOffEntry(id: null, employeeId: id, date: start.add(Duration(days: i)), timeOffType: 'vac', hours: 8, vacationGroupId: groupId);
      await timeOffDao.insertTimeOff(entry);
    }

    final has = await timeOffDao.hasTimeOffInRange(id, start.add(const Duration(days: 1)), start.add(const Duration(days: 1)));
    expect(has, true);

    final notHas = await timeOffDao.hasTimeOffInRange(id, DateTime(2026, 3, 1), DateTime(2026, 3, 2));
    expect(notHas, false);
  });

  test('getTimeOffInRange returns entries for conflicts', () async {
    final emp = Employee(firstName: 'Charlie', jobCode: 'assistant');
    final id = await employeeDao.insertEmployee(emp);

    final start = DateTime(2026, 4, 10);
    final g = 'g3';
    await timeOffDao.insertTimeOff(TimeOffEntry(id: null, employeeId: id, date: start, timeOffType: 'vac', hours: 8, vacationGroupId: g));
    await timeOffDao.insertTimeOff(TimeOffEntry(id: null, employeeId: id, date: start.add(const Duration(days: 1)), timeOffType: 'pto', hours: 8, vacationGroupId: null));

    final conflicts = await timeOffDao.getTimeOffInRange(id, start, start.add(const Duration(days: 1)));
    expect(conflicts.length, 2);
    expect(conflicts.map((c) => c.timeOffType).toSet(), containsAll(['vac', 'pto']));
  });
}
