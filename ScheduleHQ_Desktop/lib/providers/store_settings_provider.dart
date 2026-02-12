import 'package:flutter/material.dart';
import '../database/store_hours_dao.dart';
import '../database/shift_template_dao.dart';
import '../database/shift_runner_settings_dao.dart';
import '../models/store_hours.dart';
import '../models/shift_template.dart';
import '../models/shift_runner_settings.dart';
import 'base_provider.dart';

/// Provider for managing store-related settings (hours, templates, shift runners)
class StoreSettingsProvider extends BaseProvider {
  final StoreHoursDao _storeHoursDao = StoreHoursDao();
  final ShiftTemplateDao _templateDao = ShiftTemplateDao();
  final ShiftRunnerSettingsDao _shiftRunnerDao = ShiftRunnerSettingsDao();

  // Store data
  StoreHours? _storeHours;
  List<ShiftTemplate> _shiftTemplates = [];
  List<ShiftRunnerSettings> _shiftRunnerSettings = [];

  // Getters
  StoreHours? get storeHours => _storeHours;
  List<ShiftTemplate> get shiftTemplates => List.unmodifiable(_shiftTemplates);
  List<ShiftRunnerSettings> get shiftRunnerSettings => List.unmodifiable(_shiftRunnerSettings);

  /// Load store hours only
  Future<void> loadStoreHours() async {
    await executeWithLoading(() async {
      final hours = await _storeHoursDao.getStoreHours();
      _storeHours = hours;
    });
  }

  /// Load shift templates only
  Future<void> loadShiftTemplates() async {
    await executeWithLoading(() async {
      await _templateDao.insertDefaultTemplatesIfMissing();
      final templates = await _templateDao.getAllTemplates();
      _shiftTemplates = templates;
    });
  }

  /// Load shift runner settings only
  Future<void> loadShiftRunnerSettings() async {
    await executeWithLoading(() async {
      final shiftRunnerMap = await _shiftRunnerDao.getAllSettings();
      _shiftRunnerSettings = shiftRunnerMap.values.toList();
    });
  }

  /// Load all store settings data
  Future<void> loadData() async {
    await executeWithLoading(() async {
      final storeHours = await _storeHoursDao.getStoreHours();
      
      // Insert default templates if missing
      await _templateDao.insertDefaultTemplatesIfMissing();
      final templates = await _templateDao.getAllTemplates();
      
      final shiftRunnerMap = await _shiftRunnerDao.getAllSettings();
      final shiftRunnerSettings = shiftRunnerMap.values.toList();

      _storeHours = storeHours;
      _shiftTemplates = templates;
      _shiftRunnerSettings = shiftRunnerSettings;
    });
  }

  /// Update store hours
  Future<bool> updateStoreHours(StoreHours hours) async {
    try {
      await _storeHoursDao.updateStoreHours(hours);
      _storeHours = hours;
      notifyListeners();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update store hours: $e');
      return false;
    }
  }

  /// Create a new shift template
  Future<bool> createShiftTemplate({
    required String name,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    String? description,
  }) async {
    try {
      final template = ShiftTemplate(
        templateName: name,
        startTime: _timeOfDayToString(startTime),
        endTime: _timeOfDayToString(endTime),
      );

      await _templateDao.insertTemplate(template);
      await _reloadTemplates();
      return true;
    } catch (e) {
      setErrorMessage('Failed to create shift template: $e');
      return false;
    }
  }

  /// Update an existing shift template
  Future<bool> updateShiftTemplate({
    required ShiftTemplate original,
    required String name,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    String? description,
  }) async {
    try {
      final updated = original.copyWith(
        templateName: name,
        startTime: _timeOfDayToString(startTime),
        endTime: _timeOfDayToString(endTime),
      );

      await _templateDao.updateTemplate(updated);
      await _reloadTemplates();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update shift template: $e');
      return false;
    }
  }

