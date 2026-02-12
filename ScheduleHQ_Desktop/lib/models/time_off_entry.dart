class TimeOffEntry {
  final int? id;
  final int employeeId;
  final DateTime date;
  final DateTime? endDate; // For multi-day entries (vacation)
  final String timeOffType; // pto / vac / requested
  final int hours;
  final String? vacationGroupId;
  final bool isAllDay; // true = all day, false = specific time range
  final String? startTime; // format: "HH:mm" (e.g., "09:00")
  final String? endTime;   // format: "HH:mm" (e.g., "17:00")

  TimeOffEntry({
    required this.id,
    required this.employeeId,
    required this.date,
    this.endDate,
    required this.timeOffType,
    required this.hours,
    this.vacationGroupId,
    this.isAllDay = true,
    this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'date': date.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'timeOffType': timeOffType,
      'hours': hours,
      'vacationGroupId': vacationGroupId,
      'isAllDay': isAllDay ? 1 : 0,
      'startTime': startTime,
      'endTime': endTime,
    };
  }

  factory TimeOffEntry.fromMap(Map<String, dynamic> map) {
    return TimeOffEntry(
      id: map['id'],
      employeeId: map['employeeId'],
      date: DateTime.parse(map['date']),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      timeOffType: map['timeOffType'],
      hours: map['hours'] ?? 0,
      vacationGroupId: map['vacationGroupId'],
      isAllDay: (map['isAllDay'] ?? 1) == 1,
      startTime: map['startTime'],
      endTime: map['endTime'],
    );
  }

  /// Create a copy with selected fields replaced.
  TimeOffEntry copyWith({
    int? id,
    int? employeeId,
    DateTime? date,
    DateTime? endDate,
    String? timeOffType,
    int? hours,
    String? vacationGroupId,
    bool? isAllDay,
    String? startTime,
    String? endTime,
  }) {
    return TimeOffEntry(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      date: date ?? this.date,
      endDate: endDate ?? this.endDate,
      timeOffType: timeOffType ?? this.timeOffType,
      hours: hours ?? this.hours,
      vacationGroupId: vacationGroupId ?? this.vacationGroupId,
      isAllDay: isAllDay ?? this.isAllDay,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// Returns a human-readable time range string
  String get timeRangeDisplay {
    if (isAllDay) return 'All Day';
    if (startTime == null || endTime == null) return 'All Day';
    return '$startTime - $endTime';
  }

  /// Check if a given time falls within this time off entry
  bool coversTime(int hour, int minute) {
    if (isAllDay) return true;
    if (startTime == null || endTime == null) return true;
    
    final checkTime = hour * 60 + minute;
    final startParts = startTime!.split(':');
    final endParts = endTime!.split(':');
    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    
    return checkTime >= startMinutes && checkTime < endMinutes;
  }

  /// Check if this time off overlaps with a shift time range
  bool overlapsWithShift(DateTime shiftStart, DateTime shiftEnd) {
    // Check if same day
    if (date.year != shiftStart.year || 
        date.month != shiftStart.month || 
        date.day != shiftStart.day) {
      return false;
    }
    
    if (isAllDay) return true;
    if (startTime == null || endTime == null) return true;
    
    final startParts = startTime!.split(':');
    final endParts = endTime!.split(':');
    final timeOffStart = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    int timeOffEnd = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    
    // Handle midnight crossing - if end time is before or equal to start time, it crosses midnight
    if (timeOffEnd <= timeOffStart) {
      timeOffEnd += 24 * 60; // Add 24 hours worth of minutes
    }
    
    final shiftStartMinutes = shiftStart.hour * 60 + shiftStart.minute;
    int shiftEndMinutes = shiftEnd.hour * 60 + shiftEnd.minute;
    
    // Handle shift crossing midnight too
    if (shiftEndMinutes <= shiftStartMinutes) {
      shiftEndMinutes += 24 * 60;
    }
    
    // Check for overlap
    return timeOffStart < shiftEndMinutes && timeOffEnd > shiftStartMinutes;
  }
}
