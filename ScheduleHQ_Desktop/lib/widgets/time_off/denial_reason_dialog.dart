import 'package:flutter/material.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';

class DenialReasonDialog extends StatefulWidget {
  const DenialReasonDialog({super.key});

  @override
  State<DenialReasonDialog> createState() => _DenialReasonDialogState();
}

class _DenialReasonDialogState extends State<DenialReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXLarge),
      ),
      title: Row(
        children: [
          Icon(Icons.block, color: appColors.errorForeground),
          const SizedBox(width: 8),
          const Text('Deny Request'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please provide a reason for denying this request:'),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter reason...',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _reasonController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reasonController.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: appColors.destructive,
            foregroundColor: Colors.white,
          ),
          child: const Text('Deny Request'),
        ),
      ],
    );
  }
}
