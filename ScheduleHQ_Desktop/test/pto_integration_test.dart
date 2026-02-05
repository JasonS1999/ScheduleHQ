import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedulehq_desktop/database/app_database.dart';
import 'package:schedulehq_desktop/database/time_off_dao.dart';
import 'package:schedulehq_desktop/database/employee_dao.dart';
import 'package:schedulehq_desktop/services/pto_trimester_service.dart';
import 'package:schedulehq_desktop/models/employee.dart';
import 'package:schedulehq_desktop/models/time_off_entry.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await AppDatabase.instance.init(dbPath: ':memory:');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('pto added as full day is counted in trimester summary', () async {
    final employeeDao = EmployeeDao();
    final timeOffDao = TimeOffDao();
    final ptoService = PtoTrimesterService(timeOffDao: timeOffDao);

    final id = await employeeDao.insertEmployee(Employee(firstName: 'PTO', lastName: 'Tester', jobCode: 'assistant'));

    const ptoHours = 9; // Hardcoded default hours per PTO request

    final now = DateTime.now();
    final ptoDate = DateTime(now.year, 3, 3);

    await timeOffDao.insertTimeOff(TimeOffEntry(id: null, employeeId: id, date: ptoDate, timeOffType: 'pto', hours: ptoHours, vacationGroupId: null));

    final summaries = await ptoService.calculateTrimesterSummaries(id);

    expect(summaries[0].used, ptoHours);
  });

  test('multi-day PTO blocked if not enough remaining in trimester', () async {
    final employeeDao = EmployeeDao();
    final timeOffDao = TimeOffDao();
    final ptoService = PtoTrimesterService(timeOffDao: timeOffDao);

    final id = await employeeDao.insertEmployee(Employee(firstName: 'PTO', lastName: 'Insufficient', jobCode: 'assistant'));

    const hoursPerDay = 9; // Hardcoded default hours per PTO request

    final now = DateTime.now();
    final startDate = DateTime(now.year, 3, 1);

    final days = 4; // 4 * 9 = 36 > default 30 earned
    final requestedHours = days * hoursPerDay;

    final remaining = await ptoService.getRemainingForDate(id, startDate);

    expect(remaining < requestedHours, isTrue);
  });

  test('multi-day PTO allowed when enough remaining and consumed by inserts', () async {
    final employeeDao = EmployeeDao();
    final timeOffDao = TimeOffDao();
    final ptoService = PtoTrimesterService(timeOffDao: timeOffDao);

    final id = await employeeDao.insertEmployee(Employee(firstName: 'PTO', lastName: 'Allowed', jobCode: 'assistant'));

    const hoursPerDay = 9; // Hardcoded default hours per PTO request

    final now = DateTime.now();
    final startDate = DateTime(now.year, 3, 1);

    final days = 3; // 3 * 9 = 27 <= default 30
    final requestedHours = days * hoursPerDay;

    final remaining = await ptoService.getRemainingForDate(id, startDate);
    expect(remaining >= requestedHours, isTrue);

    final groupId = 'test-group-pto';
    for (int i = 0; i < days; i++) {
      await timeOffDao.insertTimeOff(TimeOffEntry(id: null, employeeId: id, date: startDate.add(Duration(days: i)), timeOffType: 'pto', hours: hoursPerDay, vacationGroupId: groupId));
    }

    final used = await timeOffDao.getPtoUsedInRange(id, startDate, DateTime(now.year, 4, 30));
    expect(used, requestedHours);
  });
}

