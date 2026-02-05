import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? nickname;
  final String jobCode;
  final String? email;
  final String? uid; // Firebase Auth UID
  final int vacationWeeksAllowed;
  final int vacationWeeksUsed;

  Employee({
    this.id,
    this.firstName,
    this.lastName,
    this.nickname,
    required this.jobCode,
    this.email,
    this.uid,
    this.vacationWeeksAllowed = 0,
    this.vacationWeeksUsed = 0,
  });

  /// Display name: nickname if set, otherwise firstName
  /// Falls back to "Unknown" if neither is set
  String get displayName => nickname?.isNotEmpty == true 
      ? nickname! 
      : (firstName?.isNotEmpty == true ? firstName! : 'Unknown');

  /// Full name: "FirstName LastName"
  String get fullName {
    final first = firstName ?? '';
    final last = lastName ?? '';
    if (first.isEmpty && last.isEmpty) return 'Unknown';
    if (first.isEmpty) return last;
    if (last.isEmpty) return first;
    return '$first $last';
  }

  /// Legacy name field for backwards compatibility
  /// Returns fullName
  String get name => fullName;

  Employee copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? nickname,
    String? jobCode,
    String? email,
    String? uid,
    int? vacationWeeksAllowed,
    int? vacationWeeksUsed,
  }) {
    return Employee(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      nickname: nickname ?? this.nickname,
      jobCode: jobCode ?? this.jobCode,
      email: email ?? this.email,
      uid: uid ?? this.uid,
      vacationWeeksAllowed: vacationWeeksAllowed ?? this.vacationWeeksAllowed,
      vacationWeeksUsed: vacationWeeksUsed ?? this.vacationWeeksUsed,
    );
  }

  /// Convert to SQLite map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'nickname': nickname,
      'jobCode': jobCode,
      'email': email,
      'uid': uid,
      'vacationWeeksAllowed': vacationWeeksAllowed,
      'vacationWeeksUsed': vacationWeeksUsed,
    };
  }

  /// Create from SQLite map
  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      nickname: map['nickname'],
      jobCode: map['jobCode'],
      email: map['email'],
      uid: map['uid'],
      vacationWeeksAllowed: map['vacationWeeksAllowed'] ?? 0,
      vacationWeeksUsed: map['vacationWeeksUsed'] ?? 0,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'nickname': nickname,
      'jobCode': jobCode,
      'email': email,
      'uid': uid,
      'vacationWeeksAllowed': vacationWeeksAllowed,
      'vacationWeeksUsed': vacationWeeksUsed,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Create from Firestore document
  factory Employee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Employee(
      id: data['id'],
      firstName: data['firstName'],
      lastName: data['lastName'],
      nickname: data['nickname'],
      jobCode: data['jobCode'] ?? '',
      email: data['email'],
      uid: data['uid'],
      vacationWeeksAllowed: data['vacationWeeksAllowed'] ?? 0,
      vacationWeeksUsed: data['vacationWeeksUsed'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'Employee(id: $id, firstName: $firstName, lastName: $lastName, nickname: $nickname, jobCode: $jobCode, email: $email)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Employee &&
        other.id == id &&
        other.firstName == firstName &&
        other.lastName == lastName &&
        other.jobCode == jobCode &&
        other.email == email;
  }

  @override
  int get hashCode => Object.hash(id, firstName, lastName, jobCode, email);
}
