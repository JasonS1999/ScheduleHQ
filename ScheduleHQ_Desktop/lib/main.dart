import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database/app_database.dart';
import 'database/shift_runner_dao.dart';
import 'firebase_options.dart';
import 'navigation_shell.dart';
import 'pages/login_page.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/employee_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/time_off_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/approval_provider.dart';
import 'providers/job_code_provider.dart';
import 'providers/store_settings_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/notification_provider.dart';
import 'services/app_colors.dart';
import 'services/auto_sync_service.dart';
import 'services/firestore_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize SQLite FFI for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Note: Database is now initialized per-manager in AuthWrapper after login
  // This ensures each manager gets their own database file

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Authentication provider - must be first
        ChangeNotifierProvider<app_auth.AuthProvider>(
          create: (_) => app_auth.AuthProvider(),
        ),

        // Settings provider - depends on database initialization
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),

        // Employee provider
        ChangeNotifierProvider<EmployeeProvider>(
          create: (_) => EmployeeProvider(),
        ),

        // Schedule provider
        ChangeNotifierProvider<ScheduleProvider>(
          create: (_) => ScheduleProvider(),
        ),

        // Time Off provider
        ChangeNotifierProvider<TimeOffProvider>(
          create: (_) => TimeOffProvider(),
        ),

        // Analytics provider
        ChangeNotifierProvider<AnalyticsProvider>(
          create: (_) => AnalyticsProvider(),
        ),

        // Approval provider
        ChangeNotifierProvider<ApprovalProvider>(
          create: (_) => ApprovalProvider(),
        ),

        // Job Code provider
        ChangeNotifierProvider<JobCodeProvider>(
          create: (_) => JobCodeProvider(),
        ),

        // Store Settings provider
        ChangeNotifierProvider<StoreSettingsProvider>(
          create: (_) => StoreSettingsProvider(),
        ),

        // Onboarding provider
        ChangeNotifierProvider<OnboardingProvider>(
          create: (_) => OnboardingProvider(),
        ),

        // Notification provider
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
      ],
      child: Selector<SettingsProvider, String>(
        selector: (_, settings) => settings.themeMode,
        builder: (context, themeModeStr, child) {
          // Determine theme mode from settings provider
          ThemeMode themeMode;
          switch (themeModeStr) {
            case 'light':
              themeMode = ThemeMode.light;
              break;
            case 'dark':
              themeMode = ThemeMode.dark;
              break;
            case 'system':
            default:
              themeMode = ThemeMode.system;
              break;
          }

          // Shared component theme overrides
          final cardThemeLight = CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );
          final cardThemeDark = CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF3D3D3D)),
            ),
          );
          const inputBorderRadius = BorderRadius.all(Radius.circular(8));
          final inputTheme = InputDecorationTheme(
            border: const OutlineInputBorder(borderRadius: inputBorderRadius),
            enabledBorder: OutlineInputBorder(
              borderRadius: inputBorderRadius,
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: inputBorderRadius,
              borderSide: const BorderSide(width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            isDense: true,
          );
          final buttonShape = WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );
          final buttonPadding = const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          );
          final dialogTheme = DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          );
          const dividerTheme = DividerThemeData(thickness: 1);
          const snackBarTheme = SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            width: 400,
          );

          return MaterialApp(
            title: 'ScheduleHQ',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorSchemeSeed: Colors.blue,
              brightness: Brightness.light,
              useMaterial3: true,
              extensions: const [AppColors.light],
              cardTheme: cardThemeLight,
              inputDecorationTheme: inputTheme,
              filledButtonTheme: FilledButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              dialogTheme: dialogTheme,
              dividerTheme: dividerTheme,
              snackBarTheme: snackBarTheme,
              appBarTheme: const AppBarTheme(
                centerTitle: false,
                scrolledUnderElevation: 1,
              ),
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.blue,
              brightness: Brightness.dark,
              useMaterial3: true,
              extensions: const [AppColors.dark],
              cardTheme: cardThemeDark,
              inputDecorationTheme: inputTheme,
              filledButtonTheme: FilledButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
              ),
              dialogTheme: dialogTheme,
              dividerTheme: dividerTheme,
              snackBarTheme: snackBarTheme,
              appBarTheme: const AppBarTheme(
                centerTitle: false,
                scrolledUnderElevation: 1,
              ),
            ),
            themeMode: themeMode,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

