import 'package:flutter/material.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';

class TimeOffTypeBadge extends StatelessWidget {
  final String timeOffType;

  const TimeOffTypeBadge({super.key, required this.timeOffType});

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final (label, bg, fg, border) = _colorsForType(appColors);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  (String, Color, Color, Color) _colorsForType(AppColors appColors) {
    switch (timeOffType.toLowerCase()) {
      case 'pto':
        return ('PTO', appColors.infoBackground, appColors.infoForeground, appColors.infoBorder);
      case 'vacation':
        return ('VACATION', appColors.successBackground, appColors.successForeground, appColors.successBorder);
      case 'requested':
        return ('REQUESTED', appColors.warningBackground, appColors.warningForeground, appColors.warningBorder);
      default:
        return (timeOffType.toUpperCase(), appColors.surfaceContainer, appColors.textSecondary, appColors.borderMedium);
    }
  }
}
