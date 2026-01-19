import 'package:flutter/material.dart';
import 'pages/schedule_page.dart';
import 'pages/time_off_page.dart';
import 'pages/roster_page.dart';
import 'package:work_schedule_app/pages/settings_page.dart';
import 'pages/pto_vac_tracker_page.dart';
import 'pages/analytics_page.dart';
import 'services/update_service.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _index = 0;
  bool _updateAvailable = false;
  bool _checkingUpdate = false;

  final List<Widget> _pages = const [
    SchedulePage(),
    TimeOffPage(),
    RosterPage(),
    PtoVacTrackerPage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  final List<String> _titles = const [
    "Schedule",
    "Time Off",
    "Roster",
    "PTO / VAC Tracker",
    "Analytics",
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates({bool showDialogIfAvailable = false}) async {
    setState(() => _checkingUpdate = true);
    final hasUpdate = await UpdateService.checkForUpdates();
    if (mounted) {
      setState(() {
        _updateAvailable = hasUpdate;
        _checkingUpdate = false;
      });
      if (showDialogIfAvailable) {
        if (hasUpdate) {
          _showUpdateDialog();
        } else {
          // Show snackbar that app is up to date
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You\'re up to date! (v${UpdateService.currentVersion})'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => _UpdateDialog(
        currentVersion: UpdateService.currentVersion,
        latestVersion: UpdateService.latestVersion ?? 'Unknown',
        releaseNotes: UpdateService.releaseNotes ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.calendar_month),
                        label: Text("Schedule"),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.beach_access),
                        label: Text("Time Off"),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.people),
                        label: Text("Roster"),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.track_changes),
                        label: Text("PTO / VAC"),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.analytics),
                        label: Text("Analytics"),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text("Settings"),
                      ),
                    ],
                  ),
                ),
                // Update button at the bottom of navigation rail
                _buildUpdateButton(),
              ],
            ),

          Expanded(
            child: _pages[_index],
          ),
        ],
      ),

      bottomNavigationBar: isWide
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Update button above bottom navigation
                if (_updateAvailable || _checkingUpdate)
                  _buildUpdateButtonHorizontal(),
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month),
                      label: "Schedule",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.beach_access),
                      label: "Time Off",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people),
                      label: "Roster",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.track_changes),
                      label: "PTO / VAC",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.analytics),
                      label: "Analytics",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings),
                      label: "Settings",
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildUpdateButton() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          if (_checkingUpdate)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_updateAvailable)
            Tooltip(
              message: 'Update available: v${UpdateService.latestVersion}',
              child: ElevatedButton.icon(
                onPressed: _showUpdateDialog,
                icon: const Icon(Icons.system_update, size: 18),
                label: const Text('Update'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: () => _checkForUpdates(showDialogIfAvailable: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'v${UpdateService.currentVersion}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpdateButtonHorizontal() {
    if (_checkingUpdate) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    
    if (_updateAvailable) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.green.shade50,
        child: ElevatedButton.icon(
          onPressed: _showUpdateDialog,
          icon: const Icon(Icons.system_update),
          label: Text('Update available: v${UpdateService.latestVersion}'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
}

/// Dialog for showing update information and downloading
class _UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;

  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String _status = '';
  String? _error;

  void _startDownload() {
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Preparing download...';
      _error = null;
    });

    UpdateService.downloadUpdate(
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
      onStatus: (status) {
        if (mounted) {
          setState(() => _status = status);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error;
            _downloading = false;
          });
        }
      },
      onComplete: () {
        if (mounted) {
          setState(() {
            _downloading = false;
            _status = 'Download complete! Check your Downloads folder.';
          });
          // Show instructions
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Update downloaded! Close the app, extract the zip, and replace the old files.',
              ),
              duration: Duration(seconds: 8),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: Colors.green.shade600),
          const SizedBox(width: 8),
          const Text('Update Available'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Current', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('v${widget.currentVersion}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  Column(
                    children: [
                      const Text('New', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        'v${widget.latestVersion}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Release notes
            if (widget.releaseNotes.isNotEmpty) ...[
              const Text('What\'s New:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.releaseNotes,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Progress indicator
            if (_downloading) ...[
              Text(_status, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            
            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            
            // Success message
            if (!_downloading && _status.contains('complete'))
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                        const SizedBox(width: 8),
                        const Text('Download complete!', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'To install:\n'
                      '1. Close this application\n'
                      '2. Extract the downloaded zip file\n'
                      '3. Replace the old app folder with the new files\n'
                      '4. Launch the app again',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => UpdateService.openReleasesPage(),
          child: const Text('View on GitHub'),
        ),
        if (!_downloading && !_status.contains('complete'))
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        if (!_downloading && !_status.contains('complete'))
          ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        if (_status.contains('complete'))
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}
