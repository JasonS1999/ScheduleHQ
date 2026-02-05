import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/pnl_dao.dart';
import '../models/pnl_entry.dart';
import '../models/store_hours.dart';
import '../services/pnl_calculation_service.dart';
import '../services/pnl_pdf_service.dart';

/// Row edit mode
enum _EditMode { editable, dollarOnly, percentOnly, readOnly }

/// Configuration for row behaviors
class _RowConfig {
  final _EditMode mode;
  final double? fixedDollar;
  final double? fixedPercent;
  final double? defaultDollar;  // Default value when creating new period
  final double? defaultPercent; // Default value when creating new period
  final bool useGoalPercent; // Special case for GOAL row
  final bool useSalesPercent; // Special case for SALES (ALL NET) = NON-PRODUCT % + 100%

  const _RowConfig(
    this.mode, {
    this.fixedDollar,
    this.fixedPercent,
    this.defaultDollar,
    this.defaultPercent,
    this.useGoalPercent = false,
    this.useSalesPercent = false,
  });

  // Convenience constructors
  const _RowConfig.editable({double? defaultDollar, double? defaultPercent})
      : this(_EditMode.editable, defaultDollar: defaultDollar, defaultPercent: defaultPercent);
  const _RowConfig.dollarOnly({double? fixedPercent, double? defaultDollar})
      : this(_EditMode.dollarOnly, fixedPercent: fixedPercent, defaultDollar: defaultDollar);
  const _RowConfig.percentOnly({double? fixedDollar, double? defaultPercent})
      : this(_EditMode.percentOnly, fixedDollar: fixedDollar, defaultPercent: defaultPercent);
  const _RowConfig.readOnly({double? fixedDollar, double? fixedPercent, bool useSalesPercent = false})
      : this(_EditMode.readOnly, fixedDollar: fixedDollar, fixedPercent: fixedPercent, useSalesPercent: useSalesPercent);
  const _RowConfig.goal() : this(_EditMode.readOnly, useGoalPercent: true);
  const _RowConfig.salesTotal() : this(_EditMode.dollarOnly, useSalesPercent: true);

  bool get isDollarEditable => mode == _EditMode.editable || mode == _EditMode.dollarOnly;
  bool get isPercentEditable => mode == _EditMode.editable || mode == _EditMode.percentOnly;
}

class PnlPage extends StatefulWidget {
  const PnlPage({super.key});

  @override
  State<PnlPage> createState() => _PnlPageState();
}

class _PnlPageState extends State<PnlPage> {
  final PnlDao _dao = PnlDao();
  final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _percentFormat = NumberFormat('0.0', 'en_US');

  // Row configuration by label - use _RowConfig constructors:
  // .editable()     - both $ and % editable
  // .dollarOnly()   - $ editable, % calculated (can add fixedPercent)
  // .percentOnly()  - % editable, $ calculated (can add fixedDollar)
  // .readOnly()     - both read-only (can add fixedDollar/fixedPercent)
  // .goal()         - uses special GOAL % lookup
  
  static const _rowConfigs = <String, _RowConfig>{
    // === SALES ===
    'SALES (ALL NET)': _RowConfig.readOnly(useSalesPercent: true),    // Read-only (entered in header), % = NON-PRODUCT % + 100%
    'NON-PRODUCT SALES': _RowConfig.percentOnly(),                    // % editable, $ calculated from SALES ALL NET
    'PRODUCT NET SALES': _RowConfig.readOnly(fixedPercent: 100.0),    // Calculated: SALES ALL NET - NON-PRODUCT, % fixed 100%
    
    // === COGS ===
    'FOOD COST': _RowConfig.percentOnly(),                             // $ editable, % calculated
    'PAPER COST': _RowConfig.percentOnly(),                            // $ editable, % calculated
    'GROSS PROFIT': _RowConfig.readOnly(),                            // Calculated: SALES ALL NET - FOOD - PAPER
    
    // === LABOR ===
    'LABOR - MANAGEMENT': _RowConfig.dollarOnly(),                    // $ editable, % calculated
    'LABOR - CREW': _RowConfig.percentOnly(),                          // $ editable, % calculated
    'LABOR - TOTAL': _RowConfig.readOnly(),                           // Calculated: MGMT + CREW
    
    // === CONTROLLABLES ===
    'PAYROLL TAXES': _RowConfig.percentOnly(),                        
    'BONUSES': _RowConfig.dollarOnly(),
    'ADVERTISING - CO-OP': _RowConfig.percentOnly(),
    'ADVERTISING - OPNAD': _RowConfig.percentOnly(),
    'PROMOTION': _RowConfig.percentOnly(),
    'LINEN': _RowConfig.dollarOnly(),
    'CREW AWARDS': _RowConfig.dollarOnly(),
    'OUTSIDE SERVICES': _RowConfig.percentOnly(),
    'OPERATING SUPPLIES': _RowConfig.dollarOnly(),
    'M & R': _RowConfig.dollarOnly(),
    'UTILITIES': _RowConfig.percentOnly(),
    'CASH +/-': _RowConfig.dollarOnly(),
    'DUES & SUBSCRIPTIONS': _RowConfig.dollarOnly(),
    'CONTROLLABLES': _RowConfig.readOnly(),                           // Calculated: sum of above
    
    // === FINAL ===
    'P.A.C.': _RowConfig.readOnly(),                                  // Calculated: GROSS PROFIT - LABOR TOTAL - CONTROLLABLES
    'GOAL': _RowConfig.goal(),                                        // Calculated: uses PAC goal lookup table
  };

