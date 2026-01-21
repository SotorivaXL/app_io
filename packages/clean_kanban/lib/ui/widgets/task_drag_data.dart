import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';

/// Data class that holds information about a task being dragged.
///
/// This class encapsulates all the necessary information needed during
/// drag-and-drop operations of tasks between columns in the Kanban board.
class TaskDragData {
  /// The task being dragged.
  final Task task;

  /// The column from which the task is being dragged.
  final KanbanColumn sourceColumn;

  /// The index position of the task in its source column.
  final int sourceIndex;

  /// Creates a [TaskDragData] instance with the required drag information.
  ///
  /// Parameters:
  /// - [task]: The task being dragged
  /// - [sourceColumn]: The column from which the task originated
  /// - [sourceIndex]: The original position of the task in its column
  TaskDragData({
    required this.task,
    required this.sourceColumn,
    required this.sourceIndex,
  });
}
