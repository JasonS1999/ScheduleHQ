import 'package:flutter/material.dart';
import '../../database/shift_template_dao.dart';
import '../../database/job_code_settings_dao.dart';
import '../../models/shift_template.dart';
import '../../models/job_code_settings.dart';

class ShiftTemplatesTab extends StatefulWidget {
  const ShiftTemplatesTab({super.key});

  @override
  State<ShiftTemplatesTab> createState() => _ShiftTemplatesTabState();
}

class _ShiftTemplatesTabState extends State<ShiftTemplatesTab> {
  final ShiftTemplateDao _templateDao = ShiftTemplateDao();
  final JobCodeSettingsDao _jobCodeDao = JobCodeSettingsDao();
  
  List<JobCodeSettings> _jobCodes = [];
  Map<String, List<ShiftTemplate>> _templatesByJobCode = {};
  String? _selectedJobCode;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _jobCodeDao.insertDefaultsIfMissing();
    final jobCodes = await _jobCodeDao.getAll();
    final allTemplates = await _templateDao.getAllTemplates();
    
    // Group templates by job code
    final Map<String, List<ShiftTemplate>> grouped = {};
    for (var template in allTemplates) {
      grouped.putIfAbsent(template.jobCode, () => []).add(template);
    }

    // Ensure default templates exist for each job code
    for (var jobCode in jobCodes) {
      await _templateDao.insertDefaultTemplatesIfMissing(jobCode.code);
      if (!grouped.containsKey(jobCode.code)) {
        grouped[jobCode.code] = await _templateDao.getTemplatesForJobCode(jobCode.code);
      }
    }

    setState(() {
      _jobCodes = jobCodes;
      _templatesByJobCode = grouped;
      if (_selectedJobCode == null && jobCodes.isNotEmpty) {
        _selectedJobCode = jobCodes.first.code;
      }
    });
  }

  Future<void> _addTemplate() async {
    if (_selectedJobCode == null) return;

    String name = '';
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);

    await showDialog(
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (name.trim().isEmpty) return;
                
                final template = ShiftTemplate(
                  jobCode: _selectedJobCode!,
                  templateName: name.trim(),
                  startTime: '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                );
                
                await _templateDao.insertTemplate(template);
                Navigator.pop(context);
                _loadData();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTemplate(ShiftTemplate template) async {
    String name = template.templateName;
    final parts = template.startTime.split(':');
    TimeOfDay startTime = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    await showDialog(
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (name.trim().isEmpty) return;
                
                final updated = template.copyWith(
                  templateName: name.trim(),
                  startTime: '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                );
                
                await _templateDao.updateTemplate(updated);
                Navigator.pop(context);
                _loadData();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTemplate(ShiftTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Delete "${template.templateName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && template.id != null) {
      await _templateDao.deleteTemplate(template.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _selectedJobCode != null 
        ? (_templatesByJobCode[_selectedJobCode!] ?? [])
        : <ShiftTemplate>[];

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
            'Create custom shift templates for each job code. Templates use the default shift hours from Job Code Settings.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Job Code: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedJobCode,
                  isExpanded: true,
                  items: _jobCodes.map((jc) => DropdownMenuItem(
                    value: jc.code,
                    child: Text(jc.code),
                  )).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedJobCode = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _addTemplate,
                icon: const Icon(Icons.add),
                label: const Text('Add Template'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: templates.isEmpty
                ? const Center(child: Text('No templates for this job code'))
                : ListView.builder(
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      final jobCode = _jobCodes.firstWhere(
                        (jc) => jc.code == template.jobCode,
                        orElse: () => JobCodeSettings(
                          code: template.jobCode,
                          hasPTO: true,
                          defaultDailyHours: 8.0,
                          maxHoursPerWeek: 40,
                          colorHex: '#000000',
                        ),
                      );
                      final duration = jobCode.defaultDailyHours;
                      final startParts = template.startTime.split(':');
                      final startHour = int.parse(startParts[0]);
                      final startMin = int.parse(startParts[1]);
                      final endTime = DateTime(2000, 1, 1, startHour, startMin)
                          .add(Duration(minutes: (duration * 60).round()));
                      final endTimeStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                      return Card(
                        child: ListTile(
                          title: Text(template.templateName),
                          subtitle: Text('${template.startTime} - $endTimeStr (${duration % 1 == 0 ? duration.toInt() : duration} hours)'),
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
  }
}