  /// Delete a shift template
  Future<bool> deleteShiftTemplate(ShiftTemplate template) async {
    try {
      if (template.id == null) {
        setErrorMessage('Cannot delete template: Invalid ID');
        return false;
      }

      await _templateDao.deleteTemplate(template.id!);
      await _reloadTemplates();
      return true;
    } catch (e) {
      setErrorMessage('Failed to delete shift template: $e');
      return false;
    }
  }

  /// Create a new shift runner setting
  Future<bool> createShiftRunnerSetting({
    required String shiftType,
    String? customLabel,
    String? shiftRangeStart,
    String? shiftRangeEnd,
    String? defaultStartTime,
    String? defaultEndTime,
  }) async {
    try {
      final setting = ShiftRunnerSettings(
        shiftType: shiftType,
        customLabel: customLabel,
        shiftRangeStart: shiftRangeStart,
        shiftRangeEnd: shiftRangeEnd,
        defaultStartTime: defaultStartTime,
        defaultEndTime: defaultEndTime,
      );

      await _shiftRunnerDao.upsert(setting);
      await _reloadShiftRunnerSettings();
      return true;
    } catch (e) {
      setErrorMessage('Failed to create shift runner setting: $e');
      return false;
    }
  }

  /// Update an existing shift runner setting
  Future<bool> updateShiftRunnerSetting({
    required ShiftRunnerSettings original,
    String? customLabel,
    String? shiftRangeStart,
    String? shiftRangeEnd,
    String? defaultStartTime,
    String? defaultEndTime,
  }) async {
    try {
      final updated = original.copyWith(
        customLabel: customLabel,
        shiftRangeStart: shiftRangeStart,
        shiftRangeEnd: shiftRangeEnd,
        defaultStartTime: defaultStartTime,
        defaultEndTime: defaultEndTime,
      );

      await _shiftRunnerDao.upsert(updated);
      await _reloadShiftRunnerSettings();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update shift runner setting: $e');
      return false;
    }
  }

  /// Delete a shift runner setting
  Future<bool> deleteShiftRunnerSetting(ShiftRunnerSettings setting) async {
    try {
      await _shiftRunnerDao.delete(setting.shiftType);
      await _reloadShiftRunnerSettings();
      return true;
    } catch (e) {
      setErrorMessage('Failed to delete shift runner setting: $e');
      return false;
    }
  }

