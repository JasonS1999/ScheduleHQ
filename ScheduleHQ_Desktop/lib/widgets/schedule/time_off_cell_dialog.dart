import 'package:flutter/material.dart';
import '../../models/time_off_entry.dart';
import '../../services/app_colors.dart';

/// Compact add/edit dialog for time-off entries from the schedule grid.
///
/// Field visibility depends on type:
///   - **PTO**: hours only
///   - **Vacation**: start date + end date only
///   - **Requested Off**: all-day toggle + time range (if not all-day)
///
/// Returns a `Map<String, dynamic>` with keys:
///   - `timeOffType` (String): 'pto', 'vacation', or 'requested'
///   - `hours` (int)
///   - `isAllDay` (bool)
///   - `startTime` (String?): "HH:mm" or null
///   - `endTime` (String?): "HH:mm" or null
///   - `startDate` (DateTime): for vacation range
///   - `endDate` (DateTime): for vacation range
class TimeOffCellDialog extends StatefulWidget {
  final String employeeName;
  final DateTime date;
  final TimeOffEntry? existingEntry; // null = add mode

  const TimeOffCellDialog({
    super.key,
    required this.employeeName,
    required this.date,
    this.existingEntry,
  });

  @override
  State<TimeOffCellDialog> createState() => _TimeOffCellDialogState();
}

class _TimeOffCellDialogState extends State<TimeOffCellDialog> {
  late String _selectedType;
  late int _hours;
  late bool _isAllDay;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late DateTime _vacStartDate;
  late DateTime _vacEndDate;

  bool get _isEdit => widget.existingEntry != null;

  @override
  void initState() {
    super.initState();
    _vacStartDate = widget.date;
    _vacEndDate = widget.date;

    if (_isEdit) {
      final entry = widget.existingEntry!;
      _selectedType = _normalizeType(entry.timeOffType);
      _hours = entry.hours > 0 ? entry.hours : 8;
      _isAllDay = entry.isAllDay;
      _startTime = _parseTime(entry.startTime) ?? const TimeOfDay(hour: 9, minute: 0);
      _endTime = _parseTime(entry.endTime) ?? const TimeOfDay(hour: 17, minute: 0);
      _vacStartDate = entry.date;
      _vacEndDate = entry.endDate ?? entry.date;
    } else {
      _selectedType = 'requested';
      _hours = 8;
      _isAllDay = true;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 17, minute: 0);
    }
  }

  String _normalizeType(String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'vac' || lower == 'vacation') return 'vacation';
    if (lower == 'pto') return 'pto';
    return 'requested';
  }

  TimeOfDay? _parseTime(String? time) {
    if (time == null || time.isEmpty) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$mm $suffix';
  }

  String _timeOfDayToString(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _vacStartDate : _vacEndDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _vacStartDate = picked;
          if (_vacEndDate.isBefore(_vacStartDate)) {
            _vacEndDate = _vacStartDate;
          }
        } else {
          _vacEndDate = picked;
          if (_vacStartDate.isAfter(_vacEndDate)) {
            _vacStartDate = _vacEndDate;
          }
        }
      });
    }
  }

  bool _validate() {
    if (_selectedType == 'pto') {
      return _hours >= 1 && _hours <= 24;
    } else if (_selectedType == 'vacation') {
      return !_vacEndDate.isBefore(_vacStartDate);
    } else {
      // requested
      if (!_isAllDay) {
        final startMin = _startTime.hour * 60 + _startTime.minute;
        final endMin = _endTime.hour * 60 + _endTime.minute;
        if (startMin == endMin) return false;
      }
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dateLabel =
        '${dayNames[widget.date.weekday - 1]}, '
        '${months[widget.date.month - 1]} ${widget.date.day}';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEdit ? Icons.edit_calendar : Icons.event_busy,
            color: context.appColors.infoIcon,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_isEdit ? 'Edit Time Off' : 'Add Time Off'),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee + date display
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, size: 18, color: context.appColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.employeeName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.calendar_today, size: 16, color: context.appColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Type dropdown
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'pto', child: Text('PTO')),
                DropdownMenuItem(value: 'vacation', child: Text('Vacation')),
                DropdownMenuItem(value: 'requested', child: Text('Requested Off')),
              ],
              onChanged: (v) => setState(() => _selectedType = v ?? 'requested'),
            ),
            const SizedBox(height: 12),

            // --- PTO: hours only ---
            if (_selectedType == 'pto')
              TextFormField(
                key: const ValueKey('pto_hours'),
                initialValue: _hours.toString(),
                decoration: const InputDecoration(
                  labelText: 'Hours',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null && parsed >= 1 && parsed <= 24) {
                    _hours = parsed;
                  }
                },
              ),

            // --- Vacation: start date + end date ---
            if (_selectedType == 'vacation') ...[
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Start Date',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: Text(_formatDate(_vacStartDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'End Date',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: Text(_formatDate(_vacEndDate)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_vacEndDate.difference(_vacStartDate).inDays + 1} day(s)',
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textSecondary,
                ),
              ),
            ],

            // --- Requested Off: all-day toggle + time pickers ---
            if (_selectedType == 'requested') ...[
              SwitchListTile(
                title: const Text('All Day'),
                value: _isAllDay,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (v) => setState(() => _isAllDay = v),
              ),
              if (!_isAllDay) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: Text(_formatTimeOfDay(_startTime)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: Text(_formatTimeOfDay(_endTime)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_validate()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter valid values')),
              );
              return;
            }

            final result = <String, dynamic>{
              'timeOffType': _selectedType,
            };

            if (_selectedType == 'pto') {
              result['hours'] = _hours;
              result['isAllDay'] = true;
            } else if (_selectedType == 'vacation') {
              result['startDate'] = _vacStartDate;
              result['endDate'] = _vacEndDate;
              result['hours'] = 8;
              result['isAllDay'] = true;
            } else {
              // requested
              result['hours'] = 8;
              result['isAllDay'] = _isAllDay;
              if (!_isAllDay) {
                result['startTime'] = _timeOfDayToString(_startTime);
                result['endTime'] = _timeOfDayToString(_endTime);
              }
            }

            Navigator.pop(context, result);
          },
          child: Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
