import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class TimeOffPage extends StatefulWidget {
  const TimeOffPage({super.key});

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _employeeUid;
  int? _employeeLocalId;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployeeInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          _employeeLocalId = data['localId'] as int?;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Off'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Requests'),
            Tab(text: 'Upcoming'),
          ],
        ),
      ),
      body: _employeeUid == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildRequestsTab(), _buildUpcomingTab()],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRequestDialog,
        icon: const Icon(Icons.add),
        label: const Text('Request Time Off'),
      ),
    );
  }

  Widget _buildRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('timeOffRequests')
          .where('employeeUid', isEqualTo: _employeeUid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data?.docs ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No time off requests yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                const Text('Tap + to request time off'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildRequestCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(String id, Map<String, dynamic> data) {
    final date = DateTime.parse(data['date'] as String);
    final type = data['timeOffType'] as String;
    final status = data['status'] as String;
    final hours = data['hours'] as int? ?? 8;
    final denialReason = data['denialReason'] as String?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'denied':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeChip(type),
                const SizedBox(width: 8),
                Text('$hours hours'),
              ],
            ),
            if (denialReason != null && denialReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        denialReason,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('timeOff')
          .where('employeeUid', isEqualTo: _employeeUid)
          .where(
            'date',
            isGreaterThanOrEqualTo: DateFormat(
              'yyyy-MM-dd',
            ).format(DateTime.now()),
          )
          .orderBy('date')
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snapshot.data?.docs ?? [];

        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_available,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No upcoming time off',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final data = entries[index].data() as Map<String, dynamic>;
            final date = DateTime.parse(data['date'] as String);
            final type = data['timeOffType'] as String;
            final hours = data['hours'] as int? ?? 8;
            final isAllDay = data['isAllDay'] as bool? ?? true;
            final startTime = data['startTime'] as String?;
            final endTime = data['endTime'] as String?;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: _buildTypeChip(type),
                title: Text(
                  DateFormat('EEEE, MMMM d').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  isAllDay ? 'All Day ($hours hours)' : '$startTime - $endTime',
                ),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTypeChip(String type) {
    Color color;
    String label;
    switch (type.toLowerCase()) {
      case 'vac':
        color = Colors.blue;
        label = 'Vacation';
        break;
      case 'pto':
        color = Colors.green;
        label = 'PTO';
        break;
      case 'sick':
      case 'dayoff':
        color = Colors.orange;
        label = 'Day Off';
        break;
      default:
        color = Colors.grey;
        label = type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TimeOffRequestSheet(
        employeeUid: _employeeUid,
        employeeLocalId: _employeeLocalId,
        employeeName: _employeeName,
      ),
    );
  }
}

class _TimeOffRequestSheet extends StatefulWidget {
  final String? employeeUid;
  final int? employeeLocalId;
  final String? employeeName;

  const _TimeOffRequestSheet({
    required this.employeeUid,
    required this.employeeLocalId,
    required this.employeeName,
  });

  @override
  State<_TimeOffRequestSheet> createState() => _TimeOffRequestSheetState();
}

class _TimeOffRequestSheetState extends State<_TimeOffRequestSheet> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _vacationEndDate; // For vacation multi-day selection
  String _selectedType = 'pto';
  int _hours = 8;
  bool _isAllDay = true;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  bool _submitting = false;

  // Employee balance info
  int? _ptoAvailable;
  int? _vacationWeeksRemaining;
  bool _loadingBalance = true;

  @override
  void initState() {
    super.initState();
    _loadEmployeeBalance();
  }

  Future<void> _loadEmployeeBalance() async {
    if (widget.employeeUid == null) {
      setState(() => _loadingBalance = false);
      return;
    }

    try {
      // Get employee data to find managerUid and local info
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.employeeUid)
          .get();

      if (!userDoc.exists) {
        setState(() => _loadingBalance = false);
        return;
      }

      final userData = userDoc.data()!;
      final managerUid = userData['managerUid'] as String?;

      if (managerUid == null || widget.employeeLocalId == null) {
        setState(() => _loadingBalance = false);
        return;
      }

      // Get employee data from manager's collection
      final employeeDoc = await FirebaseFirestore.instance
          .collection('managers')
          .doc(managerUid)
          .collection('employees')
          .doc(widget.employeeLocalId.toString())
          .get();

      if (!employeeDoc.exists) {
        setState(() => _loadingBalance = false);
        return;
      }

      final empData = employeeDoc.data()!;
      final vacationWeeksAllowed = empData['vacationWeeksAllowed'] as int? ?? 0;
      final vacationWeeksUsed = empData['vacationWeeksUsed'] as int? ?? 0;

      // Calculate PTO balance for current trimester
      final now = DateTime.now();
      final trimesterStart = _getTrimesterStart(now);
      final trimesterEnd = _getTrimesterEnd(now);

      final timeOffQuery = await FirebaseFirestore.instance
          .collection('managers')
          .doc(managerUid)
          .collection('timeOff')
          .where('employeeLocalId', isEqualTo: widget.employeeLocalId)
          .get();

      int usedPtoHours = 0;
      for (final doc in timeOffQuery.docs) {
        final data = doc.data();
        final type = data['timeOffType'] as String?;
        if (type != 'pto') continue;

        final dateStr = data['date'] as String?;
        if (dateStr == null) continue;

        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        if (date.isBefore(trimesterStart) || date.isAfter(trimesterEnd))
          continue;

        final hours = data['hours'] as int? ?? 8;
        usedPtoHours += hours;
      }

      const allowancePerTrimester = 40;
      final ptoRemaining = allowancePerTrimester - usedPtoHours;

      setState(() {
        _ptoAvailable = ptoRemaining > 0 ? ptoRemaining : 0;
        _vacationWeeksRemaining = vacationWeeksAllowed - vacationWeeksUsed;
        _loadingBalance = false;

        // Default to an available type
        if (_ptoAvailable == 0 && _vacationWeeksRemaining! <= 0) {
          _selectedType = 'dayoff';
        } else if (_ptoAvailable == 0) {
          _selectedType = 'vac';
        }
      });
    } catch (e) {
      debugPrint('Error loading balance: $e');
      setState(() => _loadingBalance = false);
    }
  }

  DateTime _getTrimesterStart(DateTime date) {
    final year = date.year;
    if (date.month <= 4) {
      return DateTime(year, 1, 1);
    } else if (date.month <= 8) {
      return DateTime(year, 5, 1);
    } else {
      return DateTime(year, 9, 1);
    }
  }

  DateTime _getTrimesterEnd(DateTime date) {
    final year = date.year;
    if (date.month <= 4) {
      return DateTime(year, 4, 30);
    } else if (date.month <= 8) {
      return DateTime(year, 8, 31);
    } else {
      return DateTime(year, 12, 31);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Reset vacation end date if start date changes
        if (_vacationEndDate != null && _vacationEndDate!.isBefore(picked)) {
          _vacationEndDate = null;
        }
      });
    }
  }

  Future<void> _selectVacationDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _vacationEndDate != null
          ? DateTimeRange(start: _selectedDate, end: _vacationEndDate!)
          : null,
      helpText: 'Select vacation dates',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked.start;
        _vacationEndDate = picked.end;
      });
    }
  }

  Future<void> _submit() async {
    if (widget.employeeUid == null) return;

    setState(() => _submitting = true);

    try {
      // For vacation, handle multi-day date range
      if (_selectedType.toLowerCase() == 'vac') {
        final startDate = _selectedDate;
        final endDate = _vacationEndDate ?? _selectedDate;

        // Calculate number of days
        final dayCount = endDate.difference(startDate).inDays + 1;

        // Create a single vacation request with date range
        await FirebaseFirestore.instance.collection('timeOffRequests').add({
          'employeeUid': widget.employeeUid,
          'employeeLocalId': widget.employeeLocalId,
          'employeeName': widget.employeeName,
          'date': DateFormat('yyyy-MM-dd').format(startDate),
          'endDate': DateFormat('yyyy-MM-dd').format(endDate),
          'timeOffType': _selectedType,
          'hours': dayCount * 8, // 8 hours per day
          'isAllDay': true,
          'status': 'pending', // Vacation always requires approval
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dayCount == 1
                    ? 'Vacation request submitted for approval'
                    : 'Vacation request for $dayCount days submitted for approval',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      // For PTO and Day Off, single day handling
      // Check if approval is required
      // PTO/DayOff require approval if 2+ entries already exist for that day
      bool requiresApproval = false;

      // Check existing time-off for this date
      final existingCount = await FirebaseFirestore.instance
          .collection('timeOff')
          .where(
            'date',
            isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate),
          )
          .count()
          .get();

      requiresApproval = (existingCount.count ?? 0) >= 2;

      // For Day Off, set hours to 8 for all day, or calculate from time range
      final effectiveHours = _selectedType == 'dayoff'
          ? (_isAllDay ? 8 : _calculateHoursFromTimeRange())
          : _hours;

      // Create the request
      await FirebaseFirestore.instance.collection('timeOffRequests').add({
        'employeeUid': widget.employeeUid,
        'employeeLocalId': widget.employeeLocalId,
        'employeeName': widget.employeeName,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'timeOffType': _selectedType == 'dayoff'
            ? 'sick'
            : _selectedType, // Store as 'sick' for backward compatibility
        'hours': effectiveHours,
        'isAllDay': _isAllDay,
        'startTime': _isAllDay
            ? null
            : '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
        'endTime': _isAllDay
            ? null
            : '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
        'status': requiresApproval ? 'pending' : 'approved',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // If auto-approved, also create the time-off entry
      if (!requiresApproval) {
        await FirebaseFirestore.instance.collection('timeOff').add({
          'employeeUid': widget.employeeUid,
          'employeeLocalId': widget.employeeLocalId,
          'employeeName': widget.employeeName,
          'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
          'timeOffType': _selectedType == 'dayoff' ? 'sick' : _selectedType,
          'hours': effectiveHours,
          'isAllDay': _isAllDay,
          'startTime': _isAllDay
              ? null
              : '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
          'endTime': _isAllDay
              ? null
              : '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
          'status': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requiresApproval
                  ? 'Request submitted for approval'
                  : 'Time off approved!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _submitting = false);
      }
    }
  }

  int _calculateHoursFromTimeRange() {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    final diffMinutes = endMinutes - startMinutes;
    return (diffMinutes / 60).round().clamp(1, 12);
  }

  @override
  Widget build(BuildContext context) {
    final bool ptoEnabled = !_loadingBalance && (_ptoAvailable ?? 0) > 0;
    final bool vacationEnabled =
        !_loadingBalance && (_vacationWeeksRemaining ?? 0) > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Request Time Off',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date picker - varies by type
            if (_selectedType == 'vac') ...[
              // Vacation: multi-day date range picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: const Text('Dates'),
                subtitle: Text(
                  _vacationEndDate != null && _vacationEndDate != _selectedDate
                      ? '${DateFormat('MMM d').format(_selectedDate)} - ${DateFormat('MMM d, yyyy').format(_vacationEndDate!)}'
                      : DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectVacationDateRange,
              ),
            ] else ...[
              // PTO and Day Off: single date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectDate,
              ),
            ],
            const Divider(),

            // Type selector with conditional enabling
            const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loadingBalance)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'pto',
                    label: Text('PTO'),
                    enabled: ptoEnabled,
                  ),
                  ButtonSegment(
                    value: 'vac',
                    label: Text('Vacation'),
                    enabled: vacationEnabled,
                  ),
                  const ButtonSegment(value: 'dayoff', label: Text('Day Off')),
                ],
                selected: {_selectedType},
                onSelectionChanged: (selected) {
                  final newType = selected.first;
                  // Only allow selection if enabled
                  if (newType == 'pto' && !ptoEnabled) return;
                  if (newType == 'vac' && !vacationEnabled) return;
                  setState(() {
                    _selectedType = newType;
                    // Reset vacation end date when switching types
                    if (newType != 'vac') {
                      _vacationEndDate = null;
                    }
                  });
                },
              ),

            // Show balance info
            if (!_loadingBalance) ...[
              const SizedBox(height: 8),
              if (!ptoEnabled && _selectedType != 'pto')
                Text(
                  'PTO: No hours available this trimester',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )
              else if (ptoEnabled)
                Text(
                  'PTO: $_ptoAvailable hours available',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              if (!vacationEnabled && _selectedType != 'vac')
                Text(
                  'Vacation: No weeks remaining this year',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )
              else if (vacationEnabled)
                Text(
                  'Vacation: $_vacationWeeksRemaining week${_vacationWeeksRemaining == 1 ? '' : 's'} remaining',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
            const SizedBox(height: 16),

            // All day toggle - only for PTO and Day Off (not Vacation)
            if (_selectedType != 'vac') ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('All Day'),
                value: _isAllDay,
                onChanged: (value) {
                  setState(() {
                    _isAllDay = value;
                  });
                },
              ),

              // Time selector for Day Off when not all day
              if (!_isAllDay && _selectedType == 'dayoff') ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.amber.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Time you'll be unavailable",
                          style: TextStyle(
                            color: Colors.amber.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Start'),
                        subtitle: Text(_startTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _startTime,
                          );
                          if (picked != null) {
                            setState(() => _startTime = picked);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('End'),
                        subtitle: Text(_endTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _endTime,
                          );
                          if (picked != null) {
                            setState(() => _endTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],

              // Time selector for PTO when not all day
              if (!_isAllDay && _selectedType == 'pto') ...[
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Start'),
                        subtitle: Text(_startTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _startTime,
                          );
                          if (picked != null) {
                            setState(() => _startTime = picked);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('End'),
                        subtitle: Text(_endTime.format(context)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _endTime,
                          );
                          if (picked != null) {
                            setState(() => _endTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],

            // Hours slider - only for PTO
            if (_selectedType == 'pto') ...[
              Row(
                children: [
                  const Text('Hours: '),
                  Expanded(
                    child: Slider(
                      value: _hours.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '$_hours',
                      onChanged: (value) {
                        setState(() {
                          _hours = value.toInt();
                        });
                      },
                    ),
                  ),
                  Text('$_hours'),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Info about approval
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedType == 'vac'
                          ? 'Vacation requests require manager approval'
                          : 'PTO/Day Off requests are auto-approved unless 2+ requests already exist for that day',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Submit button
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
