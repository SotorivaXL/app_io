import 'package:flutter/material.dart';
import 'package:app_io/data/models/UserModel/user_model.dart';

class UserProvider with ChangeNotifier {
  List<UserModel> _users = [];

  List<UserModel> get users => _users;

  void fetchUsers() {
    // Lógica para buscar usuários
    // Exemplo:
    _users = [
      UserModel(id: 1, name: 'Usuário 1', email: 'user1@example.com'),
      UserModel(id: 2, name: 'Usuário 2', email: 'user2@example.com'),
    ];
    notifyListeners();
  }

  void addUser(UserModel user) {
    _users.add(user);
    notifyListeners();
  }

  void removeUser(int id) {
    _users.removeWhere((user) => user.id == id);
    notifyListeners();
  }

  void updateUser(UserModel user) {
    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      _users[index] = user;
      notifyListeners();
    }
  }
}
