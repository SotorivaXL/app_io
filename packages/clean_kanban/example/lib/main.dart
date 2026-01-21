import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clean_kanban/clean_kanban.dart';
import 'repositories/shared_preferences_board_repository.dart';
import 'repositories/theme_provider.dart'; 
import 'theme.dart'; 
import 'screens/column_settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupInjection(SharedPreferencesBoardRepository());
  EventNotifier().subscribe((event) {
    switch (event) {
      case BoardLoadedEvent loaded:
        debugPrint('Board loaded: ${loaded.board}');
      case BoardSavedEvent saved:
        debugPrint('Board saved: ${saved.board}');
      case TaskMovedEvent moved:
        debugPrint('Task "${moved.task.title}" moved from ${moved.source.header} to ${moved.destination.header}');
      case TaskAddedEvent added:
        debugPrint('New task added: "${added.task.title}"');
      case TaskRemovedEvent removed:
        debugPrint('Task removed: "${removed.task.title}"');
      case TaskEditedEvent edited:
        debugPrint('Task edited: title="${edited.newTask.title}"');
      case TaskReorderedEvent reordered:
        debugPrint('Task reordered: "${reordered.task.title}" moved from ${reordered.oldIndex} to ${reordered.newIndex} in ${reordered.column.header}');
      case DoneColumnClearedEvent cleared:
        debugPrint('${cleared.removedTasks.length} tasks cleared from Done column');
    }
  });
  runApp(const MyExampleApp());
}

class MyExampleApp extends StatelessWidget {
  const MyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create an instance of MaterialTheme with default TextTheme
    final materialTheme = MaterialTheme(ThemeData().textTheme);
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) {
          final boardProv = BoardProvider();
          boardProv.loadBoard(config: _boardConfig);
          boardProv.addListener(() {
            // auto save function
            if (boardProv.board != null) {
              boardProv.saveBoard();
            }
          });
          return boardProv;
        }),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Clean Kanban Example',
            theme: materialTheme.light(),
            darkTheme: materialTheme.dark(),
            themeMode: themeProvider.themeMode,
            home: const HomeScreen(),
          );
        }
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final boardProv = Provider.of<BoardProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    // Create Kanban themes that match our Material themes
    final materialTheme = MaterialTheme(Theme.of(context).textTheme);
    final kanbanLightTheme = KanbanTheme.fromTheme(materialTheme.light());
    final kanbanDarkTheme = KanbanTheme.fromTheme(materialTheme.dark());
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kanban Board'),
        actions: [
          // Add save button
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              if (boardProv.board != null) {
                boardProv.saveBoard();
              }
            },
          ),
          // Add theme toggle button
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              themeProvider.toggleTheme();
            },
          ),
          // Add navigation to column settings screen
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ColumnSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: BoardWidget(
        theme: themeProvider.themeMode == ThemeMode.dark 
          ? kanbanDarkTheme 
          : kanbanLightTheme,
      ),
    );
  }
}

const Map<String, dynamic> _boardConfig = {
  'columns': [
    {
      'id': 'todo',
      'header': 'To Do',
      "headerBgColorLight": "#FFF6F6F6",  // Light theme color (white-ish)
      "headerBgColorDark": "#FF333333",   // Dark theme color (dark gray)
      'limit': 15,
      'tasks': [
        {'id': '1', 'title': 'Task 1', 'subtitle': 'Description 1'},
        {'id': '2', 'title': 'Task 2', 'subtitle': 'Description 2'},
      ]
    },
    {
      'id': 'doing',
      'header': 'In Progress',
      'limit': 1,
      'tasks': [],
      'canAddTask': false
    },
    {
      'id': 'review',
      'header': 'Review',
      'limit': null,
      'tasks': [],
      'canAddTask': false
    },
    {
      'id': 'done',
      'header': 'Done',
      "headerBgColorLight": "#FFA6CCA6",  // Light theme color (light green)
      "headerBgColorDark": "#FF006400",   // Dark theme color (dark green)
      'limit': null,
      'tasks': [],
      'canAddTask': false
    }
  ]
};
