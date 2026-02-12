import '../database/job_code_settings_dao.dart';
import '../database/job_code_group_dao.dart';
import '../models/job_code_settings.dart';
import '../models/job_code_group.dart';
import 'base_provider.dart';

/// Provider for managing job code settings and groups
class JobCodeProvider extends BaseProvider {
  final JobCodeSettingsDao _dao = JobCodeSettingsDao();
  final JobCodeGroupDao _groupDao = JobCodeGroupDao();

  List<JobCodeSettings> _codes = [];
  List<JobCodeGroup> _groups = [];
  bool _orderDirty = false;

  // Getters
  List<JobCodeSettings> get codes => List.unmodifiable(_codes);
  List<JobCodeSettings> get jobCodes => List.unmodifiable(_codes); // Alias for codes
  List<JobCodeGroup> get groups => List.unmodifiable(_groups);
  bool get isOrderDirty => _orderDirty;
  
  /// Error getter for compatibility (delegates to base class)
  String? get error => errorMessage;

  /// Initialize the provider (alias for loadData)
  Future<void> initialize() async {
    await loadData();
  }

  /// Load groups only
  Future<void> loadGroups() async {
    await executeWithLoading(() async {
      final groups = await _groupDao.getAll();
      _groups = groups;
    });
  }

  /// Load all job codes and groups
  Future<void> loadData() async {
    await executeWithLoading(() async {
      await _dao.insertDefaultsIfMissing();
      
      final codes = await _dao.getAll();
      final groups = await _groupDao.getAll();
      
      _codes = codes;
      _groups = groups;
      _orderDirty = false;
    });
  }

  /// Create a new job code
  Future<bool> createJobCode({
    required String code,
    required String colorHex,
    required bool hasPTO,
    String? sortGroup,
  }) async {
    try {
      final newJobCode = JobCodeSettings(
        code: code,
        colorHex: colorHex,
        hasPTO: hasPTO,
        sortGroup: sortGroup,
        sortOrder: _codes.length,
      );

      await _dao.upsert(newJobCode);
      await loadData(); // Reload to get updated data
      return true;
    } catch (e) {
      setErrorMessage('Failed to create job code: $e');
      return false;
    }
  }

  /// Update an existing job code
  Future<bool> updateJobCode({
    required String originalCode,
    required String newCode,
    required String colorHex,
    required bool hasPTO,
    String? sortGroup,
  }) async {
    try {
      final existingCode = _codes.firstWhere(
        (c) => c.code.toLowerCase() == originalCode.toLowerCase(),
      );

      final updatedCode = existingCode.copyWith(
        colorHex: colorHex,
        hasPTO: hasPTO,
        sortGroup: sortGroup,
      );

      if (originalCode != newCode) {
        // If code is changing, use renameCode method
        await _dao.renameCode(originalCode, updatedCode.copyWith());
      } else {
        // Otherwise just update
        await _dao.upsert(updatedCode);
      }
      
      await loadData(); // Reload to get updated data
      return true;
    } catch (e) {
      setErrorMessage('Failed to update job code: $e');
      return false;
    }
  }

  /// Delete a job code with optional employee reassignment
  Future<bool> deleteJobCode(
    JobCodeSettings codeToDelete, {
    String? reassignmentCode,
  }) async {
    try {
      final usage = await _dao.getUsageCounts(codeToDelete.code);
      final employeeCount = usage['employees'] ?? 0;

      if (employeeCount > 0 && reassignmentCode == null) {
        setErrorMessage('Cannot delete: employees still assigned and no reassignment selected');
        return false;
      }

      final reassigned = await _dao.deleteJobCode(
        codeToDelete.code,
        reassignEmployeesTo: reassignmentCode,
      );

      if (reassigned > 0) {
        await loadData(); // Reload to get updated data
        return true;
      } else {
        setErrorMessage('Job code no longer exists');
        return false;
      }
    } catch (e) {
      setErrorMessage('Failed to delete job code: $e');
      return false;
    }
  }

