class JobCodeGroup {
  final String name;
  final String colorHex;
  final int sortOrder;

  JobCodeGroup({
    required this.name,
    required this.colorHex,
    this.sortOrder = 0,
  });

  JobCodeGroup copyWith({
    String? name,
    String? colorHex,
    int? sortOrder,
  }) {
    return JobCodeGroup(
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'colorHex': colorHex,
      'sortOrder': sortOrder,
    };
  }

  factory JobCodeGroup.fromMap(Map<String, dynamic> map) {
    return JobCodeGroup(
      name: map['name'] as String,
      colorHex: map['colorHex'] as String? ?? '#4285F4',
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }
}
