import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? userName;
  String? userEmail;
  Map<String, dynamic>? userData;
  String? cnpj;
  String? contract;
  String? role;
  bool notificationsEnabled = true;
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _getUserData();
    _loadPreferences();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName');
    });
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (empresaDoc.exists) {
          userData = empresaDoc.data();
          userName = userData?['NomeEmpresa'] ?? 'Nome não disponível';
          userEmail = user.email;
          cnpj = userData?['cnpj'] ?? 'CNPJ não disponível';
          contract = userData?['contract'] ?? 'Contrato não disponível';
        } else {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            userData = userDoc.data();
            userName = userData?['name'] ?? 'Nome não disponível';
            userEmail = user.email;
            role = userData?['role'] ?? 'Função não disponível';
          } else {
            showErrorDialog(context, 'Usuário não encontrado.', "Atenção");
            return;
          }
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', userName ?? '');

        setState(() {});
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', "Erro");
      }
    } else {
      showErrorDialog(context, 'Usuário não está autenticado.', "Atenção");
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: userEmail!);
      showErrorDialog(
          context,
          'Um e-mail para redefinir sua senha foi enviado para $userEmail.',
          "Sucesso");
    } catch (e) {
      showErrorDialog(context, 'Erro ao enviar o e-mail: $e', "Erro");
    }
  }

  Future<void> _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _updatePreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', notificationsEnabled);
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  void _showLogoutConfirmationDialog() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
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
                'Confirmar Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Tem certeza que deseja sair?',
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
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancelar',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondary)),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final authProvider =
                          Provider.of<appAuthProvider.AuthProvider>(context,
                              listen: false);
                      await authProvider.signOut();
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: Text('Sair',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            "Ativar/Desativar Notificações",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              color: Theme.of(context).colorScheme.surfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              notificationsEnabled = !notificationsEnabled;
              _updatePreferences();
            });
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 300),
            width: 90,
            height: 45,
            decoration: BoxDecoration(
              color: notificationsEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onPrimary,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  offset: Offset(0, 4),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: Duration(milliseconds: 300),
                  alignment: notificationsEnabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: Icon(
                      notificationsEnabled
                          ? Icons.notifications
                          : Icons.notifications_off,
                      color: notificationsEnabled
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: userName == null
                  ? CircularProgressIndicator()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(
                            Icons.camera_alt,
                            color: Theme.of(context).colorScheme.outline,
                            size: 40,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          '$userName',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextField(
                          readOnly: true,
                          enableInteractiveSelection: false,
                          controller: TextEditingController(
                              text: userEmail ?? 'Email não disponível'),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        if (cnpj != null) ...[
                          TextField(
                            readOnly: true,
                            controller: TextEditingController(
                                text: cnpj ?? 'CNPJ não disponível'),
                            decoration: InputDecoration(
                              labelText: 'CNPJ',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                              border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                              focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            ),
                          ),
                          SizedBox(height: 20),
                          TextField(
                            readOnly: true,
                            enableInteractiveSelection: false,
                            controller: TextEditingController(
                                text: contract ?? 'Contrato não disponível'),
                            decoration: InputDecoration(
                              labelText: 'Final do contrato',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                        ],
                        if (role != null) ...[
                          TextField(
                            readOnly: true,
                            enableInteractiveSelection: false,
                            controller: TextEditingController(
                                text: role ?? 'Função não disponível'),
                            decoration: InputDecoration(
                              labelText: 'Função',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _sendPasswordResetEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.outline,
                            minimumSize: Size(200, 60),
                          ),
                          label: Text(
                            'Alterar senha',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          icon: Icon(
                            Icons.settings_backup_restore_rounded,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        SizedBox(height: 30),
                        _buildNotificationToggle(),
                      ],
                    ),
            ),
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Theme.of(context).colorScheme.error,
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              child: InkWell(
                onTap: _showLogoutConfirmationDialog,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
