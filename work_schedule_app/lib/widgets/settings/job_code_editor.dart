import 'package:flutter/material.dart';
import '../../models/job_code_settings.dart';
import '../../database/job_code_settings_dao.dart';

class JobCodeEditor extends StatefulWidget {
  final JobCodeSettings settings;

  const JobCodeEditor({super.key, required this.settings});

  @override
  State<JobCodeEditor> createState() => _JobCodeEditorState();
}

class _JobCodeEditorState extends State<JobCodeEditor> {
  late JobCodeSettings _settings;
  final JobCodeSettingsDao _dao = JobCodeSettingsDao();

  List<JobCodeSettings> _allCodes = [];

  late TextEditingController _hoursController;
  late TextEditingController _maxHoursController;
  late TextEditingController _codeController;
  bool _editingCode = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;

    _loadAllCodes();

    _hoursController = TextEditingController(
      text: _settings.defaultDailyHours.toString(),
    );
    _maxHoursController = TextEditingController(
      text: _settings.maxHoursPerWeek.toString(),
    );
    _codeController = TextEditingController(text: _settings.code);
  }

  Future<void> _loadAllCodes() async {
    final codes = await _dao.getAll();
    if (!mounted) return;
    setState(() => _allCodes = codes);
  }

  Future<void> _deleteThisJobCode() async {
    final usage = await _dao.getUsageCounts(_settings.code);
    final employeeCount = usage['employees'] ?? 0;
    final templateCount = usage['templates'] ?? 0;

    final codes = _allCodes.isNotEmpty ? _allCodes : await _dao.getAll();
    if (_allCodes.isEmpty && mounted) {
      setState(() => _allCodes = codes);
    }

    final otherCodes = codes
        .where((c) => c.code.toLowerCase() != _settings.code.toLowerCase())
        .toList();
    String? selectedReplacement = otherCodes.isNotEmpty ? otherCodes.first.code : null;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Delete job code "${_settings.code}"?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('This cannot be undone.'),
                    const SizedBox(height: 8),
                    Text('Employees using it: $employeeCount'),
                    Text('Shift templates tied to it: $templateCount (will be deleted)'),
                    if (employeeCount > 0) ...[
                      const SizedBox(height: 12),
                      const Text('You must reassign those employees first:'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedReplacement),
                        initialValue: selectedReplacement,
                        items: otherCodes
                            .map((jc) => DropdownMenuItem(value: jc.code, child: Text(jc.code)))
                            .toList(),
                        onChanged: otherCodes.isEmpty
                            ? null
                            : (v) => setDialogState(() => selectedReplacement = v),
                        decoration: const InputDecoration(labelText: 'Reassign employees to'),
                      ),
                      if (otherCodes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Add another job code first before deleting this one.',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: (employeeCount > 0 && otherCodes.isEmpty)
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final reassigned = await _dao.deleteJobCode(
      _settings.code,
      reassignEmployeesTo: employeeCount > 0 ? selectedReplacement : null,
    );

    if (!mounted) return;
    if (reassigned == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job code no longer exists.')),
      );
      Navigator.pop(context);
      return;
    }
    if (reassigned == -2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete: employees still assigned and no reassignment selected.')),
      );
      return;
    }

    final msg = reassigned > 0
        ? 'Deleted. Reassigned $reassigned employee(s).'
        : 'Deleted.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _maxHoursController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Color _colorFromHex(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }

  Future<void> _pickColor() async {
    final colors = [
      '#4285F4', // Blue
      '#DB4437', // Red
      '#8E24AA', // Purple
      '#009688', // Teal
      '#F4B400', // Amber
      '#5E35B1', // Deep Purple
      '#039BE5', // Light Blue
      '#43A047', // Green
      '#F4511E', // Orange
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select Color"),
          content: SizedBox(
            width: 300,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((hex) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, hex),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _colorFromHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        _settings = _settings.copyWith(colorHex: selected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _editingCode
                      ? TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(labelText: 'Code'),
                        )
                      : Text(
                          _settings.code,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(_editingCode ? Icons.check : Icons.edit),
                  onPressed: () {
                    setState(() {
                      if (_editingCode) {
                        // Commit editing into local settings object (but don't save DB yet)
                        final newCode = _codeController.text.trim();
                        if (newCode.isNotEmpty) {
                          _settings = JobCodeSettings(
                            code: newCode,
                            hasPTO: _settings.hasPTO,
                            defaultDailyHours: _settings.defaultDailyHours,
                            maxHoursPerWeek: _settings.maxHoursPerWeek,
                            colorHex: _settings.colorHex,
                          );
                        }
                      }
                      _editingCode = !_editingCode;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // PTO Switch
            SwitchListTile(
              title: const Text("PTO Eligible"),
              value: _settings.hasPTO,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(hasPTO: v);
                });
              },
            ),

            // Default Daily Hours
            TextField(
              decoration: const InputDecoration(labelText: "Default Daily Hours"),
              keyboardType: TextInputType.number,
              controller: _hoursController,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(
                    defaultDailyHours: int.tryParse(v) ?? 8,
                  );
                });
              },
            ),

            const SizedBox(height: 12),

            // Max Hours Per Week
            TextField(
              decoration: const InputDecoration(labelText: "Max Hours Per Week"),
              keyboardType: TextInputType.number,
              controller: _maxHoursController,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(
                    maxHoursPerWeek: int.tryParse(v) ?? 40,
                  );
                });
              },
            ),

            const SizedBox(height: 20),

            // Color Picker
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _colorFromHex(_settings.colorHex),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _pickColor,
                  child: const Text("Change Color"),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Save / Delete actions (keep both visible without scrolling)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _deleteThisJobCode,
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final oldCode = widget.settings.code;
                    final newCode = _settings.code.trim();

                    // Build the final settings record to store
                    final finalSettings = JobCodeSettings(
                      code: newCode,
                      hasPTO: _settings.hasPTO,
                      defaultDailyHours: _settings.defaultDailyHours,
                      maxHoursPerWeek: _settings.maxHoursPerWeek,
                      colorHex: _settings.colorHex,
                      sortOrder: _settings.sortOrder,
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);

                    int updated = 0;
                    if (newCode != oldCode) {
                      updated = await _dao.renameCode(oldCode, finalSettings);
                    } else {
                      await _dao.upsert(finalSettings);
                    }

                    if (!mounted) return;
                    if (updated == -1) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('A job code with that name already exists')),
                      );
                      return;
                    }

                    // Provide feedback to the user about how many employee assignments were updated
                    String message = 'Saved.';
                    if (updated > 0) {
                      message = 'Saved. Updated $updated employee(s) to the new job code.';
                    }
                    messenger.showSnackBar(SnackBar(content: Text(message)));

                    navigator.pop();
                  },
                  child: const Text("Save"),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
