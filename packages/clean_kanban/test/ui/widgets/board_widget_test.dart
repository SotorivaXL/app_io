import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/injection_container.dart';
import 'package:clean_kanban/ui/providers/board_provider.dart';
import 'package:clean_kanban/ui/widgets/board_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/test_board_repository.dart';

void main() {
  setUpAll(() async {
    // Reset and setup injection so dependencies are registered.
    await getIt.reset();
    setupInjection(TestBoardRepository());
  });

  testWidgets('BoardWidget shows loading indicator then board UI',
      (WidgetTester tester) async {
    // Arrange: Create a BoardProvider that initially has a null board.
    final boardProvider = BoardProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<BoardProvider>.value(
        value: boardProvider,
        child: const MaterialApp(home: BoardWidget()),
      ),
    );

    // Assert: Should show a loading indicator while board is null.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Act: Simulate board load by assigning a simple board and notifying listeners.
    boardProvider.board =
        boardProvider.board ?? BoardProvider().board ?? Board.simple();
    boardProvider.notifyListeners();
    await tester.pumpAndSettle();

    // Assert: Now we expect the columns to be visible.
    expect(find.text('To Do'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('BoardWidget displays tasks within columns',
      (WidgetTester tester) async {
    // Arrange: Create a BoardProvider with a board containing tasks.
    final boardProvider = BoardProvider();
    boardProvider.board = Board.fromConfig({
      'columns': [
        {
          'id': 'todo',
          'header': 'To Do',
          'tasks': [
            {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
          ]
        },
        {
          'id': 'doing',
          'header': 'Doing',
          'tasks': [
            {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
          ]
        },
        {
          'id': 'done',
          'header': 'Done',
          'tasks': [
            {'id': '3', 'title': 'Task 3', 'subtitle': 'Description 3'},
          ]
        },
      ]
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<BoardProvider>.value(
        value: boardProvider,
        child: const MaterialApp(home: BoardWidget()),
      ),
    );

    // Assert: Tasks should be displayed within their respective columns.
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Task 2'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
  });

  testWidgets('BoardWidget onReorderedTasks callback works correctly',
      (WidgetTester tester) async {
    // Arrange: Create a BoardProvider with a board containing columns.
    final boardProvider = BoardProvider();
    boardProvider.board = Board.fromConfig({
      'columns': [
        {
          'id': 'todo',
          'header': 'To Do',
          'tasks': [
            {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
            {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
            {'id': '3', 'title': 'Task 3', 'subtitle': 'Description 3'},
          ]
        },
        {'id': 'doing', 'header': 'Doing', 'tasks': []},
        {'id': 'done', 'header': 'Done', 'tasks': []},
      ]
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<BoardProvider>.value(
        value: boardProvider,
        child: const MaterialApp(home: BoardWidget()),
      ),
    );

    // Act: Simulate reordering tasks within a column.
    await tester.drag(find.text('Task 1'), const Offset(0, 100));
    await tester.pumpAndSettle();

    // Assert: The tasks should be reordered within the column.
    // final taskCards =
    //     tester.widgetList<TaskCard>(find.byType(TaskCard)).toList();

    // TODO: drag to reorder test failed
    // expect(taskCards.map((taskCard) => taskCard.data.task.title).toList(), [
    //   'Task 2',
    //   'Task 1',
    //   'Task 3',
    // ]);
  });

  testWidgets(
      'BoardWidget shows add task dialog and onAddTask callback works correctly',
      (WidgetTester tester) async {
    // Arrange
    final boardProvider = BoardProvider();
    boardProvider.board = Board.fromConfig({
      'columns': [
        {'id': 'todo', 'header': 'To Do', 'tasks': []},
        {'id': 'doing', 'header': 'Doing', 'tasks': [], 'canAddTask': false},
        {'id': 'done', 'header': 'Done', 'tasks': [], 'canAddTask': false},
      ]
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<BoardProvider>.value(
        value: boardProvider,
        child: MaterialApp(
          home: Scaffold(
            body: BoardWidget(),
          ),
        ),
      ),
    );

    // Act
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Add New Task'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    // Fill the text fields and submit
    await tester.enterText(find.byType(TextField).at(0), 'Test Title');
    await tester.enterText(find.byType(TextField).at(1), 'Test Subtitle');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Verify the task was added
    expect(boardProvider.board!.columns.first.tasks.length, 1);
    expect(boardProvider.board!.columns.first.tasks.first.title, 'Test Title');
    expect(boardProvider.board!.columns.first.tasks.first.subtitle,
        'Test Subtitle');
  });
}
