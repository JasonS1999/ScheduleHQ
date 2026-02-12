import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/time_off_entry.dart';
import '../../providers/approval_provider.dart';
import '../../providers/employee_provider.dart';
import '../../providers/time_off_provider.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/snackbar_helper.dart';
import 'time_off_type_badge.dart';

class TimeOffCalendarTab extends StatefulWidget {
  final ApprovalProvider approvalProvider;
  final EmployeeProvider employeeProvider;
  final TimeOffProvider timeOffProvider;

  const TimeOffCalendarTab({
    super.key,
    required this.approvalProvider,
    required this.employeeProvider,
    required this.timeOffProvider,
  });

  @override
  State<TimeOffCalendarTab> createState() => _TimeOffCalendarTabState();
}

class _TimeOffCalendarTabState extends State<TimeOffCalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<TimeOffEntry>> get _eventsMap {
    final Map<DateTime, List<TimeOffEntry>> events = {};
    for (final entry in widget.timeOffProvider.allEntries) {
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
      events.putIfAbsent(day, () => []).add(entry);
    }
    return events;
  }

  List<TimeOffEntry> _getEventsForDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return _eventsMap[normalized] ?? [];
  }

  Color _getColorForType(String type, AppColors appColors) {
    switch (type.toLowerCase()) {
      case 'pto':
        return appColors.infoForeground;
      case 'vacation':
        return appColors.successForeground;
      case 'requested':
        return appColors.warningForeground;
      default:
        return appColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Column(
      children: [
        // Calendar
        TableCalendar<TimeOffEntry>(
          firstDay: DateTime(DateTime.now().year - 1),
          lastDay: DateTime(DateTime.now().year + 2),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _getEventsForDay,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            markersMaxCount: 3,
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: events.take(3).map((entry) {
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: _getColorForType(entry.timeOffType, appColors),
                        shape: BoxShape.circle,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onPageChanged: (focusedDay) {
            setState(() => _focusedDay = focusedDay);
          },
        ),
        const Divider(),

        // Day detail panel
        Expanded(
          child: _selectedDay != null
              ? _DayDetailPanel(
                  selectedDay: _selectedDay!,
                  entries: _getEventsForDay(_selectedDay!),
                  approvalProvider: widget.approvalProvider,
                  employeeProvider: widget.employeeProvider,
                  onEntryDeleted: () {
                    widget.approvalProvider.loadApprovedEntries();
                    widget.timeOffProvider.loadData();
                    setState(() {}); // Rebuild to refresh event markers
                  },
                )
              : Center(
                  child: Text(
                    'Select a day to view time-off details',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: appColors.textTertiary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DayDetailPanel extends StatelessWidget {
  final DateTime selectedDay;
  final List<TimeOffEntry> entries;
  final ApprovalProvider approvalProvider;
  final EmployeeProvider employeeProvider;
  final VoidCallback onEntryDeleted;

  const _DayDetailPanel({
    required this.selectedDay,
    required this.entries,
    required this.approvalProvider,
    required this.employeeProvider,
    required this.onEntryDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    final dateStr =
        '${selectedDay.month}/${selectedDay.day}/${selectedDay.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.defaultPadding,
            vertical: AppConstants.smallPadding,
          ),
          child: Row(
            children: [
              Text(
                dateStr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Entries list
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'No time-off entries for this day',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: appColors.textTertiary,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final employee =
                        approvalProvider.employeeById[entry.employeeId];
                    final employeeName =
                        approvalProvider.getEmployeeName(entry.employeeId);
                    final jobCode = employee?.jobCode ?? '';
                    final avatarColor =
                        approvalProvider.getJobCodeColor(jobCode);
                    final initials = _getInitials(employeeName);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: avatarColor,
                        radius: 16,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(employeeName),
                      subtitle: Text(
                        '${entry.hours}h - ${entry.timeRangeDisplay}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TimeOffTypeBadge(timeOffType: entry.timeOffType),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 18, color: appColors.destructive),
                            onPressed: () =>
                                _confirmDelete(context, entry),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, TimeOffEntry entry) async {
    final confirmed = await DialogHelper.showDeleteConfirmDialog(
      context,
      title: 'Delete Time Off Entry',
      message:
          'Delete ${approvalProvider.getEmployeeName(entry.employeeId)}\'s ${entry.timeOffType.toUpperCase()} entry for this day?',
    );

    if (confirmed && context.mounted) {
      final success =
          await approvalProvider.deleteApprovedEntry(entry);
      if (context.mounted) {
        if (success) {
          SnackBarHelper.showSuccess(context, 'Entry deleted');
          onEntryDeleted();
        } else {
          SnackBarHelper.showError(
            context,
            approvalProvider.errorMessage ?? 'Failed to delete',
          );
        }
      }
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
