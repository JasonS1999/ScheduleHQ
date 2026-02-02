/// Represents a P&L reporting period (one month)
class PnlPeriod {
  final int? id;
  final int month; // 1-12
  final int year;
  final double avgWage;

  PnlPeriod({
    this.id,
    required this.month,
    required this.year,
    this.avgWage = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'month': month,
      'year': year,
      'avgWage': avgWage,
    };
  }

  factory PnlPeriod.fromMap(Map<String, dynamic> map) {
    return PnlPeriod(
      id: map['id'] as int?,
      month: map['month'] as int,
      year: map['year'] as int,
      avgWage: (map['avgWage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  PnlPeriod copyWith({
    int? id,
    int? month,
    int? year,
    double? avgWage,
  }) {
    return PnlPeriod(
      id: id ?? this.id,
      month: month ?? this.month,
      year: year ?? this.year,
      avgWage: avgWage ?? this.avgWage,
    );
  }

  /// Returns formatted period string (e.g., "February, 2025")
  String get periodDisplay {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[month - 1]}, $year';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PnlPeriod &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          month == other.month &&
          year == other.year;

  @override
  int get hashCode => id.hashCode ^ month.hashCode ^ year.hashCode;
}

/// Category groups for P&L line items
enum PnlCategory {
  sales,
  cogs,
  labor,
  controllables,
  final_,
}

/// Represents a single line item in a P&L report
class PnlLineItem {
  final int? id;
  final int periodId;
  final String label;
  final double value; // Dollar amount (source of truth)
  final String comment;
  final bool isCalculated; // true = auto-calculated row (totals)
  final bool isUserAdded; // true = user added this row (only in controllables)
  final int sortOrder;
  final PnlCategory category;

  PnlLineItem({
    this.id,
    required this.periodId,
    required this.label,
    this.value = 0.0,
    this.comment = '',
    this.isCalculated = false,
    this.isUserAdded = false,
    required this.sortOrder,
    required this.category,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'periodId': periodId,
      'label': label,
      'value': value,
      'comment': comment,
      'isCalculated': isCalculated ? 1 : 0,
      'isUserAdded': isUserAdded ? 1 : 0,
      'sortOrder': sortOrder,
      'category': category.name,
    };
  }

  factory PnlLineItem.fromMap(Map<String, dynamic> map) {
    return PnlLineItem(
      id: map['id'] as int?,
      periodId: map['periodId'] as int,
      label: map['label'] as String,
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      comment: map['comment'] as String? ?? '',
      isCalculated: (map['isCalculated'] as int?) == 1,
      isUserAdded: (map['isUserAdded'] as int?) == 1,
      sortOrder: map['sortOrder'] as int,
      category: PnlCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => PnlCategory.controllables,
      ),
    );
  }

  PnlLineItem copyWith({
    int? id,
    int? periodId,
    String? label,
    double? value,
    String? comment,
    bool? isCalculated,
    bool? isUserAdded,
    int? sortOrder,
    PnlCategory? category,
  }) {
    return PnlLineItem(
      id: id ?? this.id,
      periodId: periodId ?? this.periodId,
      label: label ?? this.label,
      value: value ?? this.value,
      comment: comment ?? this.comment,
      isCalculated: isCalculated ?? this.isCalculated,
      isUserAdded: isUserAdded ?? this.isUserAdded,
      sortOrder: sortOrder ?? this.sortOrder,
      category: category ?? this.category,
    );
  }

  /// Calculate percentage based on Product Net Sales
  double getPercentage(double productNetSales) {
    if (productNetSales == 0) return 0.0;
    return (value / productNetSales) * 100;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PnlLineItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          periodId == other.periodId &&
          label == other.label;

  @override
  int get hashCode => id.hashCode ^ periodId.hashCode ^ label.hashCode;
}

/// Default line item labels with their configuration
class PnlDefaults {
  static const List<Map<String, dynamic>> defaultLineItems = [
    // Sales - SALES (ALL NET) is the primary input at top
    {'label': 'SALES (ALL NET)', 'category': 'sales', 'isCalculated': false, 'sortOrder': 1},
    {'label': 'PRODUCT NET SALES', 'category': 'sales', 'isCalculated': false, 'sortOrder': 2},
    {'label': 'NON-PRODUCT SALES', 'category': 'sales', 'isCalculated': true, 'sortOrder': 3},
    
    // COGS
    {'label': 'FOOD COST', 'category': 'cogs', 'isCalculated': false, 'sortOrder': 4},
    {'label': 'PAPER COST', 'category': 'cogs', 'isCalculated': false, 'sortOrder': 5},
    {'label': 'GROSS PROFIT', 'category': 'cogs', 'isCalculated': true, 'sortOrder': 6},
    
    // Labor
    {'label': 'LABOR - MANAGEMENT', 'category': 'labor', 'isCalculated': false, 'sortOrder': 7},
    {'label': 'LABOR - CREW', 'category': 'labor', 'isCalculated': false, 'sortOrder': 8},
    {'label': 'LABOR - TOTAL', 'category': 'labor', 'isCalculated': true, 'sortOrder': 9},
    
    // Controllables
    {'label': 'PAYROLL TAXES', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 10},
    {'label': 'BONUSES', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 11},
    {'label': 'ADVERTISING - CO-OP', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 12},
    {'label': 'ADVERTISING - OPNAD', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 13},
    {'label': 'PROMOTION', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 14},
    {'label': 'LINEN', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 15},
    {'label': 'CREW AWARDS', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 16},
    {'label': 'OUTSIDE SERVICES', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 17},
    {'label': 'OPERATING SUPPLIES', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 18},
    {'label': 'M & R', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 19},
    {'label': 'UTILITIES', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 20},
    {'label': 'CASH +/-', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 21},
    {'label': 'DUES & SUBSCRIPTIONS', 'category': 'controllables', 'isCalculated': false, 'sortOrder': 22},
    {'label': 'CONTROLLABLES', 'category': 'controllables', 'isCalculated': true, 'sortOrder': 23},
    
    // Final
    {'label': 'P.A.C.', 'category': 'final_', 'isCalculated': true, 'sortOrder': 24},
    {'label': 'GOAL', 'category': 'final_', 'isCalculated': true, 'sortOrder': 25},
  ];

  /// Create default line items for a new period
  static List<PnlLineItem> createDefaultItems(int periodId) {
    return defaultLineItems.map((item) {
      return PnlLineItem(
        periodId: periodId,
        label: item['label'] as String,
        category: PnlCategory.values.firstWhere((e) => e.name == item['category']),
        isCalculated: item['isCalculated'] as bool,
        sortOrder: item['sortOrder'] as int,
      );
    }).toList();
  }
}
