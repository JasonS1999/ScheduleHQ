// Theme contrast tests to verify dark/light mode color accessibility
// and prevent hardcoded color regressions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_schedule_app/services/app_colors.dart';

void main() {
  group('AppColors ThemeExtension', () {
    test('light theme has all required colors defined', () {
      const colors = AppColors.light;
      
      // Success colors
      expect(colors.successBackground, isNotNull);
      expect(colors.successForeground, isNotNull);
      expect(colors.successBorder, isNotNull);
      expect(colors.successIcon, isNotNull);
      
      // Error colors
      expect(colors.errorBackground, isNotNull);
      expect(colors.errorForeground, isNotNull);
      expect(colors.errorBorder, isNotNull);
      expect(colors.errorIcon, isNotNull);
      
      // Warning colors
      expect(colors.warningBackground, isNotNull);
      expect(colors.warningForeground, isNotNull);
      expect(colors.warningBorder, isNotNull);
      expect(colors.warningIcon, isNotNull);
      
      // Info colors
      expect(colors.infoBackground, isNotNull);
      expect(colors.infoForeground, isNotNull);
      expect(colors.infoBorder, isNotNull);
      expect(colors.infoIcon, isNotNull);
      
      // Surface variants
      expect(colors.surfaceVariant, isNotNull);
      expect(colors.surfaceContainer, isNotNull);
      expect(colors.surfaceContainerHigh, isNotNull);
      expect(colors.surfaceContainerHighest, isNotNull);
      
      // Text colors
      expect(colors.textPrimary, isNotNull);
      expect(colors.textSecondary, isNotNull);
      expect(colors.textTertiary, isNotNull);
      expect(colors.textOnSuccess, isNotNull);
      expect(colors.textOnError, isNotNull);
      
      // Border colors
      expect(colors.borderLight, isNotNull);
      expect(colors.borderMedium, isNotNull);
      expect(colors.borderStrong, isNotNull);
      
      // Overlay colors
      expect(colors.overlayDim, isNotNull);
      expect(colors.overlayLight, isNotNull);
      
      // Selection colors
      expect(colors.selectionBackground, isNotNull);
      expect(colors.selectionForeground, isNotNull);
    });

    test('dark theme has all required colors defined', () {
      const colors = AppColors.dark;
      
      // Success colors
      expect(colors.successBackground, isNotNull);
      expect(colors.successForeground, isNotNull);
      expect(colors.successBorder, isNotNull);
      expect(colors.successIcon, isNotNull);
      
      // Error colors
      expect(colors.errorBackground, isNotNull);
      expect(colors.errorForeground, isNotNull);
      expect(colors.errorBorder, isNotNull);
      expect(colors.errorIcon, isNotNull);
      
      // Warning colors
      expect(colors.warningBackground, isNotNull);
      expect(colors.warningForeground, isNotNull);
      expect(colors.warningBorder, isNotNull);
      expect(colors.warningIcon, isNotNull);
      
      // Info colors
      expect(colors.infoBackground, isNotNull);
      expect(colors.infoForeground, isNotNull);
      expect(colors.infoBorder, isNotNull);
      expect(colors.infoIcon, isNotNull);
      
      // Surface variants
      expect(colors.surfaceVariant, isNotNull);
      expect(colors.surfaceContainer, isNotNull);
      expect(colors.surfaceContainerHigh, isNotNull);
      expect(colors.surfaceContainerHighest, isNotNull);
      
      // Text colors
      expect(colors.textPrimary, isNotNull);
      expect(colors.textSecondary, isNotNull);
      expect(colors.textTertiary, isNotNull);
      expect(colors.textOnSuccess, isNotNull);
      expect(colors.textOnError, isNotNull);
      
      // Border colors
      expect(colors.borderLight, isNotNull);
      expect(colors.borderMedium, isNotNull);
      expect(colors.borderStrong, isNotNull);
      
      // Overlay colors
      expect(colors.overlayDim, isNotNull);
      expect(colors.overlayLight, isNotNull);
      
      // Selection colors
      expect(colors.selectionBackground, isNotNull);
      expect(colors.selectionForeground, isNotNull);
    });

    test('light and dark themes have different values for key colors', () {
      const light = AppColors.light;
      const dark = AppColors.dark;
      
      // Backgrounds should be different (light vs dark)
      expect(light.successBackground, isNot(equals(dark.successBackground)));
      expect(light.errorBackground, isNot(equals(dark.errorBackground)));
      expect(light.surfaceVariant, isNot(equals(dark.surfaceVariant)));
      expect(light.selectionBackground, isNot(equals(dark.selectionBackground)));
      
      // Text should be different (dark text on light, light text on dark)
      expect(light.textPrimary, isNot(equals(dark.textPrimary)));
      expect(light.textSecondary, isNot(equals(dark.textSecondary)));
    });
  });

  group('Color contrast validation', () {
    // Helper to calculate relative luminance
    double relativeLuminance(Color color) {
      double r = color.red / 255;
      double g = color.green / 255;
      double b = color.blue / 255;
      
      r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055);
      g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055);
      b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055);
      
      r = r <= 0.03928 ? r : r * r * r;
      g = g <= 0.03928 ? g : g * g * g;
      b = b <= 0.03928 ? b : b * b * b;
      
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    // Calculate contrast ratio between two colors
    double contrastRatio(Color foreground, Color background) {
      final l1 = relativeLuminance(foreground);
      final l2 = relativeLuminance(background);
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('light theme success text on success background meets WCAG AA', () {
      const colors = AppColors.light;
      final ratio = contrastRatio(colors.successForeground, colors.successBackground);
      // WCAG AA requires 4.5:1 for normal text
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Success foreground on background contrast ratio: $ratio');
    });

    test('light theme error text on error background meets WCAG AA', () {
      const colors = AppColors.light;
      final ratio = contrastRatio(colors.errorForeground, colors.errorBackground);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Error foreground on background contrast ratio: $ratio');
    });

    test('dark theme success text on success background meets WCAG AA', () {
      const colors = AppColors.dark;
      final ratio = contrastRatio(colors.successForeground, colors.successBackground);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Success foreground on background contrast ratio: $ratio');
    });

    test('dark theme error text on error background meets WCAG AA', () {
      const colors = AppColors.dark;
      final ratio = contrastRatio(colors.errorForeground, colors.errorBackground);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Error foreground on background contrast ratio: $ratio');
    });

    test('light theme primary text is dark enough', () {
      const colors = AppColors.light;
      final luminance = relativeLuminance(colors.textPrimary);
      // Primary text in light mode should be dark (low luminance)
      expect(luminance, lessThan(0.2),
          reason: 'Light mode primary text luminance: $luminance');
    });

    test('dark theme primary text is light enough', () {
      const colors = AppColors.dark;
      final luminance = relativeLuminance(colors.textPrimary);
      // Primary text in dark mode should be light (high luminance)
      expect(luminance, greaterThan(0.5),
          reason: 'Dark mode primary text luminance: $luminance');
    });

    test('light theme surface variant is light', () {
      const colors = AppColors.light;
      final luminance = relativeLuminance(colors.surfaceVariant);
      expect(luminance, greaterThan(0.7),
          reason: 'Light mode surface variant luminance: $luminance');
    });

    test('dark theme surface variant is dark', () {
      const colors = AppColors.dark;
      final luminance = relativeLuminance(colors.surfaceVariant);
      expect(luminance, lessThan(0.15),
          reason: 'Dark mode surface variant luminance: $luminance');
    });
  });

  group('AppColors lerp interpolation', () {
    test('lerp at 0 returns original colors', () {
      const light = AppColors.light;
      const dark = AppColors.dark;
      final result = light.lerp(dark, 0);
      
      expect(result.successBackground, equals(light.successBackground));
      expect(result.errorBackground, equals(light.errorBackground));
      expect(result.textPrimary, equals(light.textPrimary));
    });

    test('lerp at 1 returns target colors', () {
      const light = AppColors.light;
      const dark = AppColors.dark;
      final result = light.lerp(dark, 1);
      
      expect(result.successBackground, equals(dark.successBackground));
      expect(result.errorBackground, equals(dark.errorBackground));
      expect(result.textPrimary, equals(dark.textPrimary));
    });

    test('lerp at 0.5 returns interpolated colors', () {
      const light = AppColors.light;
      const dark = AppColors.dark;
      final result = light.lerp(dark, 0.5);
      
      // The interpolated color should be different from both endpoints
      expect(result.successBackground, isNot(equals(light.successBackground)));
      expect(result.successBackground, isNot(equals(dark.successBackground)));
    });
  });

  group('Theme widget integration', () {
    Widget buildTestWidget({required ThemeMode themeMode, required Widget child}) {
      return MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.light,
          useMaterial3: true,
          extensions: const [AppColors.light],
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
          useMaterial3: true,
          extensions: const [AppColors.dark],
        ),
        themeMode: themeMode,
        home: child,
      );
    }

    testWidgets('AppColors extension is accessible in light mode', (tester) async {
      late AppColors? appColors;

      await tester.pumpWidget(
        buildTestWidget(
          themeMode: ThemeMode.light,
          child: Builder(
            builder: (context) {
              appColors = Theme.of(context).extension<AppColors>();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(appColors, isNotNull);
      expect(appColors, equals(AppColors.light));
    });

    testWidgets('AppColors extension is accessible in dark mode', (tester) async {
      late AppColors? appColors;

      await tester.pumpWidget(
        buildTestWidget(
          themeMode: ThemeMode.dark,
          child: Builder(
            builder: (context) {
              appColors = Theme.of(context).extension<AppColors>();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(appColors, isNotNull);
      expect(appColors, equals(AppColors.dark));
    });

    testWidgets('context.appColors extension works', (tester) async {
      late AppColors appColors;

      await tester.pumpWidget(
        buildTestWidget(
          themeMode: ThemeMode.light,
          child: Builder(
            builder: (context) {
              appColors = context.appColors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(appColors, equals(AppColors.light));
    });

    testWidgets('context.isDarkMode returns correct value for light mode', (tester) async {
      late bool isDark;

      await tester.pumpWidget(
        buildTestWidget(
          themeMode: ThemeMode.light,
          child: Builder(
            builder: (context) {
              isDark = context.isDarkMode;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDark, isFalse);
    });

    testWidgets('context.isDarkMode returns correct value for dark mode', (tester) async {
      late bool isDark;

      await tester.pumpWidget(
        buildTestWidget(
          themeMode: ThemeMode.dark,
          child: Builder(
            builder: (context) {
              isDark = context.isDarkMode;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDark, isTrue);
    });
  });

  group('Prohibited color patterns detection', () {
    // This group contains tests that can be run to detect prohibited color patterns
    // in the codebase. These are meant to be run as part of CI/CD to catch regressions.
    
    // Note: These are placeholder tests. The actual implementation would involve
    // parsing Dart source files and checking for prohibited patterns.
    // For now, we document the patterns that should be avoided.
    
    test('documents prohibited color patterns', () {
      // The following patterns should NOT be used directly in widgets:
      // - Colors.white (use theme.colorScheme.surface or appColors.textOnSuccess)
      // - Colors.black (use theme.colorScheme.onSurface or appColors.textPrimary)
      // - Colors.grey[###] (use appColors.textSecondary/textTertiary)
      // - Colors.*.shade50/100/200 (use appColors.*Background)
      // - Color.fromRGBO(0, 0, 0, ...) for overlays (use appColors.overlayDim)
      // - Color(0xFF...) hardcoded values (define in AppColors)
      
      // This test always passes - it's documentation
      expect(true, isTrue);
    });

    test('AppColors provides alternatives for all common problematic patterns', () {
      const colors = AppColors.light;
      
      // Instead of Colors.white for backgrounds
      expect(colors.surfaceVariant, isNotNull);
      expect(colors.surfaceContainer, isNotNull);
      
      // Instead of Colors.grey[500/600] for text
      expect(colors.textSecondary, isNotNull);
      expect(colors.textTertiary, isNotNull);
      
      // Instead of Colors.green.shade50 for success backgrounds
      expect(colors.successBackground, isNotNull);
      
      // Instead of Colors.red.shade50 for error backgrounds
      expect(colors.errorBackground, isNotNull);
      
      // Instead of Colors.blue.shade100 for selection
      expect(colors.selectionBackground, isNotNull);
      
      // Instead of Color.fromRGBO(0, 0, 0, 0.35) for overlays
      expect(colors.overlayDim, isNotNull);
      expect(colors.overlayLight, isNotNull);
      
      // Instead of hardcoded Colors.white on colored backgrounds
      expect(colors.textOnSuccess, isNotNull);
      expect(colors.textOnError, isNotNull);
    });
  });
}
