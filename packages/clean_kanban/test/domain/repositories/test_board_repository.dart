import 'package:clean_kanban/clean_kanban.dart';

class TestBoardRepository implements BoardRepository {
  Board? _board;

  set board(Board? board) {
    _board = board;
  }

  bool throwsOnGet = false;
  bool throwsOnSave = false;
  bool throwsOnUpdate = false;

  @override
  Future<Board> getBoard() async {
    if (throwsOnGet) throw Exception('Test exception');
    if (_board == null) throw Exception('No board saved.');
    return _board!;
  }

  @override
  Future<void> saveBoard(Board board) async {
    if (throwsOnSave) throw Exception('Test exception');
    _board = board;
  }

  @override
  Future<void> updateBoard(Board board) async {
    if (throwsOnUpdate) throw Exception('Test exception');
    if (_board == null) throw Exception('No board to update.');
    _board = board;
  }
}
