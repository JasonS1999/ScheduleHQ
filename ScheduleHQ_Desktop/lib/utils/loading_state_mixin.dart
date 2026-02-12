import 'package:flutter/material.dart';

/// Mixin that provides standardized loading state management
/// Usage: Add `with LoadingStateMixin` to your StatefulWidget's State class
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  /// Whether the widget is currently in a loading state
  bool _isLoading = false;

  /// Get the current loading state
  bool get isLoading => _isLoading;

  /// Set the loading state and rebuild the UI
  void setLoading(bool loading) {
    if (mounted) {
      setState(() {
        _isLoading = loading;
      });
    }
  }

  /// Execute an async operation with automatic loading state management
  /// 
  /// Usage:
  /// ```dart
  /// await withLoading(() async {
  ///   // Your async operation here
  ///   await someAsyncMethod();
  /// });
  /// ```
  Future<T?> withLoading<T>(Future<T> Function() operation) async {
    if (_isLoading) return null; // Prevent multiple simultaneous operations
    
    setLoading(true);
    try {
      return await operation();
    } finally {
      setLoading(false);
    }
  }

  /// Execute an async operation with custom loading state management
  /// Useful when you need to manage multiple loading states
  Future<T?> withLoadingState<T>(
    bool Function() getState,
    void Function(bool) setState,
    Future<T> Function() operation,
  ) async {
    if (getState()) return null; // Prevent multiple simultaneous operations
    
    setState(true);
    try {
      return await operation();
    } finally {
      setState(false);
    }
  }

  /// Build a loading indicator when in loading state, otherwise build content
  Widget buildWithLoading({
    required Widget Function() builder,
    Widget? loadingWidget,
    String? loadingText,
  }) {
    if (_isLoading) {
      return loadingWidget ?? 
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (loadingText != null) ...[
              const SizedBox(height: 16),
              Text(loadingText),
            ],
          ],
        );
    }
    return builder();
  }
}