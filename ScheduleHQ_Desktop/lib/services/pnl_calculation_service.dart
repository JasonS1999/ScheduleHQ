import '../models/pnl_entry.dart';

/// Service for calculating P&L values and percentages
class PnlCalculationService {
  /// PAC Goal lookup table based on Sales (ALL NET)
  /// Key: Sales threshold, Value: PAC Goal percentage
  static const Map<int, double> _pacGoalTable = {
    108000: 24.50,
    120000: 24.75,
    123000: 25.00,
    144000: 25.50,
    156000: 25.75,
    168000: 26.00,
    180000: 26.50,
    192000: 27.00,
    204000: 27.50,
    216000: 28.00,
    228000: 29.00,
    240000: 29.50,
    255000: 30.00,
    270000: 30.50,
    285000: 31.00,
    300000: 31.50,
    315000: 32.00,
    330000: 32.50,
    345000: 33.50,
    360000: 34.00,
    375000: 35.00,
    390000: 35.50,
    405000: 36.00,
    420000: 36.50,
    435000: 37.00,
    450000: 37.50,
    465000: 38.00,
    480000: 38.25,
    483000: 38.50,  // Note: Adjusted threshold based on image
    486000: 38.75,  // Note: Adjusted threshold based on image
    495000: 39.00,
    510000: 39.50,
    525000: 40.00,
    540000: 40.50,
  };

  /// Get the PAC Goal percentage based on Sales (ALL NET)
  /// Returns minimum 24.5% for sales below 108,000
  /// Returns maximum 40.5% for sales at or above 540,000
  static double getPacGoal(double salesAllNet) {
    if (salesAllNet < 108000) return 24.50;
    if (salesAllNet >= 540000) return 40.50;

    // Find the highest threshold that is <= salesAllNet
    final thresholds = _pacGoalTable.keys.toList()..sort();
    double goal = 24.50;

    for (final threshold in thresholds) {
      if (salesAllNet >= threshold) {
        goal = _pacGoalTable[threshold]!;
      } else {
        break;
      }
    }

    return goal;
  }

  /// Calculate percentage of a value relative to Sales (ALL NET)
  /// This is the new base for all percentage calculations
  static double calculatePercentage(double value, double salesAllNet) {
    if (salesAllNet == 0) return 0.0;
    return (value / salesAllNet) * 100;
  }

  /// Calculate dollar value from percentage relative to Sales (ALL NET)
  static double calculateValueFromPercentage(double percentage, double salesAllNet) {
    return (percentage * salesAllNet) / 100;
  }

  /// Get a line item's value by label from a list of items
  static double _getValue(List<PnlLineItem> items, String label) {
    final item = items.firstWhere(
      (i) => i.label == label,
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    return item.value;
  }

  /// Recalculate all computed fields and update the items list
  /// Returns a new list with updated calculated values
  /// 
  /// Calculation flow:
  /// 1. SALES (ALL NET) - user input $ (this is the base, always 100%)
  /// 2. PRODUCT NET SALES - user input %, $ calculated from SALES (ALL NET)
  /// 3. NON-PRODUCT SALES - $ = SALES (ALL NET) - PRODUCT NET SALES, % calculated
  static List<PnlLineItem> recalculateAll(List<PnlLineItem> items) {
    final updatedItems = List<PnlLineItem>.from(items);

    // SALES (ALL NET) is user input (primary sales figure) - this is the base
    final salesAllNet = _getValue(items, 'SALES (ALL NET)');
    
    // PRODUCT NET SALES: % is stored/editable, $ is calculated from SALES (ALL NET)
    final productNetSalesItem = items.firstWhere(
      (i) => i.label == 'PRODUCT NET SALES',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    final productNetSalesPercent = productNetSalesItem.percentage;
    final productNetSales = calculateValueFromPercentage(productNetSalesPercent, salesAllNet);
    
    // NON-PRODUCT SALES is calculated: Sales (All Net) - Product Net Sales
    final nonProductSales = salesAllNet - productNetSales;
    
    final foodCost = _getValue(items, 'FOOD COST');
    final paperCost = _getValue(items, 'PAPER COST');
    final laborManagement = _getValue(items, 'LABOR - MANAGEMENT');
    final laborCrew = _getValue(items, 'LABOR - CREW');

    // Calculate totals
    final grossProfit = salesAllNet - foodCost - paperCost;
    final laborTotal = laborManagement + laborCrew;

    // Sum all controllables (excluding the CONTROLLABLES total row)
    double controllablesSum = 0;
    for (final item in items) {
      if (item.category == PnlCategory.controllables && 
          !item.isCalculated && 
          item.label != 'CONTROLLABLES') {
        controllablesSum += item.value;
      }
    }

    // Calculate P.A.C.
    final pac = grossProfit - laborTotal - controllablesSum;

    // Calculate GOAL based on Sales (ALL NET)
    final goalPercent = getPacGoal(salesAllNet);
    final goalValue = calculateValueFromPercentage(goalPercent, salesAllNet);

    // Update calculated items
    for (var i = 0; i < updatedItems.length; i++) {
      final item = updatedItems[i];
      if (!item.isCalculated) continue;

      double newValue;
      switch (item.label) {
        case 'PRODUCT NET SALES':
          newValue = productNetSales;
          break;
        case 'NON-PRODUCT SALES':
          newValue = nonProductSales;
          break;
        case 'GROSS PROFIT':
          newValue = grossProfit;
          break;
        case 'LABOR - TOTAL':
          newValue = laborTotal;
          break;
        case 'CONTROLLABLES':
          newValue = controllablesSum;
          break;
        case 'P.A.C.':
          newValue = pac;
          break;
        case 'GOAL':
          newValue = goalValue;
          break;
        default:
          continue;
      }

      updatedItems[i] = item.copyWith(value: newValue);
    }

    return updatedItems;
  }

  /// Get the GOAL percentage for display (not stored, just looked up)
  static double getGoalPercentage(List<PnlLineItem> items) {
    final salesAllNet = _getValue(items, 'SALES (ALL NET)');
    return getPacGoal(salesAllNet);
  }

  /// Check if P.A.C. meets the GOAL
  static bool isPacMeetingGoal(List<PnlLineItem> items) {
    final salesAllNet = _getValue(items, 'SALES (ALL NET)');
    final pac = _getValue(items, 'P.A.C.');
    final pacPercent = calculatePercentage(pac, salesAllNet);
    final goalPercent = getGoalPercentage(items);
    return pacPercent >= goalPercent;
  }

  /// Get variance between P.A.C. and GOAL (positive = above goal)
  static double getPacVariance(List<PnlLineItem> items) {
    final salesAllNet = _getValue(items, 'SALES (ALL NET)');
    final pac = _getValue(items, 'P.A.C.');
    final pacPercent = calculatePercentage(pac, salesAllNet);
    final goalPercent = getGoalPercentage(items);
    return pacPercent - goalPercent;
  }
}
