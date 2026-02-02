import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/repositories/board_repository.dart';
import 'package:clean_kanban/domain/events/event_notifier.dart';
import 'package:clean_kanban/domain/events/board_events.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/core/exceptions.dart';

/// Use case for retrieving the Kanban board from storage.
///
/// Notifies listeners with a [BoardLoadedEvent] when the board is successfully loaded.
class GetBoardUseCase {
  /// The repository used to access board data.
  final BoardRepository repository;

  /// Creates a new [GetBoardUseCase] with the given [repository].
  GetBoardUseCase(this.repository);

  /// Retrieves the board from storage and notifies listeners.
  ///
  /// Returns a [Future] that completes with the loaded [Board].
  Future<Board> execute() async {
    final board = await repository.getBoard();
    EventNotifier().notify(BoardLoadedEvent(board));
    return board;
  }
}

/// Use case for saving a new Kanban board to storage.
///
/// Notifies listeners with a [BoardSavedEvent] when the board is successfully saved.
class SaveBoardUseCase {
  /// The repository used to save board data.
  final BoardRepository repository;

  /// Creates a new [SaveBoardUseCase] with the given [repository].
  SaveBoardUseCase(this.repository);

  /// Saves the given [board] to storage and notifies listeners.
  Future<void> execute(Board board) async {
    await repository.saveBoard(board);
    EventNotifier().notify(BoardSavedEvent(board));
  }
}

/// Use case for updating an existing Kanban board in storage.
///
/// Notifies listeners with a [BoardSavedEvent] when the board is successfully updated.
class UpdateBoardUseCase {
  /// The repository used to update board data.
  final BoardRepository repository;

  /// Creates a new [UpdateBoardUseCase] with the given [repository].
  UpdateBoardUseCase(this.repository);

  /// Updates the given [board] in storage and notifies listeners.
  Future<void> execute(Board board) async {
    await repository.updateBoard(board);
    EventNotifier().notify(BoardSavedEvent(board));
  }
}

/// Use case responsible for updating a column's task limit in a Kanban board.
///
/// This use case interfaces with the [BoardRepository] to persist changes
/// and notifies listeners via [EventNotifier] when a column's task limit
/// has been updated.
class UpdateColumnLimitUseCase {
  /// Repository responsible for board-related data operations.
  /// 
  /// This repository provides methods to create, read, update, and delete
  /// board entities from the data source.
  final BoardRepository repository;

  /// Updates the maximum number of items (limit) for a specific column in a kanban board.
  ///
  /// This use case interacts with the provided repository to modify the column limit
  /// configuration in the persistent storage.
  ///
  /// [repository] The data source that handles the persistence of board configurations.
  UpdateColumnLimitUseCase(this.repository);

  /// Updates the task limit for the specified column.
  Future<void> execute(Board board, KanbanColumn column, int? newLimit) async {
    if (column.columnLimit == newLimit) {
      return; // No change needed
    }

    final index = board.columns.indexWhere((col) => col.id == column.id);
    if (index == -1) {
      throw KanbanBoardException('Column not found');
    }

    // if the newlimit is less than the current number of tasks in the column
    if (newLimit != null && newLimit < column.tasks.length) {
      throw KanbanBoardException('New Column limit lower than current tasks for ${column.id}');
    }

    final newCol = KanbanColumn(
      header: column.header,
      id: column.id,
      columnLimit: newLimit,
      canAddTask: column.canAddTask,
      headerBgColorLight: column.headerBgColorLight,
      headerBgColorDark: column.headerBgColorDark,
    );
    newCol.tasks.addAll(column.tasks);
    
    board.columns[index] = newCol;
    await repository.updateBoard(board);
    EventNotifier().notify(ColumnTaskLimitUpdatedEvent(column, newLimit));
  }
}
