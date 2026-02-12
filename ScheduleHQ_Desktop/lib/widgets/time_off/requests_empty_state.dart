import 'package:flutter/material.dart';
import '../../services/app_colors.dart';

class RequestsEmptyState extends StatelessWidget {
  final bool isDeniedView;

  const RequestsEmptyState({super.key, this.isDeniedView = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDeniedView ? Icons.check_circle_outline : Icons.inbox_outlined,
              size: 80,
              color: appColors.textTertiary,
            ),
            const SizedBox(height: 24),
            Text(
              isDeniedView ? 'No denied requests' : 'No pending requests',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: appColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isDeniedView
                  ? 'Denied requests will appear here.'
                  : 'When employees submit time-off requests, they will appear here for your review.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
