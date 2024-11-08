import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class AddCompanyModel {
  final tfCompanyFocusNode = FocusNode();
  final tfCompanyTextController = TextEditingController();
  String? Function(String?)? tfCompanyTextControllerValidator;

  final tfEmailFocusNode = FocusNode();
  final tfEmailTextController = TextEditingController();
  String? Function(String?)? tfEmailTextControllerValidator;

  final tfContractFocusNode = FocusNode();
  final tfContractTextController = TextEditingController();
  final tfContractMask = MaskTextInputFormatter(mask: '##/##/####');
  String? Function(String?)? tfContractTextControllerValidator;

  final tfCnpjFocusNode = FocusNode();
  final tfCnpjTextController = TextEditingController();
  final tfCnpjMask = MaskTextInputFormatter(mask: '##.###.###/####-##');
  String? Function(String?)? tfCnpjTextControllerValidator;

  final tfPasswordFocusNode = FocusNode();
  final tfPasswordTextController = TextEditingController();
  bool tfPasswordVisibility = false;
  String? Function(String?)? tfPasswordTextControllerValidator;

  final tfPasswordConfirmFocusNode = FocusNode();
  final tfPasswordConfirmTextController = TextEditingController();
  bool tfPasswordConfirmVisibility = false;
  String? Function(String?)? tfPasswordConfirmTextControllerValidator;

  int countArtsValue = 0;
  int countVideosValue = 0;

  List<String>? checkboxGroupValues;

  void dispose() {
    tfCompanyFocusNode.dispose();
    tfCompanyTextController.dispose();
    tfEmailFocusNode.dispose();
    tfEmailTextController.dispose();
    tfContractFocusNode.dispose();
    tfContractTextController.dispose();
    tfCnpjFocusNode.dispose();
    tfCnpjTextController.dispose();
    tfPasswordFocusNode.dispose();
    tfPasswordTextController.dispose();
    tfPasswordConfirmFocusNode.dispose();
    tfPasswordConfirmTextController.dispose();
  }
}
