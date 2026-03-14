class Settings {
  final int id;
  final int ptoHoursPerTrimester;
  final int maxCarryoverHours;
  final int assistantVacationDays;
  final int swingVacationDays;
  final int minimumHoursBetweenShifts;
  final int inventoryDay;
  final int scheduleStartDay;
  final bool blockOverlaps; // If true, block creating vacations that overlap existing time off
  final bool autoSyncEnabled; // If true, automatically sync data to cloud on changes
  final bool requestDeadlineEnabled; // If true, restrict employee request submissions by deadline
  final int requestDeadlineDay; // Day of prior month by which requests must be submitted (1-28)

  const Settings({
    required this.id,
    required this.ptoHoursPerTrimester,
    required this.maxCarryoverHours,
    required this.assistantVacationDays,
    required this.swingVacationDays,
    required this.minimumHoursBetweenShifts,
    required this.inventoryDay,
    required this.scheduleStartDay,
    required this.blockOverlaps,
    this.autoSyncEnabled = false,
    this.requestDeadlineEnabled = false,
    this.requestDeadlineDay = 15,
  });

  // ---------------------------------------------------------------------------
  // FROM MAP (DB → Model)
  // ---------------------------------------------------------------------------
  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      id: map['id'] as int,
      ptoHoursPerTrimester: map['ptoHoursPerTrimester'] as int,
      maxCarryoverHours: map['maxCarryoverHours'] as int,
      assistantVacationDays: map['assistantVacationDays'] as int,
      swingVacationDays: map['swingVacationDays'] as int,
      minimumHoursBetweenShifts: map['minimumHoursBetweenShifts'] as int,
      inventoryDay: map['inventoryDay'] as int,
      scheduleStartDay: map['scheduleStartDay'] as int,
      blockOverlaps: (map['blockOverlaps'] ?? 0) == 1,
      autoSyncEnabled: (map['autoSyncEnabled'] ?? 0) == 1,
      requestDeadlineEnabled: (map['requestDeadlineEnabled'] ?? 0) == 1,
      requestDeadlineDay: map['requestDeadlineDay'] as int? ?? 15,
    );
  }

  // ---------------------------------------------------------------------------
  // TO MAP (Model → DB)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ptoHoursPerTrimester': ptoHoursPerTrimester,
      'ptoHoursPerRequest': 8, // Legacy column, no longer used but required by DB schema
      'maxCarryoverHours': maxCarryoverHours,
      'assistantVacationDays': assistantVacationDays,
      'swingVacationDays': swingVacationDays,
      'minimumHoursBetweenShifts': minimumHoursBetweenShifts,
      'inventoryDay': inventoryDay,
      'scheduleStartDay': scheduleStartDay,
      'blockOverlaps': blockOverlaps ? 1 : 0,
      'autoSyncEnabled': autoSyncEnabled ? 1 : 0,
      'requestDeadlineEnabled': requestDeadlineEnabled ? 1 : 0,
      'requestDeadlineDay': requestDeadlineDay,
    };
  }

  // ---------------------------------------------------------------------------
  // COPY WITH (Immutable updates)
  // ---------------------------------------------------------------------------
  Settings copyWith({
    int? id,
    int? ptoHoursPerTrimester,
    int? maxCarryoverHours,
    int? assistantVacationDays,
    int? swingVacationDays,
    int? minimumHoursBetweenShifts,
    int? inventoryDay,
    int? scheduleStartDay,
    bool? blockOverlaps,
    bool? autoSyncEnabled,
    bool? requestDeadlineEnabled,
    int? requestDeadlineDay,
  }) {
    return Settings(
      id: id ?? this.id,
      ptoHoursPerTrimester:
          ptoHoursPerTrimester ?? this.ptoHoursPerTrimester,
      maxCarryoverHours: maxCarryoverHours ?? this.maxCarryoverHours,
      assistantVacationDays:
          assistantVacationDays ?? this.assistantVacationDays,
      swingVacationDays: swingVacationDays ?? this.swingVacationDays,
      minimumHoursBetweenShifts:
          minimumHoursBetweenShifts ?? this.minimumHoursBetweenShifts,
      inventoryDay: inventoryDay ?? this.inventoryDay,
      scheduleStartDay: scheduleStartDay ?? this.scheduleStartDay,
      blockOverlaps: blockOverlaps ?? this.blockOverlaps,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      requestDeadlineEnabled:
          requestDeadlineEnabled ?? this.requestDeadlineEnabled,
      requestDeadlineDay: requestDeadlineDay ?? this.requestDeadlineDay,
    );
  }

  @override
  String toString() {
    return '''
Settings(
  id: $id,
  ptoHoursPerTrimester: $ptoHoursPerTrimester,
  maxCarryoverHours: $maxCarryoverHours,
  assistantVacationDays: $assistantVacationDays,
  swingVacationDays: $swingVacationDays,
  minimumHoursBetweenShifts: $minimumHoursBetweenShifts,
  inventoryDay: $inventoryDay,
  scheduleStartDay: $scheduleStartDay,
  blockOverlaps: $blockOverlaps,
  requestDeadlineEnabled: $requestDeadlineEnabled,
  requestDeadlineDay: $requestDeadlineDay
)
''';
  }
}
