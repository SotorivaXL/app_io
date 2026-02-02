import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/core/exceptions.dart';

void main() {
  group('Task Entity', () {
    test('should create a valid task', () {
      // Arrange
      const id = '1';
      const title = 'A valid title';
      const subtitle = 'A valid subtitle';
      
      // Act
      final task = Task(id: id, title: title, subtitle: subtitle);
      
      // Assert
      expect(task.id, equals(id));
      expect(task.title, equals(title));
      expect(task.subtitle, equals(subtitle));
    });

    test('should throw error when title is longer than 100 characters', () {
      // Arrange
      const id = '2';
      final longTitle = 't' * 101;
      const subtitle = 'Valid subtitle';

      // Act & Assert
      expect(() => Task(id: id, title: longTitle, subtitle: subtitle),
          throwsA(isA<TaskOperationException>()));
    });

    test('should throw error when subtitle is longer than 100 characters', () {
      // Arrange
      const id = '3';
      const title = 'Valid title';
      final longSubtitle = 's' * 101;

      // Act & Assert
      expect(() => Task(id: id, title: title, subtitle: longSubtitle),
          throwsA(isA<TaskOperationException>()));
    });

    test('Copy old task with new title and subtitle', (){
      // Arrange
      const id = '4';
      const title = 'Old Title';
      const subtitle = 'Old Subtitle';
      final task = Task(id: id, title: title, subtitle: subtitle);

      // Act
      final newTask = task.copyWith(title: 'New Title', subtitle: 'New Subtitle');

      // Assert
      expect(task.title, equals('Old Title'));
      expect(task.subtitle, equals('Old Subtitle'));
      expect(newTask.title, equals('New Title'));
      expect(newTask.subtitle, equals('New Subtitle'));
    });
  });
}
