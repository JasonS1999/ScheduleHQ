import '../database/settings_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../database/shift_runner_settings_dao.dart';
import '../models/settings.dart';
import '../models/job_code_settings.dart';
import '../models/shift_runner_settings.dart';
import '../services/settings_sync_service.dart';
import '../utils/app_constants.dart';
import 'base_provider.dart';

/// Provider for managing application settings
class SettingsProvider extends BaseProvider {
  final SettingsDao _settingsDao;
  final JobCodeSettingsDao _jobCodeDao;
  final ShiftRunnerSettingsDao _shiftRunnerSettingsDao;
  final SettingsSyncService _syncService;

  // Core settings
  Settings? _settings;
  List<JobCodeSettings> _jobCodeSettings = [];
  ShiftRunnerSettings? _shiftRunnerSettings;

  // UI preferences
  String _themeMode = AppConstants.systemThemeKey;
  bool _show24HourTime = false;
  bool _showWeekends = true;
  bool _autoSyncEnabled = true;

  SettingsProvider({
    SettingsDao? settingsDao,
    JobCodeSettingsDao? jobCodeDao,
    ShiftRunnerSettingsDao? shiftRunnerSettingsDao,
    SettingsSyncService? syncService,
  }) : _settingsDao = settingsDao ?? SettingsDao(),
        _jobCodeDao = jobCodeDao ?? JobCodeSettingsDao(),
        _shiftRunnerSettingsDao = shiftRunnerSettingsDao ?? ShiftRunnerSettingsDao(),
        _syncService = syncService ?? SettingsSyncService.instance;

  // Getters
  Settings? get settings => _settings;
  List<JobCodeSettings> get jobCodeSettings => List.unmodifiable(_jobCodeSettings);
  ShiftRunnerSettings? get shiftRunnerSettings => _shiftRunnerSettings;
  String get themeMode => _themeMode;
  bool get show24HourTime => _show24HourTime;
  bool get showWeekends => _showWeekends;
  bool get autoSyncEnabled => _autoSyncEnabled;
  
  /// Error getter for compatibility (delegates to base class)
  String? get error => errorMessage;

  // Computed getters
  bool get isLightTheme => _themeMode == AppConstants.lightThemeKey;
  bool get isDarkTheme => _themeMode == AppConstants.darkThemeKey;
  bool get isSystemTheme => _themeMode == AppConstants.systemThemeKey;

  /// Initialize the provider by loading all settings
  Future<void> initialize() async {
    await executeWithState(() async {
      await _loadCoreSettings();
      await _loadJobCodeSettings();
      await _loadShiftRunnerSettings();
      await _loadUIPreferences();
    }, errorPrefix: 'Failed to initialize settings');
  }

  /// Public method to load settings (for external callers)
  Future<void> loadSettings() async {
    await initialize();
  }

  /// Public method to load data (alias for loadSettings)
  Future<void> loadData() async {
    await initialize();
  }

  @override
  Future<void> refresh() async {
    await initialize();
  }

  /// Load core application settings
  Future<void> _loadCoreSettings() async {
    _settings = await _settingsDao.getSettings();
    _autoSyncEnabled = _settings?.autoSyncEnabled ?? true;
  }

  /// Load job code settings
  Future<void> _loadJobCodeSettings() async {
    await _jobCodeDao.insertDefaultsIfMissing();
    _jobCodeSettings = await _jobCodeDao.getAll();
  }

  /// Load shift runner settings
  Future<void> _loadShiftRunnerSettings() async {
    final allSettings = await _shiftRunnerSettingsDao.getAllSettings();
    _shiftRunnerSettings = allSettings.values.firstOrNull;
  }

  /// Load UI preferences from local storage
  Future<void> _loadUIPreferences() async {
    // In a full implementation, you'd load these from SharedPreferences
    // For now, use defaults
    _themeMode = AppConstants.systemThemeKey;
    _show24HourTime = false;
    _showWeekends = true;
  }

  /// Update core settings
  Future<bool> updateSettings({
    int? ptoHoursPerTrimester,
    int? maxCarryoverHours,
    int? assistantVacationDays,
    int? swingVacationDays,
    int? minimumHoursBetweenShifts,
    int? inventoryDay,
    int? scheduleStartDay,
    bool? blockOverlaps,
    bool? autoSyncEnabled,
  }) async {
    if (_settings == null) {
      setLoadingState(LoadingState.error, error: 'Settings not loaded');
      return false;
    }

    final updatedSettings = _settings!.copyWith(
      ptoHoursPerTrimester: ptoHoursPerTrimester,
      maxCarryoverHours: maxCarryoverHours,
      assistantVacationDays: assistantVacationDays,
      swingVacationDays: swingVacationDays,
      minimumHoursBetweenShifts: minimumHoursBetweenShifts,
      inventoryDay: inventoryDay,
      scheduleStartDay: scheduleStartDay,
      blockOverlaps: blockOverlaps,
      autoSyncEnabled: autoSyncEnabled,
    );

    return await executeWithState(() async {
      await _settingsDao.updateSettings(updatedSettings);
      _settings = updatedSettings;
      _autoSyncEnabled = updatedSettings.autoSyncEnabled;
      
      // Sync to cloud if enabled
      if (_autoSyncEnabled) {
        await _syncService.uploadSettings();
      }
      
      return true;
    }, errorPrefix: 'Failed to update settings') ?? false;
  }

