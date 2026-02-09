import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/shift_runner.dart';
import '../../models/employee.dart';
import '../../providers/schedule_provider.dart';
import '../../services/app_colors.dart';

class ShiftRunnerTable extends StatefulWidget {
  final DateTime weekStart;
  final VoidCallback? onChanged;
  final int refreshKey;

  const ShiftRunnerTable({
    super.key,
    required this.weekStart,
    this.onChanged,
    this.refreshKey = 0,
  });

  @override
  State<ShiftRunnerTable> createState() => _ShiftRunnerTableState();
}

class _ShiftRunnerTableState extends State<ShiftRunnerTable> {
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().initialize();
    });
  }

  @override
  void didUpdateWidget(ShiftRunnerTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart || 
        oldWidget.refreshKey != widget.refreshKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = context.read<ScheduleProvider>();
        provider.setDateRange(widget.weekStart, widget.weekStart.add(const Duration(days: 6)));
        provider.refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScheduleProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${provider.errorMessage ?? 'Unknown error'}'),
                ElevatedButton(
                  onPressed: () => provider.refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final days = List.generate(7, (i) => widget.weekStart.add(Duration(days: i)));
        final shiftTypeKeys = provider.shiftTypes.map((t) => t.key).toList();

        return Card(
          margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with expand/collapse
              InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(12),
                      bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isExpanded ? Icons.chevron_right : Icons.chevron_left,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Runners',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              // Table content - rotated: days as rows, shifts as columns
              if (_isExpanded)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white 
                            : Colors.black,
                        width: 2,
                      ),
                    ),
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(75),
                      columnWidths: const {
                        0: FixedColumnWidth(60), // Day column
                      },
                      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
                      children: [
                        // Header row with shift types (rotated text)
                        TableRow(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                          ),
                          children: [
                            _buildHeaderCell(''),
                            ...shiftTypeKeys.map((shiftType) => _buildRotatedShiftHeader(shiftType)),
                          ],
                        ),
                        // Rows for each day
                        ...days.map((day) {
                          return TableRow(
                            children: [
                              _buildDayCell(day),
                              ...shiftTypeKeys.map((shiftType) {
                                final runner = _getRunnerForCell(day, shiftType);
                                return _buildRunnerCell(day, shiftType, runner);
                              }),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _buildRotatedShiftHeader(String shiftType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      alignment: Alignment.center,
      color: _getShiftColor(shiftType).withOpacity(0.3),
      child: Text(
        ShiftRunner.getLabelForType(shiftType),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime day) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Text(
        '${_dayAbbr(day.weekday)}\n${day.month}/${day.day}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _buildRunnerCell(DateTime day, String shiftType, String? runner) {
    final hasRunner = runner != null && runner.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onSecondaryTapDown: hasRunner
          ? (details) => _showRunnerContextMenu(details.globalPosition, day, shiftType)
          : null,
      child: InkWell(
        onTap: () => _editRunner(day, shiftType, runner),
        child: Container(
          padding: const EdgeInsets.all(3),
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: hasRunner ? _getShiftColor(shiftType).withOpacity(0.15) : null,
          ),
          child: Text(
            runner ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: hasRunner 
                  ? (isDark ? Colors.white : Colors.black)
                  : context.appColors.textTertiary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _showRunnerContextMenu(Offset position, DateTime day, String shiftType) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem<String>(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.clear, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Clear Runner', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (result == 'clear') {
      final provider = context.read<ScheduleProvider>();
      await provider.clearShiftRunner(day, shiftType);
      widget.onChanged?.call();
    }
  }

  Future<void> _editRunner(
    DateTime day,
    String shiftType,
    String? currentName,
  ) async {
    final provider = context.read<ScheduleProvider>();
    
    // Get the shift type info for availability check
    final shiftTypeObj = provider.getShiftType(shiftType);
    final startTime = shiftTypeObj?.defaultShiftStart ?? '09:00';
    final endTime = shiftTypeObj?.defaultShiftEnd ?? '17:00';

    // Load available employees for this shift
    final availableEmployees = await _getAvailableEmployees(
      day,
      startTime,
      endTime,
      shiftType,
    );

    if (!mounted) return;

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return _ShiftRunnerSearchDialog(
          day: day,
          shiftType: shiftType,
          currentName: currentName,
          availableEmployees: availableEmployees,
          shiftColor: _getShiftColor(shiftType),
          startTime: startTime,
          endTime: endTime,
        );
      },
    );

    if (result != null) {
      if (result.isEmpty) {
        await provider.clearShiftRunner(day, shiftType);
      } else {
        // Find the employee by name
        final employee = provider.getEmployeeByName(result);
        
        // Create shift with default times if employee doesn't have a shift for this day
        if (employee != null) {
          final existingShifts = await provider.getEmployeeShiftsForDateRange(
            employee.id!,
            day,
            day.add(const Duration(days: 1)),
          );
          
          if (existingShifts.isEmpty) {
            // Parse the default shift times
            final startParts = startTime.split(':');
            final endParts = endTime.split(':');
            final shiftStart = DateTime(
              day.year, day.month, day.day,
              int.parse(startParts[0]), int.parse(startParts[1]),
            );
            var shiftEnd = DateTime(
              day.year, day.month, day.day,
              int.parse(endParts[0]), int.parse(endParts[1]),
            );
            // Handle overnight shifts (end time before start time)
            if (shiftEnd.isBefore(shiftStart) || shiftEnd.isAtSameMomentAs(shiftStart)) {
              shiftEnd = shiftEnd.add(const Duration(days: 1));
            }
            
            await provider.createShift(
              employeeId: employee.id!,
              startTime: shiftStart,
              endTime: shiftEnd,
            );
          }
        }
        
        await provider.upsertShiftRunner(
          ShiftRunner(
            date: day,
            shiftType: shiftType,
            runnerName: result,
            employeeId: employee?.id,
          ),
        );
      }
      widget.onChanged?.call();
    }
  }

  Future<List<Employee>> _getAvailableEmployees(
    DateTime date,
    String startTime,
    String endTime,
    String shiftType,
  ) async {
    final provider = context.read<ScheduleProvider>();
    final allEmployees = provider.employees;
    final availableEmployees = <Employee>[];

    for (final employee in allEmployees) {
      // Check if employee is available for this shift
      final availability = await provider.checkEmployeeAvailability(
        employee.id!,
        date,
        startTime,
        endTime,
      );
      
      if (availability['available'] == true) {
        availableEmployees.add(employee);
      }
    }
    
    return availableEmployees;
  }

  String? _getRunnerForCell(DateTime day, String shiftType) {
    final provider = context.read<ScheduleProvider>();
    return provider.getRunnerForCell(day, shiftType);  
  }

  Color _getShiftColor(String shiftType) {
    final provider = context.read<ScheduleProvider>();
    final shiftTypeObj = provider.getShiftType(shiftType);
    final hex = shiftTypeObj?.colorHex ?? '#808080';
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  String _dayAbbr(int weekday) {
    const abbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return abbrs[weekday % 7];
  }
}

class _ShiftRunnerSearchDialog extends StatefulWidget {
  final DateTime day;
  final String shiftType;
  final String? currentName;
  final List<Employee> availableEmployees;
  final Color shiftColor;
  final String startTime;
  final String endTime;

  const _ShiftRunnerSearchDialog({
    required this.day,
    required this.shiftType,
    required this.currentName,
    required this.availableEmployees,
    required this.shiftColor,
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_ShiftRunnerSearchDialog> createState() =>
      _ShiftRunnerSearchDialogState();
}

class _ShiftRunnerSearchDialogState extends State<_ShiftRunnerSearchDialog> {
  late TextEditingController _searchController;
  List<Employee> _filteredEmployees = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredEmployees = widget.availableEmployees;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = widget.availableEmployees;
      } else {
        _filteredEmployees = widget.availableEmployees
            .where(
              (emp) => emp.displayName.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: widget.shiftColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ShiftRunner.getLabelForType(widget.shiftType)} Runner',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '${widget.day.month}/${widget.day.day} • ${widget.startTime} - ${widget.endTime}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).extension<AppColors>()!.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search employees...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _filterEmployees('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).extension<AppColors>()!.surfaceVariant,
              ),
              onChanged: _filterEmployees,
            ),
            const SizedBox(height: 12),
            Text(
              'Available Employees (${_filteredEmployees.length})',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).extension<AppColors>()!.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            // Employee list
            SizedBox(
              height: 200,
              child: _filteredEmployees.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'No available employees for this shift'
                            : 'No matching employees',
                        style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textTertiary, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredEmployees.length,
                      itemBuilder: (context, index) {
                        final emp = _filteredEmployees[index];
                        final isCurrentRunner = widget.currentName == emp.name;

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          tileColor: isCurrentRunner
                              ? widget.shiftColor.withOpacity(0.1)
                              : null,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: widget.shiftColor.withOpacity(0.2),
                            child: Text(
                              emp.displayName.isNotEmpty
                                  ? emp.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.shiftColor,
                              ),
                            ),
                          ),
                          title: Text(
                            emp.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrentRunner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            emp.jobCode,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isCurrentRunner
                              ? Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: widget.shiftColor,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, emp.name),
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
        if (widget.currentName != null && widget.currentName!.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}
