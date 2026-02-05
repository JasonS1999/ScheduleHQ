import 'shift_type.dart';

class ShiftRunner {
  final int? id;
  final DateTime date;
  final String shiftType; // key from shift_types table
  final String runnerName;
  final int? employeeId; // ID of the employee running the shift

  // Cache for shift types loaded from database
  static List<ShiftType> _shiftTypes = [];
  static Map<String, ShiftType> _shiftTypeMap = {};

  /// Set shift types from database (call this after loading from DB)
  static void setShiftTypes(List<ShiftType> types) {
    _shiftTypes = types;
    _shiftTypeMap = {for (final t in types) t.key: t};
  }

  /// Get all shift types in order
  static List<ShiftType> get shiftTypes => _shiftTypes;

  /// Get shift type map
  static Map<String, ShiftType> get shiftTypeMap => _shiftTypeMap;

  /// Get ordered shift keys
  static List<String> get shiftOrder => _shiftTypes.map((t) => t.key).toList();

  /// Clear cached shift types
  static void clearShiftTypes() {
    _shiftTypes = [];
    _shiftTypeMap = {};
  }

  ShiftRunner({
    this.id,
    required this.date,
    required this.shiftType,
    required this.runnerName,
    this.employeeId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'shiftType': shiftType,
      'runnerName': runnerName,
      'employeeId': employeeId,
    };
  }

  factory ShiftRunner.fromMap(Map<String, dynamic> map) {
    final dateParts = (map['date'] as String).split('-');
    return ShiftRunner(
      id: map['id'] as int?,
      date: DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      ),
      shiftType: map['shiftType'] as String,
      runnerName: map['runnerName'] as String,
      employeeId: map['employeeId'] as int?,
    );
  }

  ShiftRunner copyWith({
    int? id,
    DateTime? date,
    String? shiftType,
    String? runnerName,
    int? employeeId,
  }) {
    return ShiftRunner(
      id: id ?? this.id,
      date: date ?? this.date,
      shiftType: shiftType ?? this.shiftType,
      runnerName: runnerName ?? this.runnerName,
      employeeId: employeeId ?? this.employeeId,
    );
  }

  /// Get the shift type based on a time using configured ranges
  static String? getShiftTypeForTime(int hour, int minute) {
    final timeValue = hour * 60 + minute;
    
    for (final shiftType in _shiftTypes) {
      final startParts = shiftType.rangeStart.split(':');
      final endParts = shiftType.rangeEnd.split(':');
      final startValue = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endValue = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      
      // Handle overnight shifts (end time < start time)
      if (endValue < startValue) {
        if (timeValue >= startValue || timeValue < endValue) {
          return shiftType.key;
        }
      } else {
        if (timeValue >= startValue && timeValue < endValue) {
          return shiftType.key;
        }
      }
    }
    
    return null;
  }

  static String getLabelForType(String type) {
    return _shiftTypeMap[type]?.label ?? type;
  }

  static String? getColorForType(String type) {
    return _shiftTypeMap[type]?.colorHex;
  }
}
