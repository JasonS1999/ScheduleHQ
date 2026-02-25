import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  final Widget avatar;
  final int unreadCount;
  final bool isAnimating;
  final VoidCallback onTap;

  const NotificationBadge({
    super.key,
    required this.avatar,
    required this.unreadCount,
    required this.isAnimating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: avatar,
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            top: -4,
            right: -4,
            child: _PulseBadge(
              count: unreadCount,
              isAnimating: isAnimating,
            ),
          ),
      ],
    );
  }
}

class _PulseBadge extends StatefulWidget {
  final int count;
  final bool isAnimating;

  const _PulseBadge({required this.count, required this.isAnimating});

  @override
  State<_PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<_PulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(covariant _PulseBadge old) {
    super.didUpdateWidget(old);
    if (widget.isAnimating && !old.isAnimating) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count > 99 ? '99+' : '${widget.count}';
    final isWide = widget.count > 9;

    return ScaleTransition(
      scale: _scale,
      child: Container(
        constraints: BoxConstraints(
          minWidth: isWide ? 22 : 18,
          minHeight: 18,
        ),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
