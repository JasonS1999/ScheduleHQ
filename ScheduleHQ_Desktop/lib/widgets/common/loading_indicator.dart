import 'package:flutter/material.dart';
import '../../utils/app_constants.dart';

/// A standardized loading indicator widget used throughout the app
class LoadingIndicator extends StatelessWidget {
  /// The message to display below the loading spinner
  final String? message;
  
  /// The size of the loading spinner
  final double? size;
  
  /// The color of the loading spinner
  final Color? color;
  
  /// Whether to show the loading indicator in a card
  final bool showCard;
  
  /// The padding around the loading indicator
  final EdgeInsets? padding;

  const LoadingIndicator({
    super.key,
    this.message,
    this.size,
    this.color,
    this.showCard = false,
    this.padding,
  });

  /// Small loading indicator for inline use
  const LoadingIndicator.small({
    super.key,
    this.message,
    this.color,
    this.showCard = false,
    this.padding,
  }) : size = 16.0;

  /// Large loading indicator for full screen loading
  const LoadingIndicator.large({
    super.key,
    this.message,
    this.color,
    this.showCard = true,
    this.padding,
  }) : size = 48.0;

  /// Centered loading indicator that fills available space
  const LoadingIndicator.centered({
    super.key,
    this.message,
    this.size,
    this.color,
    this.showCard = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.primaryColor;
    final effectiveSize = size ?? 32.0;
    final effectivePadding = padding ?? const EdgeInsets.all(AppConstants.defaultPadding);

    Widget loadingWidget = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: effectiveSize,
          height: effectiveSize,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
            strokeWidth: effectiveSize > 32 ? 4.0 : 2.0,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (showCard) {
      loadingWidget = Card(
        elevation: AppConstants.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        child: Padding(
          padding: effectivePadding,
          child: loadingWidget,
        ),
      );
    } else {
      loadingWidget = Padding(
        padding: effectivePadding,
        child: loadingWidget,
      );
    }

    return Center(child: loadingWidget);
  }
}

/// A loading overlay that can be shown over existing content
class LoadingOverlay extends StatelessWidget {
  /// The child widget to show the overlay over
  final Widget child;
  
  /// Whether to show the loading overlay
  final bool isLoading;
  
  /// The loading message to display
  final String? message;
  
  /// The color of the overlay background
  final Color? overlayColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.message,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: overlayColor ?? Colors.black54,
            child: LoadingIndicator(
              message: message ?? AppConstants.defaultLoadingMessage,
              showCard: true,
            ),
          ),
      ],
    );
  }
}

/// A shimmer loading effect for list items and cards
class ShimmerLoading extends StatefulWidget {
  /// The width of the shimmer area
  final double? width;
  
  /// The height of the shimmer area
  final double? height;
  
  /// The border radius of the shimmer area
  final double? borderRadius;
  
  /// The base color of the shimmer
  final Color? baseColor;
  
  /// The highlight color of the shimmer
  final Color? highlightColor;

  const ShimmerLoading({
    super.key,
    this.width,
    this.height = 20,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutQuart),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.baseColor ?? Colors.grey.shade300;
    final highlightColor = widget.highlightColor ?? Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? AppConstants.borderRadius,
            ),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              transform: GradientRotation(_animation.value),
            ),
          ),
        );
      },
    );
  }
}