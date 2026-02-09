import 'package:flutter/material.dart';
import '../../utils/app_constants.dart';

/// A standardized error message widget used throughout the app
class ErrorMessage extends StatelessWidget {
  /// The error message to display
  final String message;
  
  /// Optional detailed error message
  final String? details;
  
  /// The icon to show with the error
  final IconData? icon;
  
  /// Callback for retry action
  final VoidCallback? onRetry;
  
  /// Text for the retry button
  final String? retryText;
  
  /// Whether to show the error in a card
  final bool showCard;
  
  /// Whether to center the error message
  final bool centered;
  
  /// The padding around the error message
  final EdgeInsets? padding;

  const ErrorMessage({
    super.key,
    required this.message,
    this.details,
    this.icon,
    this.onRetry,
    this.retryText,
    this.showCard = false,
    this.centered = true,
    this.padding,
  });

  /// Network error variant with appropriate icon and styling
  const ErrorMessage.network({
    super.key,
    this.message = AppConstants.networkErrorMessage,
    this.details,
    this.onRetry,
    this.retryText = 'Retry',
    this.showCard = true,
    this.centered = true,
    this.padding,
  }) : icon = Icons.wifi_off;

  /// Database error variant
  const ErrorMessage.database({
    super.key,
    this.message = AppConstants.databaseErrorMessage,
    this.details,
    this.onRetry,
    this.retryText = 'Retry',
    this.showCard = true,
    this.centered = true,
    this.padding,
  }) : icon = Icons.storage;

  /// Generic error variant
  const ErrorMessage.generic({
    super.key,
    this.message = AppConstants.defaultErrorMessage,
    this.details,
    this.onRetry,
    this.retryText = 'Retry',
    this.showCard = true,
    this.centered = true,
    this.padding,
  }) : icon = Icons.error_outline;

  /// Inline error variant for forms or small spaces
  const ErrorMessage.inline({
    super.key,
    required this.message,
    this.details,
    this.onRetry,
    this.retryText,
    this.padding,
  }) : icon = Icons.warning,
        showCard = false,
        centered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectivePadding = padding ?? const EdgeInsets.all(AppConstants.defaultPadding);
    
    Widget errorWidget = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: showCard ? 48 : 24,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
        ],
        Text(
          message,
          style: showCard
              ? theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                )
              : theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
          textAlign: centered ? TextAlign.center : TextAlign.left,
        ),
        if (details != null) ...[
          const SizedBox(height: 8),
          Text(
            details!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
            ),
            textAlign: centered ? TextAlign.center : TextAlign.left,
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retryText ?? 'Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          ),
        ],
      ],
    );

    if (showCard) {
      errorWidget = Card(
        elevation: AppConstants.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          side: BorderSide(
            color: theme.colorScheme.error.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: effectivePadding,
          child: errorWidget,
        ),
      );
    } else {
      errorWidget = Padding(
        padding: effectivePadding,
        child: errorWidget,
      );
    }

    return centered ? Center(child: errorWidget) : errorWidget;
  }
}

/// A banner-style error message for page-level errors
class ErrorBanner extends StatelessWidget {
  /// The error message to display
  final String message;
  
  /// Callback for dismiss action
  final VoidCallback? onDismiss;
  
  /// Callback for action button
  final VoidCallback? onAction;
  
  /// Text for the action button
  final String? actionText;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.onAction,
    this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.error.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.defaultPadding,
          vertical: AppConstants.smallPadding,
        ),
        child: Row(
          children: [
            Icon(
              Icons.error,
              color: theme.colorScheme.error,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionText ?? 'Retry',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
            if (onDismiss != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.error,
                  size: 18,
                ),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact error widget for list items
class ErrorListItem extends StatelessWidget {
  /// The error message to display
  final String message;
  
  /// Callback for retry action
  final VoidCallback? onRetry;

  const ErrorListItem({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return ListTile(
      leading: Icon(
        Icons.error_outline,
        color: theme.colorScheme.error,
      ),
      title: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      trailing: onRetry != null
          ? IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              color: theme.colorScheme.primary,
            )
          : null,
    );
  }
}