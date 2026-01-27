class JobCodeSettings {
  final String code;
  final bool hasPTO;
  final int maxHoursPerWeek;
  final int defaultScheduledHours;
  final String colorHex;
  final int sortOrder;
  final String? sortGroup; // Group name for grouping job codes together

  // Static default for vacation days (not configurable)
  static const int defaultVacationDays = 8;

  JobCodeSettings({
    required this.code,
    required this.hasPTO,
    this.maxHoursPerWeek = 40,
    this.defaultScheduledHours = 40,
    required this.colorHex,
    this.sortOrder = 0,
    this.sortGroup,
  });

  JobCodeSettings copyWith({
    bool? hasPTO,
    int? maxHoursPerWeek,
    int? defaultScheduledHours,
    String? colorHex,
    int? sortOrder,
    String? sortGroup,
    bool clearSortGroup = false,
  }) {
    return JobCodeSettings(
      code: code,
      hasPTO: hasPTO ?? this.hasPTO,
      maxHoursPerWeek: maxHoursPerWeek ?? this.maxHoursPerWeek,
      defaultScheduledHours: defaultScheduledHours ?? this.defaultScheduledHours,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
      sortGroup: clearSortGroup ? null : (sortGroup ?? this.sortGroup),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'hasPTO': hasPTO ? 1 : 0,
      'defaultScheduledHours': defaultScheduledHours,
      'defaultVacationDays': defaultVacationDays,
      'maxHoursPerWeek': maxHoursPerWeek,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
      'sortGroup': sortGroup,
    };
  }

  factory JobCodeSettings.fromMap(Map<String, dynamic> map) {
    // Handle hasPTO as either bool (from cloud) or int (from local DB)
    final hasPTOValue = map['hasPTO'];
    final hasPTO = hasPTOValue is bool ? hasPTOValue : (hasPTOValue == 1);
    
    return JobCodeSettings(
      code: map['code'],
      hasPTO: hasPTO,
      maxHoursPerWeek: map['maxHoursPerWeek'] ?? 40,
      defaultScheduledHours: map['defaultScheduledHours'] ?? 40,
      colorHex: map['colorHex'] ?? '#4285F4',
      sortOrder: map['sortOrder'] ?? 0,
      sortGroup: map['sortGroup'] as String?,
    );
  }
}
