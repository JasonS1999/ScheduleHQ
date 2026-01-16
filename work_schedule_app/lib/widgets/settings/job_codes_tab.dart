import 'package:flutter/material.dart';
import '../../database/job_code_settings_dao.dart';
import '../../models/job_code_settings.dart';
import 'job_code_editor.dart';

class JobCodesTab extends StatefulWidget {
  const JobCodesTab({super.key});

  @override
  State<JobCodesTab> createState() => _JobCodesTabState();
}

class _JobCodesTabState extends State<JobCodesTab> {
  final JobCodeSettingsDao _dao = JobCodeSettingsDao();
  List<JobCodeSettings> _codes = [];

  Future<void> _deleteJobCode(JobCodeSettings codeToDelete) async {
    final usage = await _dao.getUsageCounts(codeToDelete.code);
    final employeeCount = usage['employees'] ?? 0;
    final templateCount = usage['templates'] ?? 0;

    final otherCodes = _codes.where((c) => c.code.toLowerCase() != codeToDelete.code.toLowerCase()).toList();
    String? selectedReplacement = otherCodes.isNotEmpty ? otherCodes.first.code : null;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Delete job code "${codeToDelete.code}"?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This will remove the job code from Settings.'),
                    const SizedBox(height: 8),
                    Text('Employees using it: $employeeCount'),
                    Text('Shift templates tied to it: $templateCount (will be deleted)'),
                    if (employeeCount > 0) ...[
                      const SizedBox(height: 12),
                      const Text('You must reassign those employees first:'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedReplacement,
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
      codeToDelete.code,
      reassignEmployeesTo: employeeCount > 0 ? selectedReplacement : null,
    );

    if (!mounted) return;
    if (reassigned == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job code no longer exists.')));
      await _loadCodes();
      return;
    }
    if (reassigned == -2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete: employees still assigned and no reassignment selected.')),
      );
      return;
    }

    // Keep sortOrder compact after deletion
    await _loadCodes();
    await _dao.updateSortOrders(_codes);

    if (!mounted) return;
    final msg = reassigned > 0
        ? 'Deleted. Reassigned $reassigned employee(s).'
        : 'Deleted.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    final list = await _dao.getAll();
    setState(() => _codes = list);
  }

  Future<void> _addJobCode() async {
    String code = "";

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("New Job Code"),
          content: TextField(
            decoration: const InputDecoration(labelText: "Code Name"),
            onChanged: (v) => code = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (code.trim().isEmpty) return;

                // Get next sort order for new job code
                final nextOrder = await _dao.getNextSortOrder();
                final newCode = JobCodeSettings(
                  code: code.trim(),
                  hasPTO: false,
                  defaultDailyHours: 8,
                  maxHoursPerWeek: 40,
                  colorHex: '#4285F4',
                  sortOrder: nextOrder,
                );

                await _dao.upsert(newCode);
                if (!mounted) return;
                Navigator.of(this.context).pop();
                await _loadCodes();
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // ReorderableListView adjusts newIndex when moving down
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    
    setState(() {
      final item = _codes.removeAt(oldIndex);
      _codes.insert(newIndex, item);
    });
    
    // Save the new order to database
    await _dao.updateSortOrders(_codes);
  }

  void _edit(JobCodeSettings settings) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => JobCodeEditor(settings: settings),
    );
    await _loadCodes();
  }

  Color _parseColor(String hex) {
    final colorHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$colorHex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _addJobCode,
              icon: const Icon(Icons.add),
              label: const Text("Add Job Code"),
            ),
            const SizedBox(width: 16),
            const Text(
              "Drag to reorder",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _codes.length,
            onReorder: _onReorder,
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final jc = _codes[index];
              return ListTile(
                key: ValueKey(jc.code),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.drag_handle, color: Colors.grey),
                        const SizedBox(width: 8),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _parseColor(jc.colorHex),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                title: Text(jc.code),
                subtitle: Text(
                  "PTO: ${jc.hasPTO ? 'Yes' : 'No'} • "
                  "Daily: ${jc.defaultDailyHours}h • "
                  "Max/Week: ${jc.maxHoursPerWeek}h",
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${index + 1}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Delete job code',
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _deleteJobCode(jc),
                    ),
                  ],
                ),
                onTap: () => _edit(jc),
              );
            },
          ),
        ),
      ],
    );
  }
}