  /// Update a single settings field
  Future<bool> updateSettingsField(String field, dynamic value) async {
    return await executeWithState(() async {
      await _settingsDao.updateField(field, value);
      
      // Update local cache
      switch (field) {
        case 'autoSyncEnabled':
          _autoSyncEnabled = value as bool;
          break;
        // Add other fields as needed
      }
      
      // Reload settings to ensure consistency
      await _loadCoreSettings();
      
      return true;
    }, errorPrefix: 'Failed to update $field') ?? false;
  }

  /// Update job code settings
  Future<bool> updateJobCodeSettings(List<JobCodeSettings> jobCodes) async {
    return await executeWithState(() async {
      // Upsert all job codes (replaces existing)
      for (final jobCode in jobCodes) {
        await _jobCodeDao.upsert(jobCode);
      }
      
      _jobCodeSettings = List.from(jobCodes);
      
      // Sync to cloud if enabled
      if (_autoSyncEnabled) {
        await _syncService.uploadJobCodeSettings();
      }
      
      return true;
    }, errorPrefix: 'Failed to update job code settings') ?? false;
  }

  /// Add a new job code
  Future<bool> addJobCode({
    required String code,
    required int sortOrder,
  }) async {
    final newJobCode = JobCodeSettings(
      code: code,
      sortOrder: sortOrder,
      hasPTO: false,
      colorHex: '#4285F4',
    );

    return await executeWithState(() async {
      await _jobCodeDao.upsert(newJobCode);
      _jobCodeSettings.add(newJobCode);
      _jobCodeSettings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      
      // Sync to cloud if enabled
      if (_autoSyncEnabled) {
        await _syncService.uploadJobCodeSettings();
      }
      
      return true;
    }, errorPrefix: 'Failed to add job code') ?? false;
  }

  /// Delete a job code
  Future<bool> deleteJobCode(String code) async {
    return await executeWithState(() async {
      await _jobCodeDao.deleteJobCode(code);
      _jobCodeSettings.removeWhere((jc) => jc.code == code);
      
      // Sync to cloud if enabled
      if (_autoSyncEnabled) {
        await _syncService.uploadJobCodeSettings();
      }
      
      return true;
    }, errorPrefix: 'Failed to delete job code') ?? false;
  }

  /// Update theme mode
  Future<void> setThemeMode(String mode) async {
    if ([AppConstants.lightThemeKey, AppConstants.darkThemeKey, AppConstants.systemThemeKey].contains(mode)) {
      _themeMode = mode;
      await _saveUIPreferences();
      notifyListeners();
    }
  }

  /// Toggle 24-hour time format
  Future<void> setShow24HourTime(bool show24Hour) async {
    if (_show24HourTime != show24Hour) {
      _show24HourTime = show24Hour;
      await _saveUIPreferences();
      notifyListeners();
    }
  }

  /// Toggle weekend display
  Future<void> setShowWeekends(bool showWeekends) async {
    if (_showWeekends != showWeekends) {
      _showWeekends = showWeekends;
      await _saveUIPreferences();
      notifyListeners();
    }
  }

  /// Toggle auto-sync
  Future<bool> setAutoSyncEnabled(bool enabled) async {
    return await updateSettingsField('autoSyncEnabled', enabled);
  }

  /// Save UI preferences to local storage
  Future<void> _saveUIPreferences() async {
    // In a full implementation, save to SharedPreferences
    // For now, just keep in memory
  }

  /// Get formatted time based on user preference
  String formatTime(DateTime time) {
    if (_show24HourTime) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      final hour = time.hour == 0 ? 12 : time.hour > 12 ? time.hour - 12 : time.hour;
      final period = time.hour < 12 ? 'AM' : 'PM';
      return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
    }
  }

  /// Validate settings before save
  List<String> validateSettings({
    required int ptoHoursPerTrimester,
    required int maxCarryoverHours,
    required int assistantVacationDays,
    required int swingVacationDays,
    required int minimumHoursBetweenShifts,
  }) {
    final errors = <String>[];

    if (ptoHoursPerTrimester <= 0) {
      errors.add('PTO hours per trimester must be positive');
    }

    if (maxCarryoverHours < 0) {
      errors.add('Max carryover hours cannot be negative');
    }

    if (assistantVacationDays <= 0) {
      errors.add('Assistant vacation days must be positive');
    }

    if (swingVacationDays <= 0) {
      errors.add('Swing vacation days must be positive');
    }

    if (minimumHoursBetweenShifts < 0 || minimumHoursBetweenShifts > 24) {
      errors.add('Minimum hours between shifts must be between 0 and 24');
    }

    return errors;
  }

  /// Reset settings to defaults
  Future<bool> resetToDefaults() async {
    return await executeWithState(() async {
      await _settingsDao.insertDefaultSettings();
      await _jobCodeDao.insertDefaultsIfMissing();
      await initialize();
      return true;
    }, errorPrefix: 'Failed to reset settings') ?? false;
  }

  /// Get settings summary for display
  Map<String, dynamic> getSettingsSummary() {
    return {
      'ptoHoursPerTrimester': _settings?.ptoHoursPerTrimester ?? 0,
      'assistantVacationDays': _settings?.assistantVacationDays ?? 0,
      'swingVacationDays': _settings?.swingVacationDays ?? 0,
      'autoSyncEnabled': _autoSyncEnabled,
      'jobCodeCount': _jobCodeSettings.length,
      'themeMode': _themeMode,
      'show24HourTime': _show24HourTime,
      'showWeekends': _showWeekends,
    };
  }
}