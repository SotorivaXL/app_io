import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/core/exceptions.dart';

void main() {
  group('Board Configuration', () {
    test('should create board from configuration map', () {
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

      // Act
      final board = Board.fromConfig(config);

      // Assert
      expect(board.columns.length, equals(3));
      expect(board.columns[0].id, equals('todo'));
      expect(board.columns[0].columnLimit, equals(5));
      expect(board.columns[0].tasks.length, equals(2));
      expect(board.columns[1].tasks, isEmpty);
      expect(board.columns[2].columnLimit, isNull);
      expect(board.columns[2].tasks.length, equals(1));
    });

    test('should throw error when configuration is invalid', () {
      // Arrange
      final invalidConfig = {
        'columns': [
          {'header': 'Missing ID', 'tasks': []}
        ]
      };

      // Act & Assert
      expect(
          () => Board.fromConfig(invalidConfig), throwsA(isA<BoardConfigMandatoryFieldsException>()));
    });

    test('should throw error when tasks exceed column limit in configuration',
        () {
      // Arrange
      final invalidConfig = {
        'columns': [
          {
            'id': 'todo',
            'header': 'To Do',
            'limit': 1,
            'tasks': [
              {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
              {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
            ]
          },
          {'id': 'done', 'header': 'Done', 'limit': null, 'tasks': []},
          {'id': 'doing', 'header': 'Doing', 'limit': null, 'tasks': []}
        ]
      };

      // Act & Assert
      expect(() => Board.fromConfig(invalidConfig), throwsA(isA<Exception>()));
    });
  });
}
