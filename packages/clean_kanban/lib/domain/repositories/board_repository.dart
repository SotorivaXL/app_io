import 'package:clean_kanban/domain/entities/board.dart';

/// Repository interface for managing Kanban board persistence.
///
/// Provides methods to load, save, and update board data in storage.
/// Implementations can use different storage mechanisms (e.g., local storage, 
/// network storage) while adhering to this interface.
abstract class BoardRepository {
  /// Retrieves the saved board from storage.
  ///
  /// Returns a [Future] that completes with the loaded [Board].
  /// May throw storage-specific exceptions if the load operation fails.
  Future<Board> getBoard();

  /// Saves a new board to storage.
  ///
  /// Takes a [board] parameter representing the board to save.
  /// Returns a [Future] that completes when the save operation is finished.
  /// May throw storage-specific exceptions if the save operation fails.
  Future<void> saveBoard(Board board);

  /// Updates an existing board in storage.
  ///
  /// Takes a [board] parameter representing the updated board state.
  /// Returns a [Future] that completes when the update operation is finished.
  /// May throw storage-specific exceptions if the update operation fails.
  Future<void> updateBoard(Board board);
}