  /// Update the sort order of job codes
  Future<bool> updateSortOrder(List<JobCodeSettings> reorderedCodes) async {
    try {
      _codes = reorderedCodes;
      _orderDirty = false;
      notifyListeners();

      await _dao.updateSortOrders(_codes);
      return true;
    } catch (e) {
      setErrorMessage('Failed to update sort order: $e');
      return false;
    }
  }

  /// Mark sort order as dirty (needs saving)
  void markOrderDirty() {
    _orderDirty = true;
    notifyListeners();
  }

  /// Get usage counts for a job code
  Future<Map<String, int>> getUsageCounts(String code) async {
    return await _dao.getUsageCounts(code);
  }

  /// Get available job codes for reassignment (excluding specified code)
  List<JobCodeSettings> getAvailableForReassignment(String excludeCode) {
    return _codes
        .where((c) => c.code.toLowerCase() != excludeCode.toLowerCase())
        .toList();
  }

  /// Create a new job code group
  Future<bool> createGroup({
    required String name,
    required String colorHex,
  }) async {
    try {
      final newGroup = JobCodeGroup(
        name: name,
        colorHex: colorHex,
      );

      await _groupDao.insert(newGroup);
      await loadData(); // Reload to get updated data
      return true;
    } catch (e) {
      setErrorMessage('Failed to create group: $e');
      return false;
    }
  }

  /// Update an existing job code group
  Future<bool> updateGroup(JobCodeGroup group) async {
    try {
      await _groupDao.update(group);
      await loadData(); // Reload to get updated data
      return true;
    } catch (e) {
      setErrorMessage('Failed to update group: $e');
      return false;
    }
  }

  /// Delete a job code group by name
  Future<bool> deleteGroup(String groupName) async {
    try {
      // Check if any job codes are using this group
      final codesInGroup = _codes.where((c) => c.sortGroup == groupName).length;
      if (codesInGroup > 0) {
        setErrorMessage('Cannot delete group: $codesInGroup job codes are still assigned to it');
        return false;
      }

      await _groupDao.delete(groupName);
      await loadData(); // Reload to get updated data
      return true;
    } catch (e) {
      setErrorMessage('Failed to delete group: $e');
      return false;
    }
  }

  /// Get group name by name (for compatibility)
  String? getGroupName(String? groupName) {
    if (groupName == null) return null;
    return _groups.firstWhere((g) => g.name == groupName, orElse: () => JobCodeGroup(name: 'Unknown', colorHex: '#FF0000')).name;
  }

  /// Add a job code (alias for createJobCode)
  Future<bool> addJobCode({
    required String code,
    required String colorHex,
    required bool hasPTO,
    String? sortGroup,
  }) async {
    return await createJobCode(
      code: code,
      colorHex: colorHex,
      hasPTO: hasPTO,
      sortGroup: sortGroup,
    );
  }

  /// Add a group (alias for createGroup)
  Future<bool> addGroup({
    required String name,
    required String colorHex,
  }) async {
    return await createGroup(
      name: name,
      colorHex: colorHex,
    );
  }

  /// Reorder a job code item (update local order, mark dirty)
  void reorderJobCode(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    final item = _codes.removeAt(oldIndex);
    _codes.insert(newIndex, item);
    _orderDirty = true;
    notifyListeners();
  }

  /// Save the current order to database
  Future<bool> saveOrder() async {
    if (!_orderDirty) return true;
    
    try {
      // Update sort orders for all codes based on current positions
      final reorderedCodes = <JobCodeSettings>[];
      for (int i = 0; i < _codes.length; i++) {
        reorderedCodes.add(_codes[i].copyWith(sortOrder: i));
      }
      
      await _dao.updateSortOrders(reorderedCodes);
      await loadData(); // Reload to get fresh data
      _orderDirty = false;
      return true;
    } catch (e) {
      setErrorMessage('Failed to save order: $e');
      return false;
    }
  }

  /// Delete job code with dialog confirmation
  /// This is a wrapper that the tab can use - actual dialog shown by tab
  Future<bool> deleteJobCodeWithDialog(JobCodeSettings jobCode, {String? reassignTo}) async {
    return await deleteJobCode(jobCode, reassignmentCode: reassignTo);
  }

  @override
  Future<void> refresh() async {
    await loadData();
  }
}