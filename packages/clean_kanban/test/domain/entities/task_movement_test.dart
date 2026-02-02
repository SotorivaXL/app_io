import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';

void main() {
  group('Task Movement', () {
    test('should move a task from one column to another', () {
      // Arrange
      final source =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final destination =
          KanbanColumn(id: 'col2', header: 'Done', columnLimit: 2);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      source.addTask(task);

      // Act
      source.moveTaskTo(0, destination);

      // Assert
      expect(source.tasks, isEmpty);
      expect(destination.tasks.length, equals(1));
      expect(destination.tasks.first, equals(task));
    });

    test('should throw error if moving task to a full column', () {
      // Arrange
      final source =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final destination =
          KanbanColumn(id: 'col2', header: 'Done', columnLimit: 1);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      destination.addTask(task1);
      source.addTask(task2);

      // Act & Assert
      expect(
          () => source.moveTaskTo(0, destination), throwsA(isA<Exception>()));
    });
  });
}
