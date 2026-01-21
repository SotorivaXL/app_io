import 'package:clean_kanban/clean_kanban.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:clean_kanban/ui/widgets/task_card.dart';

/// Constants for KanbanColumn layout measurements
class KanbanColumnLayout {
  // espaço entre header e 1º card
  static const double headerToTasksSpacing = 10.0;

  // padding interno da lista
  static const EdgeInsets taskListPadding =
  EdgeInsets.fromLTRB(12, 6, 12, 12);

  // espaçamento entre cards
  static const double taskCardSpacing = 10.0;

  // header menor
  static const double headerHeight = 48.0;
  static const double headerPadding = 12.0;

  // coluna mais “premium”
  static const double columnBorderRadius = 14.0;

  static const double actionButtonSize = 32.0;
  static const double actionIconSize = 20.0;

  static const double defaultMobileMaxHeight = 400.0;
  static const double narrowScreenThreshold = 600.0;
}

/// Theme configuration for a Kanban column.
///
/// Defines the visual appearance of a column including colors for various
/// components like background, borders, headers, and action buttons.
class KanbanColumnTheme {
  /// Background color of the column.
  final Color columnBackgroundColor;

  /// Color of the column's border.
  final Color columnBorderColor;

  /// Border width for the column
  final double columnBorderWidth;

  /// Background color of the column header.
  final Color columnHeaderColor;

  /// Text color for the column header.
  final Color columnHeaderTextColor;

  /// Background color for the add task button.
  final Color columnAddButtonBoxColor;

  /// Color of the add task icon.
  final Color columnAddIconColor;

  /// Creates a [KanbanColumnTheme] with customizable colors.
  ///
  /// All parameters have default values that create a standard light theme.
  const KanbanColumnTheme({
    this.columnBackgroundColor = Colors.white,
    this.columnBorderColor = const Color(0xFFE0E0E0),
    this.columnBorderWidth = 0.0,
    this.columnHeaderColor = Colors.blue,
    this.columnHeaderTextColor = Colors.black87,
    this.columnAddButtonBoxColor = const Color.fromARGB(255, 76, 127, 175),
    this.columnAddIconColor = Colors.white,
  });

  /// Creates a copy of this [KanbanColumnTheme] with modified values.
  /// 
  /// Any parameter that is null will keep its original value.
  KanbanColumnTheme copyWith({
    Color? columnBackgroundColor,
    Color? columnBorderColor,
    double? columnBorderWidth,
    Color? columnHeaderColor,
    Color? columnHeaderTextColor,
    Color? columnAddButtonBoxColor,
    Color? columnAddIconColor,
  }) {
    return KanbanColumnTheme(
      columnBackgroundColor: columnBackgroundColor ?? this.columnBackgroundColor,
      columnBorderColor: columnBorderColor ?? this.columnBorderColor,
      columnBorderWidth: columnBorderWidth ?? this.columnBorderWidth,
      columnHeaderColor: columnHeaderColor ?? this.columnHeaderColor,
      columnHeaderTextColor: columnHeaderTextColor ?? this.columnHeaderTextColor,
      columnAddButtonBoxColor: columnAddButtonBoxColor ?? this.columnAddButtonBoxColor,
      columnAddIconColor: columnAddIconColor ?? this.columnAddIconColor,
    );
  }
}

/// A widget that displays the header of a Kanban column.
class ColumnHeader extends StatelessWidget {
  /// The column data
  final KanbanColumn column;

  /// Theme configuration for the column
  final KanbanColumnTheme theme;

  /// Callback when the add task button is pressed
  final VoidCallback? onAddTask;

  /// Callback when the clear all done tasks button is pressed
  final VoidCallback? onClearDone;

  /// Creates a [ColumnHeader] widget.
  const ColumnHeader({
    super.key,
    required this.column,
    required this.theme,
    this.onAddTask,
    this.onClearDone,
  }) : super();

