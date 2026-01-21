/// Base class for all Kanban-related exceptions.
///
/// Provides a common interface for handling Kanban-specific errors
/// with a detailed error [message].
sealed class KanbanException implements Exception {
  /// The error message describing what went wrong.
  final String message;
  
  /// Creates a new [KanbanException] with the specified error [message].
  const KanbanException(this.message);
}

/// Exception thrown when attempting to add a task to a column that has reached its limit.
class ColumnLimitExceededException extends KanbanException {
  /// The ID of the column that has reached its limit.
  final String columnId;
  
  /// Creates a new [ColumnLimitExceededException] for the specified [columnId].
  const ColumnLimitExceededException(this.columnId)
      : super('Column limit exceeded for $columnId');
}

/// Exception thrown when an operation is attempted on a non-Done column
/// that should only be performed on the Done column.
class OperationLimitedToDoneColumnException extends KanbanException {
  /// Creates a new [OperationLimitedToDoneColumnException].
  const OperationLimitedToDoneColumnException()
      : super('This operation is only allowed for the Done column');
}

/// Exception thrown when a task-related operation fails.
class TaskOperationException extends KanbanException {
  /// Creates a new [TaskOperationException] with the specified error [message].
  const TaskOperationException(super.message);
}

/// Exception thrown when a column-related operation fails.
class ColumnOperationException extends KanbanException {
  /// Creates a new [ColumnOperationException] with the specified error [message].
  const ColumnOperationException(super.message);
}

/// Base exception for Kanban board-related errors.
class KanbanBoardException extends KanbanException {
  /// Creates a new [KanbanBoardException] with the specified error [message].
  const KanbanBoardException(super.message);
}

/// Exception thrown when attempting to create a board with fewer than the minimum required columns.
class KanbanBoardMinimumColumnRequirementException extends KanbanBoardException {
  /// Creates a new [KanbanBoardMinimumColumnRequirementException].
  const KanbanBoardMinimumColumnRequirementException()
      : super('Kanban board must have at least 3 columns.');
}

/// Exception thrown when the board configuration is missing required columns.
class BoardConfigColumnsRequirementException extends KanbanBoardException {
  /// Creates a new [BoardConfigColumnsRequirementException].
  const BoardConfigColumnsRequirementException()
      : super('Configuration must contain columns');
}

/// Exception thrown when column configuration is missing mandatory fields.
class BoardConfigMandatoryFieldsException extends KanbanBoardException {
  /// Creates a new [BoardConfigMandatoryFieldsException].
  const BoardConfigMandatoryFieldsException()
      : super('Column configuration must contain id and header');
}

/// Exception thrown when the hex color format is invalid.
/// with a field [field].
class InvalidHexColorFormatException extends KanbanBoardException {
  /// The name of the field with the invalid hex color format.
  final String field;
  /// Creates a new [InvalidHexColorFormatException] with the specified field [field].
  const InvalidHexColorFormatException(this.field)
      : super('Invalid hex color format in field $field. Must be hex ARGB like "#FF333333"');
}