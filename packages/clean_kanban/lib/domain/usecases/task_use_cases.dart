import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/events/event_notifier.dart';
import 'package:clean_kanban/domain/events/board_events.dart';
import 'package:clean_kanban/core/result.dart';
import 'package:clean_kanban/core/exceptions.dart';

/// Use case for adding a new task to a column.
class AddTaskUseCase {
  /// Adds a task to the given column.
  ///
  /// Notifies listeners with a [TaskAddedEvent] when successful.
  /// 
  /// Parameters:
  /// - [column]: The column to add the task to
  /// - [task]: The task to be added
  void execute(KanbanColumn column, Task task) {
    column.addTask(task);
    EventNotifier().notify(TaskAddedEvent(task, column));
  }
}

/// Use case for deleting a task from a column.
class DeleteTaskUseCase {
  /// Deletes a task at the specified index from the column.
  ///
  /// Notifies listeners with a [TaskRemovedEvent] when successful.
  /// Returns a [Result] containing the removed task.
  /// 
  /// Parameters:
  /// - [column]: The column containing the task
  /// - [index]: The index of the task to delete
  Result<Task> execute(KanbanColumn column, int index) {
    final removed = column.deleteTask(index);
    EventNotifier().notify(TaskRemovedEvent(removed, column));
    return Success(removed);
  }
}

/// Use case for reordering tasks within a column.
class ReorderTaskUseCase {
  /// Reorders a task within the same column.
  ///
  /// Notifies listeners with a [TaskReorderedEvent] when successful.
  /// 
  /// Parameters:
  /// - [column]: The column containing the task
  /// - [oldIndex]: The current index of the task
  /// - [newIndex]: The desired index for the task
  void execute(KanbanColumn column, int oldIndex, int newIndex) {
    Task task = column.tasks[oldIndex];
    column.reorderTask(oldIndex, newIndex);
    EventNotifier()
        .notify(TaskReorderedEvent(column, task, oldIndex, newIndex));
  }
}

/// Use case for moving tasks between columns.
class MoveTaskUseCase {
  /// Moves a task from the source column to the destination column.
  ///
  /// Notifies listeners with a [TaskMovedEvent] when successful.
  /// 
  /// Parameters:
  /// - [source]: The source column
  /// - [sourceIndex]: The index of the task in the source column
  /// - [destination]: The destination column
  /// - [destinationIndex]: Optional index in the destination column
  void execute(KanbanColumn source, int sourceIndex, KanbanColumn destination, [int? destinationIndex]) {
    final task = source.tasks[sourceIndex];
    source.moveTaskTo(sourceIndex, destination, destinationIndex);
    EventNotifier().notify(TaskMovedEvent(task, source, destination));
  }
}

/// Use case for deleting tasks from the Done column.
class DeleteDoneTaskUseCase {
  /// Deletes a single task from the Done column.
  /// 
  /// Notifies listeners with a [TaskRemovedEvent] when successful.
  /// Returns a [Result] containing the removed task.
  /// 
  /// Parameters:
  /// - [doneColumn]: The Done column
  /// - [index]: The index of the task to delete
  Result<Task> execute(KanbanColumn doneColumn, int index) {
    try {
      if (!doneColumn.isDoneColumn()) {
        throw OperationLimitedToDoneColumnException();
      }
      final removed = doneColumn.deleteTask(index);
      EventNotifier().notify(TaskRemovedEvent(removed, doneColumn));
      return Success(removed);
    } on OperationLimitedToDoneColumnException catch (e) {
      return Failure(e.message);
    } catch (e) {
      throw TaskOperationException('Failed to delete task: ${e.toString()}');
    }
  }
}

/// Use case for clearing all tasks from the Done column.
class ClearDoneColumnUseCase {
  /// Removes all tasks from the Done column.
  /// 
  /// Notifies listeners with a [DoneColumnClearedEvent] when successful.
  /// Returns a [Result] containing the list of removed tasks.
  /// 
  /// Parameters:
  /// - [doneColumn]: The Done column to clear
  Result<List<Task>> execute(KanbanColumn doneColumn) {
    try {
      if (!doneColumn.isDoneColumn()) {
        throw OperationLimitedToDoneColumnException();
      }
      final removedTasks = List<Task>.from(doneColumn.tasks);
      doneColumn.tasks.clear();
      EventNotifier().notify(DoneColumnClearedEvent(removedTasks, doneColumn));
      return Success(removedTasks);
    } on OperationLimitedToDoneColumnException catch (e) {
      return Failure(e.message);
    } catch (e) {
      throw TaskOperationException('Failed to clear Done column: ${e.toString()}');
    }
  }
}

/// Use case for editing an existing task.
class EditTaskUseCase {
  /// Edits an existing task at the specified index in the column.
  /// 
  /// Notifies listeners with a [TaskEditedEvent] when successful.
  /// Returns a [Result] containing the updated task.
  /// 
  /// Parameters:
  /// - [column]: The column containing the task
  /// - [index]: The index of the task to edit
  /// - [newTitle]: The new title for the task
  /// - [newSubtitle]: The new subtitle for the task
  /// 
  /// Throws [TaskOperationException] if the task cannot be edited.
  Result<Task> execute(KanbanColumn column, int index, String newTitle, String newSubtitle) {
    try {
      final task = column.tasks[index];
      
      // Check if any changes are needed
      if (task.title == newTitle && task.subtitle == newSubtitle) {
        return Success(task);
      }

      final updatedTask = task.copyWith(
        title: newTitle,
        subtitle: newSubtitle,
      );
      
      column.replaceTask(index, updatedTask);
      EventNotifier().notify(TaskEditedEvent(task, updatedTask, column));
      return Success(updatedTask);
    } catch (e) {
      throw TaskOperationException('Failed to edit task: ${e.toString()}');
    }
  }
}
