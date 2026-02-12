import 'package:flutter/material.dart';
import '../../services/settings_sync_service.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/auto_sync_service.dart';
import '../../services/auth_service.dart';
import '../../database/settings_dao.dart';

class CloudSyncTab extends StatefulWidget {
  const CloudSyncTab({super.key});

  @override
  State<CloudSyncTab> createState() => _CloudSyncTabState();
}

class _CloudSyncTabState extends State<CloudSyncTab> {
  final SettingsSyncService _settingsSyncService = SettingsSyncService.instance;
  final FirestoreSyncService _dataSyncService = FirestoreSyncService.instance;
  final AutoSyncService _autoSyncService = AutoSyncService.instance;
  final SettingsDao _settingsDao = SettingsDao();
  bool _isLoading = false;
  bool _hasCloudSettings = false;
  bool _hasCloudData = false;
  bool _autoSyncEnabled = false;
  DateTime? _lastCloudUpdate;
  String? _statusMessage;
  bool _isSuccess = true;

  @override
  void initState() {
    super.initState();
    _checkCloudStatus();
    _loadAutoSyncSetting();
  }

  Future<void> _loadAutoSyncSetting() async {
    final settings = await _settingsDao.getSettings();
    setState(() {
      _autoSyncEnabled = settings.autoSyncEnabled;
    });
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    setState(() => _isLoading = true);
    try {
      await _autoSyncService.setAutoSyncEnabled(enabled);
      setState(() {
        _autoSyncEnabled = enabled;
        _isLoading = false;
        _statusMessage = enabled
            ? 'Auto-sync enabled! Changes will sync automatically.'
            : 'Auto-sync disabled. Use manual sync buttons below.';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error changing auto-sync setting: $e';
        _isSuccess = false;
      });
    }
  }

  Future<void> _checkCloudStatus() async {
    setState(() => _isLoading = true);

    try {
      final hasSettings = await _settingsSyncService.hasCloudSettings();
      final lastUpdate = await _settingsSyncService
          .getCloudSettingsLastUpdated();
      final hasData = await _dataSyncService.hasCloudData();

      setState(() {
        _hasCloudSettings = hasSettings;
        _hasCloudData = hasData;
        _lastCloudUpdate = lastUpdate;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error checking cloud status: $e';
        _isSuccess = false;
      });
    }
  }

  Future<void> _uploadToCloud() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      // Upload both settings and data
      await _settingsSyncService.uploadAllSettings();
      await _dataSyncService.uploadAllDataToCloud();
      await _checkCloudStatus();
      setState(() {
        _statusMessage =
            'All settings and data uploaded to cloud successfully!';
        _isSuccess = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error uploading to cloud: $e';
        _isSuccess = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadFromCloud() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download from Cloud?'),
        content: const Text(
          'This will overwrite your local settings and data with the cloud backup. '
          'Any local changes that haven\'t been uploaded will be lost.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      // Download both settings and data
      final settingsResult = await _settingsSyncService.downloadAllSettings();
      await _dataSyncService.downloadAllDataFromCloud();
      setState(() {
        _statusMessage = settingsResult.success
            ? 'All settings and data downloaded from cloud successfully!'
            : 'Downloaded data, but settings had issues: ${settingsResult.message}';
        _isSuccess = settingsResult.success;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error downloading from cloud: $e';
        _isSuccess = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final email = AuthService.instance.currentUserEmail;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud, color: colorScheme.primary, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Cloud Sync',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sync your settings to the cloud so you can access them from any computer.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Signed in as: $email',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  if (_lastCloudUpdate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Last cloud update: ${_formatDateTime(_lastCloudUpdate!)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Auto-sync toggle card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _autoSyncEnabled ? Icons.sync : Icons.sync_disabled,
                        color: _autoSyncEnabled
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Automatic Sync',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _autoSyncEnabled
                                  ? 'Changes sync automatically when online'
                                  : 'Manual sync only',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoSyncEnabled,
                        onChanged: _isLoading ? null : _toggleAutoSync,
                      ),
                    ],
                  ),
                  if (_autoSyncEnabled) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _autoSyncService.isOnline
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            size: 20,
                            color: _autoSyncService.isOnline
                                ? colorScheme.primary
                                : colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _autoSyncService.isOnline
                                  ? 'Online - syncing automatically'
                                  : 'Offline - changes will sync when back online'
                                        '${_autoSyncService.pendingTaskCount > 0 ? ' (${_autoSyncService.pendingTaskCount} pending)' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status message
          if (_statusMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isSuccess ? Icons.check_circle : Icons.error,
                    color: _isSuccess
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isSuccess
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Cloud Sync card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cloud Sync',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sync your settings, employee roster, and time-off entries to the cloud.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Upload button
                  ListTile(
                    leading: const Icon(Icons.cloud_upload),
                    title: const Text('Upload to Cloud'),
                    subtitle: const Text(
                      'Backup all settings and data to the cloud',
                    ),
                    trailing: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _isLoading ? null : _uploadToCloud,
                  ),
                  const Divider(),

                  // Download button
                  ListTile(
                    leading: const Icon(Icons.cloud_download),
                    title: const Text('Download from Cloud'),
                    subtitle: Text(
                      (_hasCloudSettings || _hasCloudData)
                          ? 'Restore all settings and data from the cloud'
                          : 'No cloud backup found - upload first',
                    ),
                    trailing: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled:
                        (_hasCloudSettings || _hasCloudData) && !_isLoading,
                    onTap: (_hasCloudSettings || _hasCloudData) && !_isLoading
                        ? _downloadFromCloud
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // What gets synced card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What Gets Synced',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSyncItem(
                    context,
                    icon: Icons.schedule,
                    title: 'PTO & Schedule Rules',
                    description:
                        'Hours per trimester, vacation days, schedule start day, etc.',
                  ),
                  _buildSyncItem(
                    context,
                    icon: Icons.store,
                    title: 'Store Settings',
                    description:
                        'Store name, NSN, and operating hours for each day.',
                  ),
                  _buildSyncItem(
                    context,
                    icon: Icons.palette,
                    title: 'Shift Types & Colors',
                    description:
                        'Open, Lunch, Dinner, Close configurations and colors.',
                  ),
                  _buildSyncItem(
                    context,
                    icon: Icons.badge,
                    title: 'Job Codes & Groups',
                    description:
                        'Job code settings, groups, PTO eligibility and max hours.',
                  ),
                  _buildSyncItem(
                    context,
                    icon: Icons.people,
                    title: 'Employee Roster',
                    description:
                        'Your employees and their job codes, emails, and vacation allowances.',
                  ),
                  _buildSyncItem(
                    context,
                    icon: Icons.beach_access,
                    title: 'Time Off Entries',
                    description: 'PTO, requested days, and other time-off records.',
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Schedules are stored locally and shared with employees '
                    'when you publish them from the schedule view.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Note about per-manager data
          Card(
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Note',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Each manager account has their own separate roster, schedules, and time-off data. '
                    'Data is not shared between manager accounts. Use the sync buttons above to backup '
                    'your data to the cloud and restore it on another computer.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} hours ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${dt.month}/${dt.day}/${dt.year}';
    }
  }
}
