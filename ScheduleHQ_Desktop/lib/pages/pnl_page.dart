import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/pnl_dao.dart';
import '../models/pnl_entry.dart';
import '../models/store_hours.dart';
import '../services/pnl_calculation_service.dart';
import '../services/pnl_pdf_service.dart';

class PnlPage extends StatefulWidget {
  const PnlPage({super.key});

  @override
  State<PnlPage> createState() => _PnlPageState();
}

class _PnlPageState extends State<PnlPage> {
  final PnlDao _dao = PnlDao();
  final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _percentFormat = NumberFormat('0.0', 'en_US');

  PnlPeriod? _currentPeriod;
  List<PnlLineItem> _lineItems = [];
  List<PnlPeriod> _allPeriods = [];
  bool _isLoading = true;
  bool _hasChanges = false;

  // Text controllers for avgWage
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

    // Update avgWage controller
    _avgWageController.text = _currentPeriod!.avgWage > 0 
        ? _currentPeriod!.avgWage.toStringAsFixed(2) 
        : '';

    // Clear and rebuild controllers
    _valueControllers.clear();
    _percentControllers.clear();
    _commentControllers.clear();

    final productNetSales = _getProductNetSales();

    for (final item in _lineItems) {
      if (item.id != null) {
        _valueControllers[item.id!] = TextEditingController(
          text: item.value != 0 ? item.value.toStringAsFixed(2) : '',
        );
        // SALES (ALL NET) always shows 100%
        final percentText = item.label == 'SALES (ALL NET)'
            ? '100.0'
            : (item.value != 0 
                ? PnlCalculationService.calculatePercentage(item.value, productNetSales).toStringAsFixed(1)
                : '');
        _percentControllers[item.id!] = TextEditingController(text: percentText);
        _commentControllers[item.id!] = TextEditingController(text: item.comment);
      }
    }

