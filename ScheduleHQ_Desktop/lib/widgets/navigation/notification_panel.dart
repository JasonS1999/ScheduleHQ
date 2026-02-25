import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/notification_item.dart';
import '../../services/app_colors.dart';
import '../common/employee_avatar.dart';
import '../time_off/time_off_type_badge.dart';

class NotificationPanel extends StatelessWidget {
  const NotificationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) {
        Provider.of<NotificationProvider>(context, listen: false).closePanel();
      },
      child: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          // Capture the list once so itemCount and itemBuilder are consistent
          final items = provider.notifications;

          return Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width: 320,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PanelHeader(provider: provider),
                    const Divider(height: 1),
                    Flexible(
                      child: items.isEmpty
                          ? _EmptyState()
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                return _NotificationRow(
                                  notif: items[index],
                                  onMarkRead: () =>
                                      provider.markAsRead(items[index].id),
                                  onDelete: () =>
                                      provider.deleteNotification(items[index].id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final NotificationProvider provider;

  const _PanelHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(
            'Notifications',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (provider.hasUnread)
            TextButton(
              onPressed: provider.markAllAsRead,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
            ),
          IconButton(
            onPressed: provider.closePanel,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 40,
            color: appColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            'No notifications',
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final NotificationItem notif;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  const _NotificationRow({
    required this.notif,
    required this.onMarkRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isPending = notif.status == 'pending';

    final accentColor = isPending
        ? appColors.warningForeground
        : appColors.successForeground;

    final rowBg = notif.isRead
        ? Colors.transparent
        : appColors.infoBackground.withValues(alpha: 0.4);

    return Container(
      color: rowBg,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 3px left accent bar
            Container(width: 3, color: accentColor),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmployeeAvatar(name: notif.employeeName, radius: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            notif.employeeName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: notif.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              color: appColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              TimeOffTypeBadge(timeOffType: notif.timeOffType),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _formatDateRange(notif.date, notif.endDate),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: appColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPending ? 'Pending approval' : 'Approved',
                            style: TextStyle(
                              fontSize: 11,
                              color: accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _relativeTime(notif.arrivedAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: appColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!notif.isRead)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 15,
                                  onPressed: onMarkRead,
                                  icon: const Icon(Icons.mark_email_read_outlined),
                                  tooltip: 'Mark as read',
                                  color: appColors.textSecondary,
                                ),
                              ),
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 15,
                                onPressed: onDelete,
                                icon: const Icon(Icons.close),
                                tooltip: 'Remove',
                                color: appColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(String date, String? endDate) {
    if (date.isEmpty) return '';
    try {
      final start = DateTime.parse(date);
      if (endDate == null || endDate.isEmpty || endDate == date) {
        return _fmtDate(start);
      }
      final end = DateTime.parse(endDate);
      final days = end.difference(start).inDays + 1;
      return '${_fmtShortDate(start)} \u2013 ${_fmtDate(end)} ($days days)';
    } catch (_) {
      return date;
    }
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDate(DateTime d) =>
      '${_months[d.month]} ${d.day}, ${d.year}';

  String _fmtShortDate(DateTime d) =>
      '${_months[d.month]} ${d.day}';

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _fmtShortDate(dt);
  }
}
