import 'package:flutter/material.dart';
import '../../database/shift_runner_dao.dart';
import '../../database/shift_runner_color_dao.dart';
import '../../database/employee_dao.dart';
import '../../models/shift_runner.dart';
import '../../models/shift_runner_color.dart';
import '../../models/employee.dart';

class ShiftRunnerTable extends StatefulWidget {
  final DateTime weekStart;
  final VoidCallback? onChanged;

  const ShiftRunnerTable({
    super.key,
    required this.weekStart,
    this.onChanged,
  });

  @override
  State<ShiftRunnerTable> createState() => _ShiftRunnerTableState();
}

class _ShiftRunnerTableState extends State<ShiftRunnerTable> {
  final ShiftRunnerDao _dao = ShiftRunnerDao();
  final ShiftRunnerColorDao _colorDao = ShiftRunnerColorDao();
  final EmployeeDao _employeeDao = EmployeeDao();
  
  List<ShiftRunner> _runners = [];
  List<Employee> _employees = [];
  Map<String, String> _colors = {};
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(ShiftRunnerTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final weekEnd = widget.weekStart.add(const Duration(days: 6));
    final runners = await _dao.getForDateRange(widget.weekStart, weekEnd);
    final employees = await _employeeDao.getEmployees();
    final colors = await _colorDao.getColorMap();
    
    if (mounted) {
      setState(() {
        _runners = runners;
        _employees = employees;
        _colors = colors;
      });
    }
  }

  String? _getRunnerForCell(DateTime day, String shiftType) {
    final runner = _runners.cast<ShiftRunner?>().firstWhere(
      (r) => r != null &&
          r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day &&
          r.shiftType == shiftType,
      orElse: () => null,
    );
    return runner?.runnerName;
  }

  Future<void> _editRunner(DateTime day, String shiftType, String? currentName) async {
    final controller = TextEditingController(text: currentName ?? '');
    
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${ShiftRunner.getLabelForType(shiftType)} Runner - ${day.month}/${day.day}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Runner Name',
                  hintText: 'Enter name or select below',
                ),
                autofocus: true,
                onSubmitted: (value) => Navigator.pop(ctx, value),
              ),
              const SizedBox(height: 16),
              if (_employees.isNotEmpty) ...[
                const Text('Quick select:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  width: 250,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _employees.length,
                    itemBuilder: (context, index) {
                      final emp = _employees[index];
                      return ListTile(
                        dense: true,
                        title: Text(emp.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(emp.jobCode, style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, emp.name),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (currentName != null && currentName.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (result.isEmpty) {
        await _dao.clear(day, shiftType);
      } else {
        await _dao.upsert(ShiftRunner(
          date: day,
          shiftType: shiftType,
          runnerName: result,
        ));
      }
      await _loadData();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => widget.weekStart.add(Duration(days: i)));
    final shiftTypes = ShiftRunner.shiftOrder;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          // Header with expand/collapse
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Shift Runner',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    _isExpanded ? 'Click to collapse' : 'Click to expand',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          
          // Table content
          if (_isExpanded)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(80),
                  columnWidths: const {
                    0: FixedColumnWidth(60), // Shift type column
                  },
                  border: TableBorder.all(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  children: [
                    // Header row with days
                    TableRow(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                      ),
                      children: [
                        _buildHeaderCell(''),
                        ...days.map((d) => _buildHeaderCell(
                          '${_dayAbbr(d.weekday)}\n${d.month}/${d.day}',
                        )),
                      ],
                    ),
                    // Rows for each shift type
                    ...shiftTypes.map((shiftType) {
                      return TableRow(
                        children: [
                          _buildShiftTypeCell(shiftType),
                          ...days.map((day) {
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
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildShiftTypeCell(String shiftType) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      color: _getShiftColor(shiftType).withOpacity(0.2),
      child: Text(
        ShiftRunner.getLabelForType(shiftType),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: _getShiftColor(shiftType),
        ),
      ),
    );
  }

  Widget _buildRunnerCell(DateTime day, String shiftType, String? runner) {
    final hasRunner = runner != null && runner.isNotEmpty;
    
    return InkWell(
      onTap: () => _editRunner(day, shiftType, runner),
      child: Container(
        padding: const EdgeInsets.all(4),
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 36),
        decoration: BoxDecoration(
          color: hasRunner 
              ? _getShiftColor(shiftType).withOpacity(0.1)
              : null,
        ),
        child: Text(
          runner ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: hasRunner ? Colors.black87 : Colors.grey,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Color _getShiftColor(String shiftType) {
    final hex = _colors[shiftType] ?? ShiftRunnerColor.defaultColors[shiftType] ?? '#808080';
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  String _dayAbbr(int weekday) {
    const abbrs = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return abbrs[weekday];
  }
}
