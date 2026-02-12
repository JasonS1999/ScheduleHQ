import 'package:flutter/material.dart';

/// A ThemeExtension that provides semantic colors for the app.
/// These colors automatically adapt to light and dark themes.
///
/// Usage:
/// ```dart
/// final appColors = Theme.of(context).extension<AppColors>()!;
/// Container(color: appColors.successBackground);
/// ```
class AppColors extends ThemeExtension<AppColors> {
  // Success colors (green variants)
  final Color successBackground;
  final Color successForeground;
  final Color successBorder;
  final Color successIcon;

  // Error colors (red variants)
  final Color errorBackground;
  final Color errorForeground;
  final Color errorBorder;
  final Color errorIcon;

  // Warning colors (amber/orange variants)
  final Color warningBackground;
  final Color warningForeground;
  final Color warningBorder;
  final Color warningIcon;

  // Info colors (blue variants)
  final Color infoBackground;
  final Color infoForeground;
  final Color infoBorder;
  final Color infoIcon;

  // Surface variants for containers, cards, etc.
  final Color surfaceVariant;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  // Text colors
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnSuccess;
  final Color textOnError;

  // Border colors
  final Color borderLight;
  final Color borderMedium;
  final Color borderStrong;

  // Overlay colors
  final Color overlayDim;
  final Color overlayLight;

  // Selection colors
  final Color selectionBackground;
  final Color selectionForeground;

  // Table colors
  final Color tableHeaderBackground;
  final Color tableBorder;

  // Misc
  final Color subtleTint;
  final Color disabledForeground;
  final Color destructive;

  const AppColors({
    required this.successBackground,
    required this.successForeground,
    required this.successBorder,
    required this.successIcon,
    required this.errorBackground,
    required this.errorForeground,
    required this.errorBorder,
    required this.errorIcon,
    required this.warningBackground,
    required this.warningForeground,
    required this.warningBorder,
    required this.warningIcon,
    required this.infoBackground,
    required this.infoForeground,
    required this.infoBorder,
    required this.infoIcon,
    required this.surfaceVariant,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnSuccess,
    required this.textOnError,
    required this.borderLight,
    required this.borderMedium,
    required this.borderStrong,
    required this.overlayDim,
    required this.overlayLight,
    required this.selectionBackground,
    required this.selectionForeground,
    required this.tableHeaderBackground,
    required this.tableBorder,
    required this.subtleTint,
    required this.disabledForeground,
    required this.destructive,
  });

  /// Light theme colors
  static const light = AppColors(
    // Success (green)
    successBackground: Color(0xFFE8F5E9), // green.shade50 equivalent
    successForeground: Color(0xFF2E7D32), // green.shade700
    successBorder: Color(0xFF81C784), // green.shade300
    successIcon: Color(0xFF43A047), // green.shade600
    // Error (red)
    errorBackground: Color(0xFFFFEBEE), // red.shade50
    errorForeground: Color(0xFFC62828), // red.shade800
    errorBorder: Color(0xFFEF9A9A), // red.shade200
    errorIcon: Color(0xFFE53935), // red.shade600
    // Warning (amber)
    warningBackground: Color(0xFFFFF8E1), // amber.shade50
    warningForeground: Color(0xFFFF8F00), // amber.shade800
    warningBorder: Color(0xFFFFE082), // amber.shade200
    warningIcon: Color(0xFFFFB300), // amber.shade600
    // Info (blue)
    infoBackground: Color(0xFFE3F2FD), // blue.shade50
    infoForeground: Color(0xFF1565C0), // blue.shade800
    infoBorder: Color(0xFF90CAF9), // blue.shade200
    infoIcon: Color(0xFF1E88E5), // blue.shade600
    // Surfaces
    surfaceVariant: Color(0xFFF5F5F5), // grey.shade100
    surfaceContainer: Color(0xFFEEEEEE), // grey.shade200
    surfaceContainerHigh: Color(0xFFE0E0E0), // grey.shade300
    surfaceContainerHighest: Color(0xFFBDBDBD), // grey.shade400
    // Text
    textPrimary: Color(0xFF212121), // grey.shade900
    textSecondary: Color(0xFF757575), // grey.shade600
    textTertiary: Color(0xFF9E9E9E), // grey.shade500
    textOnSuccess: Color(0xFFFFFFFF),
    textOnError: Color(0xFFFFFFFF),

    // Borders
    borderLight: Color(0xFFE0E0E0), // grey.shade300
    borderMedium: Color(0xFFBDBDBD), // grey.shade400
    borderStrong: Color(0xFF9E9E9E), // grey.shade500
    // Overlays
    overlayDim: Color(0x59000000), // black with 35% opacity
    overlayLight: Color(0x1F000000), // black with 12% opacity
    // Selection
    selectionBackground: Color(0xFFBBDEFB), // blue.shade100
    selectionForeground: Color(0xFF1565C0), // blue.shade800
    // Table
    tableHeaderBackground: Color(0xFFE0E0E0), // grey.shade300
    tableBorder: Color(0xFFBDBDBD), // grey.shade400
    // Misc
    subtleTint: Color(0xFFF5F5F5), // grey.shade100
    disabledForeground: Color(0xFF9E9E9E), // grey.shade500
    destructive: Color(0xFFC62828), // red.shade800
  );

