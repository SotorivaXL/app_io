import 'dart:convert';
import 'package:clean_kanban/clean_kanban.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesBoardRepository implements BoardRepository {
  static const String _boardKey = 'kanban_board';

  @override
  Future<Board> getBoard() async {
    final prefs = await SharedPreferences.getInstance();
    final boardJson = prefs.getString(_boardKey);

    if (boardJson == null) {
      throw Exception('No board saved.');
    }

    final boardMap = jsonDecode(boardJson) as Map<String, dynamic>;
    return Board.fromConfig(boardMap);
  }

  @override
  Future<void> saveBoard(Board board) async {
    final prefs = await SharedPreferences.getInstance();
    final boardJson = jsonEncode(board.toJson());
    await prefs.setString(_boardKey, boardJson);
  }

  @override
  Future<void> updateBoard(Board board) async {
    await saveBoard(board);
  }
}
