class StoreHours {
  final int? id;
  final String storeName;
  final String storeNsn;
  
  // Per-day open times (0=Sunday, 1=Monday, ..., 6=Saturday)
  final String sundayOpen;
  final String sundayClose;
  final String mondayOpen;
  final String mondayClose;
  final String tuesdayOpen;
  final String tuesdayClose;
  final String wednesdayOpen;
  final String wednesdayClose;
  final String thursdayOpen;
  final String thursdayClose;
  final String fridayOpen;
  final String fridayClose;
  final String saturdayOpen;
  final String saturdayClose;

  static const String defaultOpenTime = '04:30';
  static const String defaultCloseTime = '01:00';

  // Static cache for global access
  static StoreHours _cached = StoreHours.defaults();
  
  /// Get the cached store hours (synchronous access)
  static StoreHours get cached => _cached;
  
  /// Update the cache (call this after loading from DB)
  static void setCache(StoreHours hours) {
    _cached = hours;
  }

  StoreHours({
    this.id,
    this.storeName = '',
    this.storeNsn = '',
    required this.sundayOpen,
    required this.sundayClose,
    required this.mondayOpen,
    required this.mondayClose,
    required this.tuesdayOpen,
    required this.tuesdayClose,
    required this.wednesdayOpen,
    required this.wednesdayClose,
    required this.thursdayOpen,
    required this.thursdayClose,
    required this.fridayOpen,
    required this.fridayClose,
    required this.saturdayOpen,
    required this.saturdayClose,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeName': storeName,
      'storeNsn': storeNsn,
      'sundayOpen': sundayOpen,
      'sundayClose': sundayClose,
      'mondayOpen': mondayOpen,
      'mondayClose': mondayClose,
      'tuesdayOpen': tuesdayOpen,
      'tuesdayClose': tuesdayClose,
      'wednesdayOpen': wednesdayOpen,
      'wednesdayClose': wednesdayClose,
      'thursdayOpen': thursdayOpen,
      'thursdayClose': thursdayClose,
      'fridayOpen': fridayOpen,
      'fridayClose': fridayClose,
      'saturdayOpen': saturdayOpen,
      'saturdayClose': saturdayClose,
    };
  }

  factory StoreHours.fromMap(Map<String, dynamic> map) {
    return StoreHours(
      id: map['id'] as int?,
      storeName: map['storeName'] as String? ?? '',
      storeNsn: map['storeNsn'] as String? ?? '',
      sundayOpen: map['sundayOpen'] as String? ?? defaultOpenTime,
      sundayClose: map['sundayClose'] as String? ?? defaultCloseTime,
      mondayOpen: map['mondayOpen'] as String? ?? defaultOpenTime,
      mondayClose: map['mondayClose'] as String? ?? defaultCloseTime,
      tuesdayOpen: map['tuesdayOpen'] as String? ?? defaultOpenTime,
      tuesdayClose: map['tuesdayClose'] as String? ?? defaultCloseTime,
      wednesdayOpen: map['wednesdayOpen'] as String? ?? defaultOpenTime,
      wednesdayClose: map['wednesdayClose'] as String? ?? defaultCloseTime,
      thursdayOpen: map['thursdayOpen'] as String? ?? defaultOpenTime,
      thursdayClose: map['thursdayClose'] as String? ?? defaultCloseTime,
      fridayOpen: map['fridayOpen'] as String? ?? defaultOpenTime,
      fridayClose: map['fridayClose'] as String? ?? defaultCloseTime,
      saturdayOpen: map['saturdayOpen'] as String? ?? defaultOpenTime,
      saturdayClose: map['saturdayClose'] as String? ?? defaultCloseTime,
    );
  }

