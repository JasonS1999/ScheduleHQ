import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/job_code_settings.dart';
import '../../models/job_code_group.dart';
import '../../providers/job_code_provider.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/snackbar_helper.dart';
import 'job_code_editor.dart';

class JobCodesTab extends StatefulWidget {
  const JobCodesTab({super.key});

  @override
  State<JobCodesTab> createState() => _JobCodesTabState();
}

class _JobCodesTabState extends State<JobCodesTab> {
  bool _orderDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobCodeProvider>().initialize();
    });
  }

  Future<void> _deleteJobCode(JobCodeSettings codeToDelete) async {
    final provider = context.read<JobCodeProvider>();
    final success = await provider.deleteJobCodeWithDialog(codeToDelete);
    if (success && mounted) {
      _orderDirty = false;
    }
  }

  Future<void> _addJobCode() async {
    final provider = context.read<JobCodeProvider>();
    String code = "";

    final result = await DialogHelper.showInputDialog(
      context,
      title: "New Job Code",
      labelText: "Code Name",
      onChanged: (v) => code = v,
    );

    if (result == true && code.trim().isNotEmpty) {
      await provider.addJobCode(code: code.trim(), colorHex: '#4285F4', hasPTO: false);
      setState(() => _orderDirty = false);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final provider = context.read<JobCodeProvider>();
    // ReorderableListView adjusts newIndex when moving down
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    
    provider.reorderJobCode(oldIndex, newIndex);
    setState(() => _orderDirty = true);
  }

  Future<void> _saveOrder() async {
    final provider = context.read<JobCodeProvider>();
    final success = await provider.saveOrder();
    if (success && mounted) {
      setState(() => _orderDirty = false);
      SnackBarHelper.showSuccess(context, 'Saved job code order.');
    }
  }

  void _edit(JobCodeSettings settings) async {
    final provider = context.read<JobCodeProvider>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => JobCodeEditor(
        settings: settings, 
        groups: provider.groups
      ),
    );
    // Refresh data after editing
    await provider.loadData();
  }

  Future<void> _manageGroups() async {
    final provider = context.read<JobCodeProvider>();
    await showDialog(
      context: context,
      builder: (context) => _GroupsDialog(
        groups: provider.groups,
        provider: provider,
        onGroupsChanged: () async {
          await provider.loadGroups();
        },
      ),
    );
    await provider.loadGroups();
  }

  Color _parseColor(String hex) {
    final colorHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$colorHex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JobCodeProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error?.isNotEmpty ?? false) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${provider.error}'),
                ElevatedButton(
                  onPressed: () => provider.loadData(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

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
                itemCount: provider.jobCodes.length,
                onReorder: _onReorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final jc = provider.jobCodes[index];
                  final group = jc.sortGroup != null
                      ? provider.groups.where((g) => g.name == jc.sortGroup).firstOrNull
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
      },
    );
  }
}

// Dialog for managing groups
class _GroupsDialog extends StatefulWidget {
  final List<JobCodeGroup> groups;
  final JobCodeProvider provider;
  final VoidCallback onGroupsChanged;

  const _GroupsDialog({
    required this.groups,
    required this.provider,
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
    await widget.provider.loadGroups();
    setState(() => _groups = List.from(widget.provider.groups));
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
      await widget.provider.addGroup(name: name.trim(), colorHex: colorHex);
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
      await widget.provider.updateGroup(group.copyWith(name: name.trim(), colorHex: colorHex));
      await _loadGroups();
    }
  }

  Future<void> _deleteGroup(JobCodeGroup group) async {
    final confirmed = await DialogHelper.showDeleteConfirmDialog(
      context,
      title: 'Delete group "${group.name}"?',
      message: 'Job codes in this group will become ungrouped.',
    );

    if (confirmed) {
      await widget.provider.deleteGroup(group.name);
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
