import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/core/exceptions.dart';
import 'package:clean_kanban/domain/usecases/board_use_cases.dart';
import 'package:clean_kanban/domain/events/event_notifier.dart';
import 'package:clean_kanban/domain/events/board_events.dart';
import '../repositories/test_board_repository.dart';

void main() {
  late TestBoardRepository repository;
  late UpdateColumnLimitUseCase updateColumnLimitUseCase;
  late Board board;
  late KanbanColumn column;
  
  setUp(() {
    repository = TestBoardRepository();
    updateColumnLimitUseCase = UpdateColumnLimitUseCase(repository);
    
    // Create a simple board with one column
    board = Board.simple();
    column = board.columns.first;
  });

  test('should update column limit and persist changes', () async { // unlimited to limited
    // Arrange
    final newLimit = 5;
    repository.board = board; // Set initial board
    
    // Act
    await updateColumnLimitUseCase.execute(board, column, newLimit);
    
    // Assert
    final updatedBoard = await repository.getBoard();
    final updatedColumn = updatedBoard.columns.firstWhere((c) => c.id == column.id);
    expect(updatedColumn.columnLimit, equals(newLimit));
  });

  test('should set column limit to null (unlimited)', () async {
    // Arrange
    final initialLimit = 5;
    column = column.copyWith(columnLimit: initialLimit); // Set initial limit
    board.columns[0] = column; // Replace the column in the board
    repository.board = board;
    
    // Act
    await updateColumnLimitUseCase.execute(board, column, null);
    
    // Assert
    final updatedBoard = await repository.getBoard();
    final updatedColumn = updatedBoard.columns.firstWhere((c) => c.id == column.id);
    expect(updatedColumn.columnLimit, isNull);
  });

  test('should set column limit to new limit', () async {
    // Arrange
    final initialLimit = 5;
    column = column.copyWith(columnLimit: initialLimit); // Set initial limit
    board.columns[0] = column; // Replace the column in the board
    repository.board = board;
    
    // Act
    await updateColumnLimitUseCase.execute(board, column, 10);
    
    // Assert
    final updatedBoard = await repository.getBoard();
    final updatedColumn = updatedBoard.columns.firstWhere((c) => c.id == column.id);
    expect(updatedColumn.columnLimit, equals(10));
  });

  test('should throw exception when column not found', () async {
    // Arrange
    final nonExistentColumn = KanbanColumn(id: 'non-existent', header: 'Non-existent');
    repository.board = board;
    
    // Act & Assert
    expect(
      () => updateColumnLimitUseCase.execute(board, nonExistentColumn, 5),
      throwsException,
    );
  });

  test('should notify event listeners when limit is updated', () async {
    // Arrange
    repository.board = board;
    final newLimit = 10;
    ColumnTaskLimitUpdatedEvent? capturedEvent;
    final eventNotifier = EventNotifier();

    // Set up event listener to capture events
    final subscription = eventNotifier.subscribe((event) {
      if (event is ColumnTaskLimitUpdatedEvent) {
      capturedEvent = event;
    }
    });
    
    // Act
    await updateColumnLimitUseCase.execute(board, column, newLimit);
    
    // Wait a short time for the event to propagate
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Assert
    expect(capturedEvent, isNotNull);
    expect(capturedEvent!.column.id, equals(column.id));
    expect(capturedEvent!.newLimit, equals(newLimit));
    
    // Clean up
    subscription.cancel();
  });
  
  test('should handle repository exceptions', () async {
    // Arrange
    repository.board = board;
    repository.throwsOnUpdate = true; // Set repository to throw on update
    
    // Act & Assert
    expect(
      () => updateColumnLimitUseCase.execute(board, column, 5),
      throwsException,
    );
  });

  test('should throw KanbanBoardException when new limit is lower than current tasks', () async {
    final tasks = List.generate(5, (index) => Task(id: 'task_$index', title: 'Task $index', subtitle: 'Subtitle $index'));
    final initialLimit = 5;
    column = column.copyWith(columnLimit: initialLimit, tasks: tasks);
    board.columns[0] = column;
    repository.board = board;

    expect(
      () => updateColumnLimitUseCase.execute(board, column, 3),
      throwsA(isA<KanbanBoardException>()),
    );
  });
}