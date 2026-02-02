import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/core/exceptions.dart';

/// Represents a Kanban board containing multiple columns.
///
/// A board must have at least 3 columns and provides functionality for
/// managing tasks and columns, including movement between columns and
/// checking column limits.
class Board {
  /// The list of columns in this board.
  final List<KanbanColumn> columns;

  /// Internal constructor for creating a board with the given columns.
  Board._(this.columns);

  /// Creates a simple board with exactly 3 default columns: To Do, Doing, and Done.
  ///
  /// The Doing and Done columns are configured to not accept direct task additions.
  factory Board.simple() {
    return Board._([
      KanbanColumn(id: 'todo', header: 'To Do', columnLimit: null),
      KanbanColumn(
          id: 'doing', header: 'Doing', columnLimit: null, canAddTask: false),
      KanbanColumn(
          id: 'done', header: 'Done', columnLimit: null, canAddTask: false),
    ]);
  }

  /// Creates an enhanced board with custom columns.
  ///
  /// Throws [KanbanBoardMinimumColumnRequirementException] if fewer than 3 columns are provided.
  factory Board({required List<KanbanColumn> columns}) {
    if (columns.length < 3) {
      throw KanbanBoardMinimumColumnRequirementException();
    }
    return Board._(columns);
  }

  /// Creates a board from a configuration map.
  ///
  /// The configuration must contain a 'columns' key with an array of column configurations.
  /// Each column configuration must have 'id' and 'header' fields.
  ///
  /// Throws:
  /// * [BoardConfigColumnsRequirementException] if 'columns' key is missing
  /// * [BoardConfigMandatoryFieldsException] if column config is missing required fields
  factory Board.fromConfig(Map<String, dynamic> config) {
    if (!config.containsKey('columns')) {
      throw BoardConfigColumnsRequirementException();
    }

    final columns = (config['columns'] as List).map((colConfig) {
      if (!colConfig.containsKey('id') || !colConfig.containsKey('header')) {
        throw BoardConfigMandatoryFieldsException();
      }

      final column = KanbanColumn(
        id: colConfig['id'],
        header: colConfig['header'],
        columnLimit: colConfig['limit'],
        canAddTask: colConfig['canAddTask'] ?? true,
        headerBgColorLight: colConfig['headerBgColorLight'],
        headerBgColorDark: colConfig['headerBgColorDark'],
      );

      if (colConfig['tasks'] != null) {
        for (final taskConfig in colConfig['tasks']) {
          final task = Task(
            id: taskConfig['id'],
            title: taskConfig['title'],
            subtitle: taskConfig['subtitle'],
          );
          column.addTask(task);
        }
      }

      return column;
    }).toList();

    return Board(columns: columns);
  }

  /// Checks if a column has reached its task limit.
  ///
  /// Returns true if the column with [columnId] has reached its configured limit.
  bool isColumnLimitReached(String columnId) {
    final column = columns.firstWhere((col) => col.id == columnId);
    if (column.columnLimit != null &&
        column.tasks.length >= column.columnLimit!) {
      return true;
    }
    return false;
  }

  /// Converts the board to a JSON-compatible map for persistence.
  ///
  /// Returns a map containing the board's configuration and all its columns.
  Map<String, dynamic> toJson() {
    return {
      'columns': columns.map((column) => column.toJson()).toList(),
    };
  }
}
