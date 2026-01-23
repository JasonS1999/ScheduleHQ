import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _selectedDate = DateTime.now();
  String? _employeeUid;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
  }

  Future<void> _loadEmployeeInfo() async {
    final user = AuthService.instance.currentUser;
    if (user != null) {
      setState(() {
        _employeeUid = user.uid;
      });
      
      final data = await AuthService.instance.getEmployeeData();
      if (data != null && mounted) {
        setState(() {
          _employeeName = data['name'] as String?;
        });
      }
    }
  }

  // Get start and end of week for querying
  DateTime get _weekStart {
    final start = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
    return DateTime(start.year, start.month, start.day);
  }

  DateTime get _weekEnd {
    return _weekStart.add(const Duration(days: 7));
  }

  void _previousWeek() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 7));
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Schedule'),
            if (_employeeName != null)
              Text(
                _employeeName!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Go to current week',
            onPressed: _goToCurrentWeek,
          ),
        ],
      ),
      body: Column(
        children: [
          // Week navigation
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousWeek,
                ),
                Text(
                  'Week of ${DateFormat('MMM d').format(_weekStart)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),
          
          // Schedule content
          Expanded(
            child: _employeeUid == null
                ? const Center(child: CircularProgressIndicator())
                : _buildScheduleList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shifts')
          .where('employeeUid', isEqualTo: _employeeUid)
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(_weekStart))
          .where('date', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(_weekEnd.subtract(const Duration(days: 1))))
          .orderBy('date')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error loading schedule: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final shifts = snapshot.data?.docs ?? [];

        if (shifts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_busy,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No shifts scheduled\nfor this week',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        // Group shifts by date
        final shiftsByDate = <String, List<DocumentSnapshot>>{};
        for (final shift in shifts) {
          final date = shift['date'] as String;
          shiftsByDate.putIfAbsent(date, () => []).add(shift);
        }

        // Build list with day headers
        final sortedDates = shiftsByDate.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final dateStr = sortedDates[index];
            final dayShifts = shiftsByDate[dateStr]!;
            final date = DateTime.parse(dateStr);
            final isToday = _isSameDay(date, DateTime.now());

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isToday 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('EEE').format(date).toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isToday ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              date.day.toString(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isToday ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('EEEE, MMMM d').format(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'TODAY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Shifts for this date
                ...dayShifts.map((shift) => _buildShiftCard(shift)),
                
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShiftCard(DocumentSnapshot shift) {
    final data = shift.data() as Map<String, dynamic>;
    final startTime = (data['startTime'] as Timestamp).toDate();
    final endTime = (data['endTime'] as Timestamp).toDate();
    final label = data['label'] as String?;
    final notes = data['notes'] as String?;

    // Check if this is an "OFF" or time-off label
    final isTimeOff = label?.toUpperCase() == 'OFF' || 
                      label?.toUpperCase() == 'PTO' || 
                      label?.toUpperCase() == 'VAC' ||
                      label?.toUpperCase() == 'REQ OFF';

    return Card(
      margin: const EdgeInsets.only(left: 60, bottom: 8),
      child: ListTile(
        leading: Icon(
          isTimeOff ? Icons.event_busy : Icons.access_time,
          color: isTimeOff ? Colors.orange : Theme.of(context).colorScheme.primary,
        ),
        title: isTimeOff
            ? Text(
                label ?? 'OFF',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : Text(
                '${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isTimeOff && label != null && label.isNotEmpty)
              Text(label),
            if (notes != null && notes.isNotEmpty)
              Text(
                notes,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: !isTimeOff
            ? Text(
                _formatDuration(endTime.difference(startTime)),
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              )
            : null,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
