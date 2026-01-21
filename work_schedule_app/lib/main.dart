import 'package:flutter/material.dart';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database/app_database.dart';
import 'navigation_shell.dart';
import 'services/app_colors.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize the database BEFORE the UI loads
  await AppDatabase.instance.init();

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
          home: const NavigationShell(),
        );
      },
    );
  }
}
