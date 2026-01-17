import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../database/shift_runner_color_dao.dart';
import '../../models/shift_runner_color.dart';
import '../../models/shift_runner.dart';

class ShiftRunnerColorsTab extends StatefulWidget {
  const ShiftRunnerColorsTab({super.key});

  @override
  State<ShiftRunnerColorsTab> createState() => _ShiftRunnerColorsTabState();
}

class _ShiftRunnerColorsTabState extends State<ShiftRunnerColorsTab> {
  final ShiftRunnerColorDao _dao = ShiftRunnerColorDao();
  Map<String, String> _colors = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  Future<void> _loadColors() async {
    await _dao.insertDefaultsIfMissing();
    final colors = await _dao.getColorMap();
    if (mounted) {
      setState(() {
        _colors = colors;
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

  Future<void> _pickColor(String shiftType) async {
    final currentHex = _colors[shiftType] ?? ShiftRunnerColor.defaultColors[shiftType]!;
    Color pickedColor = _hexToColor(currentHex);

    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${ShiftRunner.getLabelForType(shiftType)} Color'),
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
      await _dao.upsert(ShiftRunnerColor(shiftType: shiftType, colorHex: hex));
      await _loadColors();
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Colors'),
        content: const Text('Reset all shift runner colors to defaults?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dao.resetToDefaults();
      await _loadColors();
    }
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
                'Shift Runner Colors',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Reset to Defaults'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Customize the colors used to highlight shift runners on the schedule.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: ShiftRunner.shiftOrder.map((shiftType) {
                final hex = _colors[shiftType] ?? ShiftRunnerColor.defaultColors[shiftType]!;
                final color = _hexToColor(hex);
                final shiftInfo = ShiftRunner.shiftTimes[shiftType]!;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: InkWell(
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
                    title: Text(
                      ShiftRunner.getLabelForType(shiftType),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${shiftInfo['start']} - ${shiftInfo['end']}',
                      style: TextStyle(color: Colors.grey[600]),
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
                            hex.toUpperCase(),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _pickColor(shiftType),
                          tooltip: 'Change color',
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
