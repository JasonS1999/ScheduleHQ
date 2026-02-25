import 'package:flutter/material.dart';

class SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double padding;
  final double borderRadius;
  final Color overlayColor;
  final double progress;

  SpotlightPainter({
    required this.targetRect,
    this.padding = 8.0,
    this.borderRadius = 8.0,
    this.overlayColor = const Color(0x8C000000),
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final spotlightRect = targetRect.inflate(padding);

    final overlayPath = Path()..addRect(fullRect);
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        spotlightRect,
        Radius.circular(borderRadius),
      ));

    final combinedPath = Path.combine(
      PathOperation.difference,
      overlayPath,
      cutoutPath,
    );

    final paint = Paint()
      ..color = overlayColor.withOpacity(overlayColor.opacity * progress)
      ..style = PaintingStyle.fill;

    canvas.drawPath(combinedPath, paint);

    // Subtle border around the cutout
    if (progress > 0.5) {
      final borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.3 * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          spotlightRect,
          Radius.circular(borderRadius),
        ),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.progress != progress ||
        oldDelegate.overlayColor != overlayColor;
  }
}
