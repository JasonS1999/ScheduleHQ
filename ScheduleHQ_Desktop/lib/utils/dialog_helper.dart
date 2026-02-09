import 'package:flutter/material.dart';
import '../services/app_colors.dart';

/// Utility class for showing standardized dialogs throughout the app
class DialogHelper {
  /// Private constructor to prevent instantiation
  DialogHelper._();

  /// Show a confirmation dialog with Yes/No buttons
  /// Returns true if user confirms, false if they cancel or dismiss
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Yes',
    String cancelText = 'No',
    Color? confirmColor,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: confirmColor ?? Theme.of(context).primaryColor),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmColor != null
                ? ElevatedButton.styleFrom(backgroundColor: confirmColor)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show a delete confirmation dialog with red styling
  static Future<bool> showDeleteConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String itemName = 'item',
  }) async {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmText: 'Delete',
      cancelText: 'Cancel',
      confirmColor: context.appColors.destructive,
      icon: Icons.delete,
    );
  }

  /// Show an info dialog with just an OK button
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    IconData? icon,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show an error dialog with red icon and styling
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) async {
    await showInfoDialog(
      context,
      title: title,
      message: message,
      buttonText: buttonText,
      icon: Icons.error,
    );
  }

  /// Show a loading dialog that can be dismissed programmatically
  /// Returns a function that can be called to dismiss the dialog
  static Function() showLoadingDialog(
    BuildContext context, {
    String message = 'Loading...',
    bool barrierDismissible = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => PopScope(
        canPop: barrierDismissible,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );

    // Return a function to dismiss the dialog
    return () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    };
  }

  /// Show a choice dialog with multiple options
  /// Returns the index of the selected option, or null if cancelled
  static Future<int?> showChoiceDialog<T>(
    BuildContext context, {
    required String title,
    String? message,
    required List<String> options,
    String cancelText = 'Cancel',
    IconData? icon,
  }) async {
    return await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title)),
          ],
        ),
        content: message != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  ...options.asMap().entries.map(
                    (entry) => SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(entry.key),
                        child: Text(entry.value, textAlign: TextAlign.left),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: options
                    .asMap()
                    .entries
                    .map(
                      (entry) => SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(entry.key),
                          child: Text(entry.value),
                        ),
                      ),
                    )
                    .toList(),
              ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(cancelText),
          ),
        ],
      ),
    );
  }

  /// Show an input dialog with a text field
  /// Returns true if user confirms, false if they cancel
  static Future<bool> showInputDialog(
    BuildContext context, {
    required String title,
    required String labelText,
    String confirmText = 'Add',
    String cancelText = 'Cancel',
    String? initialValue,
    required ValueChanged<String> onChanged,
  }) async {
    String value = initialValue ?? '';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            decoration: InputDecoration(labelText: labelText),
            controller: TextEditingController(text: value)
              ..selection = TextSelection.fromPosition(
                TextPosition(offset: value.length),
              ),
            onChanged: (v) {
              value = v;
              onChanged(v);
            },
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancelText),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