  /// Generate time options for dropdowns (12:00 AM to 11:30 PM in 30-minute increments)
  List<String> generateTimeOptions() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      times.add('${hour.toString().padLeft(2, '0')}:00');
      times.add('${hour.toString().padLeft(2, '0')}:30');
    }
    return times;
  }

  /// Parse TimeOfDay from string (HH:mm format)
  TimeOfDay parseTimeOfDay(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) {
      return const TimeOfDay(hour: 9, minute: 0); // Default fallback
    }
    
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = int.tryParse(parts[1]) ?? 0;
    
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Convert TimeOfDay to string (HH:mm format)
  String _timeOfDayToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Calculate shift duration in hours
  double calculateShiftDuration(TimeOfDay startTime, TimeOfDay endTime) {
    int startMinutes = startTime.hour * 60 + startTime.minute;
    int endMinutes = endTime.hour * 60 + endTime.minute;
    
    // Handle overnight shifts
    if (endMinutes <= startMinutes) {
      endMinutes += 24 * 60; // Add 24 hours
    }
    
    return (endMinutes - startMinutes) / 60.0;
  }

  /// Format time for display (12-hour format)
  String formatTime12Hour(TimeOfDay time) {
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final hour = time.hour == 0 ? 12 : time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  /// Private helper methods
  Future<void> _reloadTemplates() async {
    final templates = await _templateDao.getAllTemplates();
    _shiftTemplates = templates;
    notifyListeners();
  }

  Future<void> _reloadShiftRunnerSettings() async {
    final settingsMap = await _shiftRunnerDao.getAllSettings();
    _shiftRunnerSettings = settingsMap.values.toList();
    notifyListeners();
  }

  /// Get default store hours if none exist
  StoreHours getDefaultStoreHours() {
    return _storeHours ?? StoreHours.defaults();
  }

  /// Update store name
  Future<bool> updateStoreName(String name) async {
    try {
      if (_storeHours == null) return false;
      
      final updated = _storeHours!.copyWith(storeName: name);
      await _storeHoursDao.updateStoreHours(updated);
      StoreHours.setCache(updated);
      _storeHours = updated;
      notifyListeners();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update store name: $e');
      return false;
    }
  }

  /// Update store NSN
  Future<bool> updateStoreNsn(String nsn) async {
    try {
      if (_storeHours == null) return false;
      
      final updated = _storeHours!.copyWith(storeNsn: nsn);
      await _storeHoursDao.updateStoreHours(updated);
      StoreHours.setCache(updated);
      _storeHours = updated;
      notifyListeners();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update store NSN: $e');
      return false;
    }
  }

  /// Update store hours for a specific day
  Future<bool> updateStoreHoursTime(int dayIndex, bool isOpen, String time) async {
    try {
      if (_storeHours == null) return false;
      
      StoreHours updated;
      switch (dayIndex) {
        case 0: // Sunday
          updated = isOpen 
              ? _storeHours!.copyWith(sundayOpen: time)
              : _storeHours!.copyWith(sundayClose: time);
          break;
        case 1: // Monday
          updated = isOpen 
              ? _storeHours!.copyWith(mondayOpen: time)
              : _storeHours!.copyWith(mondayClose: time);
          break;
        case 2: // Tuesday
          updated = isOpen 
              ? _storeHours!.copyWith(tuesdayOpen: time)
              : _storeHours!.copyWith(tuesdayClose: time);
          break;
        case 3: // Wednesday
          updated = isOpen 
              ? _storeHours!.copyWith(wednesdayOpen: time)
              : _storeHours!.copyWith(wednesdayClose: time);
          break;
        case 4: // Thursday
          updated = isOpen 
              ? _storeHours!.copyWith(thursdayOpen: time)
              : _storeHours!.copyWith(thursdayClose: time);
          break;
        case 5: // Friday
          updated = isOpen 
              ? _storeHours!.copyWith(fridayOpen: time)
              : _storeHours!.copyWith(fridayClose: time);
          break;
        case 6: // Saturday
          updated = isOpen 
              ? _storeHours!.copyWith(saturdayOpen: time)
              : _storeHours!.copyWith(saturdayClose: time);
          break;
        default:
          return false;
      }
      
      await _storeHoursDao.updateStoreHours(updated);
      StoreHours.setCache(updated);
      _storeHours = updated;
      notifyListeners();
      return true;
    } catch (e) {
      setErrorMessage('Failed to update store hours: $e');
      return false;
    }
  }

  /// Apply same times to all days
  Future<bool> applyToAllDays(String openTime, String closeTime) async {
    try {
      if (_storeHours == null) return false;
      
      final updated = _storeHours!.copyWith(
        sundayOpen: openTime,
        sundayClose: closeTime,
        mondayOpen: openTime,
        mondayClose: closeTime,
        tuesdayOpen: openTime,
        tuesdayClose: closeTime,
        wednesdayOpen: openTime,
        wednesdayClose: closeTime,
        thursdayOpen: openTime,
        thursdayClose: closeTime,
        fridayOpen: openTime,
        fridayClose: closeTime,
        saturdayOpen: openTime,
        saturdayClose: closeTime,
      );
      
      await _storeHoursDao.updateStoreHours(updated);
      StoreHours.setCache(updated);
      _storeHours = updated;
      notifyListeners();
      showSuccessMessage('Applied to all days');
      return true;
    } catch (e) {
      setErrorMessage('Failed to apply to all days: $e');
      return false;
    }
  }

  /// Reset store hours to defaults
  Future<bool> resetToDefaults() async {
    try {
      final defaults = StoreHours.defaults();
      await _storeHoursDao.updateStoreHours(defaults);
      StoreHours.setCache(defaults);
      _storeHours = defaults;
      notifyListeners();
      showSuccessMessage('Store hours reset to defaults');
      return true;
    } catch (e) {
      setErrorMessage('Failed to reset to defaults: $e');
      return false;
    }
  }

  @override
  Future<void> refresh() async {
    await loadData();
  }
}