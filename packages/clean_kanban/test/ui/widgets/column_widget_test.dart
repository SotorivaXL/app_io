import 'package:clean_kanban/domain/entities/column.dart';
import 'package:clean_kanban/domain/entities/task.dart';
import 'package:clean_kanban/ui/widgets/column_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final columnTheme = KanbanColumnTheme();
  testWidgets('ColumnWidget displays header and tasks',
      (WidgetTester tester) async {
    // Arrange: Create a test column with two tasks.
    final testColumn =
        KanbanColumn(id: 'col1', header: 'Test Column', columnLimit: null);
    testColumn.addTask(Task(id: '1', title: 'Task1', subtitle: 'Desc1'));
    testColumn.addTask(Task(id: '2', title: 'Task2', subtitle: 'Desc2'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColumnWidget(
            column: testColumn,
            theme: columnTheme,
          ),
        ),
      ),
    );

    // Assert: The header and tasks are displayed.
    expect(find.text('Test Column'), findsOneWidget);
    expect(find.text('Task1'), findsOneWidget);
    expect(find.text('Task2'), findsOneWidget);
  });

  // test add task
  testWidgets('ColumnWidget adds a task when tapped',
      (WidgetTester tester) async {
    // Arrange: Create a test column with no tasks.
    final testColumn =
        KanbanColumn(id: 'col1', header: 'Test Column', columnLimit: null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColumnWidget(
            column: testColumn,
            theme: columnTheme,
            onAddTask: () {
              testColumn
                  .addTask(Task(id: '1', title: 'title', subtitle: 'subtitle'));
            },
          ),
        ),
      ),
    );

    // Act: Tap the add_rounded icon button to add new task
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Assert: The task is added to the column.
    expect(testColumn.tasks.length, equals(1));
  });

  testWidgets('Clear button shows only in Done column with tasks',
      (WidgetTester tester) async {
    final doneColumn = KanbanColumn(
      id: 'done',
      header: 'Done',
    );
    final task = Task(id: '1', title: 'Test Task', subtitle: 'Test');
    doneColumn.addTask(task);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ColumnWidget(
          column: doneColumn,
          theme: const KanbanColumnTheme(),
          onClearDone: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.clear_all), findsOneWidget);
  });

  testWidgets('Clear button not shown in non-Done column',
      (WidgetTester tester) async {
    final todoColumn = KanbanColumn(
      id: 'todo',
      header: 'To Do',
    );
    final task = Task(id: '1', title: 'Test Task', subtitle: 'Test');
    todoColumn.addTask(task);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ColumnWidget(
          column: todoColumn,
          theme: const KanbanColumnTheme(),
          onClearDone: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.clear_all), findsNothing);
  });

  testWidgets('Clear button shows confirmation dialog',
      (WidgetTester tester) async {
    bool clearCalled = false;
    final doneColumn = KanbanColumn(
      id: 'done',
      header: 'Done',
    );
    final task = Task(id: '1', title: 'Test Task', subtitle: 'Test');
    doneColumn.addTask(task);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ColumnWidget(
          column: doneColumn,
          theme: const KanbanColumnTheme(),
          onClearDone: () => clearCalled = true,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pumpAndSettle();

    expect(find.text('Clear all done tasks'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(clearCalled, true);
  });

  testWidgets('ColumnWidget uses custom header background colors from column properties',
      (WidgetTester tester) async {
    // Arrange: Create columns with custom header background colors
    final lightThemeColumn = KanbanColumn(
      id: 'lightCol', 
      header: 'Light Theme Column',
      headerBgColorLight: '#FFC6E0C6', // Custom light theme color
    );

    final bothThemesColumn = KanbanColumn(
      id: 'bothCol', 
      header: 'Both Themes Column',
      headerBgColorLight: '#FFE6FFE6', // Custom light theme color
      headerBgColorDark: '#FF004D00', // Custom dark theme color
    );

    // Test with light theme
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: Column(
            children: [
              ColumnHeader(
                column: lightThemeColumn,
                theme: columnTheme,
              ),
              ColumnHeader(
                column: bothThemesColumn,
                theme: columnTheme,
              ),
            ],
          ),
        ),
      ),
    );

    // Need to find the Container with the custom background color
    final lightThemeHeaderFinder = find.ancestor(
      of: find.text('Light Theme Column'),
      matching: find.byType(Container),
    ).first;
    
    final bothThemesLightHeaderFinder = find.ancestor(
      of: find.text('Both Themes Column'),
      matching: find.byType(Container),
    ).first;
    
    // Get the Container widgets
    final lightThemeContainer = tester.widget<Container>(lightThemeHeaderFinder);
    final bothThemesLightContainer = tester.widget<Container>(bothThemesLightHeaderFinder);
    
    // Extract and verify the background colors
    final lightThemeBoxDecoration = lightThemeContainer.decoration as BoxDecoration;
    expect(lightThemeBoxDecoration.color, equals(Color(0xFFC6E0C6))); // Custom color
    
    final bothThemesLightBoxDecoration = bothThemesLightContainer.decoration as BoxDecoration;
    expect(bothThemesLightBoxDecoration.color, equals(Color(0xFFE6FFE6))); // Custom color
  });

  testWidgets('ColumnWidget uses custom header background colors from column properties',
      (WidgetTester tester) async {
    // Arrange: Create columns with custom header background colors    
    final darkThemeColumn = KanbanColumn(
      id: 'darkCol', 
      header: 'Dark Theme Column',
      headerBgColorDark: '#FF006400', // Custom dark theme color
    );
    
    final bothThemesColumn = KanbanColumn(
      id: 'bothCol', 
      header: 'Both Themes Column',
      headerBgColorLight: '#FFE6FFE6', // Custom light theme color
      headerBgColorDark: '#FF004D00', // Custom dark theme color
    );

    // Test with dark theme
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Column(
            children: [
              ColumnHeader(
                column: darkThemeColumn,
                theme: columnTheme,
              ),
              ColumnHeader(
                column: bothThemesColumn,
                theme: columnTheme,
              ),
            ],
          ),
        ),
      ),
    );

    // Find the Container with the custom background color
    final darkThemeHeaderFinder = find.ancestor(
      of: find.text('Dark Theme Column'),
      matching: find.byType(Container),
    ).first;
    
    final bothThemesDarkHeaderFinder = find.ancestor(
      of: find.text('Both Themes Column'),
      matching: find.byType(Container),
    ).first;
    
    // Get the Container widgets
    final darkThemeContainer = tester.widget<Container>(darkThemeHeaderFinder);
    final bothThemesDarkContainer = tester.widget<Container>(bothThemesDarkHeaderFinder);
    
    // Extract and verify the background colors
    final darkThemeBoxDecoration = darkThemeContainer.decoration as BoxDecoration;
    expect(darkThemeBoxDecoration.color, equals(Color(0xFF006400))); // Custom color
    
    final bothThemesDarkBoxDecoration = bothThemesDarkContainer.decoration as BoxDecoration;
    expect(bothThemesDarkBoxDecoration.color, equals(Color(0xFF004D00))); // Custom color
  });

  testWidgets('ColumnWidget uses App Theme header background colors when column properties are null',
      (WidgetTester tester) async {
    // Arrange: Create columns with custom header background colors    
    final lightThemeColumn = KanbanColumn(
      id: 'lightCol', 
      header: 'Light Theme Column',
    );

    final bothThemesColumn = KanbanColumn(
      id: 'bothCol', 
      header: 'Both Themes Column',
    );

    // Test with dark theme
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: Column(
            children: [
              ColumnHeader(
                column: lightThemeColumn,
                theme: columnTheme,
              ),
              ColumnHeader(
                column: bothThemesColumn,
                theme: columnTheme,
              ),
            ],
          ),
        ),
      ),
    );

    // Find the Container with the custom background color
    final darkThemeHeaderFinder = find.ancestor(
      of: find.text('Light Theme Column'),
      matching: find.byType(Container),
    ).first;
    
    final bothThemesDarkHeaderFinder = find.ancestor(
      of: find.text('Both Themes Column'),
      matching: find.byType(Container),
    ).first;
    
    // Get the Container widgets
    final darkThemeContainer = tester.widget<Container>(darkThemeHeaderFinder);
    final bothThemesDarkContainer = tester.widget<Container>(bothThemesDarkHeaderFinder);
    
    // Extract and verify the background colors
    final darkThemeBoxDecoration = darkThemeContainer.decoration as BoxDecoration;
    expect(darkThemeBoxDecoration.color, equals(Colors.blue)); // Custom color
    
    final bothThemesDarkBoxDecoration = bothThemesDarkContainer.decoration as BoxDecoration;
    expect(bothThemesDarkBoxDecoration.color, equals(Colors.blue)); // Custom color
  });
}
