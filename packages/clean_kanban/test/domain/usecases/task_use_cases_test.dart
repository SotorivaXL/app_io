import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/usecases/task_use_cases.dart';
import 'package:clean_kanban/core/result.dart';
import 'package:clean_kanban/core/exceptions.dart';
import 'package:clean_kanban/domain/events/board_events.dart';
import 'package:clean_kanban/domain/events/event_notifier.dart';

void main() {
  
  group('Task Use Cases', () {
    late KanbanColumn column;
    late KanbanColumn destination;
    late KanbanColumn doneColumn;
    late AddTaskUseCase addTaskUseCase;
    late DeleteTaskUseCase deleteTaskUseCase;
    late ReorderTaskUseCase reorderTaskUseCase;
    late MoveTaskUseCase moveTaskUseCase;
    late DeleteDoneTaskUseCase deleteDoneTaskUseCase;
    late ClearDoneColumnUseCase clearDoneColumnUseCase;
    late EditTaskUseCase editTaskUseCase;
    late EventNotifier eventNotifier;
    late List<BoardEvent> emittedEvents;
    late StreamSubscription<BoardEvent> subscription;

    setUp(() {
      column = KanbanColumn(id: 'col1', header: 'To Do', columnLimit: 3);
      destination = KanbanColumn(id: 'col2', header: 'In Progress', columnLimit: 2);
      doneColumn = KanbanColumn(id: 'col3', header: 'Done', columnLimit: 10);
      addTaskUseCase = AddTaskUseCase();
      deleteTaskUseCase = DeleteTaskUseCase();
      reorderTaskUseCase = ReorderTaskUseCase();
      moveTaskUseCase = MoveTaskUseCase();
      deleteDoneTaskUseCase = DeleteDoneTaskUseCase();
      clearDoneColumnUseCase = ClearDoneColumnUseCase();
      editTaskUseCase = EditTaskUseCase();

      emittedEvents = [];
      eventNotifier = EventNotifier();
      subscription = eventNotifier.subscribe((event) {
        emittedEvents.add(event);
      });
    });

    tearDown(() async {
      emittedEvents.clear();
      subscription.cancel();
    });

    test('should add a task to a column using AddTaskUseCase', () {
      // Arrange
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');

      // Act
      addTaskUseCase.execute(column, task);

      // Assert
      expect(column.tasks.length, equals(1));
      expect(column.tasks.first, equals(task));
    });

    test('should delete a task from a column using DeleteTaskUseCase', () {
      // Arrange
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      column.addTask(task);

      // Act
      final removed = deleteTaskUseCase.execute(column, 0);

      // Assert
      switch(removed) {
        case Success<Task> success:
          expect(success.value, equals(task));
          expect(column.tasks, isEmpty);
          break;
        default:
          fail('Expected Success<Task>, but got ${removed.runtimeType}');
      }
    });

    test('should reorder tasks in a column using ReorderTaskUseCase', () {
      // Arrange
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      final task3 = Task(id: '3', title: 'Task3', subtitle: 'Desc3');
      column.addTask(task1);
      column.addTask(task2);
      column.addTask(task3);

      // Act: move first task to last index.
      reorderTaskUseCase.execute(column, 0, 2);

      // Assert
      expect(column.tasks[0], equals(task2));
      expect(column.tasks[1], equals(task3));
      expect(column.tasks[2], equals(task1));
    });

    test('should move a task from one column to another using MoveTaskUseCase', () {
      // Arrange
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      column.addTask(task);

      // Act
      moveTaskUseCase.execute(column, 0, destination);

      // Assert
      expect(column.tasks, isEmpty);
      expect(destination.tasks.length, equals(1));
      expect(destination.tasks.first, equals(task));
    });

    test('should throw error if moving task to a full column using MoveTaskUseCase', () {
      // Arrange
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      final task3 = Task(id: '3', title: 'Task3', subtitle: 'Desc3');
      destination.addTask(task3);
      destination.addTask(task1); // destination now full for this test (limit: 2, will be reached after move if already at limit)
      column.addTask(task2);

      // Act & Assert
      expect(() => moveTaskUseCase.execute(column, 0, destination), throwsA(isA<Exception>()));
    });

    test('should throw error when adding a task to a full column using AddTaskUseCase', () {
      // Arrange
      final fullColumn = KanbanColumn(id: 'colFull', header: 'Full Column', columnLimit: 1);
      final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
      addTaskUseCase.execute(fullColumn, task1);
      
      // Act & Assert
      expect(() => addTaskUseCase.execute(fullColumn, task2), throwsA(isA<Exception>()));
    });

    group('DeleteDoneTaskUseCase', () {
      test('should delete a task from Done column', () {
        // Arrange
        final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
        addTaskUseCase.execute(doneColumn, task);

        // Act
        final removed = deleteDoneTaskUseCase.execute(doneColumn, 0);

        // Assert
        switch(removed) {
          case Success<Task> success:
            expect(success.value, equals(task));
            expect(doneColumn.tasks, isEmpty);
            break;
          default:
            fail('Expected Success<Task>, but got ${removed.runtimeType}');
        }
      });

      test('should throw error when deleting from non-Done column', () {
        // Arrange
        final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
        addTaskUseCase.execute(column, task);

        // Act & Assert
        switch(deleteDoneTaskUseCase.execute(column, 0)) {
          case Failure<Task> failure:
            expect(failure.message, equals('This operation is only allowed for the Done column'));
            break;
          default:
            fail('Expected Failure<String>, but got ${deleteDoneTaskUseCase.execute(column, 0).runtimeType}');
        }
      });
    });

    group('ClearDoneColumnUseCase', () {
      test('should clear all tasks from Done column', () {
        // Arrange
        final task1 = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
        final task2 = Task(id: '2', title: 'Task2', subtitle: 'Desc2');
        addTaskUseCase.execute(doneColumn, task1);
        addTaskUseCase.execute(doneColumn, task2);

        // Act
        final removedTasks = clearDoneColumnUseCase.execute(doneColumn);

        // Assert
        expect(doneColumn.tasks, isEmpty);
        expect(removedTasks, isA<Success<List<Task>>>());
        switch(removedTasks) {
          case Success<List<Task>> success:
            expect(success.value.length, equals(2));
            expect(success.value, contains(task1));
            expect(success.value, contains(task2));
            break;
          default:
            fail('Expected Success<List<Task>>, but got ${removedTasks.runtimeType}');
        }
        
      });

      test('should return empty list when clearing empty Done column', () {
        // Act
        final removedTasks = clearDoneColumnUseCase.execute(doneColumn);

        // Assert
        switch(removedTasks) {
          case Success<List<Task>> success:
            expect(success.value, isEmpty);
            break;
          default:
            fail('Expected Success<List<Task>>, but got ${removedTasks.runtimeType}');
        }
      });

      test('should throw error when clearing non-Done column', () {
        // Arrange
        final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
        addTaskUseCase.execute(column, task);

        // Act & Assert
        switch(clearDoneColumnUseCase.execute(column)) {
          case Failure<List<Task>> failure:
            expect(failure.message, equals('This operation is only allowed for the Done column'));
            break;
          default:
            fail('Expected Failure<String>, but got ${clearDoneColumnUseCase.execute(column).runtimeType}');
        }
      });
    });
    
    group('Edit task use case', () {
      test('should edit task title and subtitle successfully', () async {

        // Arrange
        final task = Task(id: 'task1', title: 'Original Title', subtitle: 'Original Subtitle');
        column.addTask(task);

        // Act
        final result = editTaskUseCase.execute(column, 0, 'Updated Title', 'Updated Subtitle');
        await Future.delayed(Duration(milliseconds: 10));
        // Assert
        expect(result, isA<Success>());
        expect(column.tasks[0].title, equals('Updated Title'));
        expect(column.tasks[0].subtitle, equals('Updated Subtitle'));
        expect(emittedEvents.length, equals(1));
        expect(emittedEvents.first, isA<TaskEditedEvent>());
      });

      test('should throw TaskOperationException when index is out of bounds', () {
        // Act & Assert
        expect(
          () => editTaskUseCase.execute(column, 999, 'Updated Title', 'Updated Subtitle'),
          throwsA(isA<TaskOperationException>())
        );
      });

      test('should not modify task when title and subtitle are same', () {
        // Arrange
        final task = Task(id: 'task1', title: 'Original Title', subtitle: 'Original Subtitle');
        column.addTask(task);

        // Act
        final result = editTaskUseCase.execute(
          column,
          0,
          'Original Title',
          'Original Subtitle'
        );

        // Assert
        expect(result, isA<Success>());
      });
    });
  });
}
