import 'package:flutter/material.dart';
import '../database/employee_dao.dart';
import '../models/employee.dart';
import '../database/job_code_settings_dao.dart';
import '../models/job_code_settings.dart';
import '../services/firestore_sync_service.dart';
import 'employee_availability_page.dart';
import 'weekly_template_dialog.dart';
import '../widgets/csv_import_dialog.dart';

final JobCodeSettingsDao _jobCodeDao = JobCodeSettingsDao();
List<JobCodeSettings> _jobCodes = [];

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  final EmployeeDao _employeeDao = EmployeeDao();
  List<Employee> _employees = [];
  bool _isSyncingAccounts = false;

  void _sortEmployeesInRosterOrder(List<Employee> list) {
    if (list.isEmpty) return;

    final orderByJobCodeLower = <String, int>{
      for (final jc in _jobCodes) jc.code.toLowerCase(): jc.sortOrder,
    };

    int orderFor(String jobCode) => orderByJobCodeLower[jobCode.toLowerCase()] ?? 999999;

    list.sort((a, b) {
      final aOrder = orderFor(a.jobCode);
      final bOrder = orderFor(b.jobCode);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);

      final jobCodeCmp = a.jobCode.toLowerCase().compareTo(b.jobCode.toLowerCase());
      if (jobCodeCmp != 0) return jobCodeCmp;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  void _resortIfPossible() {
    if (!mounted) return;
    if (_employees.isEmpty) return;
    final sorted = List<Employee>.from(_employees);
    _sortEmployeesInRosterOrder(sorted);
    setState(() => _employees = sorted);
  }

  @override
  void initState() {
    super.initState();
    _loadJobCodes();
    _loadEmployees();
  }

  Future<void> _loadJobCodes() async {
    // Ensure defaults exist, then load them
    await _jobCodeDao.insertDefaultsIfMissing();
    final codes = await _jobCodeDao.getAll();
    setState(() => _jobCodes = codes);
    _resortIfPossible();
  }

  Future<void> _loadEmployees() async {
    // Adjust this to match your actual DAO method
    final list = await _employeeDao.getEmployees();
    final sorted = List<Employee>.from(list);
    _sortEmployeesInRosterOrder(sorted);
    setState(() => _employees = sorted);
  }

  Future<void> _addEmployee() async {
    String name = "";
    String jobCode = _jobCodes.isNotEmpty ? _jobCodes.first.code : "Assistant";
    String? email;
    int vacationAllowed = 0;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Employee"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Name *",
                    hintText: "Required",
                  ),
                  onChanged: (v) => name = v,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Email (for employee app login)",
                    hintText: "employee@example.com",
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => email = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: jobCode,
                  decoration: const InputDecoration(labelText: "Job Code"),
                  items: _jobCodes
                      .map(
                        (jc) => DropdownMenuItem(
                          value: jc.code,
                          child: Text(jc.code),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      jobCode = v;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Vacation Weeks Allowed",
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    vacationAllowed = int.tryParse(v) ?? 0;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (name.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required')),
                  );
                  return;
                }

                final newEmployee = Employee(
                  firstName: name.trim(),
                  jobCode: jobCode,
                  email: email,
                  vacationWeeksAllowed: vacationAllowed,
                  vacationWeeksUsed: 0,
                );
                final id = await _employeeDao.insertEmployee(newEmployee);
                
                // Sync to Firestore
                try {
                  await FirestoreSyncService.instance.syncEmployee(
                    newEmployee.copyWith(id: id),
                  );
                } catch (e) {
                  // Log error but don't block - sync can happen later
                  debugPrint('Failed to sync employee to Firestore: $e');
                }
                
                if (!mounted) return;
                Navigator.of(this.context).pop();
                await _loadEmployees();
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editEmployee(Employee e) async {
    String name = e.firstName ?? '';
    String jobCode = e.jobCode;
    String? email = e.email;
    int vacationAllowed = e.vacationWeeksAllowed;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Employee"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Name *",
                    hintText: "Required",
                  ),
                  controller: TextEditingController(text: name),
                  onChanged: (v) => name = v,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: "Email (for employee app login)",
                    hintText: "employee@example.com",
                    helperText: e.uid != null 
                        ? "Account created ✓" 
                        : "Add email to enable employee app access",
                    helperStyle: TextStyle(
                      color: e.uid != null ? Colors.green : null,
                    ),
                  ),
                  controller: TextEditingController(text: email ?? ''),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => email = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: jobCode,
                  decoration: const InputDecoration(labelText: "Job Code"),
                  items: _jobCodes
                      .map(
                        (jc) => DropdownMenuItem(
                          value: jc.code,
                          child: Text(jc.code),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      jobCode = value;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Vacation Weeks Allowed",
                  ),
                  controller: TextEditingController(
                    text: vacationAllowed.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    vacationAllowed = int.tryParse(v) ?? e.vacationWeeksAllowed;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (name.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required')),
                  );
                  return;
                }
                
                final updatedEmployee = e.copyWith(
                  firstName: name.trim(),
                  jobCode: jobCode,
                  email: email,
                  vacationWeeksAllowed: vacationAllowed,
                );
                await _employeeDao.updateEmployee(updatedEmployee);
                
                // Sync to Firestore
                try {
                  await FirestoreSyncService.instance.syncEmployee(updatedEmployee);
                } catch (err) {
                  debugPrint('Failed to sync employee to Firestore: $err');
                }
                
                if (!mounted) return;
                Navigator.of(this.context).pop();
                await _loadEmployees();
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteEmployee(Employee e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Employee"),
          content: Text("Remove ${e.displayName}?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm == true && e.id != null) {
      await _employeeDao.deleteEmployee(e.id!);
      
      // Sync deletion to Firestore
      try {
        await FirestoreSyncService.instance.deleteEmployee(e.id!);
      } catch (err) {
        debugPrint('Failed to delete employee from Firestore: $err');
      }
      
      await _loadEmployees();
    }
  }

  Future<void> _showImportDialog() async {
    final importedCount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CsvImportDialog(),
    );

    if (importedCount != null && importedCount > 0) {
      await _loadEmployees();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $importedCount employee${importedCount == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// Sync employee accounts with Firebase Auth via Cloud Function.
  /// Creates Firebase Auth accounts for employees and updates local UIDs.
  Future<void> _syncEmployeeAccounts() async {
    setState(() => _isSyncingAccounts = true);
    
    try {
      // First sync all employee data to Firestore
      await FirestoreSyncService.instance.syncAllEmployees();
      
      // Then sync accounts (create Firebase Auth accounts for employees)
      final result = await FirestoreSyncService.instance.syncAllEmployeeAccounts();
      
      if (!mounted) return;
      
      final processed = result['processed'] ?? 0;
      final created = result['created'] ?? 0;
      final updated = result['updated'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      final errors = result['errors'] ?? 0;
      
      String message;
      if (created > 0 || updated > 0) {
        message = 'Synced $processed employees: $created created, $updated updated';
        if (skipped > 0) message += ', $skipped skipped';
        if (errors > 0) message += ', $errors errors';
      } else if (processed == 0) {
        message = 'No employees found to sync';
      } else {
        message = 'All $processed employees already synced';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: errors > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      
      // Reload employees to show any changes
      await _loadEmployees();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sync accounts: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingAccounts = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Roster"),
        actions: [
          IconButton(
            icon: _isSyncingAccounts 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync),
            tooltip: 'Sync Employee Accounts',
            onPressed: _isSyncingAccounts ? null : _syncEmployeeAccounts,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import from CSV',
            onPressed: _showImportDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEmployee,
        child: const Icon(Icons.add),
      ),
      body: _employees.isEmpty
          ? const Center(child: Text("No employees yet"))
          : ListView.builder(
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final e = _employees[index];
                return ListTile(
                  title: Text(e.displayName),
                  subtitle: Text(
                    "${e.jobCode} • Vacation Weeks: ${e.vacationWeeksAllowed}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_view_week, size: 16),
                        label: const Text('Weekly Template'),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => WeeklyTemplateDialog(employee: e),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Availability'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EmployeeAvailabilityPage(employee: e),
                            ),
                          ).then((_) => _loadEmployees());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editEmployee(e),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteEmployee(e),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
