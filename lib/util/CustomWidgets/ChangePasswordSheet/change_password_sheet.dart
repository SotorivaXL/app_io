import 'package:app_io/util/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordSheet extends StatefulWidget {
  final String targetUid; // UID do usuário que terá a senha alterada
  final VoidCallback? onClose; // Callback opcional

  ChangePasswordSheet({required this.targetUid, this.onClose});

  @override
  _ChangePasswordSheetState createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  bool _obscureText = true;
  TextEditingController _newPasswordController = TextEditingController();
  bool _isChangingPassword = false; // Indica se a senha está sendo alterada

  Future<void> _changePassword() async {
    String newPassword = _newPasswordController.text;

    if (newPassword.isEmpty) {
      await _showErrorDialog(
          context, 'Por favor, preencha o campo de nova senha.', 'Erro');
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      // Chamada da Cloud Function
      HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('changeUserPassword');
      await callable.call(<String, dynamic>{
        'uid': widget.targetUid,
        'newPassword': newPassword,
      });

      // Exibe sucesso e limpa o campo
      await _showErrorDialog(
          context, 'Senha atualizada com sucesso!', 'Sucesso');
      _newPasswordController.clear(); // Limpa o campo após sucesso

      // Fecha o BottomSheet principal após sucesso
      if (mounted) {
        Navigator.of(context).pop(); // Fecha o ChangePasswordSheet
        widget.onClose?.call(); // Notifica o estado do botão
      }
    } on FirebaseFunctionsException catch (e) {
      // Exibe erro detalhado
      await _showErrorDialog(
          context, 'Erro ao atualizar a senha: ${e.message}', 'Erro');
    } catch (e) {
      // Exibe erro genérico
      await _showErrorDialog(context, 'Erro ao atualizar a senha: $e', 'Erro');
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _showErrorDialog(
      BuildContext context, String message, String title) async {
    FocusScope.of(context).unfocus();

    var colorTitle = Theme.of(context).colorScheme.onSecondary;

    if (title == "Erro") {
      colorTitle = Theme.of(context).colorScheme.error;
    } else if (title == "Sucesso") {
      colorTitle = Theme.of(context).colorScheme.onTertiary;
    } else if (title == "Atenção") {
      colorTitle = Color(0xffdc9f21);
    }

    // Aguarda até que o usuário feche o dialog
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      backgroundColor: Theme.of(context).colorScheme.background,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: colorTitle),
              ),
              SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Fecha o BottomSheet do diálogo
                    },
                    child: Text(
                      'Entendi',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Alterar Senha',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 16.0),
              TextField(
                controller: _newPasswordController,
                obscureText: _obscureText,
                decoration: InputDecoration(
                  label: Text('Nova senha'),
                  labelStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  hintText: 'Digite a nova senha',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  prefixIcon: Icon(
                    Icons.lock,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility : Icons.visibility_off,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureText = !_obscureText;
                      });
                    },
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: kIsWeb
                      ? EdgeInsets.symmetric(vertical: 25)
                      : EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              SizedBox(height: 24.0),
              _isChangingPassword
                  ? CircularProgressIndicator() // Exibe um indicador de progresso
                  : ElevatedButton(
                      onPressed: _isChangingPassword ? null : _changePassword,
                      child: Text(
                        'Confirmar',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
              SizedBox(height: 16.0),
            ],
          ),
        ),
      ),
    );
  }
}
