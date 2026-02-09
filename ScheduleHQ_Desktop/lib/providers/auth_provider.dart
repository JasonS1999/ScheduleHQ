import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart' hide FirebaseAuthException;
import '../utils/app_constants.dart';
import 'base_provider.dart';

/// Provider for managing authentication state and operations
class AuthProvider extends BaseProvider {
  final AuthService _authService;
  StreamSubscription<User?>? _authSubscription;
  
  User? _currentUser;
  bool _isManager = false;
  String? _lastSignInError;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService.instance {
    _setupAuthListener();
  }

  // Getters
  User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isManager => _isManager;
  String? get lastSignInError => _lastSignInError;
  String? get userEmail => _currentUser?.email;
  String? get userUid => _currentUser?.uid;
  String? get userDisplayName => _currentUser?.displayName ?? userEmail;

  /// Initialize the provider
  Future<void> initialize() async {
    await executeWithState(() async {
      _currentUser = _authService.currentUser;
      if (_currentUser != null) {
        await _checkManagerStatus();
      }
    }, errorPrefix: 'Failed to initialize auth');
  }

  @override
  Future<void> refresh() async {
    await initialize();
  }

  /// Set up listener for auth state changes
  void _setupAuthListener() {
    _authSubscription = _authService.authStateChanges.listen(
      (User? user) async {
        _currentUser = user;
        _lastSignInError = null;
        
        if (user != null) {
          await _checkManagerStatus();
          setLoadingState(LoadingState.success);
        } else {
          _isManager = false;
          setLoadingState(LoadingState.idle);
        }
      },
      onError: (error) {
        _lastSignInError = error.toString();
        setLoadingState(LoadingState.error, error: error.toString());
      },
    );
  }

  /// Check if current user has manager permissions
  Future<void> _checkManagerStatus() async {
    if (_currentUser != null) {
      try {
        // In a full implementation, you'd check Firestore for user role
        // For now, assume authenticated users are managers
        _isManager = true;
      } catch (e) {
        _isManager = false;
      }
    } else {
      _isManager = false;
    }
  }

  /// Sign in with email and password
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    // Clear previous errors
    _lastSignInError = null;
    
    // Validate inputs
    final validationErrors = _validateSignInInputs(email, password);
    if (validationErrors.isNotEmpty) {
      _lastSignInError = validationErrors.first;
      setLoadingState(LoadingState.error, error: _lastSignInError!);
      return false;
    }