  /// Gets the appropriate header color based on theme brightness and column settings
  Color _getHeaderColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light && column.headerBgColorLight != null) {
      return column.headerBgColorLight!.toColor();
    } else if (brightness == Brightness.dark && column.headerBgColorDark != null) {
      return column.headerBgColorDark!.toColor();
    }
    // Fall back to the theme's default color if no custom color is specified
    return theme.columnHeaderColor;
  }

  @override
  Widget build(BuildContext context) {
    final headerBg = theme.columnBackgroundColor; // Trello: header igual à coluna
    final accent = theme.columnHeaderColor;       // Trello: detalhe em cor

    return Container(
      height: KanbanColumnLayout.headerHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: KanbanColumnLayout.headerPadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KanbanColumnLayout.columnBorderRadius),
        ),
      ),
      child: Row(
        children: [
          // bolinha (accent)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // título
          Expanded(
            child: Text(
              column.header.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: theme.columnHeaderTextColor,
              ),
            ),
          ),

          // badge contagem (pill)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withOpacity(.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              column.columnLimit != null
                  ? '${column.tasks.length}/${column.columnLimit}'
                  : '${column.tasks.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),

          const SizedBox(width: 6),

          // menu 3 pontinhos (estilo trello, mesmo sem ação por enquanto)
          IconButton(
            splashRadius: 18,
            onPressed: null, // depois você pode abrir menu/ações aqui
            icon: Icon(
              Icons.more_horiz,
              size: 18,
              color: theme.columnHeaderTextColor.withOpacity(.65),
            ),
          ),

          if (column.canAddTask && onAddTask != null) _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildClearButton(BuildContext context) {
    return Container(
      height: KanbanColumnLayout.actionButtonSize,
      width: KanbanColumnLayout.actionButtonSize,
      margin: const EdgeInsets.only(right: 8.0),
      decoration: BoxDecoration(
        color: Colors.red[400]?.withValues(alpha: 
          column.tasks.isNotEmpty && onClearDone != null ? 1.0 : 0.3,
        ),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: IconButton(
        icon: const Icon(Icons.clear_all, size: KanbanColumnLayout.actionIconSize),
        padding: EdgeInsets.zero,
        color: Colors.white,
        tooltip: column.tasks.isEmpty
            ? 'No tasks to clear'
            : 'Clear all done tasks',
        onPressed: (column.tasks.isNotEmpty && onClearDone != null)
            ? () => ConfirmationDialog.show(
                context: context,
                title: 'Clear all done tasks',
                message: 'Are you sure you want to clear all done tasks? This action cannot be undone.',
                label: 'Clear',
                onPressed: () {
                  onClearDone?.call();
                },
              )
            : null,
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      height: KanbanColumnLayout.actionButtonSize,
      width: KanbanColumnLayout.actionButtonSize,
      decoration: BoxDecoration(
        color: theme.columnAddButtonBoxColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: IconButton(
        icon: const Icon(Icons.add_rounded, size: KanbanColumnLayout.actionIconSize),
        padding: EdgeInsets.zero,
        color: theme.columnAddIconColor,
        onPressed: onAddTask,
      ),
    );
  }
}

/// A widget that displays the list of tasks in a Kanban column with drag-and-drop support.
class ColumnTaskList extends StatelessWidget {
  /// The column containing the tasks
  final KanbanColumn column;

  /// Theme configuration for the column
  final KanbanColumnTheme theme;

  /// Whether the screen is narrow (mobile)
  final bool isNarrowScreen;

  /// Callback when a task is reordered within the column
  final Function(KanbanColumn column, int oldIndex, int newIndex)? onReorderedTask;

  /// Callback when a task is dropped into this column
  final Function(KanbanColumn source, int sourceIndex, KanbanColumn destination, [int? destinationIndex])? onTaskDropped;

  /// Callback when a task's delete button is pressed
  final Function(KanbanColumn column, int index)? onDeleteTask;

  /// Callback when a task's edit button is pressed
  final Function(KanbanColumn column, int index, String initialTitle, String initialSubtitle)? onEditTask;

  /// Creates a [ColumnTaskList] widget.
  const ColumnTaskList({
    super.key,
    required this.column,
    required this.theme,
    this.isNarrowScreen = false,
    this.onReorderedTask,
    this.onTaskDropped,
    this.onDeleteTask,
    this.onEditTask,
  }) : super();

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskDragData>(
      builder: (context, candidateData, rejectedData) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ListView.separated(
              padding: KanbanColumnLayout.taskListPadding,
              itemCount: column.tasks.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: KanbanColumnLayout.taskCardSpacing),
              itemBuilder: (context, index) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final task = column.tasks[index];
                    final effectiveTheme = KanbanThemeProvider.of(context);

                    final dragData = TaskDragData(
                      task: task,
                      sourceColumn: column,
                      sourceIndex: index,
                    );

                    // ✅ feedback com mesma largura do card original
                    Widget feedbackCard() => SizedBox(
                      width: constraints.maxWidth,
                      child: TaskCard(
                        data: dragData,
                        theme: effectiveTheme.cardTheme,
                      ),
                    );

                    // ✅ card clicável (dispara evento pro popup)
                    final card = GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        EventNotifier().notify(
                          TaskTappedEvent(task: task, column: column, index: index),
                        );
                      },
                      child: TaskCard(
                        data: dragData,
                        theme: effectiveTheme.cardTheme,
                      ),
                    );

                    if (kIsWeb) {
                      return Draggable<TaskDragData>(
                        data: dragData,
                        feedback: Material(
                          color: Colors.transparent,
                          elevation: 10,
                          child: feedbackCard(),
                        ),
                        childWhenDragging: Opacity(opacity: 0.35, child: card),
                        child: card,
                      );
                    }

                    return LongPressDraggable<TaskDragData>(
                      delay: TaskCardLayout.dragDelay,
                      data: dragData,
                      feedback: Material(
                        color: Colors.transparent,
                        elevation: 10,
                        child: feedbackCard(),
                      ),
                      childWhenDragging: Opacity(opacity: 0.35, child: card),
                      child: card,
                    );
                  },
                );
              },
            ),
            if (isNarrowScreen && column.tasks.length > 4)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        theme.columnHeaderColor.withOpacity(0.2),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      onWillAcceptWithDetails: (details) {
        return _shouldAcceptDrop(details.data.sourceColumn, column);
      },
      onAcceptWithDetails: (details) {
        // drop no fim da coluna
        onTaskDropped?.call(details.data.sourceColumn, details.data.sourceIndex, column, column.tasks.length);
      },
    );
  }

  bool _shouldAcceptDrop(KanbanColumn sourceColumn, KanbanColumn targetColumn) {
    if (targetColumn.columnLimit != null && targetColumn.tasks.length >= targetColumn.columnLimit!) {
        return false; // target column limit reached
    } else  {
      return true;
    } 
  }
}

