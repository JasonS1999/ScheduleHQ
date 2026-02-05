import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database/app_database.dart';
import 'database/shift_runner_dao.dart';
import 'firebase_options.dart';
import 'navigation_shell.dart';
import 'pages/login_page.dart';
import 'services/app_colors.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/auto_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Workforce Manager',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.light,
            useMaterial3: true,
            extensions: const [AppColors.light],
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
            useMaterial3: true,
            extensions: const [AppColors.dark],
          ),
          themeMode: mode,
          home: const AuthWrapper(),
        );
      },
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

  @override
  void initState() {
    super.initState();
    // Initialize auto-sync service (it will check if enabled in settings)
    AutoSyncService.instance.initialize();
  }

  Future<void> _initDatabaseForUser(String uid) async {
    if (_currentUid != uid) {
      _dbInitialized = false;
      _currentUid = uid;
    }
    if (!_dbInitialized) {
      await AppDatabase.instance.initForManager(uid);
      
      // One-time fix: populate employeeId for existing shift runners
      try {
        final updated = await ShiftRunnerDao().populateMissingEmployeeIds();
        if (updated > 0) {
          log('Populated employeeId for $updated existing shift runners', name: 'Main');
        }
      } catch (e) {
        log('Error populating shift runner employeeIds: $e', name: 'Main');
      }
      
      _dbInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is signed in, initialize their database and show main app
        if (snapshot.hasData) {
          final user = snapshot.data!;
          return FutureBuilder(
            future: _initDatabaseForUser(user.uid),
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
              return const NavigationShell();
            },
          );
        }

        // Otherwise show login
        return LoginPage(
          onLoginSuccess: () {
            // StreamBuilder will automatically rebuild when auth state changes
          },
        );
      },
    );
  }
}
