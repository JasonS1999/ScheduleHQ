import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/employee_dao.dart';
import '../database/time_off_dao.dart';
import '../database/settings_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/employee.dart';
import '../models/time_off_entry.dart';
import '../models/settings.dart' as app_models;
import '../services/app_colors.dart';
import '../services/auth_service.dart';
import '../services/firestore_sync_service.dart';
import '../services/pto_trimester_service.dart';

class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({super.key});

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final EmployeeDao _employeeDao = EmployeeDao();
  final TimeOffDao _timeOffDao = TimeOffDao();
  final SettingsDao _settingsDao = SettingsDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();
  late final PtoTrimesterService _ptoService;

  List<Employee> _employees = [];
  Map<int, Employee> _employeeById = {};
  app_models.Settings? _settings;
  
  // For approved tab - local database entries
  List<TimeOffEntry> _approvedEntries = [];
  bool _loadingApproved = false;

  // Job code colors cache
  final Map<String, Color> _jobCodeColorCache = {};

  String? get _managerUid => AuthService.instance.currentUserUid;

  CollectionReference<Map<String, dynamic>>? get _requestsRef {
    final uid = _managerUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('managers')
        .doc(uid)
        .collection('timeOff');
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _ptoService = PtoTrimesterService(timeOffDao: _timeOffDao);
    _loadData();
    
    // Listen for tab changes to reload approved entries
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _loadApprovedEntries();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final settings = await _settingsDao.getSettings();
    final employees = await _employeeDao.getEmployees();

    setState(() {
      _settings = settings;
      _employees = employees;
      _employeeById = {for (var e in employees) e.id!: e};
    });

    await _preloadJobCodeColors();
    await _loadApprovedEntries();
  }

  Future<void> _preloadJobCodeColors() async {
    for (final e in _employees) {
      final code = e.jobCode;
      if (_jobCodeColorCache.containsKey(code)) continue;

      final hex = await _jobCodeSettingsDao.getColorForJobCode(code);
      _jobCodeColorCache[code] = _colorFromHex(hex);
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadApprovedEntries() async {
    setState(() => _loadingApproved = true);
    
    // Get raw entries (not expanded) for display
    final entries = await _timeOffDao.getAllTimeOffRaw();
    
    // Sort by date ascending (oldest first, newest last)
    entries.sort((a, b) => a.date.compareTo(b.date));
    
    if (mounted) {
      setState(() {
        _approvedEntries = entries;
        _loadingApproved = false;
      });
    }
  }

  Color _colorFromHex(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    final value = int.tryParse(clean, radix: 16) ?? 0xFF4285F4;
    return Color(value);
  }

  Color _colorForEmployee(int employeeId) {
    final emp = _employeeById[employeeId];
    if (emp == null) return Theme.of(context).extension<AppColors>()!.textSecondary;
    final code = emp.jobCode;
    return _jobCodeColorCache[code] ?? Theme.of(context).extension<AppColors>()!.textSecondary;
  }

  // Simple date formatting helpers
  static const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  
  String _formatDateShort(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}';
  }
  
  String _formatDateFull(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Off Management'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Denied'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _loadData();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingTab(),
          _buildApprovedTab(),
          _buildDeniedTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showBulkAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Time Off'),
      ),
    );
  }

  // ============================================================
  // PENDING TAB - Employee requests from Firestore
  // ============================================================
  Widget _buildPendingTab() {
    final ref = _requestsRef;
    if (ref == null) {
      return const Center(child: Text('Please sign in to view requests'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          log('Pending tab error: ${snapshot.error}', name: 'ApprovalQueuePage');
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        // Sort by createdAt client-side to avoid needing composite index
        docs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
        
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).extension<AppColors>()!.textTertiary),
                const SizedBox(height: 16),
                Text('No pending requests', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return _buildRequestCard(doc, isPending: true);
          },
        );
      },
    );
  }

  // ============================================================
  // APPROVED TAB - All approved time-off from local database
  // ============================================================
  Widget _buildApprovedTab() {
    if (_loadingApproved) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_approvedEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Theme.of(context).extension<AppColors>()!.textTertiary),
            const SizedBox(height: 16),
            Text('No approved time off', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary)),
            const SizedBox(height: 8),
            Text('Use the + button to add time off', style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textTertiary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadApprovedEntries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _approvedEntries.length,
        itemBuilder: (context, index) {
          final entry = _approvedEntries[index];
          return _buildApprovedEntryCard(entry);
        },
      ),
    );
  }

  Widget _buildApprovedEntryCard(TimeOffEntry entry) {
    final employee = _employeeById[entry.employeeId];
    final employeeName = employee?.name ?? 'Unknown Employee';
    final color = _colorForEmployee(entry.employeeId);
    
    // Format date(s)
    String dateStr;
    if (entry.endDate != null && entry.endDate != entry.date) {
      final startStr = _formatDateShort(entry.date);
      final endStr = _formatDateFull(entry.endDate!);
      final days = entry.endDate!.difference(entry.date).inDays + 1;
      dateStr = '$startStr - $endStr (${days}d)';
    } else {
      dateStr = _formatDateFull(entry.date);
    }
    
    // Format type
    String typeLabel;
    switch (entry.timeOffType.toLowerCase()) {
      case 'vac':
        typeLabel = 'Vacation';
        break;
      case 'pto':
        typeLabel = 'PTO';
        break;
      case 'sick':
        typeLabel = 'Requested';
        break;
      default:
        typeLabel = entry.timeOffType.toUpperCase();
    }
    
    // Time range for partial day
    String? timeRange;
    if (!entry.isAllDay && entry.startTime != null && entry.endTime != null) {
      timeRange = '${_formatTime(entry.startTime!)} - ${_formatTime(entry.endTime!)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text(
            employeeName.isNotEmpty ? employeeName[0].toUpperCase() : '?',
            style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textOnSuccess),
          ),
        ),
        title: Text(employeeName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$typeLabel • $dateStr'),
            if (timeRange != null)
              Text(timeRange, style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textTertiary)),
            if (entry.hours > 0 && entry.timeOffType != 'vac')
              Text('${entry.hours} hours', style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textTertiary)),
          ],
        ),
        isThreeLine: timeRange != null || (entry.hours > 0 && entry.timeOffType != 'vac'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await _editEntry(entry);
            } else if (value == 'delete') {
              await _deleteEntry(entry);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.errorForeground)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$h:$minute $suffix';
  }

  // ============================================================
  // DENIED TAB - Denied requests from Firestore
  // ============================================================
  Widget _buildDeniedTab() {
    final ref = _requestsRef;
    if (ref == null) {
      return const Center(child: Text('Please sign in to view requests'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref
          .where('status', isEqualTo: 'denied')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          log('Denied tab error: ${snapshot.error}', name: 'ApprovalQueuePage');
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        // Sort by createdAt client-side to avoid needing composite index
        docs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
        
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Theme.of(context).extension<AppColors>()!.textTertiary),
                const SizedBox(height: 16),
                Text('No denied requests', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return _buildRequestCard(doc, isPending: false);
          },
        );
      },
    );
  }

  // ============================================================
  // REQUEST CARD - For pending/denied Firestore requests
  // ============================================================
  Widget _buildRequestCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool isPending,
  }) {
    final data = doc.data();
    final employeeName = data['employeeName'] as String? ?? 'Unknown';
    final dateStr = data['date'] as String? ?? '';
    final endDateStr = data['endDate'] as String?;
    final type = data['timeOffType'] as String? ?? '';
    final hours = data['hours'] as int? ?? 8;
    final reason = data['denialReason'] as String?;

    // Format dates
    String displayDate;
    if (endDateStr != null && endDateStr != dateStr) {
      final start = DateTime.tryParse(dateStr);
      final end = DateTime.tryParse(endDateStr);
      if (start != null && end != null) {
        final days = end.difference(start).inDays + 1;
        displayDate = '${_formatDateShort(start)} - ${_formatDateFull(end)} (${days}d)';
      } else {
        displayDate = dateStr;
      }
    } else {
      final date = DateTime.tryParse(dateStr);
      displayDate = date != null ? _formatDateFull(date) : dateStr;
    }

    // Format type
    String typeLabel;
    switch (type.toLowerCase()) {
      case 'vac':
        typeLabel = 'Vacation';
        break;
      case 'pto':
        typeLabel = 'PTO';
        break;
      case 'sick':
        typeLabel = 'Requested';
        break;
      default:
        typeLabel = type.toUpperCase();
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
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    employeeName.isNotEmpty ? employeeName[0].toUpperCase() : '?',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employeeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('$typeLabel • $displayDate', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary)),
                      if (type != 'vac')
                        Text('$hours hours', style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reason: $reason', style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textSecondary, fontStyle: FontStyle.italic)),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _denyRequest(doc.id),
                    child: Text('Deny', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.errorForeground)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _approveRequest(doc.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).extension<AppColors>()!.successForeground,
                    ),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // APPROVE / DENY REQUEST
  // ============================================================
  Future<void> _approveRequest(String requestId) async {
    try {
      await FirestoreSyncService.instance.approveTimeOffRequest(requestId);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Request approved'),
          backgroundColor: Theme.of(context).extension<AppColors>()!.successForeground,
        ),
      );
      
      // Reload approved entries
      await _loadApprovedEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error approving request: $e'),
          backgroundColor: Theme.of(context).extension<AppColors>()!.errorForeground,
        ),
      );
    }
  }

  Future<void> _denyRequest(String requestId) async {
    // Show dialog to optionally enter a reason
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Deny Request'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Enter reason for denial...',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text('Deny', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.errorForeground)),
            ),
          ],
        );
      },
    );

    if (reason == null) return; // User cancelled

    try {
      await FirestoreSyncService.instance.denyTimeOffRequest(
        requestId,
        reason: reason.isNotEmpty ? reason : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Request denied'),
          backgroundColor: Theme.of(context).extension<AppColors>()!.warningBackground,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error denying request: $e'),
          backgroundColor: Theme.of(context).extension<AppColors>()!.errorForeground,
        ),
      );
    }
  }

  // ============================================================
  // EDIT ENTRY
  // ============================================================
  Future<void> _editEntry(TimeOffEntry entry) async {
    final employee = _employeeById[entry.employeeId];
    if (employee == null) return;

    // Create editable copy
    DateTime editDate = entry.date;
    DateTime? editEndDate = entry.endDate;
    String editType = entry.timeOffType;
    int editHours = entry.hours;
    bool editIsAllDay = entry.isAllDay;
    String? editStartTime = entry.startTime;
    String? editEndTime = entry.endTime;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Calculate days for vacation
            int days = 1;
            if (editEndDate != null) {
              days = editEndDate!.difference(editDate).inDays + 1;
            }

            return AlertDialog(
              title: Text('Edit Time Off - ${employee.displayName}'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type dropdown
                    DropdownButtonFormField<String>(
                      value: editType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'pto', child: Text('PTO')),
                        DropdownMenuItem(value: 'vac', child: Text('Vacation')),
                        DropdownMenuItem(value: 'sick', child: Text('Requested')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            editType = v;
                            if (v != 'vac') {
                              editEndDate = null;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Date picker
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: editDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  editDate = picked;
                                  if (editEndDate != null && editEndDate!.isBefore(picked)) {
                                    editEndDate = picked;
                                  }
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Start Date'),
                              child: Text(_formatDateFull(editDate)),
                            ),
                          ),
                        ),
                        if (editType == 'vac') ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: editEndDate ?? editDate,
                                  firstDate: editDate,
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() => editEndDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'End Date'),
                                child: Text(editEndDate != null
                                    ? _formatDateFull(editEndDate!)
                                    : 'Same day'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (editType == 'vac') ...[
                      const SizedBox(height: 8),
                      Text('$days day(s)', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textSecondary)),
                    ],

                    // Hours for PTO
                    if (editType == 'pto') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: TextEditingController(text: editHours.toString()),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Hours'),
                        onChanged: (v) {
                          editHours = int.tryParse(v) ?? editHours;
                        },
                      ),
                    ],

                    // Time range for Requested
                    if (editType == 'sick') ...[
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('All Day'),
                        value: editIsAllDay,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setDialogState(() {
                            editIsAllDay = v ?? true;
                            if (!editIsAllDay) {
                              editStartTime ??= '09:00';
                              editEndTime ??= '17:00';
                            }
                          });
                        },
                      ),
                      if (!editIsAllDay) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final parts = (editStartTime ?? '09:00').split(':');
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: int.tryParse(parts[0]) ?? 9,
                                      minute: int.tryParse(parts[1]) ?? 0,
                                    ),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      editStartTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                    });
                                  }
                                },
                                child: Text(_formatTime(editStartTime ?? '09:00')),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('to'),
                            ),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final parts = (editEndTime ?? '17:00').split(':');
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: int.tryParse(parts[0]) ?? 17,
                                      minute: int.tryParse(parts[1]) ?? 0,
                                    ),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      editEndTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                    });
                                  }
                                },
                                child: Text(_formatTime(editEndTime ?? '17:00')),
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    // Calculate hours for vacation
    if (editType == 'vac' && editEndDate != null) {
      final days = editEndDate!.difference(editDate).inDays + 1;
      editHours = days * 8;
    }

    // Update entry
    final updatedEntry = TimeOffEntry(
      id: entry.id,
      employeeId: entry.employeeId,
      date: editDate,
      endDate: editType == 'vac' ? editEndDate : null,
      timeOffType: editType,
      hours: editHours,
      vacationGroupId: entry.vacationGroupId,
      isAllDay: editType == 'sick' ? editIsAllDay : true,
      startTime: editType == 'sick' && !editIsAllDay ? editStartTime : null,
      endTime: editType == 'sick' && !editIsAllDay ? editEndTime : null,
    );

    await _timeOffDao.updateTimeOff(updatedEntry);
    
    // Sync to Firestore
    if (employee.uid != null) {
      await FirestoreSyncService.instance.syncTimeOffEntry(updatedEntry, employee);
    }

    await _loadApprovedEntries();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Time off updated'),
        backgroundColor: Theme.of(context).extension<AppColors>()!.successForeground,
      ),
    );
  }

  // ============================================================
  // DELETE ENTRY
  // ============================================================
  Future<void> _deleteEntry(TimeOffEntry entry) async {
    if (entry.id == null) return;

    final employee = _employeeById[entry.employeeId];
    final employeeName = employee?.name ?? 'Employee';

    // If it's part of a vacation group, delete the whole group
    if (entry.vacationGroupId != null) {
      final groupEntries = await _timeOffDao.getEntriesByGroup(entry.vacationGroupId!);
      final count = groupEntries.length;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Time Off'),
          content: Text('Delete all $count day(s) of ${entry.timeOffType.toUpperCase()} for $employeeName?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.errorForeground)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Delete from local DB
      await _timeOffDao.deleteVacationGroup(entry.vacationGroupId!);
      
      // Delete from Firestore
      for (final e in groupEntries) {
        if (e.id != null) {
          await FirestoreSyncService.instance.deleteTimeOffEntry(e.employeeId, e.id!);
        }
      }
    } else {
      // Single entry delete
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Time Off'),
          content: Text('Delete ${entry.timeOffType.toUpperCase()} on ${_formatDateFull(entry.date)} for $employeeName?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.errorForeground)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Delete from local DB
      await _timeOffDao.deleteTimeOff(entry.id!);
      
      // Delete from Firestore
      await FirestoreSyncService.instance.deleteTimeOffEntry(entry.employeeId, entry.id!);
    }

    await _loadApprovedEntries();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Time off deleted'),
        backgroundColor: Theme.of(context).extension<AppColors>()!.warningBackground,
      ),
    );
  }

  // ============================================================
  // BULK ADD DIALOG
  // ============================================================
  Future<void> _showBulkAddDialog() async {
    Employee? selectedEmployee;
    final entries = <_BulkTimeOffEntry>[];

    // Cache job code settings for PTO eligibility check
    final jobCodeSettings = await _jobCodeSettingsDao.getAll();
    final jobCodeMap = {for (var jc in jobCodeSettings) jc.code.toLowerCase(): jc};

    bool hasPtoEnabled(Employee? emp) {
      if (emp == null) return false;
      final setting = jobCodeMap[emp.jobCode.toLowerCase()];
      return setting?.hasPTO ?? false;
    }

    int vacationWeeksRemaining(Employee? emp) {
      if (emp == null) return 0;
      return emp.vacationWeeksAllowed - emp.vacationWeeksUsed;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canAddPto = hasPtoEnabled(selectedEmployee);
            final vacWeeksLeft = vacationWeeksRemaining(selectedEmployee);
            final canAddVacation = vacWeeksLeft > 0;

            String getDefaultType() {
              if (canAddPto) return 'pto';
              if (canAddVacation) return 'vac';
              return 'sick';
            }

            List<DropdownMenuItem<String>> getTypeOptions() {
              final items = <DropdownMenuItem<String>>[];
              if (canAddPto) {
                items.add(const DropdownMenuItem(value: 'pto', child: Text('PTO')));
              }
              if (canAddVacation) {
                items.add(const DropdownMenuItem(value: 'vac', child: Text('Vacation')));
              }
              items.add(const DropdownMenuItem(value: 'sick', child: Text('Requested')));
              return items;
            }

            String formatTime(String? time) {
              if (time == null) return '';
              final parts = time.split(':');
              if (parts.length != 2) return time;
              final hour = int.tryParse(parts[0]) ?? 0;
              final minute = parts[1];
              final h = hour % 12 == 0 ? 12 : hour % 12;
              final suffix = hour < 12 ? 'AM' : 'PM';
              return '$h:$minute $suffix';
            }

            return AlertDialog(
              title: const Text('Add Time Off'),
              content: SizedBox(
                width: 550,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee search/select
                    const Text('Select Employee:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Autocomplete<Employee>(
                      displayStringForOption: (e) => e.name,
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _employees;
                        }
                        return _employees.where((e) =>
                            e.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      onSelected: (employee) {
                        setDialogState(() {
                          selectedEmployee = employee;
                          entries.clear();
                        });
                      },
                      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            hintText: 'Search by name...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        );
                      },
                    ),
                    if (selectedEmployee != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            avatar: CircleAvatar(
                              backgroundColor: _jobCodeColorCache[selectedEmployee!.jobCode] ?? Theme.of(context).extension<AppColors>()!.textSecondary,
                              child: Text(selectedEmployee!.name[0], style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textOnSuccess, fontSize: 12)),
                            ),
                            label: Text('${selectedEmployee!.name} (${selectedEmployee!.jobCode})'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setDialogState(() {
                              selectedEmployee = null;
                              entries.clear();
                            }),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            canAddPto ? '✓ PTO' : '✗ No PTO',
                            style: TextStyle(
                              fontSize: 12,
                              color: canAddPto ? Theme.of(context).extension<AppColors>()!.successForeground : Theme.of(context).extension<AppColors>()!.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            canAddVacation ? '✓ $vacWeeksLeft vac wks' : '✗ No vacation',
                            style: TextStyle(
                              fontSize: 12,
                              color: canAddVacation ? Theme.of(context).extension<AppColors>()!.successForeground : Theme.of(context).extension<AppColors>()!.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Entries list header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Time Off Entries:', style: TextStyle(fontWeight: FontWeight.w500)),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Entry'),
                          onPressed: selectedEmployee == null
                              ? null
                              : () {
                                  setDialogState(() {
                                    entries.add(_BulkTimeOffEntry(
                                      date: DateTime.now(),
                                      type: getDefaultType(),
                                      hours: 9,
                                      days: 1,
                                    ));
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Entries list
                    Expanded(
                      child: entries.isEmpty
                          ? Center(
                              child: Text(
                                selectedEmployee == null
                                    ? 'Select an employee first'
                                    : 'No entries added yet.\nClick "Add Entry" to start.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textTertiary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final entry = entries[index];

                                // Validate entry type
                                if (entry.type == 'pto' && !canAddPto) {
                                  entry.type = canAddVacation ? 'vac' : 'sick';
                                }
                                if (entry.type == 'vac' && !canAddVacation) {
                                  entry.type = canAddPto ? 'pto' : 'sick';
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            // Date picker (Start Date)
                                            Expanded(
                                              flex: 2,
                                              child: InkWell(
                                                onTap: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: entry.date,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime(2030),
                                                  );
                                                  if (picked != null) {
                                                    setDialogState(() {
                                                      entry.date = picked;
                                                      // If end date is before new start date, clear it
                                                      if (entry.endDate != null && entry.endDate!.isBefore(picked)) {
                                                        entry.endDate = null;
                                                        entry.days = 1;
                                                      } else if (entry.endDate != null) {
                                                        // Recalculate days
                                                        entry.days = entry.endDate!.difference(picked).inDays + 1;
                                                      }
                                                    });
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Theme.of(context).extension<AppColors>()!.borderMedium),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                                                    style: const TextStyle(fontSize: 13),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Type dropdown
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButtonFormField<String>(
                                                value: entry.type,
                                                isDense: true,
                                                isExpanded: true,
                                                decoration: const InputDecoration(
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  border: OutlineInputBorder(),
                                                ),
                                                items: getTypeOptions(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setDialogState(() {
                                                      entry.type = v;
                                                      if (v == 'vac') {
                                                        entry.days = 1;
                                                      } else if (v == 'pto') {
                                                        entry.hours = 9;
                                                      } else if (v == 'sick') {
                                                        entry.isAllDay = true;
                                                        entry.hours = 9;
                                                      }
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Hours/Days input based on type
                                            if (entry.type == 'vac') ...[
                                              // End date picker for vacation
                                              Expanded(
                                                flex: 2,
                                                child: InkWell(
                                                  onTap: () async {
                                                    final picked = await showDatePicker(
                                                      context: context,
                                                      initialDate: entry.endDate ?? entry.date,
                                                      firstDate: entry.date,
                                                      lastDate: DateTime(2030),
                                                    );
                                                    if (picked != null) {
                                                      setDialogState(() {
                                                        entry.endDate = picked;
                                                        // Calculate days including start and end
                                                        entry.days = picked.difference(entry.date).inDays + 1;
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(color: Theme.of(context).extension<AppColors>()!.borderMedium),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            entry.endDate != null
                                                                ? '${entry.endDate!.month}/${entry.endDate!.day}/${entry.endDate!.year}'
                                                                : 'End Date',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: entry.endDate != null
                                                                  ? null
                                                                  : Theme.of(context).extension<AppColors>()!.textTertiary,
                                                            ),
                                                          ),
                                                        ),
                                                        if (entry.endDate != null)
                                                          Text(
                                                            '(${entry.days}d)',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Theme.of(context).extension<AppColors>()!.textSecondary,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ] else if (entry.type == 'pto') ...[
                                              Expanded(
                                                flex: 1,
                                                child: TextField(
                                                  controller: TextEditingController(text: entry.hours.toString()),
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Hrs',
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    border: OutlineInputBorder(),
                                                  ),
                                                  onChanged: (v) {
                                                    entry.hours = int.tryParse(v) ?? entry.hours;
                                                  },
                                                ),
                                              ),
                                            ] else ...[
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Theme.of(context).extension<AppColors>()!.borderLight),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    entry.isAllDay ? 'All Day' : '${entry.hours}h',
                                                    style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textSecondary),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ],

                                            // Delete button
                                            IconButton(
                                              icon: Icon(Icons.delete, size: 20, color: Theme.of(context).extension<AppColors>()!.errorIcon),
                                              onPressed: () {
                                                setDialogState(() => entries.removeAt(index));
                                              },
                                            ),
                                          ],
                                        ),

                                        // Time range options for "Requested" type
                                        if (entry.type == 'sick') ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Checkbox(
                                                value: entry.isAllDay,
                                                onChanged: (v) {
                                                  setDialogState(() {
                                                    entry.isAllDay = v ?? true;
                                                    if (!entry.isAllDay) {
                                                      entry.startTime = '09:00';
                                                      entry.endTime = '17:00';
                                                      entry.hours = 8;
                                                    } else {
                                                      entry.hours = 9;
                                                    }
                                                  });
                                                },
                                              ),
                                              const Text('All Day', style: TextStyle(fontSize: 13)),
                                              if (!entry.isAllDay) ...[
                                                const SizedBox(width: 16),
                                                const Text('From:', style: TextStyle(fontSize: 13)),
                                                const SizedBox(width: 4),
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  onPressed: () async {
                                                    final parts = (entry.startTime ?? '09:00').split(':');
                                                    final initial = TimeOfDay(
                                                      hour: int.tryParse(parts[0]) ?? 9,
                                                      minute: int.tryParse(parts[1]) ?? 0,
                                                    );
                                                    final picked = await showTimePicker(
                                                      context: context,
                                                      initialTime: initial,
                                                    );
                                                    if (picked != null) {
                                                      setDialogState(() {
                                                        entry.startTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                        final endParts = (entry.endTime ?? '17:00').split(':');
                                                        var endMins = (int.tryParse(endParts[0]) ?? 17) * 60 + (int.tryParse(endParts[1]) ?? 0);
                                                        final startMins = picked.hour * 60 + picked.minute;
                                                        if (endMins <= startMins) endMins += 24 * 60;
                                                        entry.hours = ((endMins - startMins) / 60).round().clamp(1, 24);
                                                      });
                                                    }
                                                  },
                                                  child: Text(formatTime(entry.startTime ?? '09:00'), style: const TextStyle(fontSize: 12)),
                                                ),
                                                const SizedBox(width: 8),
                                                const Text('To:', style: TextStyle(fontSize: 13)),
                                                const SizedBox(width: 4),
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  onPressed: () async {
                                                    final parts = (entry.endTime ?? '17:00').split(':');
                                                    final initial = TimeOfDay(
                                                      hour: int.tryParse(parts[0]) ?? 17,
                                                      minute: int.tryParse(parts[1]) ?? 0,
                                                    );
                                                    final picked = await showTimePicker(
                                                      context: context,
                                                      initialTime: initial,
                                                    );
                                                    if (picked != null) {
                                                      setDialogState(() {
                                                        entry.endTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                        final startParts = (entry.startTime ?? '09:00').split(':');
                                                        final startMins = (int.tryParse(startParts[0]) ?? 9) * 60 + (int.tryParse(startParts[1]) ?? 0);
                                                        var endMins = picked.hour * 60 + picked.minute;
                                                        if (endMins <= startMins) endMins += 24 * 60;
                                                        entry.hours = ((endMins - startMins) / 60).round().clamp(1, 24);
                                                      });
                                                    }
                                                  },
                                                  child: Text(formatTime(entry.endTime ?? '17:00'), style: const TextStyle(fontSize: 12)),
                                                ),
                                                const SizedBox(width: 8),
                                                Text('(${entry.hours}h)', style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textSecondary)),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (selectedEmployee == null || entries.isEmpty)
                      ? null
                      : () async {
                          // Save all entries
                          for (final entry in entries) {
                            if (entry.type == 'vac') {
                              // For vacation, create a single entry with endDate
                              final startDate = entry.date;
                              // Use entry.endDate if set, otherwise calculate from days
                              final endDate = entry.endDate ?? (entry.days > 1 ? entry.date.add(Duration(days: entry.days - 1)) : null);
                              final totalDays = endDate != null ? endDate.difference(startDate).inDays + 1 : 1;
                              
                              final timeOffEntry = TimeOffEntry(
                                id: null,
                                employeeId: selectedEmployee!.id!,
                                date: startDate,
                                endDate: endDate,
                                timeOffType: 'vac',
                                hours: totalDays * 8,
                                vacationGroupId: const Uuid().v4(),
                                isAllDay: true,
                              );
                              final localId = await _timeOffDao.insertTimeOff(timeOffEntry);
                              
                              // Sync to Firestore
                              final entryWithId = TimeOffEntry(
                                id: localId,
                                employeeId: timeOffEntry.employeeId,
                                date: timeOffEntry.date,
                                endDate: timeOffEntry.endDate,
                                timeOffType: timeOffEntry.timeOffType,
                                hours: timeOffEntry.hours,
                                vacationGroupId: timeOffEntry.vacationGroupId,
                                isAllDay: timeOffEntry.isAllDay,
                              );
                              await FirestoreSyncService.instance.syncTimeOffEntry(entryWithId, selectedEmployee!);
                            } else {
                              // PTO or Requested - single day entry
                              final timeOffEntry = TimeOffEntry(
                                id: null,
                                employeeId: selectedEmployee!.id!,
                                date: entry.date,
                                timeOffType: entry.type,
                                hours: entry.hours,
                                vacationGroupId: const Uuid().v4(),
                                isAllDay: entry.type == 'sick' ? entry.isAllDay : true,
                                startTime: entry.type == 'sick' && !entry.isAllDay ? entry.startTime : null,
                                endTime: entry.type == 'sick' && !entry.isAllDay ? entry.endTime : null,
                              );
                              final localId = await _timeOffDao.insertTimeOff(timeOffEntry);
                              
                              // Sync to Firestore
                              final entryWithId = TimeOffEntry(
                                id: localId,
                                employeeId: timeOffEntry.employeeId,
                                date: timeOffEntry.date,
                                timeOffType: timeOffEntry.timeOffType,
                                hours: timeOffEntry.hours,
                                vacationGroupId: timeOffEntry.vacationGroupId,
                                isAllDay: timeOffEntry.isAllDay,
                                startTime: timeOffEntry.startTime,
                                endTime: timeOffEntry.endTime,
                              );
                              await FirestoreSyncService.instance.syncTimeOffEntry(entryWithId, selectedEmployee!);
                            }
                          }
                          
                          if (!mounted) return;
                          Navigator.pop(context);
                          await _loadApprovedEntries();
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added ${entries.length} time off entries for ${selectedEmployee!.name}'),
                              backgroundColor: Theme.of(context).extension<AppColors>()!.successForeground,
                            ),
                          );
                        },
                  child: Text('Save ${entries.length} Entries'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Helper class for bulk time off entry
class _BulkTimeOffEntry {
  DateTime date;
  DateTime? endDate; // For vacation date ranges
  String type;
  int hours;
  int days; // For vacation entries
  bool isAllDay; // For requested entries
  String? startTime; // For partial day requested entries
  String? endTime;

  _BulkTimeOffEntry({
    required this.date,
    this.endDate,
    required this.type,
    this.hours = 8,
    this.days = 1,
    this.isAllDay = true,
    this.startTime,
    this.endTime,
  });
}
