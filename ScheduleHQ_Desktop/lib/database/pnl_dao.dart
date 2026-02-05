import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import '../models/pnl_entry.dart';

class PnlDao {
  Future<Database> get _db async => AppDatabase.instance.db;

  // ------------------------------------------------------------
  // PERIODS
  // ------------------------------------------------------------

  /// Get all P&L periods, ordered by most recent first
  Future<List<PnlPeriod>> getAllPeriods() async {
    final db = await _db;
    final result = await db.query(
      'pnl_periods',
      orderBy: 'year DESC, month DESC',
    );
    return result.map((row) => PnlPeriod.fromMap(row)).toList();
  }

  /// Get a specific period by month and year
  Future<PnlPeriod?> getPeriodByMonthYear(int month, int year) async {
    final db = await _db;
    final result = await db.query(
      'pnl_periods',
      where: 'month = ? AND year = ?',
      whereArgs: [month, year],
    );
    if (result.isEmpty) return null;
    return PnlPeriod.fromMap(result.first);
  }

  /// Get a period by ID
  Future<PnlPeriod?> getPeriodById(int id) async {
    final db = await _db;
    final result = await db.query(
      'pnl_periods',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return PnlPeriod.fromMap(result.first);
  }

  /// Insert a new period and seed with default line items
  Future<int> insertPeriod(PnlPeriod period) async {
    final db = await _db;
    final periodId = await db.insert('pnl_periods', {
      'month': period.month,
      'year': period.year,
      'avgWage': period.avgWage,
    });

    // Seed with default line items
    final defaultItems = PnlDefaults.createDefaultItems(periodId);
    for (final item in defaultItems) {
      await db.insert('pnl_line_items', item.toMap()..remove('id'));
    }

    return periodId;
  }

  /// Update a period (mainly for avgWage)
  Future<void> updatePeriod(PnlPeriod period) async {
    if (period.id == null) return;
    final db = await _db;
    await db.update(
      'pnl_periods',
      period.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [period.id],
    );
  }

  /// Delete a period and all its line items (cascade)
  Future<void> deletePeriod(int periodId) async {
    final db = await _db;
    await db.delete('pnl_line_items', where: 'periodId = ?', whereArgs: [periodId]);
    await db.delete('pnl_periods', where: 'id = ?', whereArgs: [periodId]);
  }

  // ------------------------------------------------------------
  // LINE ITEMS
  // ------------------------------------------------------------

  /// Get all line items for a period, ordered by sortOrder
  Future<List<PnlLineItem>> getLineItemsForPeriod(int periodId) async {
    final db = await _db;
    final result = await db.query(
      'pnl_line_items',
      where: 'periodId = ?',
      whereArgs: [periodId],
      orderBy: 'sortOrder ASC',
    );
    return result.map((row) => PnlLineItem.fromMap(row)).toList();
  }

  /// Get a single line item by ID
  Future<PnlLineItem?> getLineItemById(int id) async {
    final db = await _db;
    final result = await db.query(
      'pnl_line_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return PnlLineItem.fromMap(result.first);
  }

  /// Insert a new line item (for user-added controllables)
  Future<int> insertLineItem(PnlLineItem item) async {
    final db = await _db;
    return await db.insert('pnl_line_items', item.toMap()..remove('id'));
  }

  /// Update a line item (value, comment, label)
  Future<void> updateLineItem(PnlLineItem item) async {
    if (item.id == null) return;
    final db = await _db;
    await db.update(
      'pnl_line_items',
      item.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Delete a line item (only user-added items should be deletable)
  Future<void> deleteLineItem(int id) async {
    final db = await _db;
    await db.delete('pnl_line_items', where: 'id = ?', whereArgs: [id]);
  }

  /// Batch update all line items for a period
  Future<void> updateAllLineItems(List<PnlLineItem> items) async {
    final db = await _db;
    final batch = db.batch();
    for (final item in items) {
      if (item.id != null) {
        batch.update(
          'pnl_line_items',
          item.toMap()..remove('id'),
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------
  // COPY FROM PREVIOUS PERIOD
  // ------------------------------------------------------------

  /// Copy selected line items from one period to another
  /// [itemIds] - list of line item IDs to copy (from source period)
  Future<void> copySelectLinesFromPeriod({
    required int fromPeriodId,
    required int toPeriodId,
    required List<int> itemIds,
  }) async {
    final db = await _db;

    // Get the items to copy
    final sourceItems = await getLineItemsForPeriod(fromPeriodId);
    final targetItems = await getLineItemsForPeriod(toPeriodId);

    // Filter to only the selected IDs
    final itemsToCopy = sourceItems.where((item) => itemIds.contains(item.id)).toList();

    for (final sourceItem in itemsToCopy) {
      // Find matching target item by label
      final targetItem = targetItems.firstWhere(
        (t) => t.label == sourceItem.label,
        orElse: () => PnlLineItem(
          periodId: toPeriodId,
          label: sourceItem.label,
          sortOrder: sourceItem.sortOrder,
          category: sourceItem.category,
          isUserAdded: sourceItem.isUserAdded,
        ),
      );

      if (targetItem.id != null) {
        // Update existing item
        await updateLineItem(targetItem.copyWith(
          value: sourceItem.value,
          comment: sourceItem.comment,
        ));
      } else {
        // Insert as new item (for user-added controllables that don't exist in target)
        await insertLineItem(targetItem.copyWith(
          value: sourceItem.value,
          comment: sourceItem.comment,
        ));
      }
    }
  }

  // ------------------------------------------------------------
  // ADD USER CONTROLLABLE LINE ITEM
  // ------------------------------------------------------------

  /// Add a new user controllable line item
  /// Inserts before the CONTROLLABLES total row
  Future<int> addUserControllableItem(int periodId, String label) async {
    final db = await _db;

    // Get current max sortOrder in controllables (before CONTROLLABLES total)
    final items = await getLineItemsForPeriod(periodId);
    final controllablesTotal = items.firstWhere(
      (item) => item.label == 'CONTROLLABLES' && item.isCalculated,
    );

    // New item goes just before CONTROLLABLES total
    final newSortOrder = controllablesTotal.sortOrder;

    // Shift CONTROLLABLES, P.A.C., and GOAL down
    await db.rawUpdate('''
      UPDATE pnl_line_items 
      SET sortOrder = sortOrder + 1 
      WHERE periodId = ? AND sortOrder >= ?
    ''', [periodId, newSortOrder]);

    // Insert the new item
    return await insertLineItem(PnlLineItem(
      periodId: periodId,
      label: label,
      category: PnlCategory.controllables,
      isCalculated: false,
      isUserAdded: true,
      sortOrder: newSortOrder,
    ));
  }

  /// Remove a user-added controllable line item and reorder remaining items
  Future<void> removeUserControllableItem(int itemId) async {
    final db = await _db;

    // Get the item to delete
    final item = await getLineItemById(itemId);
    if (item == null || !item.isUserAdded) return;

    // Delete the item
    await deleteLineItem(itemId);

    // Shift items after it back up
    await db.rawUpdate('''
      UPDATE pnl_line_items 
      SET sortOrder = sortOrder - 1 
      WHERE periodId = ? AND sortOrder > ?
    ''', [item.periodId, item.sortOrder]);
  }

  // ------------------------------------------------------------
  // UTILITY
  // ------------------------------------------------------------

  /// Get or create period for a given month/year
  Future<PnlPeriod> getOrCreatePeriod(int month, int year) async {
    var period = await getPeriodByMonthYear(month, year);
    if (period == null) {
      final id = await insertPeriod(PnlPeriod(month: month, year: year));
      period = await getPeriodById(id);
    }
    return period!;
  }
}
