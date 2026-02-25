/// Application-wide constants for ScheduleHQ Desktop
class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();

  // App Information
  static const String appName = 'ScheduleHQ';
  static const String appVersion = '1.0.0';

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Border Radius
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;

  /// @deprecated Use radiusMedium instead
  static const double borderRadius = radiusMedium;

  static const double cardElevation = 2.0;

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // Default Loading/Error Messages
  static const String defaultLoadingMessage = 'Loading...';
  static const String defaultErrorMessage =
      'An error occurred. Please try again.';
  static const String networkErrorMessage =
      'Network error. Please check your connection and try again.';
  static const String databaseErrorMessage =
      'Database error. Please try again.';

  // Success Messages
  static const String saveSuccessMessage = 'Changes saved successfully';
  static const String deleteSuccessMessage = 'Item deleted successfully';
  static const String createSuccessMessage = 'Item created successfully';
  static const String updateSuccessMessage = 'Item updated successfully';

  // Confirmation Messages
  static const String deleteConfirmTitle = 'Confirm Delete';
  static const String unsavedChangesTitle = 'Unsaved Changes';
  static const String unsavedChangesMessage =
      'You have unsaved changes. Are you sure you want to leave?';

  // Employee Related Constants
  static const String defaultJobCode = 'Assistant';
  static const List<String> defaultJobCodes = [
    'Assistant',
    'Supervisor',
    'Manager',
    'Store Manager',
  ];

  // Schedule Related Constants
  static const int defaultScheduleWeeksToShow = 4;
  static const int maxScheduleWeeksToShow = 12;
  static const String defaultShiftStartTime = '09:00';
  static const String defaultShiftEndTime = '17:00';
  static const int defaultShiftLengthHours = 8;

  // Time Format Constants
  static const String timeFormat24Hour = 'HH:mm';
  static const String timeFormat12Hour = 'hh:mm a';
  static const String dateFormat = 'yyyy-MM-dd';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm';
  static const String displayDateFormat = 'MMM dd, yyyy';
  static const String dayOfWeekFormat = 'EEEE';

  // Database Constants
  static const String databaseName = 'schedule_database.db';
  static const int databaseVersion = 1;

  // Sync Constants
  static const Duration syncInterval = Duration(minutes: 30);
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int maxSyncRetries = 3;

  // File/Export Constants
  static const String csvFileExtension = '.csv';
  static const String pdfFileExtension = '.pdf';
  static const String excelFileExtension = '.xlsx';

  // Navigation Routes (if using named routes)
  static const String homeRoute = '/';
  static const String scheduleRoute = '/schedule';
  static const String rosterRoute = '/roster';
  static const String analyticsRoute = '/analytics';
  static const String settingsRoute = '/settings';
  static const String ptoRoute = '/pto';

  // Theme Constants
  static const String lightThemeKey = 'light';
  static const String darkThemeKey = 'dark';
  static const String systemThemeKey = 'system';

  // Local Storage Keys
  static const String themePreferenceKey = 'theme_preference';
  static const String userPreferencesKey = 'user_preferences';
  static const String lastSyncTimeKey = 'last_sync_time';
  static const String autoSyncEnabledKey = 'auto_sync_enabled';

  // Onboarding Keys
  static const String onboardingWelcomeCompletedKey = 'onboarding_welcome_completed';
  static const String onboardingSettingsCoachCompletedKey = 'onboarding_settings_coach_completed';
  static const String onboardingRosterCoachCompletedKey = 'onboarding_roster_coach_completed';
  static const String onboardingScheduleCoachCompletedKey = 'onboarding_schedule_coach_completed';
  static const String onboardingTimeOffCoachCompletedKey = 'onboarding_time_off_coach_completed';

  // Notification Keys
  static const String notificationsKey = 'notifications_v1';
  static const String seenNotificationIdsKey = 'seen_notification_ids_v1';

  // Validation Constants
  static const int minPasswordLength = 8;
  static const int maxNameLength = 100;
  static const int maxEmailLength = 254;
  static const int minShiftMinutes = 30;
  static const int maxShiftHours = 16;

  // Firebase Collection Names (if applicable)
  static const String employeesCollection = 'employees';
  static const String schedulesCollection = 'schedules';
  static const String settingsCollection = 'settings';
  static const String shiftsCollection = 'shifts';

  // Error Codes
  static const String networkErrorCode = 'NETWORK_ERROR';
  static const String databaseErrorCode = 'DATABASE_ERROR';
  static const String authErrorCode = 'AUTH_ERROR';
  static const String validationErrorCode = 'VALIDATION_ERROR';
  static const String unknownErrorCode = 'UNKNOWN_ERROR';

  // API Related (if applicable)
  static const String apiBaseUrl = 'https://api.schedulehq.com';
  static const String apiVersion = 'v1';
  static const int apiTimeoutSeconds = 30;

  // PTO/Vacation Constants
  static const double defaultPtoHours = 80.0;
  static const double defaultVacationWeeks = 2.0;
  static const int ptoRequestAdvanceNoticeDays = 14;

  // Shift Runner Colors (common defaults)
  static const Map<String, String> defaultShiftRunnerColors = {
    'Morning': '#4CAF50', // Green
    'Day': '#2196F3', // Blue
    'Evening': '#FF9800', // Orange
    'Night': '#9C27B0', // Purple
    'Closing': '#F44336', // Red
  };

  // Store Hours Defaults
  static const Map<String, Map<String, String>> defaultStoreHours = {
    'Monday': {'open': '09:00', 'close': '21:00'},
    'Tuesday': {'open': '09:00', 'close': '21:00'},
    'Wednesday': {'open': '09:00', 'close': '21:00'},
    'Thursday': {'open': '09:00', 'close': '21:00'},
    'Friday': {'open': '09:00', 'close': '22:00'},
    'Saturday': {'open': '09:00', 'close': '22:00'},
    'Sunday': {'open': '10:00', 'close': '20:00'},
  };
}

/// Enum for different loading states
enum LoadingState { idle, loading, success, error }

/// Enum for sync status
enum SyncStatus { synced, pending, syncing, error, conflict }

/// Enum for employee status
enum EmployeeStatus { active, inactive, terminated, onLeave }

/// Enum for shift types
enum ShiftType { regular, overtime, holiday, vacation, requested, personal }

/// Enum for theme modes
enum AppThemeMode { light, dark, system }