  factory StoreHours.defaults() {
    return StoreHours(
      storeName: '',
      storeNsn: '',
      sundayOpen: defaultOpenTime,
      sundayClose: defaultCloseTime,
      mondayOpen: defaultOpenTime,
      mondayClose: defaultCloseTime,
      tuesdayOpen: defaultOpenTime,
      tuesdayClose: defaultCloseTime,
      wednesdayOpen: defaultOpenTime,
      wednesdayClose: defaultCloseTime,
      thursdayOpen: defaultOpenTime,
      thursdayClose: defaultCloseTime,
      fridayOpen: defaultOpenTime,
      fridayClose: defaultCloseTime,
      saturdayOpen: defaultOpenTime,
      saturdayClose: defaultCloseTime,
    );
  }

  StoreHours copyWith({
    int? id,
    String? storeName,
    String? storeNsn,
    String? sundayOpen,
    String? sundayClose,
    String? mondayOpen,
    String? mondayClose,
    String? tuesdayOpen,
    String? tuesdayClose,
    String? wednesdayOpen,
    String? wednesdayClose,
    String? thursdayOpen,
    String? thursdayClose,
    String? fridayOpen,
    String? fridayClose,
    String? saturdayOpen,
    String? saturdayClose,
  }) {
    return StoreHours(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      storeNsn: storeNsn ?? this.storeNsn,
      sundayOpen: sundayOpen ?? this.sundayOpen,
      sundayClose: sundayClose ?? this.sundayClose,
      mondayOpen: mondayOpen ?? this.mondayOpen,
      mondayClose: mondayClose ?? this.mondayClose,
      tuesdayOpen: tuesdayOpen ?? this.tuesdayOpen,
      tuesdayClose: tuesdayClose ?? this.tuesdayClose,
      wednesdayOpen: wednesdayOpen ?? this.wednesdayOpen,
      wednesdayClose: wednesdayClose ?? this.wednesdayClose,
      thursdayOpen: thursdayOpen ?? this.thursdayOpen,
      thursdayClose: thursdayClose ?? this.thursdayClose,
      fridayOpen: fridayOpen ?? this.fridayOpen,
      fridayClose: fridayClose ?? this.fridayClose,
      saturdayOpen: saturdayOpen ?? this.saturdayOpen,
      saturdayClose: saturdayClose ?? this.saturdayClose,
    );
  }

  /// Get open time for a specific day of week (0=Sunday, 6=Saturday)
  String getOpenTimeForDay(int dayOfWeek) {
    switch (dayOfWeek) {
      case DateTime.sunday: return sundayOpen;
      case DateTime.monday: return mondayOpen;
      case DateTime.tuesday: return tuesdayOpen;
      case DateTime.wednesday: return wednesdayOpen;
      case DateTime.thursday: return thursdayOpen;
      case DateTime.friday: return fridayOpen;
      case DateTime.saturday: return saturdayOpen;
      default: return defaultOpenTime;
    }
  }

  /// Get close time for a specific day of week (0=Sunday, 6=Saturday)
  String getCloseTimeForDay(int dayOfWeek) {
    switch (dayOfWeek) {
      case DateTime.sunday: return sundayClose;
      case DateTime.monday: return mondayClose;
      case DateTime.tuesday: return tuesdayClose;
      case DateTime.wednesday: return wednesdayClose;
      case DateTime.thursday: return thursdayClose;
      case DateTime.friday: return fridayClose;
      case DateTime.saturday: return saturdayClose;
      default: return defaultCloseTime;
    }
  }

  /// Parse time string to hour and minute
  static (int hour, int minute) parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  /// Check if a given time matches the open time for a specific day
  bool isOpenTime(int hour, int minute, {int? dayOfWeek}) {
    final openTime = dayOfWeek != null ? getOpenTimeForDay(dayOfWeek) : mondayOpen;
    final (openHour, openMinute) = parseTime(openTime);
    return hour == openHour && minute == openMinute;
  }

  /// Check if a given time matches the close time for a specific day
  bool isCloseTime(int hour, int minute, {int? dayOfWeek}) {
    final closeTime = dayOfWeek != null ? getCloseTimeForDay(dayOfWeek) : mondayClose;
    final (closeHour, closeMinute) = parseTime(closeTime);
    return hour == closeHour && minute == closeMinute;
  }
}
