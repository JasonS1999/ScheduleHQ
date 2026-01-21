import 'package:flutter/material.dart';
import 'controllers/schedule_controller.dart';
import 'models/shift_entry.dart';
import 'services/app_colors.dart';

class ScheduleHomePage extends StatefulWidget {
  final int year;
  final int month;

  const ScheduleHomePage({
    super.key,
    required this.year,
    required this.month,
  });

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage> {
  late int _currentYear;
  late int _currentMonth;

  final ScheduleController _controller = ScheduleController();

  @override
  void initState() {
    super.initState();
    _currentYear = widget.year;
    _currentMonth = widget.month;
  }

  // Generate calendar weeks (Sunday–Saturday)
  List<List<DateTime>> generateCalendarWeeks(int year, int month) {
    final firstOfMonth = DateTime(year, month, 1);
    final lastOfMonth = DateTime(year, month + 1, 0);

    DateTime start = firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday % 7),
    );

    List<List<DateTime>> weeks = [];
    DateTime current = start;

    while (current.isBefore(lastOfMonth) || current.weekday != DateTime.sunday) {
      List<DateTime> week = [];
      for (int i = 0; i < 7; i++) {
        week.add(current);
        current = current.add(const Duration(days: 1));
      }
      weeks.add(week);
    }

    return weeks;
  }

  void _goToPreviousMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear -= 1;
      } else {
        _currentMonth -= 1;
      }
    });
  }

  void _goToNextMonth() {
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear += 1;
      } else {
        _currentMonth += 1;
      }
    });
  }

  String _monthName(int month) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final weeks = generateCalendarWeeks(_currentYear, _currentMonth);

    return Scaffold(
      body: Column(
        children: [
          // Month navigation header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _goToPreviousMonth,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_monthName(_currentMonth)} $_currentYear',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _goToNextMonth,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          _buildWeekdayHeader(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: weeks.map((week) => _buildWeekRow(week)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildWeekRow(List<DateTime> week) {
    return Row(
      children: week.map((day) => _buildDayCell(day)).toList(),
    );
  }

  Widget _buildDayCell(DateTime day) {
    final isCurrentMonth = day.month == _currentMonth;
    final entries = _controller.entriesForDay(day);
    final appColors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: () => _onDayTapped(day),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: appColors.borderLight),
            color: isCurrentMonth ? colorScheme.surface : appColors.surfaceVariant,
          ),
          padding: const EdgeInsets.all(4),
          height: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrentMonth ? appColors.textPrimary : appColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              ...entries.take(2).map(
                (e) => Text(
                  e.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (entries.length > 2)
                Text(
                  '+${entries.length - 2} more',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDayTapped(DateTime day) async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return _DayEntriesSheet(
          day: day,
          entries: _controller.entriesForDay(day),
          onAdd: (text) {
            setState(() => _controller.addEntry(day, text));
          },
          onDelete: (id) {
            setState(() => _controller.deleteEntry(id));
          },
          onUpdate: (updated) {
            setState(() => _controller.updateEntry(updated));
          },
        );
      },
    );
  }
}

class _DayEntriesSheet extends StatefulWidget {
  final DateTime day;
  final List<ShiftEntry> entries;
  final void Function(String text) onAdd;
  final void Function(String id) onDelete;
  final void Function(ShiftEntry updated) onUpdate;

  const _DayEntriesSheet({
    required this.day,
    required this.entries,
    required this.onAdd,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<_DayEntriesSheet> createState() => _DayEntriesSheetState();
}

class _DayEntriesSheetState extends State<_DayEntriesSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formattedDate(DateTime d) {
    return '${d.month}/${d.day}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        initialChildSize: 0.6,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Entries for ${_formattedDate(widget.day)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(entry.text),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editEntry(entry),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete),
                            onPressed: () => widget.onDelete(entry.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          labelText: 'Add entry (e.g. "Alex - PTO")',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _submitNewEntry(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitNewEntry,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _submitNewEntry() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAdd(text);
    _controller.clear();
    setState(() {});
  }

  void _editEntry(ShiftEntry entry) {
    final editController = TextEditingController(text: entry.text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit entry'),
          content: TextField(
            controller: editController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty) {
                  widget.onUpdate(
                    entry.copyWith(text: newText),
                  );
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
