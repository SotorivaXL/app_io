import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? userName;
  String? userEmail; // Variável para o email do usuário
  Map<String, dynamic>? userData; // Para armazenar dados do usuário
  String? cnpj; // Para armazenar o CNPJ
  String? contract; // Para armazenar o contrato
  String? role; // Para armazenar a função

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _getUserData();
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
        // Primeiro tenta buscar na coleção 'empresas'
        final empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (empresaDoc.exists) {
          userData = empresaDoc.data();
          userName = userData?['NomeEmpresa'] ?? 'Nome não disponível';
          userEmail = user.email; // Pega o email do usuário logado
          cnpj = userData?['cnpj'] ?? 'CNPJ não disponível'; // Adiciona CNPJ
          contract = userData?['contract'] ?? 'Contrato não disponível'; // Adiciona contrato
        } else {
          // Se não encontrou, tenta buscar na coleção 'users'
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            userData = userDoc.data();
            userName = userData?['name'] ?? 'Nome não disponível';
            userEmail = user.email; // Pega o email do usuário logado
            role = userData?['role'] ?? 'Função não disponível'; // Adiciona função
          } else {
            showErrorDialog(context, 'Usuário não encontrado.', "Atenção");
            return;
          }
        }

        // Armazenar o nome do usuário em SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', userName ?? '');

        setState(() {}); // Atualiza o estado para re-renderizar a tela
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
      showErrorDialog(context, 'Um e-mail para redefinir sua senha foi enviado para $userEmail.', "Sucesso");
    } catch (e) {
      showErrorDialog(context, 'Erro ao enviar o e-mail: $e', "Erro");
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<appAuthProvider.AuthProvider>(context);
    final user = authProvider.user;

    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Perfil do Usuário'),
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'BrandingSF',
            fontWeight: FontWeight.w900,
            fontSize: 26,
            color: Theme.of(context).colorScheme.outline,
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.outline,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: userName == null
                ? CircularProgressIndicator()
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$userName',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  '${user?.email ?? 'Email não disponível'}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                SizedBox(height: 10),
                if (cnpj != null) ...[
                  Text(
                    'CNPJ: ${cnpj ?? 'CNPJ não disponível'}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Final do contrato: ${contract ?? 'Contrato não disponível'}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                if (role != null) ...[
                  Text(
                    'Função: ${role ?? 'Função não disponível'}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ],
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _sendPasswordResetEmail(); // Chama a função para enviar o e-mail
                  },
                  child: Text('Alterar senha'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                    foregroundColor: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}