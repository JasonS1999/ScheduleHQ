import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/settings.dart' as app_models;
import '../../providers/approval_provider.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/snackbar_helper.dart';
import 'time_off_type_badge.dart';
import 'denial_reason_dialog.dart';

class RequestCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> document;
  final ApprovalProvider approvalProvider;
  final app_models.Settings settings;
  final VoidCallback? onApproved;
  final VoidCallback? onDenied;

  const RequestCard({
    super.key,
    required this.document,
    required this.approvalProvider,
    required this.settings,
    this.onApproved,
    this.onDenied,
  });

  @override
  Widget build(BuildContext context) {
    final data = document.data();
    if (data == null) return const SizedBox.shrink();

    final appColors = context.appColors;
    final theme = Theme.of(context);
    final employeeId = data['employeeLocalId'] as int? ?? 0;
    final employeeName = approvalProvider.getEmployeeName(employeeId);
    final employee = approvalProvider.employeeById[employeeId];
    final timeOffType = data['timeOffType'] as String? ?? 'pto';
    final hours = data['hours'] as int? ?? 8;
    final isAllDay = data['isAllDay'] as bool? ?? true;
    final startTime = data['startTime'] as String?;
    final endTime = data['endTime'] as String?;
    final status = data['status'] as String? ?? 'pending';
    final denialReason = data['denialReason'] as String?;
    final isPending = status == 'pending';
    final isDenied = status == 'denied';

    // Parse dates (stored as ISO strings in timeOff collection)
    final dateStr = data['date'] as String?;
    final startDate = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
    final endDateStr = data['endDate'] as String?;
    final endDate = endDateStr != null ? DateTime.tryParse(endDateStr) : null;

    final dateRangeString = _formatDateRange(startDate, endDate);
    final initials = _getInitials(employeeName);
    final jobCode = employee?.jobCode ?? '';
    final avatarColor = approvalProvider.getJobCodeColor(jobCode);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.defaultPadding,
        vertical: AppConstants.smallPadding,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        side: BorderSide(color: appColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: avatarColor,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + type badge
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          employeeName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TimeOffTypeBadge(timeOffType: timeOffType),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Date range
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: appColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        dateRangeString,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Hours + time range
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: appColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '$hours hours',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (!isAllDay && startTime != null && endTime != null) ...[
                        Text(
                          ' ($startTime - $endTime)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Denial reason (only for denied requests)
                  if (isDenied && denialReason != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: appColors.errorBackground,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusSmall),
                        border: Border.all(color: appColors.errorBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block,
                              size: 14, color: appColors.errorForeground),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Denied: $denialReason',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: appColors.errorForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions (pending only)
            if (isPending) ...[
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _handleApprove(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: appColors.successBackground,
                      foregroundColor: appColors.successForeground,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 16),
                        SizedBox(width: 4),
                        Text('Approve'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _handleDeny(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: appColors.errorForeground,
                      side: BorderSide(color: appColors.errorBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 16),
                        SizedBox(width: 4),
                        Text('Deny'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleApprove(BuildContext context) async {
    final data = document.data();
    final employeeId = data?['employeeLocalId'] as int? ?? 0;
    final employeeName = approvalProvider.getEmployeeName(employeeId);
    final timeOffType = data?['timeOffType'] as String? ?? 'pto';

    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: 'Approve Request',
      message:
          "Approve $employeeName's ${timeOffType.toUpperCase()} request?",
      confirmText: 'Approve',
      icon: Icons.check_circle,
    );

    if (confirmed && context.mounted) {
      final success = await approvalProvider.approveRequest(document, settings);
      if (context.mounted) {
        if (success) {
          SnackBarHelper.showSuccess(context, 'Request approved');
          onApproved?.call();
        } else {
          SnackBarHelper.showError(
            context,
            approvalProvider.errorMessage ?? 'Failed to approve',
          );
        }
      }
    }
  }

  Future<void> _handleDeny(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const DenialReasonDialog(),
    );

    if (reason != null && context.mounted) {
      final success = await approvalProvider.denyRequest(document, reason);
      if (context.mounted) {
        if (success) {
          SnackBarHelper.showSuccess(context, 'Request denied');
          onDenied?.call();
        } else {
          SnackBarHelper.showError(
            context,
            approvalProvider.errorMessage ?? 'Failed to deny',
          );
        }
      }
    }
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    final startStr = '${start.month}/${start.day}/${start.year}';
    if (end == null || end == start) return startStr;
    final endStr = '${end.month}/${end.day}/${end.year}';
    return '$startStr - $endStr';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
