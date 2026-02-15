class Employee {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? nickname;
  final String jobCode;

  // Firebase sync fields
  final String? email;
  final String? uid; // Firebase Auth UID
  final String? profileImageURL; // Profile picture URL from Firebase Storage

  // Vacation tracking
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
    this.profileImageURL,
    this.vacationWeeksAllowed = 0,
    this.vacationWeeksUsed = 0,
  });

  /// Display name: same as firstName
  /// Falls back to "Unknown" if not set
  String get displayName => firstName?.isNotEmpty == true ? firstName! : 'Unknown';

  /// Full name: same as firstName (lastName deprecated)
  String get fullName => firstName?.isNotEmpty == true ? firstName! : 'Unknown';

  /// Name getter - returns firstName
  String get name => firstName?.isNotEmpty == true ? firstName! : 'Unknown';

  Employee copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? nickname,
    String? jobCode,
    String? email,
    String? uid,
    String? profileImageURL,
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
      profileImageURL: profileImageURL ?? this.profileImageURL,
      vacationWeeksAllowed:
          vacationWeeksAllowed ?? this.vacationWeeksAllowed,
      vacationWeeksUsed: vacationWeeksUsed ?? this.vacationWeeksUsed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'nickname': nickname,
      'jobCode': jobCode,
      'email': email,
      'uid': uid,
      'profileImageURL': profileImageURL,
      'vacationWeeksAllowed': vacationWeeksAllowed,
      'vacationWeeksUsed': vacationWeeksUsed,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      nickname: map['nickname'],
      jobCode: map['jobCode'],
      email: map['email'],
      uid: map['uid'],
      profileImageURL: map['profileImageURL'],
      vacationWeeksAllowed: map['vacationWeeksAllowed'] ?? 0,
      vacationWeeksUsed: map['vacationWeeksUsed'] ?? 0,
    );
  }
}
