import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:clean_kanban/domain/repositories/board_repository.dart';
import 'package:clean_kanban/domain/usecases/board_use_cases.dart';
import 'package:clean_kanban/domain/usecases/task_use_cases.dart';
import 'package:clean_kanban/injection_container.dart';
import 'domain/repositories/test_board_repository.dart';

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    // Reset GetIt to avoid duplicate registrations.
    await getIt.reset();
    setupInjection(TestBoardRepository());
  });

  test('should register BoardRepository', () {
    final repository = getIt<BoardRepository>();
    expect(repository, isNotNull);
  });

  test('should resolve board use cases', () {
    final getBoardUseCase = getIt<GetBoardUseCase>();
    final saveBoardUseCase = getIt<SaveBoardUseCase>();
    final updateBoardUseCase = getIt<UpdateBoardUseCase>();

    expect(getBoardUseCase, isNotNull);
    expect(saveBoardUseCase, isNotNull);
    expect(updateBoardUseCase, isNotNull);
  });

  test('should resolve task use cases', () {
    final addTaskUseCase = getIt<AddTaskUseCase>();
    final deleteTaskUseCase = getIt<DeleteTaskUseCase>();
    final reorderTaskUseCase = getIt<ReorderTaskUseCase>();
    final moveTaskUseCase = getIt<MoveTaskUseCase>();

    expect(addTaskUseCase, isNotNull);
    expect(deleteTaskUseCase, isNotNull);
    expect(reorderTaskUseCase, isNotNull);
    expect(moveTaskUseCase, isNotNull);
  });
}
