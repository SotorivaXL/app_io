import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';

/// Base class for all events that occur on a Kanban board.
abstract class BoardEvent {}

/// Event fired when a board is loaded from storage.
class BoardLoadedEvent extends BoardEvent {
  /// The loaded board instance.
  final Board board;
  
  /// Creates a new board loaded event.
  BoardLoadedEvent(this.board);
}

/// Event fired when a board is saved to storage.
class BoardSavedEvent extends BoardEvent {
  /// The saved board instance.
  final Board board;
  
  /// Creates a new board saved event.
  BoardSavedEvent(this.board);
}

/// Event fired when a new task is added to a column.
class TaskAddedEvent extends BoardEvent {
  /// The task that was added.
  final Task task;
  
  /// The column where the task was added.
  final KanbanColumn column;
  
  /// Creates a new task added event.
  TaskAddedEvent(this.task, this.column);
}

/// Event fired when a task is removed from a column.
class TaskRemovedEvent extends BoardEvent {
  /// The task that was removed.
  final Task task;
  
  /// The column from which the task was removed.
  final KanbanColumn column;
  
  /// Creates a new task removed event.
  TaskRemovedEvent(this.task, this.column);
}

/// Event fired when a task is moved between columns.
class TaskMovedEvent extends BoardEvent {
  /// The task that was moved.
  final Task task;
  
  /// The source column from which the task was moved.
  final KanbanColumn source;
  
  /// The destination column to which the task was moved.
  final KanbanColumn destination;
  
  /// Creates a new task moved event.
  TaskMovedEvent(this.task, this.source, this.destination);
}

/// Event fired when a task is reordered within a column.
class TaskReorderedEvent extends BoardEvent {
  /// The column where the reordering occurred.
  final KanbanColumn column;
  
  /// The task that was reordered.
  final Task task;
  
  /// The original index of the task.
  final int oldIndex;
  
  /// The new index of the task.
  final int newIndex;
  
  /// Creates a new task reordered event.
  TaskReorderedEvent(this.column, this.task, this.oldIndex, this.newIndex);
}

/// Event fired when the Done column is cleared of all tasks.
class DoneColumnClearedEvent extends BoardEvent {
  /// The list of tasks that were removed.
  final List<Task> removedTasks;
  
  /// The Done column that was cleared.
  final KanbanColumn column;

  /// Creates a new done column cleared event.
  DoneColumnClearedEvent(this.removedTasks, this.column);
}

/// Event fired when a task is edited.
class TaskEditedEvent extends BoardEvent {
  /// The original task before editing.
  final Task oldTask;
  
  /// The updated task after editing.
  final Task newTask;
  
  /// The column containing the edited task.
  final KanbanColumn column;

  /// Creates a new task edited event.
  TaskEditedEvent(this.oldTask, this.newTask, this.column);
}

/// An event that occurs when a Kanban column's task limit is updated.
///
/// This event contains the reference to the affected [column] and the [newLimit]
/// that was set. The [newLimit] can be null, which typically indicates no limit
/// is set for the column. This can happen when a previous limit was set and
/// then removed.
///
/// This event is dispatched after a column's task limit has been changed, allowing
/// listeners to react to this change accordingly.
class ColumnTaskLimitUpdatedEvent extends BoardEvent {
  /// The column whose task limit was updated.
  final KanbanColumn column;
  
  /// The new task limit.
  final int? newLimit;

  /// Creates a new task limit updated event.
  ColumnTaskLimitUpdatedEvent(this.column, this.newLimit);
}

class TaskTappedEvent extends BoardEvent {
  final Task task;
  final KanbanColumn column;
  final int index;

  TaskTappedEvent({
    required this.task,
    required this.column,
    required this.index,
  });
}