import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

class AddCollaboratorsModel extends ChangeNotifier {
  ///  State fields for stateful widgets in this page.

  // State field(s) for tfName widget.
  FocusNode tfNameFocusNode = FocusNode();
  TextEditingController tfNameTextController = TextEditingController();
  String? Function(BuildContext, String?)? tfNameTextControllerValidator;

  // State field(s) for tfEmail widget.
  FocusNode tfEmailFocusNode = FocusNode();
  TextEditingController tfEmailTextController = TextEditingController();
  String? Function(BuildContext, String?)? tfEmailTextControllerValidator;

  // State field(s) for tfRole widget.
  FocusNode tfRoleFocusNode = FocusNode();
  TextEditingController tfRoleTextController = TextEditingController();
  String? Function(BuildContext, String?)? tfRoleTextControllerValidator;

  // State field(s) for tfPassword widget.
  FocusNode tfPasswordFocusNode = FocusNode();
  TextEditingController tfPasswordTextController = TextEditingController();
  bool tfPasswordVisibility = false;
  String? Function(BuildContext, String?)? tfPasswordTextControllerValidator;

  // State field(s) for tfPasswordConfirm widget.
  FocusNode tfPasswordConfirmFocusNode = FocusNode();
  TextEditingController tfPasswordConfirmTextController = TextEditingController();
  bool tfPasswordConfirmVisibility = false;
  String? Function(BuildContext, String?)? tfPasswordConfirmTextControllerValidator;

  // State field(s) for CheckboxGroup widget.
  ValueNotifier<List<String>> checkboxGroupValuesNotifier = ValueNotifier<List<String>>([]);

  List<String> get checkboxGroupValues => checkboxGroupValuesNotifier.value;
  set checkboxGroupValues(List<String> values) {
    checkboxGroupValuesNotifier.value = values;
    notifyListeners();
  }

  @override
  void initState() {
    // Inicializa a visibilidade das senhas
    tfPasswordVisibility = false;
    tfPasswordConfirmVisibility = false;
  }

  @override
  void dispose() {
    // Descartar os controladores e focus nodes
    tfNameFocusNode.dispose();
    tfNameTextController.dispose();

    tfEmailFocusNode.dispose();
    tfEmailTextController.dispose();

    tfRoleFocusNode.dispose();
    tfRoleTextController.dispose();

    tfPasswordFocusNode.dispose();
    tfPasswordTextController.dispose();

    tfPasswordConfirmFocusNode.dispose();
    tfPasswordConfirmTextController.dispose();

    checkboxGroupValuesNotifier.dispose();

    super.dispose();
  }

  // Métodos adicionais para gerenciar o estado da visibilidade da senha
  void togglePasswordVisibility() {
    tfPasswordVisibility = !tfPasswordVisibility;
    notifyListeners();
  }

  void togglePasswordConfirmVisibility() {
    tfPasswordConfirmVisibility = !tfPasswordConfirmVisibility;
    notifyListeners();
  }
}
