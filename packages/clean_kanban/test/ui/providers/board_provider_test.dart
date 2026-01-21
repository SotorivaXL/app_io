import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/ui/providers/board_provider.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/injection_container.dart';
import 'package:clean_kanban/core/result.dart';
import '../../domain/repositories/test_board_repository.dart';

void main() {
  late TestBoardRepository testBoardRepository;
  setUpAll(() async {
    testBoardRepository = TestBoardRepository();
    // Reset and setup injection so dependencies are registered.
    await getIt.reset();
    setupInjection(testBoardRepository);
  });

  group('BoardProvider', () {
    
    test('should load a simple board if no board exists', () async {
      // Arrange
      final boardProvider = BoardProvider();

      // Act
      await boardProvider.loadBoard();

      // Assert
      expect(boardProvider.board, isNotNull);
      expect(boardProvider.board!.columns.length, equals(3));
      expect(boardProvider.board!.columns[0].header, equals('To Do'));
    });

    test('should load a board with custom configuration', () async {
      // force a null board, to simulate no previous board
      testBoardRepository.board = null;
      // Arrange
      final config = {
        'columns': [
          {
            'id': 'todo',
            'header': 'To Do',
            'limit': 5,
            'tasks': [
              {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
              {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
            ]
          },
          {'id': 'doing', 'header': 'In Progress', 'limit': 3, 'tasks': []},
          {
            'id': 'done',
            'header': 'Done',
            'limit': null,
            'tasks': [
              {'id': '3', 'title': 'Task 3', 'subtitle': 'Description 3'}
            ]
          }
        ]
      };
      final boardProvider = BoardProvider();

      // Act
      await boardProvider.loadBoard(config: config);

      // Assert
      expect(boardProvider.board, isNotNull);
      expect(boardProvider.board!.columns.length, equals(3));
      expect(boardProvider.board!.columns[0].header, equals('To Do'));
      expect(boardProvider.board!.columns[0].tasks.length, equals(2));
      expect(boardProvider.board!.columns[1].tasks, isEmpty);
      expect(boardProvider.board!.columns[2].tasks.length, equals(1));
    });

    test('Load previously saved board', () async {
      // Arrange
      final config = {
        'columns': [
          {
            'id': 'todo',
            'header': 'To Do',
            'limit': 5,
            'tasks': [
              {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
              {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
              {'id': '3', 'title': 'Task 3', 'subtitle': 'Description 3'},
            ]
          },
          {'id': 'doing', 'header': 'In Progress', 'limit': 3, 'tasks': []},
          {
            'id': 'done',
            'header': 'Done',
            'limit': null,
            'tasks': [
              {'id': '3', 'title': 'Task 3', 'subtitle': 'Description 3'}
            ]
          }
        ]
      };
      testBoardRepository.board = Board.fromConfig(config);
      final boardProvider = BoardProvider();

      // Act
      await boardProvider.loadBoard();

      // Assert
      expect(boardProvider.board, isNotNull);
      expect(boardProvider.board!.columns.length, equals(3));
      expect(boardProvider.board!.columns[0].header, equals('To Do'));
      expect(boardProvider.board!.columns[0].tasks.length, equals(3));
      expect(boardProvider.board!.columns[1].tasks, isEmpty);
      expect(boardProvider.board!.columns[2].tasks.length, equals(1));
    });

    test('should add a task to a column', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');

      // Act
      boardProvider.addTask('todo', task);

      // Assert
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      expect(column.tasks.length, equals(1));
      expect(column.tasks.first, equals(task));
    });

    test('should remove a task from a column', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      boardProvider.addTask('todo', task);

      // Act
      boardProvider.removeTask('todo', 0);

      // Assert
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      expect(column.tasks, isEmpty);
    });

    test('should move a task from one column to another', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      boardProvider.addTask('todo', task);

      // Act
      boardProvider.moveTask('todo', 0, 'doing');

      // Assert
      final sourceColumn =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      final destColumn =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'doing');
      expect(sourceColumn.tasks, isEmpty);
      expect(destColumn.tasks.length, equals(1));
      expect(destColumn.tasks.first, equals(task));
    });

    test('should move a task from one column to another at specific index', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      boardProvider.addTask('todo', task);

      // Act
      boardProvider.moveTask('todo', 0, 'doing', -1);

      // Assert
      final sourceColumn =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      final destColumn =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'doing');
      expect(sourceColumn.tasks, isEmpty);
      expect(destColumn.tasks.length, equals(1));
      expect(destColumn.tasks.first, equals(task));
    });

    test('should reorder the task within the same column', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      boardProvider.addTask('todo', task);
      boardProvider.addTask('todo', task2);

      // Act
      boardProvider.reorderTask('todo', 1, 0);

      // Assert
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      expect(column.tasks[0], equals(task2), reason: 'Task2 should be first');
      expect(column.tasks[1], equals(task));
    });
  });

  group('Done Column Management', () {
    late BoardProvider boardProvider;
    late Task task1;
    late Task task2;

    setUp(() {
      boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      task1 = Task(
        id: '1',
        title: 'Task 1',
        subtitle: 'Subtitle 1',
      );
      task2 = Task(
        id: '2',
        title: 'Task 2',
        subtitle: 'Subtitle 2',
      );

      boardProvider.addTask('done', task1);
      boardProvider.addTask('done', task2);
    });

    test('should delete single task from Done column', () {
      // Act
      boardProvider.deleteDoneTask('done', 0);

      // Assert
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'done');
      expect(column.tasks.length, 1);
      expect(column.tasks[0], task2);
    });

    test('should throw error when deleting task from non-Done column', () {
      // Arrange
      boardProvider.addTask('todo', task1);

      // Act & Assert
      final result = boardProvider.deleteDoneTask('todo', 0);
      switch (result) {
        case Failure<Task> failure:
          expect(failure.message, 'This operation is only allowed for the Done column');
          break;
        default:
          fail('Expected Failure, but got $result');
      }
    });

    test('should clear all tasks from Done column', () {
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'done');

      // Act
      expect(column.tasks.length, 2); // Ensure there are tasks before clearing
      boardProvider.clearDoneColumn('done');

      // Assert
      expect(column.tasks.length, 0);
    });

    test('should throw error when clearing non-Done column', () {
      // Arrange
      boardProvider.addTask('todo', task1);

      // Act & Assert
      final result = boardProvider.clearDoneColumn('todo');
      switch (result) {
        case Failure<List<Task>> failure:
          expect(failure.message, 'This operation is only allowed for the Done column');
          break;
        default:
          fail('Expected Failure, but got $result');
      }
    });

    test('should notify listeners when deleting done task', () {
      // Arrange
      var notified = false;
      boardProvider.addListener(() => notified = true);

      // Act
      boardProvider.deleteDoneTask('done', 0);

      // Assert
      expect(notified, true);
    });

    test('should notify listeners when clearing done column', () {
      // Arrange
      var notified = false;
      boardProvider.addListener(() => notified = true);

      // Act
      boardProvider.clearDoneColumn('done');

      // Assert
      expect(notified, true);
    });

    test('should update a task in column', () {
      // Arrange
      final boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      boardProvider.addTask('todo', task);

      final expectedTask = task.copyWith(
        title: 'Updated Title',
        subtitle: 'Updated Subtitle',
      );

      // Act
      boardProvider.editTask('todo', 0,  'Updated Title', 'Updated Subtitle');

      // Assert
      final column =
          boardProvider.board!.columns.firstWhere((c) => c.id == 'todo');
      expect(column.tasks.length, equals(1));
      expect(column.tasks.first, equals(expectedTask));
    });
  });
  group('Column Limit Management', () {
    late BoardProvider boardProvider;

    setUp(() {
      boardProvider = BoardProvider();
      boardProvider.board = Board.simple();
    });

    test('should update column limit for a column', () async {
      // Arrange
      final columnId = 'todo';
      final newLimit = 5;
      var notified = false;
      boardProvider.addListener(() => notified = true);

      // Act
      await boardProvider.updateColumnLimit(columnId, newLimit);

      // Assert
      final column = boardProvider.board!.columns.firstWhere((c) => c.id == columnId);
      expect(column.columnLimit, equals(newLimit));
      expect(notified, true, reason: 'BoardProvider should notify listeners after updating column limit');
    });

    test('should set column limit to null (unlimited)', () async {
      // Arrange
      final columnId = 'todo';
      // First set a limit
      await boardProvider.updateColumnLimit(columnId, 5);
      var column = boardProvider.board!.columns.firstWhere((c) => c.id == columnId);
      expect(column.columnLimit, equals(5), reason: 'Column should have a limit before test');
      
      var notified = false;
      boardProvider.addListener(() => notified = true);

      // Act - set limit to null
      await boardProvider.updateColumnLimit(columnId, null);

      // Assert
      column = boardProvider.board!.columns.firstWhere((c) => c.id == columnId);
      expect(column.columnLimit, isNull, reason: 'Column should have no limit after setting to null');
      expect(notified, true);
    });

    test('should enforce column limit when adding tasks after limit update', () async {
      // Arrange
      final columnId = 'todo';
      await boardProvider.updateColumnLimit(columnId, 2);
      
      // Add tasks up to the limit
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      final task3 = Task(id: '3', title: 'Task3', subtitle: 'Desc3');
      
      boardProvider.addTask(columnId, task1);
      boardProvider.addTask(columnId, task2);
      
      // Act & Assert
      final column = boardProvider.board!.columns.firstWhere((c) => c.id == columnId);
      expect(column.tasks.length, equals(2));
      
      // This should fail because the column limit is 2
      expect(() => boardProvider.addTask(columnId, task3), throwsA(isA<Exception>()));
    });

    // test('should do nothing when trying to update limit for non-existent column', () async { // TODO: Fix test
    //   // Arrange
    //   final columnId = 'non-existent';
    //   final newLimit = 5;
    //   var notified = false;
    //   boardProvider.addListener(() => notified = true);

    //   // Act
    //   await boardProvider.updateColumnLimit(columnId, newLimit);

    //   // Assert - nothing should happen, no errors
    //   expect(notified, false, reason: 'BoardProvider should not notify listeners when column not found');
    // });
  });
}
