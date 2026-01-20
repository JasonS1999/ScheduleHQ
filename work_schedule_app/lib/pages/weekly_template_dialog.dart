import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/weekly_template.dart';
import '../database/weekly_template_dao.dart';

class WeeklyTemplateDialog extends StatefulWidget {
  final Employee employee;

  const WeeklyTemplateDialog({super.key, required this.employee});

  @override
  State<WeeklyTemplateDialog> createState() => _WeeklyTemplateDialogState();
}

class _WeeklyTemplateDialogState extends State<WeeklyTemplateDialog> {
  final WeeklyTemplateDao _dao = WeeklyTemplateDao();
  
  // Template entries for each day (0 = Sunday, 6 = Saturday)
  late List<WeeklyTemplateEntry> _entries;
  bool _isLoading = true;

  static const List<String> _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  @override
  void initState() {
    super.initState();
    _initializeEntries();
    _loadTemplate();
  }

  void _initializeEntries() {
    // Create blank entries for all 7 days
    _entries = List.generate(
      7,
      (dayOfWeek) => WeeklyTemplateEntry(
        employeeId: widget.employee.id!,
        dayOfWeek: dayOfWeek,
      ),
    );
  }

  Future<void> _loadTemplate() async {
    final existingEntries = await _dao.getTemplateForEmployee(widget.employee.id!);
    
    setState(() {
      // Merge existing entries with blank entries
      for (final entry in existingEntries) {
        _entries[entry.dayOfWeek] = entry;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveTemplate() async {
    // Only save entries that have a shift or are marked as off
    final entriesToSave = _entries.where((e) => e.hasShift || e.isOff).toList();
    
    await _dao.saveWeekTemplate(widget.employee.id!, entriesToSave);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekly template saved')),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _clearTemplate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Template'),
        content: const Text('Are you sure you want to clear all template entries for this employee?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dao.deleteTemplateForEmployee(widget.employee.id!);
      _initializeEntries();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template cleared')),
        );
      }
    }
  }

  void _updateEntry(int dayOfWeek, WeeklyTemplateEntry newEntry) {
    setState(() {
      _entries[dayOfWeek] = newEntry;
    });
  }

  Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay? initialTime) async {
    return showTimePicker(
      context: context,
      initialTime: initialTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
  }

  String _formatTime(String? time) {
    if (time == null) return '--:--';
    return time;
  }

  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _timeOfDayToString(TimeOfDay tod) {
    return '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_view_week, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Template',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.employee.name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Set the default schedule for each day. Leave blank for no default, '
                            'or mark as OFF for days the employee doesn\'t work.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ..._entries.map((entry) => _buildDayRow(entry)),
                        ],
                      ),
                    ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Clear All', style: TextStyle(color: Colors.red)),
                    onPressed: _clearTemplate,
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save Template'),
                        onPressed: _saveTemplate,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(WeeklyTemplateEntry entry) {
    final dayName = _dayNames[entry.dayOfWeek];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Day name
            SizedBox(
              width: 100,
              child: Text(
                dayName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            
            // Status indicator
            if (entry.isOff)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('OFF', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              )
            else if (entry.hasShift)
              Expanded(
                child: Row(
                  children: [
                    // Start time
                    InkWell(
                      onTap: () async {
                        final time = await _pickTime(context, _parseTime(entry.startTime));
                        if (time != null) {
                          _updateEntry(
                            entry.dayOfWeek,
                            entry.copyWith(startTime: _timeOfDayToString(time)),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_formatTime(entry.startTime)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('to'),
                    ),
                    // End time
                    InkWell(
                      onTap: () async {
                        final time = await _pickTime(context, _parseTime(entry.endTime));
                        if (time != null) {
                          _updateEntry(
                            entry.dayOfWeek,
                            entry.copyWith(endTime: _timeOfDayToString(time)),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_formatTime(entry.endTime)),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Text(
                  'Not set',
                  style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                ),
              ),
            
            // Action buttons
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'set_time':
                    _showSetTimeDialog(entry);
                    break;
                  case 'mark_off':
                    _updateEntry(entry.dayOfWeek, entry.markAsOff());
                    break;
                  case 'clear':
                    _updateEntry(entry.dayOfWeek, entry.clearDay());
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'set_time',
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 20),
                      SizedBox(width: 8),
                      Text('Set Time'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'mark_off',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Mark as OFF'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear, size: 20),
                      SizedBox(width: 8),
                      Text('Clear (Blank)'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSetTimeDialog(WeeklyTemplateEntry entry) async {
    TimeOfDay startTime = _parseTime(entry.startTime) ?? const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = _parseTime(entry.endTime) ?? const TimeOfDay(hour: 17, minute: 0);

    final result = await showDialog<Map<String, TimeOfDay>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Set Time for ${_dayNames[entry.dayOfWeek]}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Start Time'),
                    trailing: TextButton(
                      onPressed: () async {
                        final time = await _pickTime(context, startTime);
                        if (time != null) {
                          setDialogState(() => startTime = time);
                        }
                      },
                      child: Text(
                        startTime.format(context),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('End Time'),
                    trailing: TextButton(
                      onPressed: () async {
                        final time = await _pickTime(context, endTime);
                        if (time != null) {
                          setDialogState(() => endTime = time);
                        }
                      },
                      child: Text(
                        endTime.format(context),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {
                    'start': startTime,
                    'end': endTime,
                  }),
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      _updateEntry(
        entry.dayOfWeek,
        WeeklyTemplateEntry(
          id: entry.id,
          employeeId: entry.employeeId,
          dayOfWeek: entry.dayOfWeek,
          startTime: _timeOfDayToString(result['start']!),
          endTime: _timeOfDayToString(result['end']!),
          isOff: false,
        ),
      );
    }
  }
}
