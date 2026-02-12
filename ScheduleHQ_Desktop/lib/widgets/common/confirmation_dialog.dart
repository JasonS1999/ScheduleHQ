import 'package:flutter/material.dart';
import '../../utils/app_constants.dart';

/// A reusable confirmation dialog widget
class ConfirmationDialog extends StatelessWidget {
  /// The title of the dialog
  final String title;
  
  /// The message/content of the dialog
  final String message;
  
  /// Text for the confirm button
  final String confirmText;
  
  /// Text for the cancel button
  final String cancelText;
  
  /// Color for the confirm button
  final Color? confirmColor;
  
  /// Icon to show in the dialog
  final IconData? icon;
  
  /// Whether the dialog is destructive (uses error colors)
  final bool isDestructive;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
    this.confirmColor,
    this.icon,
    this.isDestructive = false,
  });

  /// Delete confirmation dialog variant
  const ConfirmationDialog.delete({
    super.key,
    required this.title,
    required this.message,
    this.cancelText = 'Cancel',
  }) : confirmText = 'Delete',
        confirmColor = null,
        icon = Icons.delete,
        isDestructive = true;

  /// Save changes confirmation dialog variant
  const ConfirmationDialog.saveChanges({
    super.key,
    this.title = 'Save Changes',
    this.message = 'Do you want to save your changes?',
    this.cancelText = 'Don\'t Save',
  }) : confirmText = 'Save',
        confirmColor = null,
        icon = Icons.save,
        isDestructive = false;

  /// Discard changes confirmation dialog variant
  const ConfirmationDialog.discardChanges({
    super.key,
    this.title = 'Discard Changes',
    this.message = AppConstants.unsavedChangesMessage,
    this.cancelText = 'Keep Editing',
  }) : confirmText = 'Discard',
        confirmColor = null,
        icon = Icons.warning,
        isDestructive = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveConfirmColor = isDestructive
        ? theme.colorScheme.error
        : confirmColor ?? theme.colorScheme.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius * 1.5),
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: isDestructive ? theme.colorScheme.error : effectiveConfirmColor,
              size: 28,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: theme.textTheme.bodyMedium,
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(
            cancelText,
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: effectiveConfirmColor,
            foregroundColor: isDestructive
                ? theme.colorScheme.onError
                : theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
          ),
          child: Text(
            confirmText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// Static method to show the dialog and return the result
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
    IconData? icon,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmColor: confirmColor,
        icon: icon,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  /// Static method to show a delete confirmation dialog
  static Future<bool> showDelete({
    required BuildContext context,
    required String title,
    required String message,
    String cancelText = 'Cancel',
  }) async {
    return await show(
      context: context,
      title: title,
      message: message,
      confirmText: 'Delete',
      cancelText: cancelText,
      icon: Icons.delete,
      isDestructive: true,
    );
  }

  /// Static method to show unsaved changes dialog
  static Future<bool> showUnsavedChanges({
    required BuildContext context,
    String title = AppConstants.unsavedChangesTitle,
    String message = AppConstants.unsavedChangesMessage,
  }) async {
    return await show(
      context: context,
      title: title,
      message: message,
      confirmText: 'Leave',
      cancelText: 'Stay',
      icon: Icons.warning,
      isDestructive: true,
    );
  }
}

/// A custom choice dialog for multiple options
class ChoiceDialog<T> extends StatelessWidget {
  /// The title of the dialog
  final String title;
  
  /// Optional description/message
  final String? message;
  
  /// The list of choices to display
  final List<ChoiceOption<T>> options;
  
  /// The currently selected value
  final T? selectedValue;
  
  /// Whether to show radio buttons (single selection)
  final bool showRadioButtons;
  
  /// Icon to show in the dialog
  final IconData? icon;

  const ChoiceDialog({
    super.key,
    required this.title,
    required this.options,
    this.message,
    this.selectedValue,
    this.showRadioButtons = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius * 1.5),
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) ...[
            Text(
              message!,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
          ...options.map((option) {
            if (showRadioButtons) {
              return RadioListTile<T>(
                title: Text(option.label),
                subtitle: option.description != null ? Text(option.description!) : null,
                value: option.value,
                groupValue: selectedValue,
                onChanged: (value) => Navigator.of(context).pop(value),
                contentPadding: EdgeInsets.zero,
              );
            } else {
              return ListTile(
                title: Text(option.label),
                subtitle: option.description != null ? Text(option.description!) : null,
                leading: option.icon != null ? Icon(option.icon) : null,
                onTap: () => Navigator.of(context).pop(option.value),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
              );
            }
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// Static method to show the choice dialog
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<ChoiceOption<T>> options,
    String? message,
    T? selectedValue,
    bool showRadioButtons = false,
    IconData? icon,
  }) async {
    return await showDialog<T>(
      context: context,
      builder: (context) => ChoiceDialog<T>(
        title: title,
        message: message,
        options: options,
        selectedValue: selectedValue,
        showRadioButtons: showRadioButtons,
        icon: icon,
      ),
    );
  }
}

/// A choice option for the ChoiceDialog
class ChoiceOption<T> {
  /// The value that will be returned when this option is selected
  final T value;
  
  /// The display text for this option
  final String label;
  
  /// Optional description text shown below the label
  final String? description;
  
  /// Optional icon to show for this option
  final IconData? icon;

  const ChoiceOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });
}