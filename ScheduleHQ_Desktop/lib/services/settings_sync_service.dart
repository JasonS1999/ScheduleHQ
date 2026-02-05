import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import '../database/settings_dao.dart';
import '../database/store_hours_dao.dart';
import '../database/shift_type_dao.dart';
import '../database/job_code_settings_dao.dart';
import '../database/job_code_group_dao.dart';
import '../database/shift_template_dao.dart';
import '../models/settings.dart';
import '../models/store_hours.dart';
import '../models/shift_type.dart';
import '../models/job_code_settings.dart';
import '../models/job_code_group.dart';
import '../models/shift_template.dart';
import 'auth_service.dart';

/// Service for syncing local settings to Firestore so managers can access
/// their configuration from different computers.
/// 
/// Settings are stored per-manager using their UID.
class SettingsSyncService {
  static final SettingsSyncService _instance = SettingsSyncService._internal();
  static SettingsSyncService get instance => _instance;

  SettingsSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SettingsDao _settingsDao = SettingsDao();
  final StoreHoursDao _storeHoursDao = StoreHoursDao();
  final ShiftTypeDao _shiftTypeDao = ShiftTypeDao();
  final JobCodeSettingsDao _jobCodeSettingsDao = JobCodeSettingsDao();
  final JobCodeGroupDao _jobCodeGroupDao = JobCodeGroupDao();
  final ShiftTemplateDao _shiftTemplateDao = ShiftTemplateDao();

  /// Get the current manager's settings document reference
  DocumentReference<Map<String, dynamic>>? get _managerSettingsRef {
    final uid = AuthService.instance.currentUserUid;
    if (uid == null) return null;
    return _firestore.collection('managerSettings').doc(uid);
  }

  // ============== UPLOAD TO CLOUD ==============

