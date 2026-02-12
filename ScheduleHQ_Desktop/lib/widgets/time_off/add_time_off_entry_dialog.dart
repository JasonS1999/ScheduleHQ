import 'package:flutter/material.dart';
import '../../database/time_off_dao.dart';
import '../../models/employee.dart';
import '../../models/settings.dart';
import '../../models/time_off_entry.dart';
import '../../providers/approval_provider.dart';
import '../../providers/time_off_provider.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/snackbar_helper.dart';

class AddTimeOffEntryDialog extends StatefulWidget {
  final List<Employee> employees;
  final ApprovalProvider approvalProvider;
  final TimeOffProvider timeOffProvider;
  final Settings settings;

  const AddTimeOffEntryDialog({
    super.key,
    required this.employees,
    required this.approvalProvider,
    required this.timeOffProvider,
    required this.settings,
  });

  @override
  State<AddTimeOffEntryDialog> createState() => _AddTimeOffEntryDialogState();
}

class _AddTimeOffEntryDialogState extends State<AddTimeOffEntryDialog> {
  int? _selectedEmployeeId;
  String _selectedType = 'pto';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isAllDay = true;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _hoursController = TextEditingController(text: '8');
  bool _isSubmitting = false;

  bool get _isValid =>
      _selectedEmployeeId != null &&
      _startDate != null &&
      _hoursController.text.isNotEmpty &&
      int.tryParse(_hoursController.text) != null &&
      int.parse(_hoursController.text) > 0;

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXLarge),
      ),
      title: Row(
        children: [
          Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          const Text('Add Time Off Entry'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Employee dropdown
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Employee'),
                value: _selectedEmployeeId,
                isExpanded: true,
                items: widget.employees.map((e) {
                  return DropdownMenuItem<int>(
                    value: e.id,
                    child: Text(e.displayName),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedEmployeeId = value),
              ),
              const SizedBox(height: 16),

              // Type dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Type'),
                value: _selectedType,
                items: const [
                  DropdownMenuItem(value: 'pto', child: Text('PTO')),
                  DropdownMenuItem(value: 'vacation', child: Text('Vacation')),
                  DropdownMenuItem(value: 'requested', child: Text('Requested')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _selectedType = value);
                },
              ),
              const SizedBox(height: 16),

              // Date pickers
              Row(
                children: [
                  Expanded(
                    child: _DatePickerField(
                      label: 'Start Date',
                      value: _startDate,
                      onChanged: (date) => setState(() => _startDate = date),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DatePickerField(
                      label: 'End Date (optional)',
                      value: _endDate,
                      onChanged: (date) => setState(() => _endDate = date),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // All day toggle
              SwitchListTile(
                title: const Text('All Day'),
                value: _isAllDay,
                onChanged: (value) => setState(() => _isAllDay = value),
                contentPadding: EdgeInsets.zero,
              ),

              // Time pickers (if not all day)
              if (!_isAllDay) ...[
                Row(
                  children: [
                    Expanded(
                      child: _TimePickerField(
                        label: 'Start Time',
                        value: _startTime,
                        onChanged: (time) =>
                            setState(() => _startTime = time),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _TimePickerField(
                        label: 'End Time',
                        value: _endTime,
                        onChanged: (time) => setState(() => _endTime = time),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Hours
              TextFormField(
                controller: _hoursController,
                decoration: const InputDecoration(labelText: 'Hours'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid && !_isSubmitting ? _handleSubmit : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Entry'),
        ),
      ],
    );
  }

  String? _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return null;
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _handleSubmit() async {
    setState(() => _isSubmitting = true);

    try {
      final entry = TimeOffEntry(
        id: null,
        employeeId: _selectedEmployeeId!,
        date: _startDate!,
        endDate: _endDate,
        timeOffType: _selectedType,
        hours: int.parse(_hoursController.text),
        isAllDay: _isAllDay,
        startTime: _isAllDay ? null : _formatTimeOfDay(_startTime),
        endTime: _isAllDay ? null : _formatTimeOfDay(_endTime),
      );

      final employee = widget.employees.firstWhere(
        (e) => e.id == _selectedEmployeeId,
      );

      // Check for conflicts
      final hasConflict = await TimeOffDao().hasTimeOffInRange(
        entry.employeeId,
        entry.date,
        entry.endDate ?? entry.date,
      );

      if (hasConflict && mounted) {
        final proceed = await DialogHelper.showConfirmDialog(
          context,
          title: 'Conflict Detected',
          message:
              'This employee already has time off scheduled in this date range. Add anyway?',
          confirmText: 'Add Anyway',
          icon: Icons.warning,
        );
        if (!proceed) {
          setState(() => _isSubmitting = false);
          return;
        }
      }

      final success =
          await widget.approvalProvider.addManualEntry(entry, employee);

      if (mounted) {
        if (success) {
          SnackBarHelper.showSuccess(context, 'Time-off entry added');
          Navigator.pop(context, true);
        } else {
          SnackBarHelper.showError(
            context,
            widget.approvalProvider.errorMessage ?? 'Failed to add entry',
          );
          setState(() => _isSubmitting = false);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Error: $e');
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = value != null
        ? '${value!.month}/${value!.day}/${value!.year}'
        : '';

    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      readOnly: true,
      controller: TextEditingController(text: displayText),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(DateTime.now().year - 1),
          lastDate: DateTime(DateTime.now().year + 2),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onChanged;

  const _TimePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = value != null ? value!.format(context) : '';

    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.access_time, size: 18),
      ),
      readOnly: true,
      controller: TextEditingController(text: displayText),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 9, minute: 0),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
