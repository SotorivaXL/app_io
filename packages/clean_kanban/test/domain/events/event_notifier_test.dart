import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/events/event_notifier.dart';
import 'package:clean_kanban/domain/events/board_events.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/entities/task.dart';

void main() {
  group('EventNotifier', () {
    late EventNotifier notifier;

    setUp(() {
      // Reuse the singleton instance.
      notifier = EventNotifier();
    });

    test('should notify BoardLoadedEvent when board is loaded', () async {
      final board = Board.simple();
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(BoardLoadedEvent(board));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<BoardLoadedEvent>());
      subscription.cancel();
    });

    test('should notify BoardSavedEvent when board is saved', () async {
      final board = Board.simple();
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(BoardSavedEvent(board));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<BoardSavedEvent>());
      subscription.cancel();
    });

    test('should notify TaskAddedEvent when a task is added', () async {
      final column =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(TaskAddedEvent(task, column));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<TaskAddedEvent>());
      subscription.cancel();
    });

    test('should notify TaskRemovedEvent when a task is removed', () async {
      final column =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(TaskRemovedEvent(task, column));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<TaskRemovedEvent>());
      subscription.cancel();
    });

    test('should notify TaskMovedEvent when a task is moved', () async {
      final source =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final destination =
          KanbanColumn(id: 'col2', header: 'Done', columnLimit: null);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(TaskMovedEvent(task, source, destination));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<TaskMovedEvent>());
      subscription.cancel();
    });

    test('should notify TaskEditedEvent when a task is edited', () async {
      final source =
          KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final updatedTask = task.copyWith(title: 'Updated Task', subtitle: 'Updated Desc');
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) {
        events.add(event);
      });

      notifier.notify(TaskEditedEvent(task, updatedTask, source));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first, isA<TaskEditedEvent>());
      subscription.cancel();
    });

    test('should handle multiple subscribers', () async {
      final events1 = <BoardEvent>[];
      final events2 = <BoardEvent>[];
      
      final subscription1 = notifier.subscribe((event) => events1.add(event));
      final subscription2 = notifier.subscribe((event) => events2.add(event));

      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final column = KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      
      notifier.notify(TaskAddedEvent(task, column));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      
      subscription1.cancel();
      subscription2.cancel();
    });

    test('should stop receiving events after unsubscribe', () async {
      final events = <BoardEvent>[];
      final subscription = notifier.subscribe((event) => events.add(event));
      
      final task = Task(id: '1', title: 'Task1', subtitle: 'Desc1');
      final column = KanbanColumn(id: 'col1', header: 'To Do', columnLimit: null);
      
      notifier.notify(TaskAddedEvent(task, column));
      await Future.delayed(Duration(milliseconds: 10));
      subscription.cancel();
      
      notifier.notify(TaskAddedEvent(task, column));
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
    });

    test('should properly dispose stream controller', () async {
      notifier.dispose();
      
      expect(() => notifier.notify(BoardLoadedEvent(Board.simple())), 
        throwsStateError);
    });
  });
}
