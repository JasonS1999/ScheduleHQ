import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../database/shift_type_dao.dart';
import '../../models/shift_type.dart';

class ShiftRunnerColorsTab extends StatefulWidget {
  const ShiftRunnerColorsTab({super.key});

  @override
  State<ShiftRunnerColorsTab> createState() => _ShiftRunnerColorsTabState();
}

class _ShiftRunnerColorsTabState extends State<ShiftRunnerColorsTab> {
  final ShiftTypeDao _dao = ShiftTypeDao();
  List<ShiftType> _shiftTypes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final types = await _dao.getAll();
    if (mounted) {
      setState(() {
        _shiftTypes = types;
        _loading = false;
      });
    }
  }

  Color _hexToColor(String hex) {
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _pickColor(ShiftType shiftType) async {
    Color pickedColor = _hexToColor(shiftType.colorHex);

    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${shiftType.label} Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) => pickedColor = color,
              enableAlpha: false,
              displayThumbColor: true,
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, pickedColor),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final hex = _colorToHex(result);
      await _dao.update(shiftType.copyWith(colorHex: hex));
      await _loadData();
    }
  }

  Future<void> _editShiftType(ShiftType shiftType) async {
    final labelController = TextEditingController(text: shiftType.label);
    String rangeStart = shiftType.rangeStart;
    String rangeEnd = shiftType.rangeEnd;
    String defaultStart = shiftType.defaultShiftStart;
    String defaultEnd = shiftType.defaultShiftEnd;

    final result = await showDialog<ShiftType>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit ${shiftType.label}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Lunch, Morning, etc.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Shift Time Range',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The time window that defines this shift.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeRangePicker(
                      startTime: rangeStart,
                      endTime: rangeEnd,
                      onStartTimeChanged: (time) => setDialogState(() => rangeStart = time),
                      onEndTimeChanged: (time) => setDialogState(() => rangeEnd = time),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Default Employee Shift',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The shift created when a runner is assigned without an existing shift.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeRangePicker(
                      startTime: defaultStart,
                      endTime: defaultEnd,
                      onStartTimeChanged: (time) => setDialogState(() => defaultStart = time),
                      onEndTimeChanged: (time) => setDialogState(() => defaultEnd = time),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (labelController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Shift name is required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, shiftType.copyWith(
                      label: labelController.text,
                      rangeStart: rangeStart,
                      rangeEnd: rangeEnd,
                      defaultShiftStart: defaultStart,
                      defaultShiftEnd: defaultEnd,
                    ));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _dao.update(result);
      await _loadData();
    }
  }

  Future<void> _addShiftType() async {
    final labelController = TextEditingController();
    String rangeStart = '09:00';
    String rangeEnd = '17:00';
    String defaultStart = '09:00';
    String defaultEnd = '17:00';
    Color pickedColor = Colors.teal;

    final result = await showDialog<ShiftType>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Shift Type'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Morning, Mid-Day, etc.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Color',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final result = await showDialog<Color>(
                          context: context,
                          builder: (ctx2) {
                            Color tempColor = pickedColor;
                            return AlertDialog(
                              title: const Text('Pick a Color'),
                              content: SingleChildScrollView(
                                child: ColorPicker(
                                  pickerColor: tempColor,
                                  onColorChanged: (color) => tempColor = color,
                                  enableAlpha: false,
                                  displayThumbColor: true,
                                  pickerAreaHeightPercent: 0.7,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, tempColor),
                                  child: const Text('Select'),
                                ),
                              ],
                            );
                          },
                        );
                        if (result != null) {
                          setDialogState(() => pickedColor = result);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: pickedColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: const Icon(Icons.colorize, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Shift Time Range',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The time window that defines this shift.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeRangePicker(
                      startTime: rangeStart,
                      endTime: rangeEnd,
                      onStartTimeChanged: (time) => setDialogState(() => rangeStart = time),
                      onEndTimeChanged: (time) => setDialogState(() => rangeEnd = time),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Default Employee Shift',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The shift created when a runner is assigned without an existing shift.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeRangePicker(
                      startTime: defaultStart,
                      endTime: defaultEnd,
                      onStartTimeChanged: (time) => setDialogState(() => defaultStart = time),
                      onEndTimeChanged: (time) => setDialogState(() => defaultEnd = time),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (labelController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Shift name is required')),
                      );
                      return;
                    }
                    final nextOrder = await _dao.getNextSortOrder();
                    Navigator.pop(ctx, ShiftType(
                      key: ShiftType.generateKey(),
                      label: labelController.text,
                      sortOrder: nextOrder,
                      rangeStart: rangeStart,
                      rangeEnd: rangeEnd,
                      defaultShiftStart: defaultStart,
                      defaultShiftEnd: defaultEnd,
                      colorHex: _colorToHex(pickedColor),
                    ));
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _dao.insert(result);
      await _loadData();
    }
  }

  Future<void> _deleteShiftType(ShiftType shiftType) async {
    if (_shiftTypes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the last shift type')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Shift Type'),
        content: Text('Are you sure you want to delete "${shiftType.label}"? '
            'This will not delete existing shift runner assignments, but they will no longer be displayed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dao.delete(shiftType.id!);
      await _loadData();
    }
  }

  void _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    setState(() {
      final item = _shiftTypes.removeAt(oldIndex);
      _shiftTypes.insert(newIndex, item);
    });
    
    await _dao.updateSortOrders(_shiftTypes);
    await _loadData();
  }

  Widget _buildTimeRangePicker({
    required String startTime,
    required String endTime,
    required Function(String) onStartTimeChanged,
    required Function(String) onEndTimeChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Start Time'),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final parts = startTime.split(':');
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.parse(parts[0]),
                      minute: int.parse(parts[1]),
                    ),
                  );
                  if (picked != null) {
                    onStartTimeChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(startTime)),
                      const Icon(Icons.access_time, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('End Time'),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final parts = endTime.split(':');
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.parse(parts[0]),
                      minute: int.parse(parts[1]),
                    ),
                  );
                  if (picked != null) {
                    onEndTimeChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(endTime)),
                      const Icon(Icons.access_time, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(String time24) {
    final parts = time24.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Shift Types',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addShiftType,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Shift'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure your shift types. Drag to reorder, click the color to change it, or use the settings icon to edit details.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _shiftTypes.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final shiftType = _shiftTypes[index];
                final color = _hexToColor(shiftType.colorHex);
                
                // Check if default employee shift differs from range
                final hasCustomEmployeeShift = 
                    shiftType.defaultShiftStart != shiftType.rangeStart ||
                    shiftType.defaultShiftEnd != shiftType.rangeEnd;
                
                return Card(
                  key: ValueKey(shiftType.id),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _pickColor(shiftType),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Icon(Icons.colorize, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      shiftType.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          '${_formatTime(shiftType.rangeStart)} - ${_formatTime(shiftType.rangeEnd)}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        if (hasCustomEmployeeShift) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color.withOpacity(0.3)),
                            ),
                            child: Text(
                              'Default: ${_formatTime(shiftType.defaultShiftStart)} - ${_formatTime(shiftType.defaultShiftEnd)}',
                              style: TextStyle(fontSize: 11, color: color),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            shiftType.colorHex.toUpperCase(),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: () => _editShiftType(shiftType),
                          tooltip: 'Edit shift settings',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteShiftType(shiftType),
                          tooltip: 'Delete shift type',
                          color: Colors.red.shade300,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
