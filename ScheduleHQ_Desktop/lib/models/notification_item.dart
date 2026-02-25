class NotificationItem {
  final String id;
  final String employeeName;
  final String timeOffType; // 'pto' | 'vacation' | 'requested'
  final String date; // "YYYY-MM-DD"
  final String? endDate; // null for single-day
  final String status; // 'pending' | 'approved'
  final DateTime arrivedAt;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.employeeName,
    required this.timeOffType,
    required this.date,
    this.endDate,
    required this.status,
    required this.arrivedAt,
    this.isRead = false,
  });

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      employeeName: employeeName,
      timeOffType: timeOffType,
      date: date,
      endDate: endDate,
      status: status,
      arrivedAt: arrivedAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeName': employeeName,
        'timeOffType': timeOffType,
        'date': date,
        'endDate': endDate,
        'status': status,
        'arrivedAt': arrivedAt.toIso8601String(),
        'isRead': isRead,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      employeeName: json['employeeName'] as String,
      timeOffType: json['timeOffType'] as String,
      date: json['date'] as String,
      endDate: json['endDate'] as String?,
      status: json['status'] as String,
      arrivedAt: DateTime.parse(json['arrivedAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
    );
  }
}