/// Wrapper that handles authentication state
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _dbInitialized = false;
  String? _currentUid;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    // Initialize auto-sync service (it will check if enabled in settings)
    AutoSyncService.instance.initialize();
    // Defer auth initialization to avoid notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<app_auth.AuthProvider>(context, listen: false).initialize();
    });
  }

  Future<void> _initDatabaseAndProviders(String uid) async {
    if (_currentUid != uid) {
      _dbInitialized = false;
      _currentUid = uid;
      // Stop previous listener when switching accounts
      FirestoreSyncService.instance.stopTimeOffListener();
      if (mounted) {
        Provider.of<NotificationProvider>(context, listen: false).stopPolling();
      }
    }
    if (!_dbInitialized) {
      await AppDatabase.instance.initForManager(uid);

      // One-time fix: populate employeeId for existing shift runners
      try {
        final updated = await ShiftRunnerDao().populateMissingEmployeeIds();
        if (updated > 0) {
          log(
            'Populated employeeId for $updated existing shift runners',
            name: 'Main',
          );
        }
      } catch (e) {
        log('Error populating shift runner employeeIds: $e', name: 'Main');
      }

      // Initialize providers that depend on database
      if (mounted) {
        final settingsProvider = Provider.of<SettingsProvider>(
          context,
          listen: false,
        );
        final employeeProvider = Provider.of<EmployeeProvider>(
          context,
          listen: false,
        );
        final scheduleProvider = Provider.of<ScheduleProvider>(
          context,
          listen: false,
        );
        final jobCodeProvider = Provider.of<JobCodeProvider>(
          context,
          listen: false,
        );

        await settingsProvider.initialize();
        await employeeProvider.initialize();
        await scheduleProvider.initialize();
        await jobCodeProvider.initialize();

        // Initialize onboarding state
        final onboardingProvider = Provider.of<OnboardingProvider>(
          context,
          listen: false,
        );
        await onboardingProvider.initialize();

        // Initialize and start notification polling
        final notificationProvider = Provider.of<NotificationProvider>(
          context,
          listen: false,
        );
        await notificationProvider.initialize();
        notificationProvider.startPolling();

        // Sync profile image URLs from Firestore in the background (non-blocking)
        FirestoreSyncService.instance.syncEmployeeUidsFromFirestore().then((_) {
          if (mounted) {
            employeeProvider.loadEmployees();
          }
        }).catchError((e) {
          debugPrint('Background profile image sync failed: $e');
        });

        // Start real-time cloud listener for time-off entries
        final timeOffProvider = Provider.of<TimeOffProvider>(
          context,
          listen: false,
        );
        FirestoreSyncService.instance.startTimeOffListener(() {
          if (mounted) {
            timeOffProvider.loadData();
          }
        });
      }

      _dbInitialized = true;
    }
  }

  @override
  void dispose() {
    FirestoreSyncService.instance.stopTimeOffListener();
    Provider.of<NotificationProvider>(context, listen: false).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<app_auth.AuthProvider>(
      builder: (context, authProvider, child) {
        // Show loading while checking auth state
        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is signed in, initialize their database and show main app
        if (authProvider.isSignedIn) {
          final user = authProvider.currentUser!;
          // Cache future so FutureBuilder doesn't restart on every Consumer rebuild
          if (_currentUid != user.uid || _initFuture == null) {
            _initFuture = _initDatabaseAndProviders(user.uid);
          }
          return FutureBuilder(
            future: _initFuture,
            builder: (context, dbSnapshot) {
              if (dbSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading your data...'),
                      ],
                    ),
                  ),
                );
              }

              // Show any initialization errors
              if (dbSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Failed to initialize app'),
                        const SizedBox(height: 8),
                        Text(dbSnapshot.error.toString()),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _dbInitialized = false;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return const NavigationShell();
            },
          );
        }

        // Otherwise show login - pass any auth errors to login page
        return LoginPage(
          onLoginSuccess: () {
            // Provider will automatically rebuild when auth state changes
          },
        );
      },
    );
  }
}
