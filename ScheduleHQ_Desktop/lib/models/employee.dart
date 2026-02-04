class Employee {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? nickname;
  final String jobCode;

  // Firebase sync fields
  final String? email;
  final String? uid; // Firebase Auth UID

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
      vacationWeeksAllowed: map['vacationWeeksAllowed'] ?? 0,
      vacationWeeksUsed: map['vacationWeeksUsed'] ?? 0,
    );
  }
}
