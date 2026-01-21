import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/core/exceptions.dart';

void main() {
  group('Column Entity', () {
    test('should create a valid column with unlimited tasks when limit is null',
        () {
      // Arrange
      final column =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);

      // Assert
      expect(column.id, equals('col1'));
      expect(column.header, equals('To Do'));
      expect(column.tasks, isEmpty);
    });

    test('should add a task when under column limit', () {
      // Arrange
      final column =
          KanbanColumn(id: 'col2', header: 'In Progress', columnLimit: 2);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');

      // Act
      column.addTask(task);

      // Assert
      expect(column.tasks.length, equals(1));
      expect(column.tasks.first, equals(task));
    });

    test('should throw error when adding a task exceeding the column limit',
        () {
      // Arrange
      final column = KanbanColumn(id: 'col3', header: 'Done', columnLimit: 1);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      column.addTask(task1);

      // Act & Assert
      expect(() => column.addTask(task2), throwsA(isA<Exception>()));
    });

    test('should reorder tasks', () {
      // Arrange
      final column =
          KanbanColumn(id: 'col4', header: 'Backlog', columnLimit: null);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      final task3 = Task(id: '3', title: 'Task3', subtitle: 'Desc3');
      column.addTask(task1);
      column.addTask(task2);
      column.addTask(task3);

      // Act
      column.reorderTask(0, 2); // move first task to last

      // Assert
      expect(column.tasks[0], equals(task2));
      expect(column.tasks[1], equals(task3));
      expect(column.tasks[2], equals(task1));
    });

    test('should delete a task', () {
      // Arrange
      final column =
          KanbanColumn(id: 'col5', header: 'Review', columnLimit: null);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      column.addTask(task1);
      column.addTask(task2);

      // Act
      final deleted = column.deleteTask(0);

      // Assert
      expect(deleted, equals(task1));
      expect(column.tasks.length, equals(1));
      expect(column.tasks.first, equals(task2));
    });

    test('should move a task from one column to another', () {
      // Arrange
      final source =
          KanbanColumn(id: 'col6', header: 'Source', columnLimit: null);
      final destination =
          KanbanColumn(id: 'col7', header: 'Destination', columnLimit: 2);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      source.addTask(task);

      // Act
      source.moveTaskTo(0, destination);

      // Assert
      expect(source.tasks, isEmpty);
      expect(destination.tasks.length, equals(1));
      expect(destination.tasks.first, equals(task));
    });

    test('should throw error when moving a task to a full column', () {
      // Arrange
      final source =
          KanbanColumn(id: 'col8', header: 'Source', columnLimit: null);
      final destination =
          KanbanColumn(id: 'col9', header: 'Destination', columnLimit: 1);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      destination.addTask(task1);
      source.addTask(task2);

      // Act & Assert
      expect(
          () => source.moveTaskTo(0, destination), throwsA(isA<Exception>()));
    });
  });

  group('edit task in column', (){
    test('should edit a task in place', () {
      // Arrange
      final column =
          KanbanColumn(id: 'col10', header: 'Edit Test', columnLimit: null);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      column.addTask(task);

      // Act
      final updatedTask = task.copyWith(title: 'Updated Task', subtitle: 'Updated Desc');
      column.replaceTask(0, updatedTask);

      // Assert
      expect(column.tasks.first.title, equals('Updated Task'));
      expect(column.tasks.first.subtitle, equals('Updated Desc'));
    });
  });
  
  group('header background colors', () {
    test('should create a column with valid custom header colors', () {
      // Arrange & Act
      final column = KanbanColumn(
        id: 'col11', 
        header: 'Colored', 
        headerBgColorLight: '#FFF8F8F8',
        headerBgColorDark: '#FF333333',
      );

      // Assert
      expect(column.headerBgColorLight, equals('#FFF8F8F8'));
      expect(column.headerBgColorDark, equals('#FF333333'));
    });

    test('should throw InvalidHexColorFormatException for invalid light theme color format', () {
      // Act & Assert
      expect(() => KanbanColumn(
        id: 'col12', 
        header: 'Invalid Light', 
        headerBgColorLight: '#F8F8F8', // Missing alpha channel
      ), throwsA(isA<InvalidHexColorFormatException>()));
    });

    test('should throw InvalidHexColorFormatException for invalid dark theme color format', () {
      // Act & Assert
      expect(() => KanbanColumn(
        id: 'col13', 
        header: 'Invalid Dark', 
        headerBgColorDark: 'FF333333', // Missing # prefix
      ), throwsA(isA<InvalidHexColorFormatException>()));
    });

    test('should include header colors in JSON when provided', () {
      // Arrange
      final column = KanbanColumn(
        id: 'col14', 
        header: 'JSON Test', 
        headerBgColorLight: '#FFFFFFFF',
        headerBgColorDark: '#FF000000',
      );

      // Act
      final json = column.toJson();

      // Assert
      expect(json['headerBgColorLight'], equals('#FFFFFFFF'));
      expect(json['headerBgColorDark'], equals('#FF000000'));
    });

    test('should exclude header colors from JSON when not provided', () {
      // Arrange
      final column = KanbanColumn(
        id: 'col15', 
        header: 'JSON Test No Colors',
      );

      // Act
      final json = column.toJson();

      // Assert
      expect(json.containsKey('headerBgColorLight'), isFalse);
      expect(json.containsKey('headerBgColorDark'), isFalse);
    });
  });
}