  // Highlight colors by label
  static const _yellowRows = {'SALES (ALL NET)', 'GROSS PROFIT', 'LABOR - TOTAL', 'CONTROLLABLES'};
  static const _cyanRows = {'P.A.C.', 'GOAL'};
  
  // Section break rows (thick top border)
  static const _sectionBreaks = {'FOOD COST', 'LABOR - MANAGEMENT', 'PAYROLL TAXES', 'P.A.C.'};

  // Labor hours lookup table based on daily sales
  static const _laborHoursTable = <int, int>{
    4000: 90,
    5000: 100,
    6000: 115,
    7000: 125,
    8000: 140,
    9000: 150,
    10000: 160,
    12000: 185,
    14000: 205,
  };

  PnlPeriod? _currentPeriod;
  List<PnlLineItem> _lineItems = [];
  List<PnlPeriod> _allPeriods = [];
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _autoLaborEnabled = false;
  Timer? _autosaveTimer;

  // Text controllers for header fields
  final _salesController = TextEditingController();
  final _avgWageController = TextEditingController();

  // Map of line item id to controllers for $ and % fields
  final Map<int, TextEditingController> _valueControllers = {};
  final Map<int, TextEditingController> _percentControllers = {};
  final Map<int, TextEditingController> _commentControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _salesController.dispose();
    _avgWageController.dispose();
    for (final c in _valueControllers.values) {
      c.dispose();
    }
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load all periods
    _allPeriods = await _dao.getAllPeriods();

    // Get or create current month's period
    final now = DateTime.now();
    _currentPeriod = await _dao.getOrCreatePeriod(now.month, now.year);

    // Load line items for current period
    await _loadPeriodData();