  /// Dark theme colors
  static const dark = AppColors(
    // Success (green) - darker backgrounds, lighter foregrounds
    successBackground: Color(0xFF1B3D1F), // dark green background
    successForeground: Color(0xFF81C784), // green.shade300
    successBorder: Color(0xFF2E7D32), // green.shade700
    successIcon: Color(0xFF66BB6A), // green.shade400
    // Error (red)
    errorBackground: Color(0xFF3D1B1B), // dark red background
    errorForeground: Color(0xFFEF9A9A), // red.shade200
    errorBorder: Color(0xFFC62828), // red.shade800
    errorIcon: Color(0xFFEF5350), // red.shade400
    // Warning (amber)
    warningBackground: Color(0xFF3D321B), // dark amber background
    warningForeground: Color(0xFFFFE082), // amber.shade200
    warningBorder: Color(0xFFFF8F00), // amber.shade800
    warningIcon: Color(0xFFFFCA28), // amber.shade400
    // Info (blue)
    infoBackground: Color(0xFF1B2D3D), // dark blue background
    infoForeground: Color(0xFF90CAF9), // blue.shade200
    infoBorder: Color(0xFF1565C0), // blue.shade800
    infoIcon: Color(0xFF42A5F5), // blue.shade400
    // Surfaces - using Material 3 dark surface tones
    surfaceVariant: Color(0xFF2C2C2C),
    surfaceContainer: Color(0xFF1E1E1E),
    surfaceContainerHigh: Color(0xFF383838),
    surfaceContainerHighest: Color(0xFF484848),

    // Text
    textPrimary: Color(0xFFE0E0E0), // grey.shade300
    textSecondary: Color(0xFFB0B0B0), // lighter grey
    textTertiary: Color(0xFF808080), // grey
    textOnSuccess: Color(0xFF1B3D1F), // dark for contrast
    textOnError: Color(0xFF3D1B1B), // dark for contrast
    // Borders
    borderLight: Color(0xFF3D3D3D),
    borderMedium: Color(0xFF4D4D4D),
    borderStrong: Color(0xFF6D6D6D),

    // Overlays
    overlayDim: Color(0x8C000000), // black with 55% opacity for dark mode
    overlayLight: Color(0x33FFFFFF), // white with 20% opacity
    // Selection
    selectionBackground: Color(0xFF1E3A5F), // dark blue background
    selectionForeground: Color(0xFF90CAF9), // blue.shade200
    // Table
    tableHeaderBackground: Color(0xFF383838), // dark grey
    tableBorder: Color(0xFF4D4D4D), // medium dark grey
    // Misc
    subtleTint: Color(0xFF2C2C2C), // dark surface
    disabledForeground: Color(0xFF6D6D6D), // muted grey
    destructive: Color(0xFFEF5350), // red.shade400
  );

