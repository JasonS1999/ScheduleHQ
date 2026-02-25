import 'package:flutter/material.dart';
import 'coach_mark_overlay.dart';

class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final TooltipPosition preferredPosition;
  final VoidCallback? onShow;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.preferredPosition = TooltipPosition.below,
    this.onShow,
  });
}

class CoachMarkController {
  final List<CoachMarkStep> steps;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  int _currentStep = 0;
  OverlayEntry? _overlayEntry;
  bool _isActive = false;

  CoachMarkController({
    required this.steps,
    required this.onComplete,
    required this.onSkip,
  });

  bool get isActive => _isActive;

  void start(BuildContext context) {
    if (steps.isEmpty || _isActive) return;
    _isActive = true;
    _currentStep = 0;
    _showStep(context);
  }

  void next(BuildContext context) {
    _removeOverlay();
    _currentStep++;
    if (_currentStep >= steps.length) {
      _isActive = false;
      onComplete();
    } else {
      _showStep(context);
    }
  }

  void previous(BuildContext context) {
    if (_currentStep <= 0) return;
    _removeOverlay();
    _currentStep--;
    _showStep(context);
  }

  void skip() {
    _removeOverlay();
    _isActive = false;
    onSkip();
  }

  void _showStep(BuildContext context) {
    final step = steps[_currentStep];

    // Call onShow first (e.g. switching tabs)
    step.onShow?.call();

    // Wait one frame for the target widget to render after any onShow action
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Verify target exists
      if (step.targetKey.currentContext == null) {
        // Target not found, try next step
        _currentStep++;
        if (_currentStep >= steps.length) {
          _isActive = false;
          onComplete();
        } else {
          _showStep(context);
        }
        return;
      }

      _removeOverlay();

      _overlayEntry = OverlayEntry(
        builder: (overlayContext) => CoachMarkOverlay(
          targetKey: step.targetKey,
          title: step.title,
          description: step.description,
          stepIndex: _currentStep,
          totalSteps: steps.length,
          onNext: () => next(context),
          onSkip: () => skip(),
          onPrevious: _currentStep > 0 ? () => previous(context) : null,
          preferredPosition: step.preferredPosition,
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void dispose() {
    _removeOverlay();
    _isActive = false;
  }
}
