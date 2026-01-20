/// Represents a single day's schedule template for an employee.
/// Each employee can have up to 7 entries (one per day of the week).
class WeeklyTemplateEntry {
  final int? id;
  final int employeeId;
  final int dayOfWeek; // 0 = Sunday, 6 = Saturday
  final String? startTime; // HH:MM format, null if day is blank
  final String? endTime; // HH:MM format, null if day is blank
  final bool isOff; // true if explicitly marked as OFF

  WeeklyTemplateEntry({
    this.id,
    required this.employeeId,
    required this.dayOfWeek,
    this.startTime,
    this.endTime,
    this.isOff = false,
  });

  /// Returns true if this day has a scheduled shift (not blank and not off)
  bool get hasShift => !isOff && startTime != null && endTime != null;

  /// Returns true if this day is blank (no shift, not marked as off)
  bool get isBlank => !isOff && (startTime == null || endTime == null);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'isOff': isOff ? 1 : 0,
    };
  }

  factory WeeklyTemplateEntry.fromMap(Map<String, dynamic> map) {
    return WeeklyTemplateEntry(
      id: map['id'] as int?,
      employeeId: map['employeeId'] as int,
      dayOfWeek: map['dayOfWeek'] as int,
      startTime: map['startTime'] as String?,
      endTime: map['endTime'] as String?,
      isOff: (map['isOff'] as int?) == 1,
    );
  }

  WeeklyTemplateEntry copyWith({
    int? id,
    int? employeeId,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    bool? isOff,
  }) {
    return WeeklyTemplateEntry(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isOff: isOff ?? this.isOff,
    );
  }

  /// Creates a blank entry (clear the day)
  WeeklyTemplateEntry clearDay() {
    return WeeklyTemplateEntry(
      id: id,
      employeeId: employeeId,
      dayOfWeek: dayOfWeek,
      startTime: null,
      endTime: null,
      isOff: false,
    );
  }

  /// Creates an entry marked as OFF
  WeeklyTemplateEntry markAsOff() {
    return WeeklyTemplateEntry(
      id: id,
      employeeId: employeeId,
      dayOfWeek: dayOfWeek,
      startTime: null,
      endTime: null,
      isOff: true,
    );
  }
}