    _hasChanges = false;
  }

  double _getProductNetSales() {
    final item = _lineItems.firstWhere(
      (i) => i.label == 'PRODUCT NET SALES',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    return item.value;
  }

  void _onValueChanged(PnlLineItem item, String newValue) {
    final value = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
    
    // Update item value
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(value: value);
      
      // Recalculate all
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);
      
      // Update percentage field (SALES (ALL NET) always stays 100%)
      if (item.label == 'SALES (ALL NET)') {
        _percentControllers[item.id!]?.text = '100.0';
      } else {
        final productNetSales = _getProductNetSales();
        final percent = PnlCalculationService.calculatePercentage(value, productNetSales);
        _percentControllers[item.id!]?.text = percent.toStringAsFixed(1);
      }

      // Update all calculated rows' controllers
      _updateCalculatedRowControllers();

      setState(() => _hasChanges = true);
    }
  }

  void _onPercentChanged(PnlLineItem item, String newPercent) {
    final percent = double.tryParse(newPercent) ?? 0;
    final productNetSales = _getProductNetSales();
    final value = PnlCalculationService.calculateValueFromPercentage(percent, productNetSales);

    // Update item value
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(value: value);

      // Recalculate all
      _lineItems = PnlCalculationService.recalculateAll(_lineItems);

      // Update value field
      _valueControllers[item.id!]?.text = value.toStringAsFixed(2);

      // Update all calculated rows' controllers
      _updateCalculatedRowControllers();

      setState(() => _hasChanges = true);
    }
  }

  void _updateCalculatedRowControllers() {
    final productNetSales = _getProductNetSales();
    
    for (final item in _lineItems) {
      if (item.isCalculated && item.id != null) {
        _valueControllers[item.id!]?.text = item.value.toStringAsFixed(2);
        // SALES (ALL NET) always shows 100%
        final percent = item.label == 'SALES (ALL NET)'
            ? 100.0
            : PnlCalculationService.calculatePercentage(item.value, productNetSales);
        _percentControllers[item.id!]?.text = percent.toStringAsFixed(1);
      }
    }
    
    // Also update SALES (ALL NET) percentage if it exists (it's an input row but % is always 100%)
    final salesAllNetItem = _lineItems.firstWhere(
      (i) => i.label == 'SALES (ALL NET)',
      orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
    );
    if (salesAllNetItem.id != null) {
      _percentControllers[salesAllNetItem.id!]?.text = '100.0';
    }
  }

  void _onCommentChanged(PnlLineItem item, String newComment) {
    final index = _lineItems.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _lineItems[index] = _lineItems[index].copyWith(comment: newComment);
      setState(() => _hasChanges = true);
    }
  }

  void _onAvgWageChanged(String value) {
    final wage = double.tryParse(value) ?? 0;
    _currentPeriod = _currentPeriod?.copyWith(avgWage: wage);
    setState(() => _hasChanges = true);
  }

  Future<void> _save() async {
    if (_currentPeriod == null) return;

    // Save period (avgWage)
    await _dao.updatePeriod(_currentPeriod!);

    // Save all line items
    await _dao.updateAllLineItems(_lineItems);

    // Refresh periods list
    _allPeriods = await _dao.getAllPeriods();

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('P&L saved successfully')),
      );
    }
  }

  Future<void> _selectPeriod() async {
    final result = await showDialog<PnlPeriod>(
      context: context,
      builder: (context) => _PeriodSelectorDialog(
        periods: _allPeriods,
        currentPeriod: _currentPeriod,
        onCreateNew: _createNewPeriod,
      ),
    );

    if (result != null && result.id != _currentPeriod?.id) {
      setState(() => _isLoading = true);
      _currentPeriod = result;
      await _loadPeriodData();
      setState(() => _isLoading = false);
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
    // Color coding matching Excel
    if (item.label == 'P.A.C.') {
      return isDark ? Colors.cyan.shade900 : Colors.cyan.shade100;
    }
    if (item.isCalculated) {
      return isDark ? Colors.yellow.shade900.withValues(alpha: 0.3) : Colors.yellow.shade100;
    }
    if (item.category == PnlCategory.sales && item.label != 'SALES (ALL NET)') {
      return isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50;
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
          ],
        ),
        actions: [
          // Period selector
          TextButton.icon(
            onPressed: _selectPeriod,
            icon: const Icon(Icons.calendar_month),
            label: Text(_currentPeriod?.periodDisplay ?? 'Select Period'),
          ),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          // Save button
          FilledButton.icon(
            onPressed: _hasChanges ? _save : null,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
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
                const SizedBox(width: 24),
                // Goal display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blue.shade900 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Text(
                    'GOAL: ${_percentFormat.format(goalPercent)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
    final rowColor = _getRowColor(item, isDark);
    final isGoalRow = item.label == 'GOAL';
    final goalPercent = isGoalRow ? PnlCalculationService.getGoalPercentage(_lineItems) : null;

    // Check if this is a section break (before certain rows)
    final needsTopBorder = [
      'FOOD COST',
      'LABOR - MANAGEMENT',
      'PAYROLL TAXES',
      'P.A.C.',
    ].contains(item.label);

    return TableRow(
      decoration: BoxDecoration(
        color: rowColor,
        border: needsTopBorder
            ? Border(top: BorderSide(color: isDark ? Colors.grey.shade500 : Colors.grey.shade500, width: 2))
            : null,
      ),
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            item.label,
            style: TextStyle(
              fontWeight: item.isCalculated ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),

        // Projected $ - editable for input rows, read-only for calculated
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: item.isCalculated
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _currencyFormat.format(item.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
              : TextField(
                  controller: _valueControllers[item.id],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  onChanged: (v) => _onValueChanged(item, v),
                ),
        ),

        // Projected % - read-only for calculated rows and SALES (ALL NET) (always 100%)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: (item.isCalculated || item.label == 'SALES (ALL NET)')
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    item.label == 'SALES (ALL NET)'
                        ? '100.0%'
                        : (isGoalRow 
                            ? '${_percentFormat.format(goalPercent)}%'
                            : '${_percentFormat.format(PnlCalculationService.calculatePercentage(item.value, productNetSales))}%'),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: item.isCalculated ? FontWeight.bold : FontWeight.normal),
                  ),
                )
              : TextField(
                  controller: _percentControllers[item.id],
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (v) => _onPercentChanged(item, v),
                ),
        ),

        // Comments
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: item.label == 'LABOR - CREW'
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentControllers[item.id],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        onChanged: (v) => _onCommentChanged(item, v),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                )
              : TextField(
                  controller: _commentControllers[item.id],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (v) => _onCommentChanged(item, v),
                ),
        ),

        // Actions
        item.isUserAdded
            ? IconButton(
                onPressed: () => _removeControllableRow(item),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                tooltip: 'Remove',
              )
            : item.label == 'CONTROLLABLES'
                ? IconButton(
                    onPressed: _addControllableRow,
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                    tooltip: 'Add Line Item',
                  )
                : const SizedBox(),
      ],
    );
  }
}

// Dialog for selecting a period
class _PeriodSelectorDialog extends StatefulWidget {
  final List<PnlPeriod> periods;
  final PnlPeriod? currentPeriod;
  final Future<PnlPeriod?> Function(int month, int year) onCreateNew;

  const _PeriodSelectorDialog({
    required this.periods,
    required this.currentPeriod,
    required this.onCreateNew,
  });

  @override
  State<_PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<_PeriodSelectorDialog> {
  int _newMonth = DateTime.now().month;
  int _newYear = DateTime.now().year;

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
            if (widget.periods.isNotEmpty) ...[
              const Text('Existing Periods:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.periods.length,
                  itemBuilder: (context, index) {
                    final period = widget.periods[index];
                    final isSelected = period.id == widget.currentPeriod?.id;
                    return ListTile(
                      title: Text(period.periodDisplay),
                      selected: isSelected,
                      onTap: () => Navigator.pop(context, period),
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
