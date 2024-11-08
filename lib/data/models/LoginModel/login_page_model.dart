import 'package:flutter/material.dart';

class LoginPageModel with ChangeNotifier {
  final FocusNode unfocusNode = FocusNode();
  TextEditingController? tfEmailTextController;
  TextEditingController? tfPasswordTextController;
  bool tfPasswordVisibility = false;

  void initState() {
    tfEmailTextController = TextEditingController();
    tfPasswordTextController = TextEditingController();
  }

  void dispose() {
    unfocusNode.dispose();
    tfEmailTextController?.dispose();
    tfPasswordTextController?.dispose();
  }

  void togglePasswordVisibility() {
    tfPasswordVisibility = !tfPasswordVisibility;
    notifyListeners();
  }
}
