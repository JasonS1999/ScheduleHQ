// Color Pattern Checker Script
// Run with: dart run tool/check_color_patterns.dart
//
// This script scans Dart files in lib/ for hardcoded color patterns that
// may cause dark/light mode issues. It helps enforce the use of AppColors
// theme extension for consistent theming.

import 'dart:io';

/// Patterns that should be flagged as problematic
final List<PatternRule> prohibitedPatterns = [
  PatternRule(
    pattern: RegExp(r'Colors\.white(?!\s*\.\s*withOpacity)'),
    description: 'Hardcoded Colors.white',
    suggestion: 'Use Theme.of(context).colorScheme.surface or appColors.textOnSuccess',
    severity: Severity.warning,
  ),
  PatternRule(
    pattern: RegExp(r'Colors\.black(?!\s*\.\s*withOpacity)'),
    description: 'Hardcoded Colors.black',
    suggestion: 'Use Theme.of(context).colorScheme.onSurface or appColors.textPrimary',
    severity: Severity.warning,
  ),
  PatternRule(
    pattern: RegExp(r'Colors\.grey\s*\[\s*\d+\s*\]'),
    description: 'Hardcoded Colors.grey[###]',
    suggestion: 'Use appColors.textSecondary, textTertiary, or borderLight/Medium/Strong',
    severity: Severity.warning,
  ),
  PatternRule(
    pattern: RegExp(r'Colors\.\w+\.shade(50|100|200)'),
    description: 'Light shade color (shade50/100/200)',
    suggestion: 'Use appColors.*Background (e.g., successBackground, errorBackground)',
    severity: Severity.error,
  ),
  PatternRule(
    pattern: RegExp(r'Color\.fromRGBO\s*\(\s*0\s*,\s*0\s*,\s*0'),
    description: 'Hardcoded black Color.fromRGBO',
    suggestion: 'Use appColors.overlayDim or overlayLight for overlays',
    severity: Severity.warning,
  ),
  PatternRule(
    pattern: RegExp(r"const\s+Color\s*\(\s*0x[fF]{2}[fF]{6}\s*\)"),
    description: 'Hardcoded white Color(0xFFFFFFFF)',
    suggestion: 'Use Theme.of(context).colorScheme.surface or appColors.*',
    severity: Severity.warning,
  ),
  PatternRule(
    pattern: RegExp(r"const\s+Color\s*\(\s*0x[fF]{2}0{6}\s*\)"),
    description: 'Hardcoded black Color(0xFF000000)',
    suggestion: 'Use Theme.of(context).colorScheme.onSurface or appColors.*',
    severity: Severity.warning,
  ),
];

/// Files/directories to exclude from scanning
final List<String> excludedPaths = [
  'app_colors.dart', // The theme definition file itself
  'schedule_pdf_service.dart', // PDF generation - always printed, no dark mode needed
  '.dart_tool',
  'build/',
];

enum Severity { warning, error }

class PatternRule {
  final RegExp pattern;
  final String description;
  final String suggestion;
  final Severity severity;

  PatternRule({
    required this.pattern,
    required this.description,
    required this.suggestion,
    required this.severity,
  });
}

class Violation {
  final String file;
  final int line;
  final String content;
  final PatternRule rule;

  Violation({
    required this.file,
    required this.line,
    required this.content,
    required this.rule,
  });

  @override
  String toString() {
    final severityIcon = rule.severity == Severity.error ? '❌' : '⚠️';
    return '''
$severityIcon ${rule.description}
   File: $file:$line
   Code: ${content.trim()}
   Fix:  ${rule.suggestion}
''';
  }
}

void main(List<String> args) async {
  final libDir = Directory('lib');
  
  if (!libDir.existsSync()) {
    print('Error: lib/ directory not found. Run this script from the project root.');
    exit(1);
  }

  print('🔍 Scanning for hardcoded color patterns...\n');

  final violations = <Violation>[];
  var filesScanned = 0;

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    
    // Check if file should be excluded
    final shouldExclude = excludedPaths.any((excluded) => 
      entity.path.contains(excluded));
    if (shouldExclude) continue;

    filesScanned++;
    final content = await entity.readAsString();
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Skip comments
      if (line.trim().startsWith('//')) continue;
      
      // Skip lines with ignore directive
      if (line.contains('// ignore: hardcoded_color') ||
          line.contains('// ignore_for_file: hardcoded_color')) continue;

      for (final rule in prohibitedPatterns) {
        if (rule.pattern.hasMatch(line)) {
          violations.add(Violation(
            file: entity.path,
            line: i + 1,
            content: line,
            rule: rule,
          ));
        }
      }
    }
  }

  // Print results
  print('Files scanned: $filesScanned\n');

  if (violations.isEmpty) {
    print('✅ No hardcoded color patterns found!\n');
    exit(0);
  }

  // Group by file
  final byFile = <String, List<Violation>>{};
  for (final v in violations) {
    byFile.putIfAbsent(v.file, () => []).add(v);
  }

  // Print violations
  final errors = violations.where((v) => v.rule.severity == Severity.error).length;
  final warnings = violations.where((v) => v.rule.severity == Severity.warning).length;

  print('Found ${violations.length} potential issues ($errors errors, $warnings warnings):\n');

  for (final entry in byFile.entries) {
    print('📄 ${entry.key}');
    for (final v in entry.value) {
      print(v);
    }
  }

  // Summary
  print('─' * 60);
  print('Summary:');
  print('  Errors:   $errors');
  print('  Warnings: $warnings');
  print('');
  print('To suppress a specific line, add: // ignore: hardcoded_color');
  print('To suppress a file, add:         // ignore_for_file: hardcoded_color');
  print('');
  print('See lib/services/app_colors.dart for theme-aware color alternatives.');

  // Exit with error code if there are errors
  if (errors > 0) {
    exit(1);
  }
}
