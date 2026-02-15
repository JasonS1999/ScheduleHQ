import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/job_code_provider.dart';

/// Reusable avatar widget that displays a profile image from a URL,
/// falling back to initials on a colored background.
///
/// When [jobCode] is provided and no explicit [backgroundColor] is set,
/// the avatar resolves its color from the [JobCodeProvider] (group-aware).
class EmployeeAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final String? jobCode;

  const EmployeeAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 20,
    this.backgroundColor,
    this.jobCode,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.startsWith('http');
    final initials = _getInitials(name);
    final bgColor = backgroundColor ?? _resolveColor(context);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: !hasImage
          ? Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            )
          : null,
    );
  }

  Color _resolveColor(BuildContext context) {
    if (jobCode == null) {
      return Theme.of(context).colorScheme.primary;
    }

    final jobCodeProvider = Provider.of<JobCodeProvider>(context);
    final codes = jobCodeProvider.codes;
    final groups = jobCodeProvider.groups;

    final settings = codes.cast<dynamic>().firstWhere(
      (s) => s != null && s.code.toLowerCase() == jobCode!.toLowerCase(),
      orElse: () => null,
    );

    if (settings != null && settings.sortGroup != null) {
      final group = groups.cast<dynamic>().firstWhere(
        (g) => g != null && g.name == settings.sortGroup,
        orElse: () => null,
      );
      if (group != null) {
        return _colorFromHex(group.colorHex, context);
      }
    }

    final hex = settings?.colorHex;
    if (hex == null || (hex as String).trim().isEmpty) {
      return Theme.of(context).colorScheme.primary;
    }
    return _colorFromHex(hex, context);
  }

  static Color _colorFromHex(String hex, BuildContext context) {
    try {
      String clean = hex.replaceAll('#', '').toUpperCase();
      if (clean.length == 6) clean = 'FF$clean';
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
      return Theme.of(context).colorScheme.primary;
    } catch (_) {
      return Theme.of(context).colorScheme.primary;
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }
}
