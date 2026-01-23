import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for handling Firebase Authentication for employees
class AuthService {
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;
  
  AuthService._internal();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Get current user
  User? get currentUser => _auth.currentUser;
  
  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  /// Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      log('User signed in: ${credential.user?.email}', name: 'AuthService');
      return credential;
    } catch (e) {
      log('Sign in error: $e', name: 'AuthService');
      rethrow;
    }
  }
  
  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    log('User signed out', name: 'AuthService');
  }
  
  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
    log('Password reset email sent to $email', name: 'AuthService');
  }
  
  /// Get employee data from Firestore
  Future<Map<String, dynamic>?> getEmployeeData() async {
    final user = currentUser;
    if (user == null) return null;
    
    // First get the user document to find managerUid and employeeId
    final userDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    
    if (!userDoc.exists) {
      log('User document not found for uid: ${user.uid}', name: 'AuthService');
      return null;
    }
    
    final userData = userDoc.data()!;
    final managerUid = userData['managerUid'] as String?;
    final employeeId = userData['employeeId'];
    
    if (managerUid == null || employeeId == null) {
      log('User document missing managerUid or employeeId', name: 'AuthService');
      return null;
    }
    
    // Now get the employee data from the manager's subcollection
    final employeeDoc = await _firestore
        .collection('managers')
        .doc(managerUid)
        .collection('employees')
        .doc(employeeId.toString())
        .get();
    
    if (!employeeDoc.exists) {
      log('Employee document not found: managers/$managerUid/employees/$employeeId', name: 'AuthService');
      return null;
    }
    
    return employeeDoc.data();
  }
  
  /// Get employee's local ID (from manager app)
  Future<int?> getEmployeeLocalId() async {
    final user = currentUser;
    if (user == null) return null;
    
    // Get from user document first (faster)
    final userDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    
    if (userDoc.exists) {
      final employeeId = userDoc.data()?['employeeId'];
      if (employeeId is int) return employeeId;
      if (employeeId is String) return int.tryParse(employeeId);
    }
    
    return null;
  }
  
  /// Get the manager's UID for the current employee
  Future<String?> getManagerUid() async {
    final user = currentUser;
    if (user == null) return null;
    
    final userDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    
    return userDoc.data()?['managerUid'] as String?;
  }
}

/// Custom exception for Employee Auth
class EmployeeAuthException implements Exception {
  final String code;
  final String message;
  
  EmployeeAuthException({required this.code, required this.message});
  
  @override
  String toString() => message;
}
