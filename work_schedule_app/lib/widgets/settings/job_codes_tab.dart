import 'package:flutter/material.dart';
import '../../database/job_code_settings_dao.dart';
import '../../database/job_code_group_dao.dart';
import '../../models/job_code_settings.dart';
import '../../models/job_code_group.dart';
import 'job_code_editor.dart';

class JobCodesTab extends StatefulWidget {
  const JobCodesTab({super.key});

  @override
  State<JobCodesTab> createState() => _JobCodesTabState();
}

class _JobCodesTabState extends State<JobCodesTab> {
  final JobCodeSettingsDao _dao = JobCodeSettingsDao();
  final JobCodeGroupDao _groupDao = JobCodeGroupDao();
  List<JobCodeSettings> _codes = [];
  List<JobCodeGroup> _groups = [];
  bool _orderDirty = false;

  Future<void> _deleteJobCode(JobCodeSettings codeToDelete) async {
    final usage = await _dao.getUsageCounts(codeToDelete.code);
    final employeeCount = usage['employees'] ?? 0;

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
    _init();
  }

  Future<void> _init() async {
    await _dao.insertDefaultsIfMissing();
    await _loadCodes();
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    final list = await _groupDao.getAll();
    setState(() => _groups = list);
  }

  Future<void> _loadCodes() async {
    final list = await _dao.getAll();
    setState(() {
      _codes = list;
      _orderDirty = false;
    });
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
      _orderDirty = true;
    });
  }

  Future<void> _saveOrder() async {
    await _dao.updateSortOrders(_codes);
    if (!mounted) return;
    setState(() => _orderDirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved job code order.')),
    );
  }

  void _edit(JobCodeSettings settings) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => JobCodeEditor(settings: settings, groups: _groups),
    );
    await _loadCodes();
    await _loadGroups();
  }

  Future<void> _manageGroups() async {
    await showDialog(
      context: context,
      builder: (context) => _GroupsDialog(
        groups: _groups,
        groupDao: _groupDao,
        onGroupsChanged: () async {
          await _loadGroups();
        },
      ),
    );
    await _loadGroups();
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
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _addJobCode,
              icon: const Icon(Icons.add),
              label: const Text("Add Job Code"),
            ),
            ElevatedButton.icon(
              onPressed: _manageGroups,
              icon: const Icon(Icons.folder_outlined),
              label: const Text("Manage Groups"),
            ),
            ElevatedButton.icon(
              onPressed: _orderDirty ? _saveOrder : null,
              icon: const Icon(Icons.save),
              label: const Text('Save Order'),
            ),
            if (_orderDirty)
              const Text(
                'Reordered (not saved yet)',
                style: TextStyle(color: Colors.orange, fontSize: 12),
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
              final group = jc.sortGroup != null
                  ? _groups.where((g) => g.name == jc.sortGroup).firstOrNull
                  : null;
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
                  "Max/Week: ${jc.maxHoursPerWeek}h",
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (group != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _parseColor(group.colorHex).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _parseColor(group.colorHex)),
                        ),
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: _parseColor(group.colorHex),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Text(
                        'No group',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
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

// Dialog for managing groups
class _GroupsDialog extends StatefulWidget {
  final List<JobCodeGroup> groups;
  final JobCodeGroupDao groupDao;
  final VoidCallback onGroupsChanged;

  const _GroupsDialog({
    required this.groups,
    required this.groupDao,
    required this.onGroupsChanged,
  });

  @override
  State<_GroupsDialog> createState() => _GroupsDialogState();
}

class _GroupsDialogState extends State<_GroupsDialog> {
  late List<JobCodeGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = List.from(widget.groups);
  }

  Future<void> _loadGroups() async {
    final list = await widget.groupDao.getAll();
    setState(() => _groups = list);
    widget.onGroupsChanged();
  }

  Color _parseColor(String hex) {
    final colorHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$colorHex', radix: 16));
  }

  Future<void> _addGroup() async {
    String name = '';
    String colorHex = '#4285F4';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Group'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Group Name'),
                    onChanged: (v) => name = v,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Color: '),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final selected = await _pickColor(context, colorHex);
                          if (selected != null) {
                            setDialogState(() => colorHex = selected);
                          }
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _parseColor(colorHex),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && name.trim().isNotEmpty) {
      final nextOrder = _groups.isEmpty ? 1 : (_groups.map((g) => g.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
      await widget.groupDao.insert(JobCodeGroup(
        name: name.trim(),
        colorHex: colorHex,
        sortOrder: nextOrder,
      ));
      await _loadGroups();
    }
  }

  Future<String?> _pickColor(BuildContext context, String currentColor) async {
    final colors = [
      '#4285F4', '#DB4437', '#8E24AA', '#009688', '#F4B400',
      '#5E35B1', '#039BE5', '#43A047', '#F4511E', '#795548',
      '#607D8B', '#E91E63', '#00BCD4', '#CDDC39',
    ];

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Color'),
          content: SizedBox(
            width: 280,
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
                      color: _parseColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hex == currentColor ? Colors.black : Colors.black12,
                        width: hex == currentColor ? 2 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editGroup(JobCodeGroup group) async {
    String name = group.name;
    String colorHex = group.colorHex;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Group'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: 'Group Name'),
                    onChanged: (v) => name = v,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Color: '),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final selected = await _pickColor(context, colorHex);
                          if (selected != null) {
                            setDialogState(() => colorHex = selected);
                          }
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _parseColor(colorHex),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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

    if (result == true && name.trim().isNotEmpty) {
      if (name.trim() != group.name) {
        // Rename group (updates all job codes)
        await widget.groupDao.rename(group.name, name.trim());
      }
      // Update color
      final updated = JobCodeGroup(
        name: name.trim(),
        colorHex: colorHex,
        sortOrder: group.sortOrder,
      );
      await widget.groupDao.update(updated);
      await _loadGroups();
    }
  }

  Future<void> _deleteGroup(JobCodeGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete group "${group.name}"?'),
        content: const Text('Job codes in this group will become ungrouped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.groupDao.delete(group.name);
      await _loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Groups'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _addGroup,
              icon: const Icon(Icons.add),
              label: const Text('Add Group'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _groups.isEmpty
                  ? const Center(
                      child: Text(
                        'No groups yet.\nGroups let you organize job codes together.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _groups.length,
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        return ListTile(
                          leading: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _parseColor(group.colorHex),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(group.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _deleteGroup(group),
                          ),
                          onTap: () => _editGroup(group),
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
          child: const Text('Done'),
        ),
      ],
    );
  }
}
