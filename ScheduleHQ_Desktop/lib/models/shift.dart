class Shift {
  final int? id;
  final int employeeId;
  final DateTime startTime;
  final DateTime endTime;
  final String? label;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Shift({
    this.id,
    required this.employeeId,
    required this.startTime,
    required this.endTime,
    this.label,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Shift copyWith({
    int? id,
    int? employeeId,
    DateTime? startTime,
    DateTime? endTime,
    String? label,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Shift(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      label: label ?? this.label,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    // Store in both formats: new component format (DST-safe) and legacy ISO8601
    return {
      'id': id,
      'employeeId': employeeId,
      // Legacy format (still needed for backward compatibility)
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      // New component format (DST-safe)
      'startDate': '${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}',
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endDate': '${endTime.year}-${endTime.month.toString().padLeft(2, '0')}-${endTime.day.toString().padLeft(2, '0')}',
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'label': label,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Shift.fromMap(Map<String, dynamic> map) {
    // Try to read date components first (new DST-safe format)
    DateTime? startTime;
    DateTime? endTime;
    
    if (map['startDate'] != null && map['startHour'] != null && map['startMinute'] != null) {
      // Parse date components (DST-safe)
      final startDateParts = (map['startDate'] as String).split('-');
      startTime = DateTime(
        int.parse(startDateParts[0]), // year
        int.parse(startDateParts[1]), // month
        int.parse(startDateParts[2]), // day
        map['startHour'] as int,
        map['startMinute'] as int,
      );
      
      final endDateParts = (map['endDate'] as String).split('-');
      endTime = DateTime(
        int.parse(endDateParts[0]), // year
        int.parse(endDateParts[1]), // month
        int.parse(endDateParts[2]), // day
        map['endHour'] as int,
        map['endMinute'] as int,
      );
    } else {
      // Fall back to legacy ISO8601 format
      startTime = DateTime.parse(map['startTime'] as String);
      endTime = DateTime.parse(map['endTime'] as String);
    }
    
    return Shift(
      id: map['id'] as int?,
      employeeId: map['employeeId'] as int,
      startTime: startTime,
      endTime: endTime,
      label: map['label'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  String toString() {
    return 'Shift(id: $id, employeeId: $employeeId, start: $startTime, end: $endTime, label: $label)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Shift &&
        other.id == id &&
        other.employeeId == employeeId &&
        other.startTime == startTime &&
        other.endTime == endTime;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        employeeId.hashCode ^
        startTime.hashCode ^
        endTime.hashCode;
  }
}
