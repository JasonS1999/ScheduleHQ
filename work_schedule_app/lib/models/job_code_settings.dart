class JobCodeSettings {
  final String code;
  final bool hasPTO;
  final int defaultScheduledHours;
  final int defaultVacationDays;
  final String colorHex;
  final int sortOrder;

  JobCodeSettings({
    required this.code,
    required this.hasPTO,
    required this.defaultScheduledHours,
    required this.defaultVacationDays,
    required this.colorHex,
    this.sortOrder = 0,
  });

  JobCodeSettings copyWith({
    bool? hasPTO,
    int? defaultScheduledHours,
    int? defaultVacationDays,
    String? colorHex,
    int? sortOrder,
  }) {
    return JobCodeSettings(
      code: code,
      hasPTO: hasPTO ?? this.hasPTO,
      defaultScheduledHours:
          defaultScheduledHours ?? this.defaultScheduledHours,
      defaultVacationDays:
          defaultVacationDays ?? this.defaultVacationDays,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'hasPTO': hasPTO ? 1 : 0,
      'defaultScheduledHours': defaultScheduledHours,
      'defaultVacationDays': defaultVacationDays,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
    };
  }

  factory JobCodeSettings.fromMap(Map<String, dynamic> map) {
    return JobCodeSettings(
      code: map['code'],
      hasPTO: map['hasPTO'] == 1,
      defaultScheduledHours: map['defaultScheduledHours'],
      defaultVacationDays: map['defaultVacationDays'],
      colorHex: map['colorHex'] ?? '#4285F4',
      sortOrder: map['sortOrder'] ?? 0,
    );
  }
}