    return await executeWithState(() async {
      try {
        final credential = await _authService.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        
        _currentUser = credential.user;
        await _checkManagerStatus();
        
        if (!_isManager) {
          await signOut();
          throw Exception('Account does not have manager access');
        }
        
        return true;
      } on FirebaseAuthException catch (e) {
        _lastSignInError = _getFirebaseAuthErrorMessage(e);
        throw Exception(_lastSignInError);
      } catch (e) {
        _lastSignInError = e.toString();
        rethrow;
      }
    }, errorPrefix: 'Sign in failed') ?? false;
  }

  /// Sign out the current user
  Future<bool> signOut() async {
    return await executeWithState(() async {
      await _authService.signOut();
      _currentUser = null;
      _isManager = false;
      _lastSignInError = null;
      return true;
    }, errorPrefix: 'Sign out failed') ?? false;
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) {
      setLoadingState(LoadingState.error, error: 'Email is required');
      return false;
    }

    if (!_isValidEmail(email)) {
      setLoadingState(LoadingState.error, error: 'Invalid email format');
      return false;
    }

    return await executeWithState(() async {
      await _authService.sendPasswordResetEmail(email.trim());
      return true;
    }, errorPrefix: 'Failed to send password reset email') ?? false;
  }

  /// Create a new manager account with auth code
  Future<bool> createManagerAccount({
    required String email,
    required String password,
    required String authCode,
  }) async {
    // Validate inputs
    final validationErrors = _validateCreateAccountInputs(email, password, authCode);
    if (validationErrors.isNotEmpty) {
      setLoadingState(LoadingState.error, error: validationErrors.first);
      return false;
    }

    return await executeWithState(() async {
      try {
        final credential = await _authService.createManagerAccount(
          email: email.trim(),
          password: password,
          authCode: authCode.trim(),
        );
        
        _currentUser = credential.user;
        _isManager = true;
        
        return true;
      } on FirebaseAuthException catch (e) {
        _lastSignInError = _getFirebaseAuthErrorMessage(e);
        throw Exception(_lastSignInError);
      } catch (e) {
        _lastSignInError = e.toString();
        rethrow;
      }
    }, errorPrefix: 'Failed to create manager account') ?? false;
  }

  /// Get manager auth code for creating employee accounts
  Future<String?> getManagerAuthCode() async {
    if (!_isManager || _currentUser == null) {
      setLoadingState(LoadingState.error, error: 'Manager authentication required');
      return null;
    }

    return await executeWithState<String?>(() async {
      return await _authService.getManagerAuthCode();
    }, errorPrefix: 'Failed to get auth code');
  }

  /// Change user password
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_currentUser == null) {
      setLoadingState(LoadingState.error, error: 'User not signed in');
      return false;
    }

    // Validate new password
    final passwordErrors = _validatePassword(newPassword);
    if (passwordErrors.isNotEmpty) {
      setLoadingState(LoadingState.error, error: passwordErrors.first);
      return false;
    }

    return await executeWithState(() async {
      try {
        // Re-authenticate with current password
        final credential = EmailAuthProvider.credential(
          email: _currentUser!.email!,
          password: currentPassword,
        );
        await _currentUser!.reauthenticateWithCredential(credential);
        
        // Update password
        await _currentUser!.updatePassword(newPassword);
        
        return true;
      } on FirebaseAuthException catch (e) {
        throw Exception(_getFirebaseAuthErrorMessage(e));
      }
    }, errorPrefix: 'Failed to change password') ?? false;
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    if (_currentUser == null) {
      setLoadingState(LoadingState.error, error: 'User not signed in');
      return false;
    }

    return await executeWithState(() async {
      await _currentUser!.updateDisplayName(displayName);
      if (photoURL != null) {
        await _currentUser!.updatePhotoURL(photoURL);
      }
      await _currentUser!.reload();
      _currentUser = _authService.currentUser;
      return true;
    }, errorPrefix: 'Failed to update profile') ?? false;
  }

  /// Validate sign-in inputs
  List<String> _validateSignInInputs(String email, String password) {
    final errors = <String>[];

    if (email.trim().isEmpty) {
      errors.add('Email is required');
    } else if (!_isValidEmail(email)) {
      errors.add('Invalid email format');
    }

    if (password.isEmpty) {
      errors.add('Password is required');
    }

    return errors;
  }

  /// Validate create account inputs
  List<String> _validateCreateAccountInputs(String email, String password, String authCode) {
    final errors = <String>[];

    if (email.trim().isEmpty) {
      errors.add('Email is required');
    } else if (email.length > AppConstants.maxEmailLength) {
      errors.add('Email is too long');
    } else if (!_isValidEmail(email)) {
      errors.add('Invalid email format');
    }

    errors.addAll(_validatePassword(password));

    if (authCode.trim().isEmpty) {
      errors.add('Authorization code is required');
    }

    return errors;
  }

  /// Validate password strength
  List<String> _validatePassword(String password) {
    final errors = <String>[];

    if (password.length < AppConstants.minPasswordLength) {
      errors.add('Password must be at least ${AppConstants.minPasswordLength} characters');
    }

    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(password)) {
      errors.add('Password must contain uppercase, lowercase, and numeric characters');
    }

    return errors;
  }

  /// Validate email format
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// Get user-friendly error message for Firebase Auth exceptions
  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'not-manager':
        return 'This account does not have manager access.';
      default:
        return e.message ?? 'An authentication error occurred.';
    }
  }

  /// Get authentication summary
  Map<String, dynamic> getAuthSummary() {
    return {
      'isSignedIn': isSignedIn,
      'isManager': _isManager,
      'userEmail': userEmail,
      'userDisplayName': userDisplayName,
      'lastSignInTime': _currentUser?.metadata.lastSignInTime?.toIso8601String(),
      'creationTime': _currentUser?.metadata.creationTime?.toIso8601String(),
      'emailVerified': _currentUser?.emailVerified ?? false,
    };
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}