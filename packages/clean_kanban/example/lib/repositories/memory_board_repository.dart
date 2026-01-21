import 'package:clean_kanban/clean_kanban.dart';

class MemoryBoardRepository implements BoardRepository {
  Board? _board;

  @override
  Future<Board> getBoard() async {
    if (_board == null) {
      throw Exception('No board saved.');
    }
    return _board!;
  }

  @override
  Future<void> saveBoard(Board board) async {
    _board = board;
  }

  @override
  Future<void> updateBoard(Board board) async {
    if (_board == null) {
      throw Exception('No board to update.');
    }
    _board = board;
  }
}