    setState(() => _isLoading = false);
  }

  Future<void> _loadPeriodData() async {
    if (_currentPeriod == null) return;

    _lineItems = await _dao.getLineItemsForPeriod(_currentPeriod!.id!);
    _lineItems = PnlCalculationService.recalculateAll(_lineItems);

    // Load auto labor setting from period
    _autoLaborEnabled = _currentPeriod!.autoLaborEnabled;

    // Update sales controller
    final salesAllNet = _getSalesAllNet();
    _salesController.text = salesAllNet > 0 ? salesAllNet.toStringAsFixed(2) : '';
    
    final productNetSales = _getProductNetSales();

    // Update avgWage controller
    _avgWageController.text = _currentPeriod!.avgWage > 0 
        ? _currentPeriod!.avgWage.toStringAsFixed(2) 
        : '';

    // Clear and rebuild controllers
    _valueControllers.clear();
    _percentControllers.clear();
    _commentControllers.clear();

    for (final item in _lineItems) {
      if (item.id != null) {
        final config = _getRowConfig(item);
        
        // Dollar controller - use fixed value or actual value
        final dollarText = config.fixedDollar != null
            ? config.fixedDollar!.toStringAsFixed(2)
            : (item.value != 0 ? item.value.toStringAsFixed(2) : '');
        _valueControllers[item.id!] = TextEditingController(text: dollarText);
        
        // Percent controller - use fixed value, stored %, sales sum, or calculated %
        String percentText;
        if (config.fixedPercent != null) {
          percentText = config.fixedPercent!.toStringAsFixed(1);
        } else if (config.useSalesPercent) {
          // SALES (ALL NET) % = NON-PRODUCT SALES % + 100%
          final nonProdPercent = _lineItems.firstWhere(
            (i) => i.label == 'NON-PRODUCT SALES',
            orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
          ).percentage;
          percentText = (nonProdPercent + 100.0).toStringAsFixed(1);
        } else if (item.label == 'NON-PRODUCT SALES') {
          // NON-PRODUCT SALES uses stored percentage (this is the editable field)
          percentText = item.percentage != 0 ? item.percentage.toStringAsFixed(1) : '';
        } else {
          // Calculate % from PRODUCT NET SALES (the base)
          percentText = item.value != 0 
              ? PnlCalculationService.calculatePercentage(item.value, productNetSales).toStringAsFixed(1)
              : '';
        }
        _percentControllers[item.id!] = TextEditingController(text: percentText);
        _commentControllers[item.id!] = TextEditingController(text: item.comment);
      }
    }

    _hasChanges = false;
  }

  _RowConfig _getRowConfig(PnlLineItem item) {
    // LABOR - CREW is read-only when auto labor is enabled
    if (item.label == 'LABOR - CREW' && _autoLaborEnabled) {
      return const _RowConfig.readOnly();
    }
    // Check for specific label config first
    if (_rowConfigs.containsKey(item.label)) {
      return _rowConfigs[item.label]!;
    }
    // User-added controllables: $ editable, % calculated
    if (item.isUserAdded && item.category == PnlCategory.controllables) {
      return const _RowConfig.dollarOnly();
    }
    // Default: calculated items are read-only, others are dollarOnly
    return item.isCalculated ? const _RowConfig.readOnly() : const _RowConfig.dollarOnly();
  }

  double _getSalesAllNet() {
    final item = _lineItems.firstWhere(
      (i) => i.label == 'SALES (ALL NET)',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    return item.value;
  }

  double _getProductNetSales() {
    final item = _lineItems.firstWhere(
      (i) => i.label == 'PRODUCT NET SALES',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    return item.value;
  }

  double _getNonProductSalesPercent() {
    final item = _lineItems.firstWhere(
      (i) => i.label == 'NON-PRODUCT SALES',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    return item.percentage;
  }

  double _getLaborCrewValue() {
    final item = _lineItems.firstWhere(
      (i) => i.label == 'LABOR - CREW',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.labor),
    );
    return item.value;
  }

  double _getPacPercent() {
    final productNetSales = _getProductNetSales();
    if (productNetSales <= 0) return 0.0;
    
    final pacItem = _lineItems.firstWhere(
      (i) => i.label == 'P.A.C.',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.controllables),
    );
    return (pacItem.value / productNetSales) * 100;
  }

  void _onValueChanged(PnlLineItem item, String newValue) {
    final value = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
    
    // Update item value
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(value: value);
      
      // Recalculate all
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);
      
      // Apply auto labor calculation if enabled and SALES changed
      if (item.label == 'SALES (ALL NET)') {
        _applyAutoLaborIfEnabled();
      }
      
      // Update percentage field based on config
      final config = _getRowConfig(item);
      if (config.fixedPercent != null) {
        _percentControllers[item.id!]?.text = config.fixedPercent!.toStringAsFixed(1);
      } else if (config.useSalesPercent) {
        // SALES (ALL NET) % = NON-PRODUCT SALES % + 100%
        final salesPercent = _getNonProductSalesPercent() + 100.0;
        _percentControllers[item.id!]?.text = salesPercent.toStringAsFixed(1);
      } else if (config.mode == _EditMode.editable) {
        // For editable rows, % stays as user entered - don't recalculate
        // (% is independent of $ for these rows)
      } else {
        // For dollarOnly rows, calculate % from $
        final productNetSales = _getProductNetSales();
        final percent = PnlCalculationService.calculatePercentage(value, productNetSales);
        _percentControllers[item.id!]?.text = percent.toStringAsFixed(1);
      }

      // Update all calculated rows' controllers
      _updateCalculatedRowControllers();

      setState(() => _hasChanges = true);
      _scheduleAutosave();
    }
  }

  void _onPercentChanged(PnlLineItem item, String newPercent) {
    // Don't process incomplete input (e.g., "0." while user is still typing)
    if (newPercent.isEmpty || newPercent.endsWith('.')) {
      return;
    }
    
    final percent = double.tryParse(newPercent) ?? 0;
    final config = _getRowConfig(item);

    // Update item
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      if (config.mode == _EditMode.editable) {
        // For editable rows, just store the percentage - don't calculate $
        _lineItems[index] = _lineItems[index].copyWith(percentage: percent);
      } else {
        // For percentOnly rows, calculate $ from % (rounded to $100)
        final productNetSales = _getProductNetSales();
        final rawValue = PnlCalculationService.calculateValueFromPercentage(percent, productNetSales);
        final value = PnlCalculationService.roundToNearest100(rawValue);
        
        // For NON-PRODUCT SALES, store the percentage since that's the user input
        if (item.label == 'NON-PRODUCT SALES') {
          _lineItems[index] = _lineItems[index].copyWith(value: value, percentage: percent);
        } else {
          _lineItems[index] = _lineItems[index].copyWith(value: value);
        }

        // Update value field
        if (config.fixedDollar == null) {
          _valueControllers[item.id!]?.text = value.toStringAsFixed(2);
        }
      }

      // Recalculate all calculated rows
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);

      // Update all calculated rows' controllers
      _updateCalculatedRowControllers();

      setState(() => _hasChanges = true);
      _scheduleAutosave();
    }
  }

  void _updateCalculatedRowControllers() {
    final productNetSales = _getProductNetSales();
    
    for (final item in _lineItems) {
      if (item.id != null) {
        final config = _getRowConfig(item);
        
        // For percentOnly rows, recalculate $ from stored % and new sales (rounded to $100)
        if (config.mode == _EditMode.percentOnly && config.fixedDollar == null) {
          // Get the current % from the controller (user's input)
          final percentText = _percentControllers[item.id!]?.text ?? '0';
          final percent = double.tryParse(percentText) ?? 0;
          final rawValue = PnlCalculationService.calculateValueFromPercentage(percent, productNetSales);
          final newValue = PnlCalculationService.roundToNearest100(rawValue);
          
          // Update the line item value
          final index = _lineItems.indexWhere((i) => i.id == item.id);
          if (index >= 0) {
            _lineItems[index] = _lineItems[index].copyWith(value: newValue);
          }
          
          // Update the controller
          _valueControllers[item.id!]?.text = newValue.toStringAsFixed(2);
        }
        // Update dollar controller for read-only items
        else if (!config.isDollarEditable) {
          final dollarText = config.fixedDollar != null
              ? config.fixedDollar!.toStringAsFixed(2)
              : item.value.toStringAsFixed(2);
          _valueControllers[item.id!]?.text = dollarText;
        }
        
        // Update percent controller for non-editable items
        if (!config.isPercentEditable) {
          if (config.fixedPercent != null) {
            _percentControllers[item.id!]?.text = config.fixedPercent!.toStringAsFixed(1);
          } else if (config.useSalesPercent) {
            // SALES (ALL NET) % = NON-PRODUCT SALES % + 100%
            final salesPercent = _getNonProductSalesPercent() + 100.0;
            _percentControllers[item.id!]?.text = salesPercent.toStringAsFixed(1);
          } else {
            final percent = PnlCalculationService.calculatePercentage(item.value, productNetSales);
            _percentControllers[item.id!]?.text = percent.toStringAsFixed(1);
          }
        }
      }
    }
    
    // Recalculate totals after updating percentOnly rows
    _lineItems = PnlCalculationService.recalculateAll(_lineItems);
    
    // Update calculated row controllers again with new totals
    for (final item in _lineItems) {
      if (item.id != null && item.isCalculated) {
        _valueControllers[item.id!]?.text = item.value.toStringAsFixed(2);
      }
    }
  }

  void _onCommentChanged(PnlLineItem item, String newComment) {
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(comment: newComment);
      setState(() => _hasChanges = true);
      _scheduleAutosave();
    }
  }

  void _onSalesChanged(String value) {
    final sales = double.tryParse(value.replaceAll(',', '')) ?? 0;
    
    // Update SALES (ALL NET) line item
    final index = _lineItems.indexWhere((i) => i.label == 'SALES (ALL NET)');
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(value: sales);
      
      // Recalculate all
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);
      
      // Apply auto labor if enabled
      _applyAutoLaborIfEnabled();
      
      // Update all calculated rows' controllers
      _updateCalculatedRowControllers();
      
      setState(() => _hasChanges = true);
      _scheduleAutosave();
    }
  }

  void _onAvgWageChanged(String value) {
    final wage = double.tryParse(value) ?? 0;
    _currentPeriod = _currentPeriod?.copyWith(avgWage: wage);
    _applyAutoLaborIfEnabled();
    setState(() => _hasChanges = true);
    _scheduleAutosave();
  }

  void _onAutoLaborChanged(bool? enabled) {
    _autoLaborEnabled = enabled ?? false;
    _currentPeriod = _currentPeriod?.copyWith(autoLaborEnabled: _autoLaborEnabled);
    if (_autoLaborEnabled) {
      _applyAutoLaborIfEnabled();
    }
    setState(() => _hasChanges = true);
    _scheduleAutosave();
  }

  void _applyAutoLaborIfEnabled() {
    if (!_autoLaborEnabled || _currentPeriod == null) return;

    final salesAllNet = _getSalesAllNet();
    final avgWage = _currentPeriod!.avgWage;
    final daysInMonth = DateUtils.getDaysInMonth(_currentPeriod!.year, _currentPeriod!.month);

    if (salesAllNet <= 0 || avgWage <= 0) return;

    // Calculate average daily sales
    final dailySales = salesAllNet / daysInMonth;

    // Look up hours from table (interpolate between brackets)
    final hours = _lookupLaborHours(dailySales);

    // Calculate labor crew cost = hours * avg wage * days in month (rounded to $100)
    final rawLaborCrewCost = hours * avgWage * daysInMonth;
    final laborCrewCost = PnlCalculationService.roundToNearest100(rawLaborCrewCost);

    // Find and update LABOR - CREW item
    final crewIndex = _lineItems.indexWhere((item) => item.label == 'LABOR - CREW');
    if (crewIndex >= 0) {
      final crewItem = _lineItems[crewIndex];
      final productNetSales = _getProductNetSales();
      final percentage = productNetSales > 0 ? (laborCrewCost / productNetSales) * 100 : 0.0;
      
      _lineItems[crewIndex] = crewItem.copyWith(
        value: laborCrewCost,
        percentage: percentage,
      );

      // Update the controllers for LABOR - CREW if they exist
      if (crewItem.id != null) {
        _valueControllers[crewItem.id!]?.text = laborCrewCost.toStringAsFixed(2);
        _percentControllers[crewItem.id!]?.text = percentage.toStringAsFixed(1);
      }
      
      // Recalculate all dependent values
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);
    }
  }

  double _lookupLaborHours(double dailySales) {
    // Get sorted thresholds
    final thresholds = _laborHoursTable.keys.toList()..sort();

    // Below minimum - use minimum hours
    if (dailySales <= thresholds.first) {
      return _laborHoursTable[thresholds.first]!.toDouble();
    }

    // Above maximum - use maximum hours
    if (dailySales >= thresholds.last) {
      return _laborHoursTable[thresholds.last]!.toDouble();
    }

    // Find the bracket and interpolate
    for (int i = 0; i < thresholds.length - 1; i++) {
      final lowerThreshold = thresholds[i];
      final upperThreshold = thresholds[i + 1];
      
      if (dailySales >= lowerThreshold && dailySales < upperThreshold) {
        final lowerHours = _laborHoursTable[lowerThreshold]!;
        final upperHours = _laborHoursTable[upperThreshold]!;
        
        // Linear interpolation
        final ratio = (dailySales - lowerThreshold) / (upperThreshold - lowerThreshold);
        return lowerHours + (upperHours - lowerHours) * ratio;
      }
    }

    return _laborHoursTable[thresholds.last]!.toDouble();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), () {
      _save();
    });
  }

  Future<void> _save() async {
    if (_currentPeriod == null) return;

    // Save period (avgWage)
    await _dao.updatePeriod(_currentPeriod!);

    // Save all line items
    await _dao.updateAllLineItems(_lineItems);

    // Refresh periods list
    _allPeriods = await _dao.getAllPeriods();

    if (mounted) {
      setState(() => _hasChanges = false);
    }
  }

  Future<void> _selectPeriod() async {
    final result = await showDialog<PnlPeriod?>(
      context: context,
      builder: (context) => _PeriodSelectorDialog(
        periods: _allPeriods,
        currentPeriod: _currentPeriod,
        onCreateNew: _createNewPeriod,
        onDelete: _deletePeriod,
      ),
    );

    // Reload periods list in case any were deleted
    _allPeriods = await _dao.getAllPeriods();

    if (result != null && result.id != _currentPeriod?.id) {
      setState(() => _isLoading = true);
      _currentPeriod = result;
      await _loadPeriodData();
      setState(() => _isLoading = false);
    } else if (result == null && _currentPeriod != null) {
      // Current period may have been deleted, check if it still exists
      final stillExists = _allPeriods.any((p) => p.id == _currentPeriod!.id);
      if (!stillExists) {
        // Load most recent period or create new one
        setState(() => _isLoading = true);
        if (_allPeriods.isNotEmpty) {
          _currentPeriod = _allPeriods.first;
        } else {
          final now = DateTime.now();
          _currentPeriod = await _dao.getOrCreatePeriod(now.month, now.year);
          _allPeriods = await _dao.getAllPeriods();
        }
        await _loadPeriodData();
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deletePeriod(PnlPeriod period) async {
    if (period.id != null) {
      await _dao.deletePeriod(period.id!);
      _allPeriods = await _dao.getAllPeriods();
    }
  }

  Future<PnlPeriod?> _createNewPeriod(int month, int year) async {
    // Check if period already exists
    final existing = await _dao.getPeriodByMonthYear(month, year);
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Period for ${_getMonthName(month)} $year already exists')),
        );
      }
      return existing;
    }

    final id = await _dao.insertPeriod(PnlPeriod(month: month, year: year));
    _allPeriods = await _dao.getAllPeriods();
    return await _dao.getPeriodById(id);
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Future<void> _copyFromPrevious() async {
    if (_currentPeriod == null || _allPeriods.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous period to copy from')),
      );
      return;
    }

    // Find previous period
    final previousPeriods = _allPeriods.where((p) => p.id != _currentPeriod!.id).toList();
    if (previousPeriods.isEmpty) return;

    // Show dialog to select which period and which lines to copy
    final result = await showDialog<_CopyResult>(
      context: context,
      builder: (context) => _CopyFromPreviousDialog(
        periods: previousPeriods,
        dao: _dao,
      ),
    );

    if (result != null && result.selectedItemIds.isNotEmpty) {
      await _dao.copySelectLinesFromPeriod(
        fromPeriodId: result.fromPeriod.id!,
        toPeriodId: _currentPeriod!.id!,
        itemIds: result.selectedItemIds,
      );

      await _loadPeriodData();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied ${result.selectedItemIds.length} items')),
        );
      }
    }
  }

  Future<void> _addControllableRow() async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _AddLineItemDialog(),
    );

    if (label != null && label.isNotEmpty && _currentPeriod != null) {
      await _dao.addUserControllableItem(_currentPeriod!.id!, label);
      await _loadPeriodData();
      setState(() {});
    }
  }

  Future<void> _removeControllableRow(PnlLineItem item) async {
    if (!item.isUserAdded) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Line Item'),
        content: Text('Are you sure you want to remove "${item.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dao.removeUserControllableItem(item.id!);
      await _loadPeriodData();
      setState(() {});
    }
  }

  Future<void> _exportPdf() async {
    if (_currentPeriod == null || _lineItems.isEmpty) return;

    await PnlPdfService.generateAndSavePdf(
      period: _currentPeriod!,
      lineItems: _lineItems,
      storeName: StoreHours.cached.storeName,
      storeNsn: StoreHours.cached.storeNsn,
    );
  }

  Color _getRowColor(PnlLineItem item, bool isDark) {
    if (_cyanRows.contains(item.label)) {
      return isDark ? Colors.cyan.shade900 : Colors.cyan.shade100;
    }
    if (_yellowRows.contains(item.label)) {
      return isDark ? Colors.yellow.shade900.withValues(alpha: 0.3) : Colors.yellow.shade100;
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final storeName = StoreHours.cached.storeName;
    final storeNsn = StoreHours.cached.storeNsn;
    final goalPercent = PnlCalculationService.getGoalPercentage(_lineItems);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(storeName.isNotEmpty ? storeName : 'P&L Projections'),
            if (storeNsn.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text(
                storeNsn,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
              ),
            ],
            const Spacer(),
            // Period selector - centered and larger
            FilledButton.icon(
              onPressed: _selectPeriod,
              icon: const Icon(Icons.calendar_month, size: 24),
              label: Text(
                _currentPeriod?.periodDisplay ?? 'Select Period',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const Spacer(),
          ],
        ),
        actions: [
          // Copy from previous
          IconButton(
            onPressed: _copyFromPrevious,
            icon: const Icon(Icons.content_copy),
            tooltip: 'Copy from Previous Period',
          ),
          // Export PDF
          IconButton(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header info row
            Row(
              children: [
                // Sales field
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _salesController,
                    decoration: const InputDecoration(
                      labelText: 'Sales',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: _onSalesChanged,
                  ),
                ),
                const SizedBox(width: 16),
                // Avg Wage field
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _avgWageController,
                    decoration: const InputDecoration(
                      labelText: 'Avg Wage',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: _onAvgWageChanged,
                  ),
                ),
                const SizedBox(width: 16),
                // Hours badge (calculated from LABOR - CREW / Avg Wage)
                Builder(
                  builder: (context) {
                    final avgWage = _currentPeriod?.avgWage ?? 0;
                    final laborCrew = _getLaborCrewValue();
                    final daysInMonth = _currentPeriod != null 
                        ? DateUtils.getDaysInMonth(_currentPeriod!.year, _currentPeriod!.month)
                        : 30;
                    final weeksInMonth = daysInMonth / 7.0;
                    
                    final monthlyHours = avgWage > 0 ? laborCrew / avgWage : 0.0;
                    final weeklyHours = weeksInMonth > 0 ? monthlyHours / weeksInMonth : 0.0;
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.purple.shade900 : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${weeklyHours.toStringAsFixed(1)} hrs/wk',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            '${monthlyHours.toStringAsFixed(0)} hrs/mo',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Spacer(),
                // P.A.C. display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.cyan.shade900 : Colors.cyan.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan),
                  ),
                  child: Text(
                    'P.A.C.: ${_percentFormat.format(_getPacPercent())}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 16),
                // Goal display with checkmark/X indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blue.shade900 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GOAL: ${_percentFormat.format(goalPercent)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      if (_getPacPercent() >= goalPercent)
                        const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      else
                        const Icon(Icons.cancel, color: Colors.red, size: 20),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Auto Labor checkbox
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.green.shade900.withOpacity(0.5) : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _autoLaborEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _autoLaborEnabled,
                        onChanged: _onAutoLaborChanged,
                        activeColor: Colors.green,
                      ),
                      const Text(
                        'Auto Labor',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // P&L Table
            _buildTable(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(bool isDark) {
    final productNetSales = _getProductNetSales();

    return Table(
      border: TableBorder.all(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      ),
      columnWidths: const {
        0: FlexColumnWidth(2.5),  // Label
        1: FlexColumnWidth(1.5),  // Projected $
        2: FlexColumnWidth(1),    // Projected %
        3: FlexColumnWidth(2),    // Comments
        4: FixedColumnWidth(48),  // Actions (delete for user-added)
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          children: const [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('PROJECTED \$', 
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('PROJECTED %', 
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('COMMENTS', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(), // Actions column header
          ],
        ),

        // Data rows
        ..._lineItems.map((item) => _buildTableRow(item, productNetSales, isDark)),
      ],
    );
  }

  TableRow _buildTableRow(PnlLineItem item, double productNetSales, bool isDark) {
    final config = _getRowConfig(item);
    final rowColor = _getRowColor(item, isDark);
    final needsTopBorder = _sectionBreaks.contains(item.label);

    return TableRow(
      decoration: BoxDecoration(
        color: rowColor,
        border: needsTopBorder
            ? Border(top: BorderSide(color: Colors.grey.shade500, width: 2))
            : null,
      ),
      children: [
        // Label
        _buildLabelCell(item),
        // Dollar value
        _buildDollarCell(item, config),
        // Percentage
        _buildPercentCell(item, config, productNetSales),
        // Comments
        _buildCommentCell(item, isDark),
        // Actions
        _buildActionCell(item),
      ],
    );
  }

  Widget _buildLabelCell(PnlLineItem item) {
    // Bold only the highlighted rows (totals)
    final isBoldRow = _yellowRows.contains(item.label) || _cyanRows.contains(item.label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        item.label,
        style: TextStyle(fontWeight: isBoldRow ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _buildDollarCell(PnlLineItem item, _RowConfig config) {
    final displayValue = config.fixedDollar ?? item.value;
    final isBoldRow = _yellowRows.contains(item.label) || _cyanRows.contains(item.label);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: config.isDollarEditable
          ? TextField(
              controller: _valueControllers[item.id],
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              onChanged: (v) => _onValueChanged(item, v),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _currencyFormat.format(displayValue),
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: isBoldRow ? FontWeight.bold : FontWeight.normal),
              ),
            ),
    );
  }

  Widget _buildPercentCell(PnlLineItem item, _RowConfig config, double productNetSales) {
    if (config.isPercentEditable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(
          controller: _percentControllers[item.id],
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            suffixText: '%',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          onChanged: (v) => _onPercentChanged(item, v),
        ),
      );
    }
    
    // Read-only percentage display
    String percentText;
    if (config.fixedPercent != null) {
      percentText = '${config.fixedPercent!.toStringAsFixed(1)}%';
    } else if (config.useGoalPercent) {
      final goalPercent = PnlCalculationService.getGoalPercentage(_lineItems);
      percentText = '${_percentFormat.format(goalPercent)}%';
    } else if (config.useSalesPercent) {
      // SALES (ALL NET) % = NON-PRODUCT SALES % + 100% (PRODUCT NET SALES)
      final salesPercent = _getNonProductSalesPercent() + 100.0;
      percentText = '${_percentFormat.format(salesPercent)}%';
    } else {
      percentText = '${_percentFormat.format(PnlCalculationService.calculatePercentage(item.value, productNetSales))}%';
    }
    
    final isBoldRow = _yellowRows.contains(item.label) || _cyanRows.contains(item.label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          percentText,
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: isBoldRow ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _buildCommentCell(PnlLineItem item, bool isDark) {
    final commentField = TextField(
      controller: _commentControllers[item.id],
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onChanged: (v) => _onCommentChanged(item, v),
    );

    // LABOR - CREW shows avg wage badge (and Auto badge when enabled)
    if (item.label == 'LABOR - CREW') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(child: commentField),
            const SizedBox(width: 8),
            if (_autoLaborEnabled) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AUTO',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Avg Wage: ${_currencyFormat.format(_currentPeriod?.avgWage ?? 0)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: commentField,
    );
  }

  Widget _buildActionCell(PnlLineItem item) {
    if (item.isUserAdded) {
      return IconButton(
        onPressed: () => _removeControllableRow(item),
        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
        tooltip: 'Remove',
      );
    }
    if (item.label == 'CONTROLLABLES') {
      return IconButton(
        onPressed: _addControllableRow,
        icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
        tooltip: 'Add Line Item',
      );
    }
    return const SizedBox();
  }
}

// Dialog for selecting a period
class _PeriodSelectorDialog extends StatefulWidget {
  final List<PnlPeriod> periods;
  final PnlPeriod? currentPeriod;
  final Future<PnlPeriod?> Function(int month, int year) onCreateNew;
  final Future<void> Function(PnlPeriod period) onDelete;

  const _PeriodSelectorDialog({
    required this.periods,
    required this.currentPeriod,
    required this.onCreateNew,
    required this.onDelete,
  });

  @override
  State<_PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<_PeriodSelectorDialog> {
  int _newMonth = DateTime.now().month;
  int _newYear = DateTime.now().year;
  late List<PnlPeriod> _periods;

  @override
  void initState() {
    super.initState();
    _periods = List.from(widget.periods);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Period'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Existing periods
            if (_periods.isNotEmpty) ...[
              const Text('Existing Periods:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _periods.length,
                  itemBuilder: (context, index) {
                    final period = _periods[index];
                    final isSelected = period.id == widget.currentPeriod?.id;
                    return ListTile(
                      title: Text(period.periodDisplay),
                      selected: isSelected,
                      onTap: () => Navigator.pop(context, period),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Delete period',
                        onPressed: () => _confirmDelete(period),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
            ],

            // Create new period
            const Text('Create New Period:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _newMonth,
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(12, (i) {
                      final month = i + 1;
                      const months = [
                        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                      ];
                      return DropdownMenuItem(value: month, child: Text(months[i]));
                    }),
                    onChanged: (v) => setState(() => _newMonth = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _newYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(5, (i) {
                      final year = DateTime.now().year - 2 + i;
                      return DropdownMenuItem(value: year, child: Text('$year'));
                    }),
                    onChanged: (v) => setState(() => _newYear = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final newPeriod = await widget.onCreateNew(_newMonth, _newYear);
                  if (newPeriod != null && context.mounted) {
                    Navigator.pop(context, newPeriod);
                  }
                },
                child: const Text('Create'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(PnlPeriod period) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Period'),
        content: Text('Are you sure you want to delete ${period.periodDisplay}? This will delete all P&L data for this period.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.onDelete(period);
      setState(() {
        _periods.removeWhere((p) => p.id == period.id);
      });
      
      // If the deleted period was the current period, close dialog with null
      if (period.id == widget.currentPeriod?.id && mounted) {
        Navigator.pop(context, null);
      }
    }
  }
}

// Dialog for copying from previous period
class _CopyFromPreviousDialog extends StatefulWidget {
  final List<PnlPeriod> periods;
  final PnlDao dao;

  const _CopyFromPreviousDialog({required this.periods, required this.dao});

  @override
  State<_CopyFromPreviousDialog> createState() => _CopyFromPreviousDialogState();
}

class _CopyFromPreviousDialogState extends State<_CopyFromPreviousDialog> {
  PnlPeriod? _selectedPeriod;
  List<PnlLineItem> _items = [];
  final Set<int> _selectedIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.periods.isNotEmpty) {
      _selectedPeriod = widget.periods.first;
      _loadItems();
    }
  }

  Future<void> _loadItems() async {
    if (_selectedPeriod == null) return;
    setState(() => _isLoading = true);
    _items = await widget.dao.getLineItemsForPeriod(_selectedPeriod!.id!);
    // Only show non-calculated items
    _items = _items.where((i) => !i.isCalculated).toList();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy from Previous Period'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period selector
            DropdownButtonFormField<PnlPeriod>(
              initialValue: _selectedPeriod,
              decoration: const InputDecoration(
                labelText: 'Copy from',
                border: OutlineInputBorder(),
              ),
              items: widget.periods.map((p) {
                return DropdownMenuItem(value: p, child: Text(p.periodDisplay));
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedPeriod = v;
                  _selectedIds.clear();
                });
                _loadItems();
              },
            ),
            const SizedBox(height: 16),

            // Select all / none buttons
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedIds.addAll(_items.map((i) => i.id!));
                  }),
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIds.clear()),
                  child: const Text('Select None'),
                ),
              ],
            ),

            // Items list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return CheckboxListTile(
                          title: Text(item.label),
                          subtitle: Text(
                            '\$${item.value.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: _selectedIds.contains(item.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(item.id!);
                              } else {
                                _selectedIds.remove(item.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CopyResult(
                      fromPeriod: _selectedPeriod!,
                      selectedItemIds: _selectedIds.toList(),
                    ),
                  ),
          child: Text('Copy ${_selectedIds.length} Items'),
        ),
      ],
    );
  }
}

class _CopyResult {
  final PnlPeriod fromPeriod;
  final List<int> selectedItemIds;

  _CopyResult({required this.fromPeriod, required this.selectedItemIds});
}

// Dialog for adding a new line item
class _AddLineItemDialog extends StatefulWidget {
  @override
  State<_AddLineItemDialog> createState() => _AddLineItemDialogState();
}

class _AddLineItemDialogState extends State<_AddLineItemDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Line Item'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Label',
          hintText: 'e.g., MISCELLANEOUS',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.characters,
        autofocus: true,
        onSubmitted: (v) {
          if (v.isNotEmpty) Navigator.pop(context, v.toUpperCase());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _controller.text.trim().toUpperCase();
            if (label.isNotEmpty) Navigator.pop(context, label);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
