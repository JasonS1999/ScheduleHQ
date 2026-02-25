import 'package:flutter/material.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';
import 'spotlight_painter.dart';

enum TooltipPosition { above, below, left, right }

class CoachMarkOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onPrevious;
  final TooltipPosition preferredPosition;

  const CoachMarkOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    this.onPrevious,
    this.preferredPosition = TooltipPosition.below,
  });

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _calculateTargetRect();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculateTargetRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderObject = widget.targetKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.attached) {
        final position = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        if (mounted) {
          setState(() {
            _targetRect = Rect.fromLTWH(
              position.dx,
              position.dy,
              size.width,
              size.height,
            );
          });
        }
      }
    });
  }

  TooltipPosition _resolvePosition(Rect target, Size screen) {
    final preferred = widget.preferredPosition;

    // Check if preferred position has enough space (need ~220px for tooltip)
    final hasSpace = switch (preferred) {
      TooltipPosition.below => screen.height - target.bottom > 220,
      TooltipPosition.above => target.top > 220,
      TooltipPosition.right => screen.width - target.right > 340,
      TooltipPosition.left => target.left > 340,
    };
    if (hasSpace) return preferred;

    // Fall back: prefer below, then above, then right, then left
    if (screen.height - target.bottom > 220) return TooltipPosition.below;
    if (target.top > 220) return TooltipPosition.above;
    if (screen.width - target.right > 340) return TooltipPosition.right;
    return TooltipPosition.left;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final isDark = context.isDarkMode;

    if (_targetRect == null) {
      return const SizedBox.shrink();
    }

    final position = _resolvePosition(_targetRect!, screenSize);
    final isLast = widget.stepIndex == widget.totalSteps - 1;

    // Calculate tooltip position
    double tooltipLeft;
    double tooltipTop;
    const tooltipWidth = 320.0;

    switch (position) {
      case TooltipPosition.below:
        tooltipLeft = (_targetRect!.left + _targetRect!.right) / 2 - tooltipWidth / 2;
        tooltipTop = _targetRect!.bottom + 16;
        break;
      case TooltipPosition.above:
        tooltipLeft = (_targetRect!.left + _targetRect!.right) / 2 - tooltipWidth / 2;
        tooltipTop = _targetRect!.top - 16 - 200;
        break;
      case TooltipPosition.right:
        tooltipLeft = _targetRect!.right + 16;
        tooltipTop = (_targetRect!.top + _targetRect!.bottom) / 2 - 100;
        break;
      case TooltipPosition.left:
        tooltipLeft = _targetRect!.left - 16 - tooltipWidth;
        tooltipTop = (_targetRect!.top + _targetRect!.bottom) / 2 - 100;
        break;
    }

    // Clamp to screen bounds
    tooltipLeft = tooltipLeft.clamp(16.0, screenSize.width - tooltipWidth - 16);
    tooltipTop = tooltipTop.clamp(16.0, screenSize.height - 220);

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Stack(
          children: [
            // Spotlight overlay
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onSkip,
                child: CustomPaint(
                  painter: SpotlightPainter(
                    targetRect: _targetRect!,
                    padding: 8,
                    borderRadius: AppConstants.radiusMedium,
                    overlayColor: isDark
                        ? const Color(0x8C000000)
                        : const Color(0x59000000),
                    progress: _fadeAnimation.value,
                  ),
                ),
              ),
            ),

            // Tooltip card
            Positioned(
              left: tooltipLeft,
              top: tooltipTop,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
                  color: colorScheme.surface,
                  child: Container(
                    width: tooltipWidth,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
                      border: isDark
                          ? Border.all(color: context.appColors.borderLight)
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Description
                        Text(
                          widget.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.appColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Step counter + buttons
                        Row(
                          children: [
                            Text(
                              'Step ${widget.stepIndex + 1} of ${widget.totalSteps}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.appColors.textTertiary,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: widget.onSkip,
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  color: context.appColors.textTertiary,
                                ),
                              ),
                            ),
                            if (widget.onPrevious != null) ...[
                              const SizedBox(width: 4),
                              OutlinedButton(
                                onPressed: widget.onPrevious,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                child: const Text('Back'),
                              ),
                            ],
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: widget.onNext,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: Text(isLast ? 'Finish' : 'Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
