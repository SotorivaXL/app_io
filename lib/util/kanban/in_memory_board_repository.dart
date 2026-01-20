import 'package:clean_kanban/clean_kanban.dart';

/// Repositório simples em memória (não persiste em disco).
class InMemoryBoardRepository implements BoardRepository {
  Board? _board;

  @override
  Future<Board> getBoard() async {
    if (_board == null) {
      throw Exception('No board saved');
    }
    return _board!;
  }

  @override
  Future<void> saveBoard(Board board) async {
    _board = board;
  }

  @override
  Future<void> updateBoard(Board board) async {
    _board = board;
  }
}