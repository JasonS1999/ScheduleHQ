import 'package:flutter/material.dart';
import '../services/app_colors.dart';

/// Color utility extensions and helpers that complement [AppColors].
///
/// [AppColors] provides semantic tokens (success, error, border, etc.).
/// These helpers cover dynamic patterns that tokens can't:
/// - Ad-hoc light/dark color pairs via [themedColor]
/// - Standard opacity tiers via [ColorOpacity]
/// - Reusable [BoxDecoration] factories via [AppDecorations]

// ---------------------------------------------------------------------------
// BuildContext extensions
// ---------------------------------------------------------------------------

extension ColorContextExtension on BuildContext {
  /// Returns [light] in light mode, [dark] in dark mode.
  ///
  /// Use for one-off themed colors not worth adding to [AppColors]:
  /// ```dart
  /// color: context.themedColor(Colors.purple.shade50, Colors.purple.shade900)
  /// ```
  Color themedColor(Color light, Color dark) => isDarkMode ? dark : light;
}

// ---------------------------------------------------------------------------
// Color extensions – standard opacity tiers
// ---------------------------------------------------------------------------

extension ColorOpacity on Color {
  /// Subtle tinted background (8% opacity).
  /// Use for barely-visible hover/focus states.
  Color get subtle => withValues(alpha: 0.08);

  /// Soft tinted background (12% opacity).
  /// Use for chip/card fills, tinted containers.
  Color get softBg => withValues(alpha: 0.12);

  /// Soft border (30% opacity).
  /// Use for borders around tinted containers.
  Color get softBorder => withValues(alpha: 0.30);

  /// Muted foreground (60% opacity).
  /// Use for de-emphasized text or icons.
  Color get muted => withValues(alpha: 0.60);
}

// ---------------------------------------------------------------------------
// Reusable BoxDecoration factories
// ---------------------------------------------------------------------------

/// Pre-built [BoxDecoration] patterns used across the app.
class AppDecorations {
  AppDecorations._();

  /// A tinted stat-card decoration.
  ///
  /// Light mode: shade50 background + hue border.
  /// Dark mode: deep shade background + hue border.
  ///
  /// Used in P&L summary cards, stat tiles, etc.
  static BoxDecoration tintedCard(
    BuildContext context,
    Color hue, {
    double radius = 8,
  }) {
    final isDark = context.isDarkMode;
    return BoxDecoration(
      color: isDark
          ? HSLColor.fromColor(hue)
              .withLightness(0.15)
              .withSaturation(0.4)
              .toColor()
          : hue.softBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? hue.withValues(alpha: 0.4) : hue.softBorder,
      ),
    );
  }

  /// A bordered container (e.g. for input-like areas, table sections).
  ///
  /// Uses [AppColors.borderLight] automatically.
  static BoxDecoration borderedContainer(
    BuildContext context, {
    double radius = 8,
    Color? backgroundColor,
  }) {
    final appColors = context.appColors;
    return BoxDecoration(
      color: backgroundColor,
      border: Border.all(color: appColors.borderLight),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// A color swatch circle (e.g. in job code / shift runner color pickers).
  static BoxDecoration colorSwatch(
    Color color, {
    bool selected = false,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected
            ? borderColor ?? Colors.white
            : color.withValues(alpha: 0.4),
        width: selected ? 3 : 1.5,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: color.softBorder,
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ]
          : null,
    );
  }

  /// A section container with subtle background tint.
  ///
  /// Used for settings sections, grouped content areas.
  static BoxDecoration sectionContainer(BuildContext context, {
    double radius = 8,
  }) {
    final appColors = context.appColors;
    return BoxDecoration(
      color: appColors.surfaceVariant,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: appColors.borderLight),
    );
  }
}
