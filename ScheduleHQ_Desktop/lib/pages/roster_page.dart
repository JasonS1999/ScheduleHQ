import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/employee_provider.dart';
import '../providers/job_code_provider.dart';
import '../models/job_code_settings.dart';
import '../models/job_code_group.dart';
import '../services/app_colors.dart';
import '../widgets/common/loading_indicator.dart';
import '../widgets/common/error_message.dart';
import '../widgets/common/confirmation_dialog.dart';
import '../utils/snackbar_helper.dart';
import '../utils/loading_state_mixin.dart';
import '../models/employee.dart';
import '../services/firestore_sync_service.dart';
import 'employee_availability_page.dart';
import 'weekly_template_dialog.dart';
import '../widgets/csv_import_dialog.dart';
import '../widgets/common/employee_avatar.dart';

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> with LoadingStateMixin {

  @override
  void initState() {
    super.initState();
    // Initialize providers if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    if (employeeProvider.isIdle) {
      await employeeProvider.initialize();
    }
    final jobCodeProvider = Provider.of<JobCodeProvider>(
      context,
      listen: false,
    );
    if (jobCodeProvider.isIdle) {
      await jobCodeProvider.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Roster'),
        actions: [
          // Sync accounts button
          Consumer<EmployeeProvider>(
            builder: (context, employeeProvider, child) {
              return IconButton(
                onPressed: employeeProvider.isLoading ? null : _syncAccounts,
                icon: const Icon(Icons.sync),
                tooltip: 'Sync Employee Accounts',
              );
            },
          ),

          // Add employee button
          IconButton(
            onPressed: _showAddEmployeeDialog,
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Employee',
          ),

          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import_csv',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Import from CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<EmployeeProvider>(
        builder: (context, employeeProvider, child) {
          if (employeeProvider.isLoading && employeeProvider.items.isEmpty) {
            return const LoadingIndicator(
              message: 'Loading employee roster...',
              showCard: true,
            );
          }

          if (employeeProvider.hasError && employeeProvider.items.isEmpty) {
            return ErrorMessage.generic(
              message:
                  employeeProvider.errorMessage ?? 'Failed to load employees',
              onRetry: () => employeeProvider.refresh(),
            );
          }

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search employees...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) => employeeProvider.setSearchQuery(query),
                ),
              ),

              // Employee stats
              if (employeeProvider.items.isNotEmpty)
                _buildEmployeeStats(employeeProvider),

              // Employee table
              Expanded(child: _buildEmployeeTable(employeeProvider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmployeeStats(EmployeeProvider employeeProvider) {
    final stats = employeeProvider.getEmployeeStats();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total', stats['total'].toString()),
          _buildStatItem('With Email', stats['withEmail'].toString()),
          _buildStatItem('Vacation Weeks', stats['totalVacationWeeks'].toString()),
          if (employeeProvider.isSearching)
            _buildStatItem('Filtered', stats['filtered'].toString()),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Color _colorFromHex(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  Color _resolveJobCodeColor(String jobCode) {
    final jobCodeProvider = context.watch<JobCodeProvider>();
    final codes = jobCodeProvider.codes;
    final groups = jobCodeProvider.groups;

    final settings = codes.cast<JobCodeSettings?>().firstWhere(
      (s) => s != null && s.code.toLowerCase() == jobCode.toLowerCase(),
      orElse: () => null,
    );

    if (settings != null && settings.sortGroup != null) {
      final group = groups.cast<JobCodeGroup?>().firstWhere(
        (g) => g != null && g.name == settings.sortGroup,
        orElse: () => null,
      );
      if (group != null) {
        return _colorFromHex(group.colorHex);
      }
    }

    final hex = settings?.colorHex;
    if (hex == null || hex.trim().isEmpty) {
      return Theme.of(context).colorScheme.primary;
    }
    return _colorFromHex(hex);
  }

  Widget _buildEmployeeTable(EmployeeProvider employeeProvider) {
    if (employeeProvider.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: context.appColors.textTertiary,
            ),
            SizedBox(height: 16),
            Text(
              'No employees found',
              style: TextStyle(
                fontSize: 18,
                color: context.appColors.textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add your first employee to get started',
              style: TextStyle(color: context.appColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Job Code')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Expanded(child: Center(child: Text('Vacation')))),
          DataColumn(label: Expanded(child: Center(child: Text('Actions')))),
        ],
        rows: employeeProvider.items.map((employee) {
          final bg = _resolveJobCodeColor(employee.jobCode);
          final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
              ? Colors.white
              : Colors.black;
          return DataRow(
            onSelectChanged: (_) => _showEditEmployeeDialog(employee),
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmployeeAvatar(
                      name: employee.displayName,
                      imageUrl: employee.profileImageURL,
                      radius: 16,
                      jobCode: employee.jobCode,
                    ),
                    const SizedBox(width: 8),
                    Text(employee.displayName),
                  ],
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    employee.jobCode,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              DataCell(Text(employee.email ?? 'No email')),
              DataCell(
                Center(
                  child: Text(
                    '${employee.vacationWeeksAllowed} weeks',
                  ),
                ),
              ),
              DataCell(
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showWeeklyTemplateForEmployee(employee),
                        icon: const Icon(Icons.calendar_view_week),
                        tooltip: 'Weekly Template',
                      ),
                      IconButton(
                        onPressed: () => _showAvailabilityPage(employee),
                        icon: const Icon(Icons.calendar_today),
                        tooltip: 'View Availability',
                      ),
                      IconButton(
                        onPressed: () => _deleteEmployee(employee),
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete Employee',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
        ),
      ),
    );
  }

  Future<void> _syncAccounts() async {
    await withLoading(() async {
      try {
        await FirestoreSyncService.instance.syncAllEmployeeAccounts();
        if (mounted) {
          SnackBarHelper.showSuccess(
            context,
            'Employee accounts synced successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Failed to sync accounts: $e');
        }
      }
    });
  }

  Future<void> _showAddEmployeeDialog() async {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    final jobCodesToSuggestions = employeeProvider.getJobCodeSuggestions();

    String firstName = '';
    String jobCode = jobCodesToSuggestions.isNotEmpty
        ? jobCodesToSuggestions.first
        : 'Assistant';
    String? email;
    int vacationWeeksAllowed = 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EmployeeFormDialog(
        title: 'Add Employee',
        initialFirstName: firstName,
        initialJobCode: jobCode,
        initialEmail: email,
        initialVacationWeeks: vacationWeeksAllowed,
        jobCodeSuggestions: jobCodesToSuggestions,
        onSave: (data) {
          firstName = data['firstName'];
          jobCode = data['jobCode'];
          email = data['email'];
          vacationWeeksAllowed = data['vacationWeeks'];
        },
      ),
    );

    if (result == true) {
      // Validate input
      final validationErrors = employeeProvider.validateEmployee(
        firstName: firstName,
        jobCode: jobCode,
        email: email,
      );

      if (validationErrors.isNotEmpty) {
        SnackBarHelper.showError(context, validationErrors.first);
        return;
      }

      // Check if name is unique
      if (!employeeProvider.isNameUnique(firstName)) {
        SnackBarHelper.showError(
          context,
          'An employee with this name already exists',
        );
        return;
      }

      // Create employee
      final success = await employeeProvider.createEmployee(
        firstName: firstName,
        jobCode: jobCode,
        email: email,
        vacationWeeksAllowed: vacationWeeksAllowed,
      );

      if (success) {
        SnackBarHelper.showSuccess(context, 'Employee added successfully');
      } else {
        SnackBarHelper.showError(
          context,
          employeeProvider.errorMessage ?? 'Failed to add employee',
        );
      }
    }
  }

  Future<void> _showEditEmployeeDialog(Employee employee) async {
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    final jobCodeSuggestions = employeeProvider.getJobCodeSuggestions();

    String firstName = employee.firstName ?? '';
    String jobCode = employee.jobCode;
    String? email = employee.email;
    int vacationWeeksAllowed = employee.vacationWeeksAllowed;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EmployeeFormDialog(
        title: 'Edit Employee',
        initialFirstName: firstName,
        initialJobCode: jobCode,
        initialEmail: email,
        initialVacationWeeks: vacationWeeksAllowed,
        jobCodeSuggestions: jobCodeSuggestions,
        onSave: (data) {
          firstName = data['firstName'];
          jobCode = data['jobCode'];
          email = data['email'];
          vacationWeeksAllowed = data['vacationWeeks'];
        },
      ),
    );

    if (result == true) {
      // Validate input
      final validationErrors = employeeProvider.validateEmployee(
        firstName: firstName,
        jobCode: jobCode,
        email: email,
      );

      if (validationErrors.isNotEmpty) {
        SnackBarHelper.showError(context, validationErrors.first);
        return;
      }

      // Check if name is unique (excluding current employee)
      if (!employeeProvider.isNameUnique(firstName, excludeId: employee.id)) {
        SnackBarHelper.showError(
          context,
          'An employee with this name already exists',
        );
        return;
      }

      // Update employee
      final success = await employeeProvider.updateEmployee(
        employee,
        firstName: firstName,
        jobCode: jobCode,
        email: email,
        vacationWeeksAllowed: vacationWeeksAllowed,
      );

      if (success) {
        SnackBarHelper.showSuccess(context, 'Employee updated successfully');
      } else {
        SnackBarHelper.showError(
          context,
          employeeProvider.errorMessage ?? 'Failed to update employee',
        );
      }
    }
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirmed = await ConfirmationDialog.showDelete(
      context: context,
      title: 'Delete Employee',
      message:
          'Are you sure you want to delete ${employee.displayName}? This action cannot be undone.',
    );

    if (confirmed) {
      final employeeProvider = Provider.of<EmployeeProvider>(
        context,
        listen: false,
      );
      final success = await employeeProvider.deleteEmployee(employee);

      if (success) {
        SnackBarHelper.showSuccess(context, 'Employee deleted successfully');
      } else {
        SnackBarHelper.showError(
          context,
          employeeProvider.errorMessage ?? 'Failed to delete employee',
        );
      }
    }
  }

  void _showAvailabilityPage(Employee employee) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EmployeeAvailabilityPage(employee: employee),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'import_csv':
        _showImportDialog();
        break;
    }
  }

  Future<void> _showImportDialog() async {
    await showDialog(
      context: context,
      builder: (context) => const CsvImportDialog(),
    );

    // Refresh data after import
    final employeeProvider = Provider.of<EmployeeProvider>(
      context,
      listen: false,
    );
    await employeeProvider.refresh();
  }

  Future<void> _showWeeklyTemplateForEmployee(Employee employee) async {
    await showDialog(
      context: context,
      builder: (context) => WeeklyTemplateDialog(employee: employee),
    );
  }
}

/// Dialog for adding/editing employee information
class _EmployeeFormDialog extends StatefulWidget {
  final String title;
  final String initialFirstName;
  final String initialJobCode;
  final String? initialEmail;
  final int initialVacationWeeks;
  final List<String> jobCodeSuggestions;
  final Function(Map<String, dynamic>) onSave;

  const _EmployeeFormDialog({
    required this.title,
    required this.initialFirstName,
    required this.initialJobCode,
    required this.initialEmail,
    required this.initialVacationWeeks,
    required this.jobCodeSuggestions,
    required this.onSave,
  });

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _vacationController;
  late String _jobCode;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.initialFirstName);
    _emailController = TextEditingController(text: widget.initialEmail);
    _vacationController = TextEditingController(
      text: widget.initialVacationWeeks.toString(),
    );
    _jobCode = widget.initialJobCode;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _emailController.dispose();
    _vacationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  hintText: 'Required',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (for employee app login)',
                  hintText: 'employee@example.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: widget.jobCodeSuggestions.contains(_jobCode)
                    ? _jobCode
                    : null,
                decoration: const InputDecoration(labelText: 'Job Code'),
                items: widget.jobCodeSuggestions
                    .map(
                      (code) =>
                          DropdownMenuItem(value: code, child: Text(code)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _jobCode = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _vacationController,
                decoration: const InputDecoration(
                  labelText: 'Vacation Weeks Allowed',
                  hintText: '0',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final firstName = _firstNameController.text.trim();
            if (firstName.isEmpty) {
              SnackBarHelper.showError(context, 'First name is required');
              return;
            }

            widget.onSave({
              'firstName': firstName,
              'jobCode': _jobCode,
              'email': _emailController.text.trim().isNotEmpty
                  ? _emailController.text.trim()
                  : null,
              'vacationWeeks': int.tryParse(_vacationController.text) ?? 0,
            });

            Navigator.of(context).pop(true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
