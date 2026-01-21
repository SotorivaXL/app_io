import 'package:flutter/material.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/usecases/board_use_cases.dart';
import 'package:clean_kanban/domain/usecases/task_use_cases.dart';
import 'package:clean_kanban/injection_container.dart';
import 'package:clean_kanban/core/result.dart';

/// Provider class that manages the state of a Kanban board.
///
/// Handles all board-related operations including loading, saving, and updating
/// the board state, as well as managing tasks within columns.
class BoardProvider extends ChangeNotifier {
  /// The current board instance being managed.
  Board? board;

  final GetBoardUseCase _getBoardUseCase = getIt<GetBoardUseCase>();
  final SaveBoardUseCase _saveBoardUseCase = getIt<SaveBoardUseCase>();
  final UpdateBoardUseCase _updateBoardUseCase = getIt<UpdateBoardUseCase>();
  final AddTaskUseCase _addTaskUseCase = getIt<AddTaskUseCase>();
  final DeleteTaskUseCase _deleteTaskUseCase = getIt<DeleteTaskUseCase>();
  final MoveTaskUseCase _moveTaskUseCase = getIt<MoveTaskUseCase>();
  final ReorderTaskUseCase _reorderTaskUseCase = getIt<ReorderTaskUseCase>();
  final DeleteDoneTaskUseCase _deleteDoneTaskUseCase = getIt<DeleteDoneTaskUseCase>();
  final ClearDoneColumnUseCase _clearDoneColumnUseCase = getIt<ClearDoneColumnUseCase>();
  final EditTaskUseCase _editTaskUseCase = getIt<EditTaskUseCase>();
  final UpdateColumnLimitUseCase _updateColumnLimitUseCase = getIt<UpdateColumnLimitUseCase>();

  /// Loads the board from storage or creates a new one.
  ///
  /// If [config] is provided, creates a board from the configuration.
  /// Otherwise, attempts to load a saved board or creates a simple board.
  Future<void> loadBoard({Map<String, dynamic>? config}) async {
    try {
      final fetchedBoard = await _getBoardUseCase.execute();
      board = fetchedBoard;
      debugPrint('Previous saved board found');
    } catch (e) {
      board = config != null ? Board.fromConfig(config) : Board.simple();
      await _saveBoardUseCase.execute(board!);
      debugPrint(
          'Error: $e, No previous saved board found, created a new one.');
    }
    notifyListeners();
  }

  /// Adds a new task to the specified column.
  ///
  /// [columnId] is the ID of the target column.
  /// [task] is the task to be added.
  void addTask(String columnId, Task task) {
    final col = _findColumn(columnId);
    if (col != null) {
      _addTaskUseCase.execute(col, task);
      notifyListeners();
    }
  }

  /// Removes a task from the specified column.
  ///
  /// [columnId] is the ID of the column containing the task.
  /// [index] is the position of the task in the column.
  ///
  /// Returns a [Result] containing the removed task or an error message.
  Result<Task> removeTask(String columnId, int index) {
    final col = _findColumn(columnId);
    if (col != null) {
      final result = _deleteTaskUseCase.execute(col, index);
      notifyListeners();
      return result;
    }
    return Failure('Column not found');
  }

  /// Moves a task between columns.
  ///
  /// [sourceColId] is the ID of the source column.
  /// [sourceIndex] is the task's current position.
  /// [destColId] is the ID of the destination column.
  /// [destinationIndex] is the optional target position.
  void moveTask(String sourceColId, int sourceIndex, String destColId, [int? destinationIndex]) {
    final source = _findColumn(sourceColId);
    final destination = _findColumn(destColId);
    if (source != null && destination != null) {
      _moveTaskUseCase.execute(source, sourceIndex, destination, destinationIndex);
      notifyListeners();
    }
  }

  /// Reorders a task within its column.
  ///
  /// [columnId] is the ID of the column.
  /// [oldIndex] is the task's current position.
  /// [newIndex] is the target position.
  void reorderTask(String columnId, int oldIndex, int newIndex) {
    final col = _findColumn(columnId);
    if (col != null) {
      _reorderTaskUseCase.execute(col, oldIndex, newIndex);
      notifyListeners();
    }
  }

  /// Deletes a task from the Done column.
  ///
  /// [columnId] must be the ID of the Done column.
  /// [index] is the position of the task to delete.
  ///
  /// Returns a [Result] containing the deleted task or an error message.
  Result<Task> deleteDoneTask(String columnId, int index) {
    final column = _findColumn(columnId);
    if (column != null) {
      final result = _deleteDoneTaskUseCase.execute(column, index);
      notifyListeners();
      return result;
    }
    return Failure('Column not found');
  }

  /// Clears all tasks from the Done column.
  ///
  /// [columnId] must be the ID of the Done column.
  ///
  /// Returns a [Result] containing the list of removed tasks or an error message.
  Result<List<Task>> clearDoneColumn(String columnId) {
    final column = _findColumn(columnId);
    if (column != null) {
      final result = _clearDoneColumnUseCase.execute(column);
      notifyListeners();
      return result;
    }
    return Failure('Column not found');
  }

  /// Edits an existing task in the specified column.
  ///
  /// [columnId] is the ID of the column containing the task.
  /// [index] is the position of the task to edit.
  /// [newTitle] is the updated title for the task.
  /// [newSubtitle] is the updated subtitle for the task.
  ///
  /// Returns a [Result] containing the updated task or an error message.
  Result<Task> editTask(String columnId, int index, String newTitle, String newSubtitle) {
    final column = _findColumn(columnId);
    if (column != null) {
      final result = _editTaskUseCase.execute(column, index, newTitle, newSubtitle);
      notifyListeners();
      return result;
    }
    return Failure('Column not found');
  }

  /// Updates the task limit for a specific column.
  ///
  /// [columnId] is the ID of the column to update.
  /// [newLimit] is the new task limit (null for unlimited).
  Future<void> updateColumnLimit(String columnId, int? newLimit) async {
    final column = _findColumn(columnId);
    if (board != null && column != null) {
      await _updateColumnLimitUseCase.execute(board!, column, newLimit);
      notifyListeners();
    }
  }

  /// Saves the current board state to storage.
  ///
  /// Does nothing if no board is currently loaded.
  Future<void> saveBoard() async {
    if (board != null) {
      await _saveBoardUseCase.execute(board!);
    }
  }

  /// Updates the current board state in storage.
  ///
  /// Does nothing if no board is currently loaded.
  Future<void> updateBoard() async {
    if (board != null) {
      await _updateBoardUseCase.execute(board!);
    }
  }
  
  KanbanColumn? _findColumn(String columnId) {
    return board?.columns.firstWhere((c) => c.id == columnId);
  }
}
