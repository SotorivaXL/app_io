import 'package:get_it/get_it.dart';
import 'package:clean_kanban/domain/repositories/board_repository.dart';
import 'package:clean_kanban/domain/usecases/board_use_cases.dart';
import 'package:clean_kanban/domain/usecases/task_use_cases.dart';

/// Global service locator instance.
///
/// Used throughout the application to access registered dependencies.
final GetIt getIt = GetIt.instance;

/// Configures dependency injection for the application.
///
/// This function sets up all dependencies needed by the Kanban board system,
/// including:
/// * Repository implementations
/// * Board-related use cases
/// * Task-related use cases
///
/// Parameters:
/// - [repository]: The concrete implementation of [BoardRepository] to use
void setupInjection(BoardRepository repository) {
  // Register repository as a lazy singleton.
  getIt.registerLazySingleton<BoardRepository>(() => repository);

  // Register board use cases.
  getIt.registerFactory(() => GetBoardUseCase(getIt<BoardRepository>()));
  getIt.registerFactory(() => SaveBoardUseCase(getIt<BoardRepository>()));
  getIt.registerFactory(() => UpdateBoardUseCase(getIt<BoardRepository>()));
  getIt.registerFactory(() => UpdateColumnLimitUseCase(getIt<BoardRepository>()));

  // Register task use cases.
  getIt.registerLazySingleton<AddTaskUseCase>(() => AddTaskUseCase());
  getIt.registerLazySingleton<DeleteTaskUseCase>(() => DeleteTaskUseCase());
  getIt.registerLazySingleton<ReorderTaskUseCase>(() => ReorderTaskUseCase());
  getIt.registerLazySingleton<MoveTaskUseCase>(() => MoveTaskUseCase());
  getIt.registerLazySingleton<DeleteDoneTaskUseCase>(() => DeleteDoneTaskUseCase());
  getIt.registerLazySingleton<ClearDoneColumnUseCase>(() => ClearDoneColumnUseCase());
  getIt.registerLazySingleton<EditTaskUseCase>(() => EditTaskUseCase());
}
