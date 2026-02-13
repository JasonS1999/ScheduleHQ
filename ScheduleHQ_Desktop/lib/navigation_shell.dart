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
import 'utils/app_constants.dart';
import 'utils/snackbar_helper.dart';
import 'utils/dialog_helper.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell>
    with TickerProviderStateMixin {
  int _index = 0;
  bool _updateAvailable = false;
  bool _checkingUpdate = false;

  late final AnimationController _sidebarController;
  late final Animation<double> _sidebarFade;
  late final Animation<Offset> _sidebarSlide;

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
    _sidebarController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _sidebarFade = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOut,
    );
    _sidebarSlide = Tween<Offset>(
      begin: const Offset(-0.05, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOut,
    ));
    _sidebarController.forward();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
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
    final isDark = context.isDarkMode;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            FadeTransition(
              opacity: _sidebarFade,
              child: SlideTransition(
                position: _sidebarSlide,
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: context.appColors.surfaceVariant,
                    border: isDark
                        ? Border(
                            right: BorderSide(
                              color: context.appColors.borderLight,
                            ),
                          )
                        : null,
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(2, 0),
                            ),
                          ],
                  ),
                  child: Column(
                    children: [
                      // User info section with avatar
                      _buildUserInfoSection(),
                      // Padded divider
                      _buildInternalDivider(),
                      // Navigation rail
                      Expanded(
                        child: NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: (i) =>
                              setState(() => _index = i),
                          labelType: NavigationRailLabelType.all,
                          backgroundColor: Colors.transparent,
                          indicatorColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          indicatorShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusLarge,
                            ),
                          ),
                          selectedIconTheme: IconThemeData(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            size: 22,
                          ),
                          unselectedIconTheme: IconThemeData(
                            color: context.appColors.textSecondary,
                            size: 22,
                          ),
                          selectedLabelStyle: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                                letterSpacing: 0.3,
                              ),
                          unselectedLabelStyle: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: context.appColors.textSecondary,
                                letterSpacing: 0.2,
                              ),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.calendar_month_outlined),
                              selectedIcon: Icon(Icons.calendar_month),
                              label: Text("Schedule"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.people_outlined),
                              selectedIcon: Icon(Icons.people),
                              label: Text("Roster"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.beach_access_outlined),
                              selectedIcon: Icon(Icons.beach_access),
                              label: Text("PTO / VAC"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.pending_actions_outlined),
                              selectedIcon: Icon(Icons.pending_actions),
                              label: Text("Time Off"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.analytics_outlined),
                              selectedIcon: Icon(Icons.analytics),
                              label: Text("Analytics"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.account_balance_outlined),
                              selectedIcon: Icon(Icons.account_balance),
                              label: Text("P&L"),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.settings_outlined),
                              selectedIcon: Icon(Icons.settings),
                              label: Text("Settings"),
                            ),
                          ],
                        ),
                      ),
                      // Bottom section
                      _buildInternalDivider(),
                      _buildUpdateButton(),
                      _buildLogoutButton(),
                    ],
                  ),
                ),
              ),
            ),

          // Content area with page transition
          Expanded(
            child: AnimatedSwitcher(
              duration: AppConstants.shortAnimation,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_index),
                child: _pageBuilders[_index](),
              ),
            ),
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
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: "Schedule",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outlined),
                      selectedIcon: Icon(Icons.people),
                      label: "Roster",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.beach_access_outlined),
                      selectedIcon: Icon(Icons.beach_access),
                      label: "PTO / VAC",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.pending_actions_outlined),
                      selectedIcon: Icon(Icons.pending_actions),
                      label: "Time Off",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: "Analytics",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_balance_outlined),
                      selectedIcon: Icon(Icons.account_balance),
                      label: "P&L",
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: "Settings",
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildUserInfoSection() {
    return Consumer<app_auth.AuthProvider>(
      builder: (context, authProvider, child) {
        final displayName = authProvider.userDisplayName ?? 'Manager';
        final parts = displayName.trim().split(' ');
        final initials = parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : displayName
                .substring(0, displayName.length.clamp(0, 2))
                .toUpperCase();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.appColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (authProvider.userEmail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        authProvider.userEmail!,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.appColors.textTertiary,
                                  fontSize: 11,
                                  letterSpacing: 0.1,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInternalDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.defaultPadding,
      ),
      child: Divider(
        height: 1,
        color: context.appColors.borderLight,
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.defaultPadding,
        0,
        AppConstants.defaultPadding,
        AppConstants.defaultPadding,
      ),
      child: Consumer<app_auth.AuthProvider>(
        builder: (context, authProvider, child) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
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
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: context.appColors.textSecondary,
                    ),
              label: Text(
                authProvider.isLoading ? 'Signing out...' : 'Sign Out',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appColors.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                side: BorderSide(color: context.appColors.borderLight),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUpdateButton() {
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.defaultPadding,
        vertical: AppConstants.smallPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_checkingUpdate)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_updateAvailable)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _showUpdateDialog,
                icon: const Icon(Icons.system_update, size: 16),
                label: const Text('Update Available'),
                style: FilledButton.styleFrom(
                  backgroundColor: appColors.successForeground,
                  foregroundColor: appColors.textOnSuccess,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMedium),
                  ),
                ),
              ),
            )
          else
            InkWell(
              onTap: () => _checkForUpdates(showDialogIfAvailable: true),
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: appColors.surfaceContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 14,
                      color: appColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'v${StoreUpdateService.currentVersion}',
                      style: TextStyle(
                        fontSize: 11,
                        color: appColors.textTertiary,
                        letterSpacing: 0.3,
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
        child: FilledButton.icon(
          onPressed: _showUpdateDialog,
          icon: const Icon(Icons.system_update),
          label: const Text('Update available in Store'),
          style: FilledButton.styleFrom(
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
