import 'package:flutter_test/flutter_test.dart';
import 'package:clean_kanban/domain/entities/board.dart';
import 'package:clean_kanban/domain/repositories/board_repository.dart';
import 'test_board_repository.dart';

void main() {
  group('BoardRepository', () {
    // Changed type from InMemoryBoardRepository to BoardRepository.
    late BoardRepository repository;

    setUp(() {
      // Using the concrete implementation.
      repository = TestBoardRepository();
    });

    test('should throw error when getting board if none saved', () async {
      // Act & Assert
      expect(() => repository.getBoard(), throwsA(isA<Exception>()));
    });

    test('should save and retrieve a board', () async {
      // Arrange
      final board = Board.simple();
      // Act
      await repository.saveBoard(board);
      final retrieved = await repository.getBoard();
      // Assert
      expect(retrieved, equals(board));
    });

    test('should update the board', () async {
      // Arrange
      final boardA = Board.simple();
      await repository.saveBoard(boardA);
      final boardB = Board(columns: [
        ...boardA.columns,
      ]);
      // Act
      await repository.updateBoard(boardB);
      final updated = await repository.getBoard();
      // Assert
      expect(updated, equals(boardB));
    });
  });
}