class _DraggableHitbox extends StatelessWidget {
  final Widget child;
  const _DraggableHitbox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // o card visual
        child,

        // ✅ overlay que garante que o item inteiro capture o toque/clique
        Positioned.fill(
          child: AbsorbPointer(
            // deixa o LongPressDraggable (pai) receber o gesto,
            // e impede que os filhos (Text/Padding/etc) “roubem” o hit-test
            absorbing: true,
            child: Container(color: Colors.transparent),
          ),
        ),
      ],
    );
  }
}

/// A widget that represents a column in a Kanban board.
///
/// Handles the display of tasks, drag-and-drop operations, and column-specific
/// actions like adding tasks and clearing completed tasks.
class ColumnWidget extends StatelessWidget {
  /// The column data to display.
  final KanbanColumn column;

  /// Theme configuration for the column.
  final KanbanColumnTheme theme;

  /// Callback when the add task button is pressed.
  final Function()? onAddTask;

  /// Callback when a task is reordered within the column.
  final Function(KanbanColumn column, int oldIndex, int newIndex)? onReorderedTask;

  /// Callback when a task is dropped into this column.
  final Function(KanbanColumn source, int sourceIndex, KanbanColumn destination, [int? destinationIndex])? onTaskDropped;

  /// Callback when the clear all done tasks button is pressed.
  final Function()? onClearDone;

  /// Callback when a task's delete button is pressed.
  final Function(KanbanColumn column, int index)? onDeleteTask;

  /// Callback when a task's edit button is pressed.
  final Function(KanbanColumn column, int index, String initialTitle, String initialSubtitle)? onEditTask;

  /// Maximum height for the column when displayed on mobile
  /// Only applied when the column is in a vertical layout
  final double? mobileMaxHeight;

  /// Creates a [ColumnWidget] with the given parameters.
  ///
  /// The [column] and [theme] parameters are required, while all callbacks
  /// are optional.
  const ColumnWidget({
    super.key,
    required this.column,
    required this.theme,
    this.onAddTask,
    this.onReorderedTask,
    this.onTaskDropped,
    this.onDeleteTask,
    this.onEditTask,
    this.onClearDone,
    this.mobileMaxHeight = KanbanColumnLayout.defaultMobileMaxHeight,
  }) : super();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrowScreen =
            constraints.maxWidth < KanbanColumnLayout.narrowScreenThreshold;

        return Container(
          constraints: isNarrowScreen && mobileMaxHeight != null
              ? BoxConstraints(maxHeight: mobileMaxHeight!)
              : null,
          decoration: BoxDecoration(
            color: theme.columnBackgroundColor,
            borderRadius: BorderRadius.circular(KanbanColumnLayout.columnBorderRadius),
            border: Border.all(color: Colors.transparent, width: 0),
            boxShadow: const [],
          ),
          child: Column(
            children: [
              ColumnHeader(
                column: column,
                theme: theme,
                onAddTask: onAddTask,
                onClearDone: onClearDone,
              ),

              const SizedBox(height: KanbanColumnLayout.headerToTasksSpacing),

              Expanded(
                child: ColumnTaskList(
                  column: column,
                  theme: theme,
                  isNarrowScreen: isNarrowScreen,
                  onReorderedTask: onReorderedTask,
                  onTaskDropped: onTaskDropped,
                  onDeleteTask: onDeleteTask,
                  onEditTask: onEditTask,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
