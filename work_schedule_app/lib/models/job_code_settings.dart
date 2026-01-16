class JobCodeSettings {
  final String code;
  final bool hasPTO;
  final double defaultDailyHours;
  final int maxHoursPerWeek;
  final String colorHex;
  final int sortOrder;

  // Static default for vacation days (not configurable)
  static const int defaultVacationDays = 8;

  JobCodeSettings({
    required this.code,
    required this.hasPTO,
    required this.defaultDailyHours,
    this.maxHoursPerWeek = 40,
    required this.colorHex,
    this.sortOrder = 0,
  });

  JobCodeSettings copyWith({
    bool? hasPTO,
    double? defaultDailyHours,
    int? maxHoursPerWeek,
    String? colorHex,
    int? sortOrder,
  }) {
    return JobCodeSettings(
      code: code,
      hasPTO: hasPTO ?? this.hasPTO,
      defaultDailyHours: defaultDailyHours ?? this.defaultDailyHours,
      maxHoursPerWeek: maxHoursPerWeek ?? this.maxHoursPerWeek,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'hasPTO': hasPTO ? 1 : 0,
      'defaultScheduledHours': defaultDailyHours,
      'defaultVacationDays': defaultVacationDays,
      'maxHoursPerWeek': maxHoursPerWeek,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
    };
  }

  factory JobCodeSettings.fromMap(Map<String, dynamic> map) {
    final raw = map['defaultScheduledHours'];
    final parsedHours = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 8.0;
    return JobCodeSettings(
      code: map['code'],
      hasPTO: map['hasPTO'] == 1,
      defaultDailyHours: parsedHours,
      maxHoursPerWeek: map['maxHoursPerWeek'] ?? 40,
      colorHex: map['colorHex'] ?? '#4285F4',
      sortOrder: map['sortOrder'] ?? 0,
    );
  }
}
