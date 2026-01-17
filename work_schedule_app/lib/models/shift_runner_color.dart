import 'package:flutter/material.dart';

class ShiftRunnerColor {
  final String shiftType; // 'open', 'lunch', 'dinner', 'close'
  final String colorHex;

  // Default colors
  static const Map<String, String> defaultColors = {
    'open': '#FF9800',    // Orange
    'lunch': '#4CAF50',   // Green
    'dinner': '#2196F3',  // Blue
    'close': '#9C27B0',   // Purple
  };

  ShiftRunnerColor({
    required this.shiftType,
    required this.colorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'shiftType': shiftType,
      'colorHex': colorHex,
    };
  }

  factory ShiftRunnerColor.fromMap(Map<String, dynamic> map) {
    return ShiftRunnerColor(
      shiftType: map['shiftType'] as String,
      colorHex: map['colorHex'] as String,
    );
  }

  Color get color {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  static Color getDefaultColor(String shiftType) {
    final hex = defaultColors[shiftType] ?? '#808080';
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  ShiftRunnerColor copyWith({
    String? shiftType,
    String? colorHex,
  }) {
    return ShiftRunnerColor(
      shiftType: shiftType ?? this.shiftType,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}