  /// Upload all local settings to Firestore
  Future<void> uploadAllSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) {
      log('Cannot upload settings - not logged in', name: 'SettingsSyncService');
      return;
    }

    try {
      final settings = await _settingsDao.getSettings();
      final storeHours = await _storeHoursDao.getStoreHours();
      final shiftTypes = await _shiftTypeDao.getAll();
      final jobCodes = await _jobCodeSettingsDao.getAll();
      final jobCodeGroups = await _jobCodeGroupDao.getAll();
      final shiftTemplates = await _shiftTemplateDao.getAll();

      await ref.set({
        'settings': _settingsToMap(settings),
        'storeHours': _storeHoursToMap(storeHours),
        'shiftTypes': shiftTypes.map((st) => st.toMap()).toList(),
        'jobCodeSettings': jobCodes.map((jc) => jc.toMap()).toList(),
        'jobCodeGroups': jobCodeGroups.map((g) => g.toMap()).toList(),
        'shiftTemplates': shiftTemplates.map((t) => t.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'email': AuthService.instance.currentUserEmail,
      }, SetOptions(merge: true));

      log('Uploaded all settings to Firestore', name: 'SettingsSyncService');
    } catch (e) {
      log('Error uploading settings: $e', name: 'SettingsSyncService');
      rethrow;
    }
  }

  /// Upload only general settings
  Future<void> uploadSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) return;

    try {
      final settings = await _settingsDao.getSettings();
      await ref.set({
        'settings': _settingsToMap(settings),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      log('Uploaded settings to Firestore', name: 'SettingsSyncService');
    } catch (e) {
      log('Error uploading settings: $e', name: 'SettingsSyncService');
      rethrow;
    }
  }

  /// Upload only store hours
  Future<void> uploadStoreHours() async {
    final ref = _managerSettingsRef;
    if (ref == null) return;

    try {
      final storeHours = await _storeHoursDao.getStoreHours();
      await ref.set({
        'storeHours': _storeHoursToMap(storeHours),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      log('Uploaded store hours to Firestore', name: 'SettingsSyncService');
    } catch (e) {
      log('Error uploading store hours: $e', name: 'SettingsSyncService');
      rethrow;
    }
  }

  /// Upload only shift types
  Future<void> uploadShiftTypes() async {
    final ref = _managerSettingsRef;
    if (ref == null) return;

    try {
      final shiftTypes = await _shiftTypeDao.getAll();
      await ref.set({
        'shiftTypes': shiftTypes.map((st) => st.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      log('Uploaded shift types to Firestore', name: 'SettingsSyncService');
    } catch (e) {
      log('Error uploading shift types: $e', name: 'SettingsSyncService');
      rethrow;
    }
  }

  /// Upload only job code settings
  Future<void> uploadJobCodeSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) return;

    try {
      final jobCodes = await _jobCodeSettingsDao.getAll();
      await ref.set({
        'jobCodeSettings': jobCodes.map((jc) => jc.toMap()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      log('Uploaded job code settings to Firestore', name: 'SettingsSyncService');
    } catch (e) {
      log('Error uploading job code settings: $e', name: 'SettingsSyncService');
      rethrow;
    }
  }

  // ============== DOWNLOAD FROM CLOUD ==============

  /// Check if cloud settings exist for this manager
  Future<bool> hasCloudSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) return false;

    try {
      final doc = await ref.get();
      return doc.exists;
    } catch (e) {
      log('Error checking cloud settings: $e', name: 'SettingsSyncService');
      return false;
    }
  }

  /// Get the last update time of cloud settings
  Future<DateTime?> getCloudSettingsLastUpdated() async {
    final ref = _managerSettingsRef;
    if (ref == null) return null;

    try {
      final doc = await ref.get();
      if (!doc.exists) return null;
      
      final timestamp = doc.data()?['lastUpdated'] as Timestamp?;
      return timestamp?.toDate();
    } catch (e) {
      log('Error getting cloud settings timestamp: $e', name: 'SettingsSyncService');
      return null;
    }
  }

  /// Download all settings from Firestore and apply to local database
  Future<SyncResult> downloadAllSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) {
      return SyncResult(success: false, message: 'Not logged in');
    }

    try {
      final doc = await ref.get();
      if (!doc.exists) {
        return SyncResult(success: false, message: 'No cloud settings found');
      }

      final data = doc.data()!;
      int itemsUpdated = 0;

      // Download settings
      if (data['settings'] != null) {
        final settings = _mapToSettings(data['settings'] as Map<String, dynamic>);
        await _settingsDao.updateSettings(settings);
        itemsUpdated++;
      }

      // Download store hours
      if (data['storeHours'] != null) {
        final storeHours = _mapToStoreHours(data['storeHours'] as Map<String, dynamic>);
        await _storeHoursDao.updateStoreHours(storeHours);
        StoreHours.setCache(storeHours);
        itemsUpdated++;
      }

      // Download shift types
      if (data['shiftTypes'] != null) {
        final shiftTypesList = data['shiftTypes'] as List<dynamic>;
        for (final stMap in shiftTypesList) {
          final shiftType = ShiftType.fromMap(Map<String, dynamic>.from(stMap));
          await _shiftTypeDao.upsert(shiftType);
        }
        itemsUpdated++;
      }

      // Download job code settings
      if (data['jobCodeSettings'] != null) {
        final jobCodesList = data['jobCodeSettings'] as List<dynamic>;
        // Get existing codes to determine what to delete
        final existingCodes = (await _jobCodeSettingsDao.getAll()).map((jc) => jc.code).toSet();
        final cloudCodes = <String>{};
        
        for (final jcMap in jobCodesList) {
          final jobCode = JobCodeSettings.fromMap(Map<String, dynamic>.from(jcMap));
          await _jobCodeSettingsDao.upsert(jobCode);
          cloudCodes.add(jobCode.code);
        }
        
        // Delete job codes that exist locally but not in cloud
        for (final code in existingCodes.difference(cloudCodes)) {
          await _jobCodeSettingsDao.deleteJobCode(code);
        }
        itemsUpdated++;
      }

      // Download job code groups
      if (data['jobCodeGroups'] != null) {
        final groupsList = data['jobCodeGroups'] as List<dynamic>;
        // Get existing groups to determine what to delete
        final existingGroups = (await _jobCodeGroupDao.getAll()).map((g) => g.name).toSet();
        final cloudGroups = <String>{};
        
        for (final gMap in groupsList) {
          final group = JobCodeGroup.fromMap(Map<String, dynamic>.from(gMap));
          await _jobCodeGroupDao.insert(group);
          cloudGroups.add(group.name);
        }
        
        // Delete groups that exist locally but not in cloud
        for (final name in existingGroups.difference(cloudGroups)) {
          await _jobCodeGroupDao.delete(name);
        }
        itemsUpdated++;
      }

      // Download shift templates
      if (data['shiftTemplates'] != null) {
        final templatesList = data['shiftTemplates'] as List<dynamic>;
        // Get existing templates to determine what to delete
        final existingTemplates = await _shiftTemplateDao.getAll();
        final existingIds = existingTemplates.map((t) => t.id).whereType<int>().toSet();
        final cloudIds = <int>{};
        
        for (final tMap in templatesList) {
          final template = ShiftTemplate.fromMap(Map<String, dynamic>.from(tMap));
          await _shiftTemplateDao.upsert(template);
          if (template.id != null) cloudIds.add(template.id!);
        }
        
        // Delete templates that exist locally but not in cloud
        for (final id in existingIds.difference(cloudIds)) {
          await _shiftTemplateDao.delete(id);
        }
        itemsUpdated++;
      }

      log('Downloaded all settings from Firestore', name: 'SettingsSyncService');
      return SyncResult(
        success: true, 
        message: 'Successfully synced $itemsUpdated setting categories',
      );
    } catch (e) {
      log('Error downloading settings: $e', name: 'SettingsSyncService');
      return SyncResult(success: false, message: 'Error: $e');
    }
  }

  /// Download only general settings
  Future<SyncResult> downloadSettings() async {
    final ref = _managerSettingsRef;
    if (ref == null) {
      return SyncResult(success: false, message: 'Not logged in');
    }

    try {
      final doc = await ref.get();
      if (!doc.exists || doc.data()?['settings'] == null) {
        return SyncResult(success: false, message: 'No cloud settings found');
      }

      final settings = _mapToSettings(doc.data()!['settings'] as Map<String, dynamic>);
      await _settingsDao.updateSettings(settings);

      log('Downloaded settings from Firestore', name: 'SettingsSyncService');
      return SyncResult(success: true, message: 'Settings downloaded successfully');
    } catch (e) {
      log('Error downloading settings: $e', name: 'SettingsSyncService');
      return SyncResult(success: false, message: 'Error: $e');
    }
  }

  /// Download only store hours
  Future<SyncResult> downloadStoreHours() async {
    final ref = _managerSettingsRef;
    if (ref == null) {
      return SyncResult(success: false, message: 'Not logged in');
    }

    try {
      final doc = await ref.get();
      if (!doc.exists || doc.data()?['storeHours'] == null) {
        return SyncResult(success: false, message: 'No cloud store hours found');
      }

      final storeHours = _mapToStoreHours(doc.data()!['storeHours'] as Map<String, dynamic>);
      await _storeHoursDao.updateStoreHours(storeHours);
      StoreHours.setCache(storeHours);

      log('Downloaded store hours from Firestore', name: 'SettingsSyncService');
      return SyncResult(success: true, message: 'Store hours downloaded successfully');
    } catch (e) {
      log('Error downloading store hours: $e', name: 'SettingsSyncService');
      return SyncResult(success: false, message: 'Error: $e');
    }
  }

  // ============== HELPERS ==============

  Map<String, dynamic> _settingsToMap(Settings settings) {
    return {
      'ptoHoursPerTrimester': settings.ptoHoursPerTrimester,
      'maxCarryoverHours': settings.maxCarryoverHours,
      'assistantVacationDays': settings.assistantVacationDays,
      'swingVacationDays': settings.swingVacationDays,
      'minimumHoursBetweenShifts': settings.minimumHoursBetweenShifts,
      'inventoryDay': settings.inventoryDay,
      'scheduleStartDay': settings.scheduleStartDay,
      'blockOverlaps': settings.blockOverlaps,
    };
  }

  Settings _mapToSettings(Map<String, dynamic> map) {
    return Settings(
      id: 1,
      ptoHoursPerTrimester: map['ptoHoursPerTrimester'] as int? ?? 30,
      maxCarryoverHours: map['maxCarryoverHours'] as int? ?? 10,
      assistantVacationDays: map['assistantVacationDays'] as int? ?? 6,
      swingVacationDays: map['swingVacationDays'] as int? ?? 7,
      minimumHoursBetweenShifts: map['minimumHoursBetweenShifts'] as int? ?? 8,
      inventoryDay: map['inventoryDay'] as int? ?? 1,
      scheduleStartDay: map['scheduleStartDay'] as int? ?? 1,
      blockOverlaps: map['blockOverlaps'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _storeHoursToMap(StoreHours storeHours) {
    return {
      'storeName': storeHours.storeName,
      'storeNsn': storeHours.storeNsn,
      'sundayOpen': storeHours.sundayOpen,
      'sundayClose': storeHours.sundayClose,
      'mondayOpen': storeHours.mondayOpen,
      'mondayClose': storeHours.mondayClose,
      'tuesdayOpen': storeHours.tuesdayOpen,
      'tuesdayClose': storeHours.tuesdayClose,
      'wednesdayOpen': storeHours.wednesdayOpen,
      'wednesdayClose': storeHours.wednesdayClose,
      'thursdayOpen': storeHours.thursdayOpen,
      'thursdayClose': storeHours.thursdayClose,
      'fridayOpen': storeHours.fridayOpen,
      'fridayClose': storeHours.fridayClose,
      'saturdayOpen': storeHours.saturdayOpen,
      'saturdayClose': storeHours.saturdayClose,
    };
  }

  StoreHours _mapToStoreHours(Map<String, dynamic> map) {
    return StoreHours(
      storeName: map['storeName'] as String? ?? '',
      storeNsn: map['storeNsn'] as String? ?? '',
      sundayOpen: map['sundayOpen'] as String? ?? StoreHours.defaultOpenTime,
      sundayClose: map['sundayClose'] as String? ?? StoreHours.defaultCloseTime,
      mondayOpen: map['mondayOpen'] as String? ?? StoreHours.defaultOpenTime,
      mondayClose: map['mondayClose'] as String? ?? StoreHours.defaultCloseTime,
      tuesdayOpen: map['tuesdayOpen'] as String? ?? StoreHours.defaultOpenTime,
      tuesdayClose: map['tuesdayClose'] as String? ?? StoreHours.defaultCloseTime,
      wednesdayOpen: map['wednesdayOpen'] as String? ?? StoreHours.defaultOpenTime,
      wednesdayClose: map['wednesdayClose'] as String? ?? StoreHours.defaultCloseTime,
      thursdayOpen: map['thursdayOpen'] as String? ?? StoreHours.defaultOpenTime,
      thursdayClose: map['thursdayClose'] as String? ?? StoreHours.defaultCloseTime,
      fridayOpen: map['fridayOpen'] as String? ?? StoreHours.defaultOpenTime,
      fridayClose: map['fridayClose'] as String? ?? StoreHours.defaultCloseTime,
      saturdayOpen: map['saturdayOpen'] as String? ?? StoreHours.defaultOpenTime,
      saturdayClose: map['saturdayClose'] as String? ?? StoreHours.defaultCloseTime,
    );
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String message;

  SyncResult({required this.success, required this.message});
}
