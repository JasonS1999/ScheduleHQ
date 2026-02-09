import 'package:flutter/scheduler.dart';
import '../models/shift.dart';
import '../models/schedule_note.dart';
import '../models/shift_runner.dart';

/// Base class for undoable schedule actions
abstract class ScheduleAction {
  String get description;
  Future<void> execute();
  Future<void> undo();
}

/// Action for creating a shift
class CreateShiftAction extends ScheduleAction {
  final Shift shift;
  final Future<int> Function(Shift) insertFn;
  final Future<void> Function(int) deleteFn;
  int? _insertedId;
  
  CreateShiftAction({
    required this.shift,
    required this.insertFn,
    required this.deleteFn,
  });
  
  @override
  String get description => 'Create shift';
  
  @override
  Future<void> execute() async {
    _insertedId = await insertFn(shift);
  }
  
  @override
  Future<void> undo() async {
    if (_insertedId != null) {
      await deleteFn(_insertedId!);
    }
  }
}

/// Action for updating a shift
class UpdateShiftAction extends ScheduleAction {
  final Shift oldShift;
  final Shift newShift;
  final Future<void> Function(Shift) updateFn;
  
  UpdateShiftAction({
    required this.oldShift,
    required this.newShift,
    required this.updateFn,
  });
  
  @override
  String get description => 'Update shift';
  
  @override
  Future<void> execute() async {
    await updateFn(newShift);
  }
  
  @override
  Future<void> undo() async {
    await updateFn(oldShift);
  }
}

/// Action for deleting a shift
class DeleteShiftAction extends ScheduleAction {
  final Shift shift;
  final Future<int> Function(Shift) insertFn;
  final Future<void> Function(int) deleteFn;
  final ShiftRunner? deletedRunner;
  final Future<void> Function(ShiftRunner)? upsertRunnerFn;
  final Future<void> Function(DateTime, String)? deleteRunnerFn;
  
  DeleteShiftAction({
    required this.shift,
    required this.insertFn,
    required this.deleteFn,
    this.deletedRunner,
    this.upsertRunnerFn,
    this.deleteRunnerFn,
  });
  
  @override
  String get description => 'Delete shift';
  
  @override
  Future<void> execute() async {
    await deleteFn(shift.id!);
    // Also delete the runner if one was assigned
    if (deletedRunner != null && deleteRunnerFn != null) {
      await deleteRunnerFn!(deletedRunner!.date, deletedRunner!.shiftType);
    }
  }
  
  @override
  Future<void> undo() async {
    await insertFn(shift);
    // Restore the runner if one was deleted
    if (deletedRunner != null && upsertRunnerFn != null) {
      await upsertRunnerFn!(deletedRunner!);
    }
  }
}

/// Action for moving a shift (change employee or date)
class MoveShiftAction extends ScheduleAction {
  final Shift oldShift;
  final Shift newShift;
  final Future<void> Function(Shift) updateFn;
  
  MoveShiftAction({
    required this.oldShift,
    required this.newShift,
    required this.updateFn,
  });
  
  @override
  String get description => 'Move shift';
  
  @override
  Future<void> execute() async {
    await updateFn(newShift);
  }
  
  @override
  Future<void> undo() async {
    await updateFn(oldShift);
  }
}

/// Action for batch operations (copy week, auto-fill, clear week)
/// Note: Batch undo is complex and currently not implemented
/// Individual shift operations use the simpler action classes above
class BatchShiftAction extends ScheduleAction {
  final List<Shift> createdShifts;
  final List<Shift> deletedShifts;
  final String actionDescription;
  final Future<void> Function(List<Shift>) insertAllFn;
  final Future<void> Function(List<int>) deleteAllFn;
  
  BatchShiftAction({
    required this.createdShifts,
    required this.deletedShifts,
    required this.actionDescription,
    required this.insertAllFn,
    required this.deleteAllFn,
  });
  
  @override
  String get description => actionDescription;
  
  @override
  Future<void> execute() async {
    // Delete shifts first
    if (deletedShifts.isNotEmpty) {
      await deleteAllFn(deletedShifts.map((s) => s.id!).toList());
    }
    // Then insert new shifts
    if (createdShifts.isNotEmpty) {
      await insertAllFn(createdShifts);
    }
  }
  
  @override
  Future<void> undo() async {
    // Re-insert deleted shifts
    if (deletedShifts.isNotEmpty) {
      await insertAllFn(deletedShifts);
    }
    // Note: Cannot easily delete created shifts without tracking their IDs
    // This is a limitation of batch undo
  }
}

/// Action for saving/deleting a note
class NoteAction extends ScheduleAction {
  final ScheduleNote? oldNote;
  final ScheduleNote? newNote;
  final Future<void> Function(ScheduleNote) upsertFn;
  final Future<void> Function(DateTime) deleteFn;
  
  NoteAction({
    this.oldNote,
    this.newNote,
    required this.upsertFn,
    required this.deleteFn,
  });
  
  @override
  String get description => newNote == null ? 'Delete note' : (oldNote == null ? 'Add note' : 'Update note');
  
  @override
  Future<void> execute() async {
    if (newNote != null) {
      await upsertFn(newNote!);
    } else if (oldNote != null) {
      await deleteFn(oldNote!.date);
    }
  }
  
  @override
  Future<void> undo() async {
    if (oldNote != null) {
      await upsertFn(oldNote!);
    } else if (newNote != null) {
      await deleteFn(newNote!.date);
    }
  }
}

/// Manages undo/redo stack for schedule operations
class ScheduleUndoManager {
  static final ScheduleUndoManager _instance = ScheduleUndoManager._internal();
  factory ScheduleUndoManager() => _instance;
  ScheduleUndoManager._internal();
  
  final List<ScheduleAction> _undoStack = [];
  final List<ScheduleAction> _redoStack = [];
  static const int _maxStackSize = 50;
  
  // Listeners for UI updates
  final List<Function()> _listeners = [];
  
  void addListener(Function() listener) {
    _listeners.add(listener);
  }
  
  void removeListener(Function() listener) {
    _listeners.remove(listener);
  }
  
  bool _notifyScheduled = false;

  void _notifyListeners() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      for (final listener in _listeners) {
        listener();
      }
      return;
    }
    // Mid-frame: defer to post-frame callback to avoid parentDataDirty.
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        for (final listener in _listeners) {
          listener();
        }
      });
    }
  }
  
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  
  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;
  
  /// Execute an action and add it to the undo stack
  Future<void> executeAction(ScheduleAction action) async {
    await action.execute();
    _undoStack.add(action);
    _redoStack.clear(); // Clear redo stack when new action is performed
    
    // Limit stack size
    while (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    
    _notifyListeners();
  }
  
  /// Undo the last action
  Future<void> undo() async {
    if (!canUndo) return;
    
    final action = _undoStack.removeLast();
    await action.undo();
    _redoStack.add(action);
    
    _notifyListeners();
  }
  
  /// Redo the last undone action
  Future<void> redo() async {
    if (!canRedo) return;
    
    final action = _redoStack.removeLast();
    await action.execute();
    _undoStack.add(action);
    
    _notifyListeners();
  }
  
  /// Clear all undo/redo history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _notifyListeners();
  }
  
  /// Get counts for debugging
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;
}
