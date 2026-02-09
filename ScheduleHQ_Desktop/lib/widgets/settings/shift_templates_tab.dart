import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/shift_template.dart';
import '../../providers/store_settings_provider.dart';
import '../../utils/dialog_helper.dart';

class ShiftTemplatesTab extends StatefulWidget {
  const ShiftTemplatesTab({super.key});

  @override
  State<ShiftTemplatesTab> createState() => _ShiftTemplatesTabState();
}

class _ShiftTemplatesTabState extends State<ShiftTemplatesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoreSettingsProvider>().loadShiftTemplates();
    });
  }

  Future<void> _addTemplate() async {
    final provider = context.read<StoreSettingsProvider>();
    String name = '';
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Shift Template'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Template Name'),
                onChanged: (v) => name = v,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Start Time'),
                trailing: Text('${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      startTime = picked;
                    });
                  }
                },
              ),
              ListTile(
                title: const Text('End Time'),
                trailing: Text('${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      endTime = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && name.trim().isNotEmpty) {
      await provider.createShiftTemplate(
        name: name.trim(),
        startTime: startTime,
        endTime: endTime,
      );
    }
  }

  Future<void> _editTemplate(ShiftTemplate template) async {
    final provider = context.read<StoreSettingsProvider>();
    String name = template.templateName;
    TimeOfDay startTime = provider.parseTimeOfDay(template.startTime);
    TimeOfDay endTime = provider.parseTimeOfDay(template.endTime);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Shift Template'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Template Name'),
                controller: TextEditingController(text: name),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Start Time'),
                trailing: Text('${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      startTime = picked;
                    });
                  }
                },
              ),
              ListTile(
                title: const Text('End Time'),
                trailing: Text('${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      endTime = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && name.trim().isNotEmpty) {
      await provider.updateShiftTemplate(
        original: template,
        name: name.trim(),
        startTime: startTime,
        endTime: endTime,
      );
    }
  }

  Future<void> _deleteTemplate(ShiftTemplate template) async {
    final provider = context.read<StoreSettingsProvider>();
    
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: 'Delete Template',
      message: 'Delete "${template.templateName}"?',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );

    if (confirmed) {
      await provider.deleteShiftTemplate(template);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreSettingsProvider>(
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
                  onPressed: () => provider.loadShiftTemplates(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Shift Templates',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create custom shift templates with start and end times. Templates are shared across all job codes.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _addTemplate,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Template'),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: provider.shiftTemplates.isEmpty
                    ? const Center(child: Text('No templates yet'))
                    : ListView.builder(
                        itemCount: provider.shiftTemplates.length,
                        itemBuilder: (context, index) {
                          final template = provider.shiftTemplates[index];

                          return Card(
                            child: ListTile(
                              title: Text(template.templateName),
                              subtitle: Text('${template.startTime} - ${template.endTime}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editTemplate(template),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteTemplate(template),
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
      },
    );
  }
}
