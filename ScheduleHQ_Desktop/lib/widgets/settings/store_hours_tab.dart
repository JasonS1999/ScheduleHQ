import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/store_hours.dart';
import '../../providers/store_settings_provider.dart';

class StoreHoursTab extends StatefulWidget {
  const StoreHoursTab({super.key});

  @override
  State<StoreHoursTab> createState() => _StoreHoursTabState();
}

class _StoreHoursTabState extends State<StoreHoursTab> {
  // Day names for display
  static const List<String> _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  
  // Map day names to DateTime weekday constants
  static const List<int> _dayValues = [
    DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, 
    DateTime.thursday, DateTime.friday, DateTime.saturday
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoreSettingsProvider>().loadStoreHours();
    });
  }

  List<String> _generateTimeOptions() {
    final times = <String>[];
    // Generate times from 12:00 AM to 11:30 PM in 30-minute increments
    for (int hour = 0; hour < 24; hour++) {
      times.add('${hour.toString().padLeft(2, '0')}:00');
      times.add('${hour.toString().padLeft(2, '0')}:30');
    }
    return times;
  }

  String _formatTimeForDisplay(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$h:$minute $suffix';
  }

  String _getOpenTimeForDay(int dayIndex, StoreHours? storeHours) {
    if (storeHours == null) return StoreHours.defaultOpenTime;
    return storeHours.getOpenTimeForDay(_dayValues[dayIndex]);
  }

  String _getCloseTimeForDay(int dayIndex, StoreHours? storeHours) {
    if (storeHours == null) return StoreHours.defaultCloseTime;
    return storeHours.getCloseTimeForDay(_dayValues[dayIndex]);
  }

  Future<void> _updateTimeForDay(int dayIndex, bool isOpen, String? newTime) async {
    if (newTime == null) return;
    
    final provider = context.read<StoreSettingsProvider>();
    await provider.updateStoreHoursTime(dayIndex, isOpen, newTime);
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
                  onPressed: () => provider.loadStoreHours(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final timeOptions = _generateTimeOptions();
        final storeHours = provider.storeHours;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Store Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.business, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Store Information',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This information will appear on PDF exports.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: storeHours?.storeName ?? '',
                              decoration: const InputDecoration(
                                labelText: 'Store Name',
                                hintText: 'e.g., Downtown Store',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.store),
                              ),
                              onChanged: (value) async {
                                await provider.updateStoreName(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: storeHours?.storeNsn ?? '',
                              decoration: const InputDecoration(
                                labelText: 'NSN (Store #)',
                                hintText: 'e.g., 12345',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.tag),
                              ),
                              onChanged: (value) async {
                                await provider.updateStoreNsn(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Store Hours Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Store Operating Hours',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set different open/close times for each day. Times are displayed as "Op" (Open) and "CL" (Close) in the schedule.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Quick apply row
                      Row(
                        children: [
                          const Icon(Icons.copy_all, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text('Quick apply: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          TextButton(
                            onPressed: () => provider.applyToAllDays(
                              _getOpenTimeForDay(1, storeHours), // Use Monday's times
                              _getCloseTimeForDay(1, storeHours),
                            ),
                            child: const Text("Use Monday's hours for all days"),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      
                      // Header row
                      Row(
                        children: [
                          const SizedBox(width: 100), // Day name column
                          Expanded(
                            child: Text(
                              'Opens',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Closes',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Day rows
                      ...List.generate(7, (index) => _buildDayRow(index, timeOptions, storeHours)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.preview, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Preview',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'How times appear in schedule cells:',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPreviewCell('Op', 'Store opens'),
                          const SizedBox(width: 16),
                          const Icon(Icons.arrow_forward, color: Colors.grey),
                          const SizedBox(width: 16),
                          _buildPreviewCell('CL', 'Store closes'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => provider.resetToDefaults(),
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset All to Defaults (4:30 AM - 1:00 AM)'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDayRow(int dayIndex, List<String> timeOptions, StoreHours? storeHours) {
    final openTime = _getOpenTimeForDay(dayIndex, storeHours);
    final closeTime = _getCloseTimeForDay(dayIndex, storeHours);
    final isWeekend = dayIndex == 0 || dayIndex == 6;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isWeekend 
            ? (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100)
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              _dayNames[dayIndex],
              style: TextStyle(
                fontWeight: isWeekend ? FontWeight.w500 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: openTime,
                  isExpanded: true,
                  isDense: true,
                  items: timeOptions.map((time) {
                    return DropdownMenuItem(
                      value: time,
                      child: Text(_formatTimeForDisplay(time), style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (v) => _updateTimeForDay(dayIndex, true, v),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: closeTime,
                  isExpanded: true,
                  isDense: true,
                  items: timeOptions.map((time) {
                    return DropdownMenuItem(
                      value: time,
                      child: Text(_formatTimeForDisplay(time), style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (v) => _updateTimeForDay(dayIndex, false, v),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCell(String label, String description) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