  @override
  AppColors copyWith({
    Color? successBackground,
    Color? successForeground,
    Color? successBorder,
    Color? successIcon,
    Color? errorBackground,
    Color? errorForeground,
    Color? errorBorder,
    Color? errorIcon,
    Color? warningBackground,
    Color? warningForeground,
    Color? warningBorder,
    Color? warningIcon,
    Color? infoBackground,
    Color? infoForeground,
    Color? infoBorder,
    Color? infoIcon,
    Color? surfaceVariant,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnSuccess,
    Color? textOnError,
    Color? borderLight,
    Color? borderMedium,
    Color? borderStrong,
    Color? overlayDim,
    Color? overlayLight,
    Color? selectionBackground,
    Color? selectionForeground,
    Color? tableHeaderBackground,
    Color? tableBorder,
    Color? subtleTint,
    Color? disabledForeground,
    Color? destructive,
  }) {
    return AppColors(
      successBackground: successBackground ?? this.successBackground,
      successForeground: successForeground ?? this.successForeground,
      successBorder: successBorder ?? this.successBorder,
      successIcon: successIcon ?? this.successIcon,
      errorBackground: errorBackground ?? this.errorBackground,
      errorForeground: errorForeground ?? this.errorForeground,
      errorBorder: errorBorder ?? this.errorBorder,
      errorIcon: errorIcon ?? this.errorIcon,
      warningBackground: warningBackground ?? this.warningBackground,
      warningForeground: warningForeground ?? this.warningForeground,
      warningBorder: warningBorder ?? this.warningBorder,
      warningIcon: warningIcon ?? this.warningIcon,
      infoBackground: infoBackground ?? this.infoBackground,
      infoForeground: infoForeground ?? this.infoForeground,
      infoBorder: infoBorder ?? this.infoBorder,
      infoIcon: infoIcon ?? this.infoIcon,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnSuccess: textOnSuccess ?? this.textOnSuccess,
      textOnError: textOnError ?? this.textOnError,
      borderLight: borderLight ?? this.borderLight,
      borderMedium: borderMedium ?? this.borderMedium,
      borderStrong: borderStrong ?? this.borderStrong,
      overlayDim: overlayDim ?? this.overlayDim,
      overlayLight: overlayLight ?? this.overlayLight,
      selectionBackground: selectionBackground ?? this.selectionBackground,
      selectionForeground: selectionForeground ?? this.selectionForeground,
      tableHeaderBackground:
          tableHeaderBackground ?? this.tableHeaderBackground,
      tableBorder: tableBorder ?? this.tableBorder,
      subtleTint: subtleTint ?? this.subtleTint,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      destructive: destructive ?? this.destructive,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      successBackground: Color.lerp(
        successBackground,
        other.successBackground,
        t,
      )!,
      successForeground: Color.lerp(
        successForeground,
        other.successForeground,
        t,
      )!,
      successBorder: Color.lerp(successBorder, other.successBorder, t)!,
      successIcon: Color.lerp(successIcon, other.successIcon, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      errorForeground: Color.lerp(errorForeground, other.errorForeground, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      errorIcon: Color.lerp(errorIcon, other.errorIcon, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      warningForeground: Color.lerp(
        warningForeground,
        other.warningForeground,
        t,
      )!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      warningIcon: Color.lerp(warningIcon, other.warningIcon, t)!,
      infoBackground: Color.lerp(infoBackground, other.infoBackground, t)!,
      infoForeground: Color.lerp(infoForeground, other.infoForeground, t)!,
      infoBorder: Color.lerp(infoBorder, other.infoBorder, t)!,
      infoIcon: Color.lerp(infoIcon, other.infoIcon, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceContainerHigh: Color.lerp(
        surfaceContainerHigh,
        other.surfaceContainerHigh,
        t,
      )!,
      surfaceContainerHighest: Color.lerp(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textOnSuccess: Color.lerp(textOnSuccess, other.textOnSuccess, t)!,
      textOnError: Color.lerp(textOnError, other.textOnError, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      borderMedium: Color.lerp(borderMedium, other.borderMedium, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      overlayDim: Color.lerp(overlayDim, other.overlayDim, t)!,
      overlayLight: Color.lerp(overlayLight, other.overlayLight, t)!,
      selectionBackground: Color.lerp(
        selectionBackground,
        other.selectionBackground,
        t,
      )!,
      selectionForeground: Color.lerp(
        selectionForeground,
        other.selectionForeground,
        t,
      )!,
      tableHeaderBackground: Color.lerp(
        tableHeaderBackground,
        other.tableHeaderBackground,
        t,
      )!,
      tableBorder: Color.lerp(tableBorder, other.tableBorder, t)!,
      subtleTint: Color.lerp(subtleTint, other.subtleTint, t)!,
      disabledForeground: Color.lerp(
        disabledForeground,
        other.disabledForeground,
        t,
      )!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
    );
  }
}

/// Extension to easily access AppColors from BuildContext
extension AppColorsExtension on BuildContext {
  /// Access the AppColors theme extension
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;

  /// Check if the current theme is dark
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
