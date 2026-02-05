import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../database/employee_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../models/employee.dart';
import '../models/job_code_settings.dart';

class CsvImportDialog extends StatefulWidget {
  const CsvImportDialog({super.key});

  @override
  State<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<CsvImportDialog> {
  final EmployeeDao _employeeDao = EmployeeDao();
  final JobCodeSettingsDao _jobCodeDao = JobCodeSettingsDao();

  List<JobCodeSettings> _jobCodes = [];
  List<String> _rawNames = [];        // Store raw names for parsing
  List<String> _displayNames = [];    // Store formatted names for display
  int _currentIndex = 0;
  bool _isDragging = false;
  bool _importing = false;
  int _importedCount = 0;

  String? _selectedJobCode;

  @override
  void initState() {
    super.initState();
    _loadJobCodes();
  }

  Future<void> _loadJobCodes() async {
    final codes = await _jobCodeDao.getAll();
    setState(() {
      _jobCodes = codes;
      if (codes.isNotEmpty) {
        _selectedJobCode = codes.first.code;
      }
    });
  }

  /// Convert full name to proper case
  String _formatName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    
    // Split into words and proper case each
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.map(_toProperCase).join(' ');
  }


  /// Convert string to proper case (first letter uppercase, rest lowercase)
  String _toProperCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  /// Parse CSV file and extract employee names from EMPLOYEE column
  Future<void> _parseFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final lines = content.split('\n');

      if (lines.isEmpty) {
        _showError('CSV file is empty');
        return;
      }

      // Find EMPLOYEE column index from header
      final header = _parseCsvLine(lines[0]);
      final employeeColIndex = header.indexWhere(
        (col) => col.trim().toUpperCase() == 'EMPLOYEE',
      );

      if (employeeColIndex == -1) {
        _showError('Could not find EMPLOYEE column in CSV');
        return;
      }

      // Parse each data row and extract names
      final rawNames = <String>[];
      final displayNames = <String>[];
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final columns = _parseCsvLine(line);
        if (columns.length > employeeColIndex) {
          final rawName = columns[employeeColIndex].trim();
          if (rawName.isNotEmpty) {
            final formatted = _formatName(rawName);
            if (formatted.isNotEmpty) {
              rawNames.add(rawName);
              displayNames.add(formatted);
            }
          }
        }
      }

      if (rawNames.isEmpty) {
        _showError('No employee names found in CSV');
        return;
      }

      setState(() {
        _rawNames = rawNames;
        _displayNames = displayNames;
        _currentIndex = 0;
        _importing = true;
      });
    } catch (e) {
      _showError('Error reading file: $e');
    }
  }

  /// Parse a single CSV line, handling quoted fields
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        // Check for escaped quote
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++; // Skip next quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    // Add last field
    result.add(buffer.toString());

    return result;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _importCurrentEmployee() async {
    if (_selectedJobCode == null) return;

    final name = _formatName(_rawNames[_currentIndex]);

    await _employeeDao.insertEmployee(
      Employee(
        firstName: name,
        jobCode: _selectedJobCode!,
        vacationWeeksAllowed: 0,
        vacationWeeksUsed: 0,
      ),
    );

    setState(() {
      _importedCount++;
      _currentIndex++;

      // Reset to first job code for next employee
      if (_jobCodes.isNotEmpty) {
        _selectedJobCode = _jobCodes.first.code;
      }
    });

    // Check if done
    if (_currentIndex >= _rawNames.length) {
      _finishImport();
    }
  }

  void _skipCurrentEmployee() {
    setState(() {
      _currentIndex++;

      // Reset to first job code for next employee
      if (_jobCodes.isNotEmpty) {
        _selectedJobCode = _jobCodes.first.code;
      }
    });

    // Check if done
    if (_currentIndex >= _rawNames.length) {
      _finishImport();
    }
  }

  void _finishImport() {
    Navigator.of(context).pop(_importedCount);
  }

  /// Show dialog to create a new job code
  Future<void> _addNewJobCode() async {
    String code = '';
    
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("New Job Code"),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: "Code Name"),
            onChanged: (v) => code = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (code.trim().isEmpty) return;

                // Get next sort order for new job code
                final nextOrder = await _jobCodeDao.getNextSortOrder();
                final newCode = JobCodeSettings(
                  code: code.trim(),
                  hasPTO: false,
                  maxHoursPerWeek: 40,
                  colorHex: '#4285F4',
                  sortOrder: nextOrder,
                );

                await _jobCodeDao.upsert(newCode);
                Navigator.pop(context, true);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );

    if (created == true) {
      // Reload job codes and select the new one
      final codes = await _jobCodeDao.getAll();
      setState(() {
        _jobCodes = codes;
        // Select the newly created code (it will be at the end or sorted)
        final newCodeEntry = codes.firstWhere(
          (jc) => jc.code.toLowerCase() == code.trim().toLowerCase(),
          orElse: () => codes.first,
        );
        _selectedJobCode = newCodeEntry.code;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: _importing ? _buildImportingUI() : _buildDropZoneUI(),
      ),
    );
  }

  Widget _buildDropZoneUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.upload_file, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Import Roster from CSV',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(0),
            ),
          ],
        ),
        const SizedBox(height: 24),
        DropTarget(
          onDragDone: (details) {
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              if (file.path.toLowerCase().endsWith('.csv')) {
                _parseFile(file.path);
              } else {
                _showError('Please drop a CSV file');
              }
            }
          },
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(
                color: _isDragging ? Theme.of(context).primaryColor : Colors.grey,
                width: _isDragging ? 3 : 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _isDragging
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 64,
                    color: _isDragging
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isDragging
                        ? 'Drop file here'
                        : 'Drag and drop your CSV file here',
                    style: TextStyle(
                      fontSize: 16,
                      color: _isDragging
                          ? Theme.of(context).primaryColor
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'The importer will read employee names from the EMPLOYEE column',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildImportingUI() {
    if (_currentIndex >= _rawNames.length) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentName = _displayNames[_currentIndex];
    final progress = (_currentIndex + 1) / _rawNames.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.person_add, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Assign Job Codes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(_importedCount),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(
          'Employee ${_currentIndex + 1} of ${_rawNames.length}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(Icons.person, size: 48),
              const SizedBox(height: 12),
              Text(
                currentName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Select Job Code:',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedJobCode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: _jobCodes
                    .map(
                      (jc) => DropdownMenuItem(
                        value: jc.code,
                        child: Text(jc.code),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedJobCode = value);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              icon: const Icon(Icons.add),
              tooltip: 'Add New Job Code',
              onPressed: _addNewJobCode,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.skip_next),
              label: const Text('Skip'),
              onPressed: _skipCurrentEmployee,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Add Employee'),
              onPressed: _importCurrentEmployee,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '$_importedCount employee${_importedCount == 1 ? '' : 's'} imported so far',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }
}
