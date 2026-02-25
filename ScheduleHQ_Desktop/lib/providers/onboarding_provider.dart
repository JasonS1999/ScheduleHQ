import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';
import 'base_provider.dart';

class OnboardingProvider extends BaseProvider {
  bool _welcomeCompleted = false;
  bool _settingsCoachCompleted = false;
  bool _rosterCoachCompleted = false;
  bool _scheduleCoachCompleted = false;
  bool _timeOffCoachCompleted = false;

  bool get shouldShowWelcome => !_welcomeCompleted;
  bool get shouldShowSettingsCoach => !_settingsCoachCompleted;
  bool get shouldShowRosterCoach => !_rosterCoachCompleted;
  bool get shouldShowScheduleCoach => !_scheduleCoachCompleted;
  bool get shouldShowTimeOffCoach => !_timeOffCoachCompleted;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _welcomeCompleted = prefs.getBool(AppConstants.onboardingWelcomeCompletedKey) ?? false;
      _settingsCoachCompleted = prefs.getBool(AppConstants.onboardingSettingsCoachCompletedKey) ?? false;
      _rosterCoachCompleted = prefs.getBool(AppConstants.onboardingRosterCoachCompletedKey) ?? false;
      _scheduleCoachCompleted = prefs.getBool(AppConstants.onboardingScheduleCoachCompletedKey) ?? false;
      _timeOffCoachCompleted = prefs.getBool(AppConstants.onboardingTimeOffCoachCompletedKey) ?? false;
      setLoadingState(LoadingState.success);
    } catch (e) {
      debugPrint('Error loading onboarding state: $e');
      setLoadingState(LoadingState.error, error: e.toString());
    }
  }

  Future<void> markWelcomeCompleted() async {
    _welcomeCompleted = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingWelcomeCompletedKey, true);
  }

  Future<void> markSettingsCoachCompleted() async {
    _settingsCoachCompleted = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingSettingsCoachCompletedKey, true);
  }

  Future<void> markRosterCoachCompleted() async {
    _rosterCoachCompleted = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingRosterCoachCompletedKey, true);
  }

  Future<void> markScheduleCoachCompleted() async {
    _scheduleCoachCompleted = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingScheduleCoachCompletedKey, true);
  }

  Future<void> markTimeOffCoachCompleted() async {
    _timeOffCoachCompleted = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingTimeOffCoachCompletedKey, true);
  }

  Future<void> resetAllOnboarding() async {
    _welcomeCompleted = false;
    _settingsCoachCompleted = false;
    _rosterCoachCompleted = false;
    _scheduleCoachCompleted = false;
    _timeOffCoachCompleted = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.onboardingWelcomeCompletedKey);
    await prefs.remove(AppConstants.onboardingSettingsCoachCompletedKey);
    await prefs.remove(AppConstants.onboardingRosterCoachCompletedKey);
    await prefs.remove(AppConstants.onboardingScheduleCoachCompletedKey);
    await prefs.remove(AppConstants.onboardingTimeOffCoachCompletedKey);
  }

  @override
  Future<void> refresh() async {
    await initialize();
  }
}
