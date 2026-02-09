import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/schedule_page.dart';
import 'pages/roster_page.dart';
import 'package:schedulehq_desktop/pages/settings_page.dart';
import 'pages/pto_vac_tracker_page.dart';
import 'pages/analytics_page.dart';
import 'pages/approval_queue_page.dart';
import 'pages/pnl_page.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'services/app_colors.dart';
import 'services/store_update_service.dart';
import 'utils/snackbar_helper.dart';
import 'utils/dialog_helper.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _index = 0;
  bool _updateAvailable = false;
  bool _checkingUpdate = false;

  // Use ValueKey to force rebuild when switching tabs
  final List<Widget Function()> _pageBuilders = [
    () => const SchedulePage(),
    () => const RosterPage(),
    () => const PtoVacTrackerPage(),
    () => const ApprovalQueuePage(),
    () => const AnalyticsPage(),
    () => const PnlPage(),
    () => const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates({bool showDialogIfAvailable = false}) async {
    setState(() => _checkingUpdate = true);
    try {
      final hasUpdate = await StoreUpdateService.checkForUpdates();
      if (mounted) {
        setState(() {
          _updateAvailable = hasUpdate;
          _checkingUpdate = false;
        });
        if (showDialogIfAvailable) {
          if (hasUpdate) {
            _showUpdateDialog();
          } else {
            // Show snackbar with status
            final error = StoreUpdateService.lastError;

            if (error != null) {
              // API failed - offer to open Store
              SnackBarHelper.showError(
                context,
                'Could not check for updates. Open Microsoft Store?',
                duration: const Duration(seconds: 6),
              );
              // TODO: Add action button to open store
            } else {
              SnackBarHelper.showSuccess(
                context,
                'You\'re up to date! (v${StoreUpdateService.currentVersion})',
                duration: const Duration(seconds: 2),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingUpdate = false);
        if (showDialogIfAvailable) {
          SnackBarHelper.showError(
            context,
            'Error checking for updates: $e',
            duration: const Duration(seconds: 4),
          );
        }
      }
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          _StoreUpdateDialog(currentVersion: StoreUpdateService.currentVersion),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            SizedBox(
              width: 220,
              child: Column(
                children: [
                  // User info section at the top
                  Consumer<app_auth.AuthProvider>(
                    builder: (context, authProvider, child) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              authProvider.userDisplayName ?? 'Manager',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (authProvider.userEmail != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                authProvider.userEmail!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.appColors.textSecondary,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 200,
                            child: NavigationRail(
                              selectedIndex: _index,
                              onDestinationSelected: (i) =>
                                  setState(() => _index = i),
                              labelType: NavigationRailLabelType.all,
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.calendar_month),
                                  label: Text("Schedule"),
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
                                  icon: Icon(Icons.approval),
                                  label: Text("Time Off"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.analytics),
                                  label: Text("Analytics"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.account_balance),
                                  label: Text("P&L"),
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
                          // Logout button
                          _buildLogoutButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(child: _pageBuilders[_index]()),
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
                      icon: Icon(Icons.people),
                      label: "Roster",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.track_changes),
                      label: "PTO / VAC",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.approval),
                      label: "Time Off",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.analytics),
                      label: "Analytics",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_balance),
                      label: "P&L",
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

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Consumer<app_auth.AuthProvider>(
        builder: (context, authProvider, child) {
          return TextButton.icon(
            onPressed: authProvider.isLoading
                ? null
                : () async {
                    final confirmed = await DialogHelper.showConfirmDialog(
                      context,
                      title: 'Sign Out',
                      message: 'Are you sure you want to sign out?',
                      confirmText: 'Sign Out',
                      cancelText: 'Cancel',
                      icon: Icons.logout,
                    );

                    if (confirmed) {
                      final success = await authProvider.signOut();
                      if (!success && mounted) {
                        SnackBarHelper.showError(
                          context,
                          'Failed to sign out. Please try again.',
                        );
                      }
                    }
                  },
            icon: authProvider.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: Text(authProvider.isLoading ? 'Signing out...' : 'Sign Out'),
          );
        },
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
              message: 'Update available in Microsoft Store',
              child: Builder(
                builder: (context) {
                  final appColors = context.appColors;
                  return ElevatedButton.icon(
                    onPressed: _showUpdateDialog,
                    icon: const Icon(Icons.system_update, size: 18),
                    label: const Text('Update'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appColors.successForeground,
                      foregroundColor: appColors.textOnSuccess,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  );
                },
              ),
            )
          else
            TextButton.icon(
              onPressed: () => _checkForUpdates(showDialogIfAvailable: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'v${StoreUpdateService.currentVersion}',
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
      final appColors = context.appColors;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: appColors.successBackground,
        child: ElevatedButton.icon(
          onPressed: _showUpdateDialog,
          icon: const Icon(Icons.system_update),
          label: const Text('Update available in Store'),
          style: ElevatedButton.styleFrom(
            backgroundColor: appColors.successForeground,
            foregroundColor: appColors.textOnSuccess,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Dialog for showing Microsoft Store update information
class _StoreUpdateDialog extends StatelessWidget {
  final String currentVersion;

  const _StoreUpdateDialog({required this.currentVersion});

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: appColors.successIcon),
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
            // Current version info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: appColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current version: v$currentVersion',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A new version is available in the Microsoft Store.',
                          style: TextStyle(
                            fontSize: 13,
                            color: appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appColors.successBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/icons/microsoft_store.png',
                        width: 24,
                        height: 24,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.store,
                          color: appColors.successIcon,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Update from Microsoft Store',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Click "Open Store" to view and install the latest update. '
                    'The Microsoft Store will handle the download and installation automatically.',
                    style: TextStyle(
                      fontSize: 13,
                      color: appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            StoreUpdateService.openStorePage();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.store),
          label: const Text('Open Store'),
          style: ElevatedButton.styleFrom(
            backgroundColor: appColors.successForeground,
            foregroundColor: appColors.textOnSuccess,
          ),
        ),
      ],
    );
  }
}
