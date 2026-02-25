import 'package:sqflite/sqflite.dart';
import '../models/employee.dart';
import '../services/auto_sync_service.dart';
import 'app_database.dart';

class EmployeeDao {
  Future<List<Employee>> getEmployees() async {
    final db = await AppDatabase.instance.db;
    final result = await db.query('employees', orderBy: 'firstName ASC');
    return result.map((row) => Employee.fromMap(row)).toList();
  }

  Future<Employee?> getById(int id) async {
    final db = await AppDatabase.instance.db;
    final result = await db.query(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Employee.fromMap(result.first);
  }

  Future<int> insertEmployee(Employee employee) async {
    final db = await AppDatabase.instance.db;
    final id = await db.insert(
      'employees',
      employee.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    // Notify auto-sync service of the change
    final insertedEmployee = employee.copyWith(id: id);
    AutoSyncService.instance.onEmployeeChanged(insertedEmployee);
    
    return id;
  }

  Future<int> updateEmployee(Employee employee) async {
    final db = await AppDatabase.instance.db;

    if (employee.id == null) {
      throw Exception("Cannot update employee without an ID");
    }

    final result = await db.update(
      'employees',
      employee.toMap(),
      where: 'id = ?',
      whereArgs: [employee.id],
    );
    
    // Notify auto-sync service of the change
    AutoSyncService.instance.onEmployeeChanged(employee);
    
    return result;
  }

  Future<int> deleteEmployee(int id) async {
    final db = await AppDatabase.instance.db;
    final result = await db.delete(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    // Notify auto-sync service of the deletion
    AutoSyncService.instance.onEmployeeDeleted(id);
    
    return result;
  }
}
