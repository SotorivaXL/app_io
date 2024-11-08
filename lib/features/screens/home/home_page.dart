import 'dart:async';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as custom_auth_provider;
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/features/screens/profile/profile_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool hasGerenciarParceirosAccess = false;
  bool hasGerenciarColaboradoresAccess = false;
  bool hasConfigurarDashAccess = false;
  bool hasCriarFormAccess = false;
  bool hasCriarCampanhaAccess = false;
  bool isLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;

  String? userName;

  @override
  void initState() {
    super.initState();
    _determineUserDocumentAndListen();
    _getUserData();
  }

  Future<void> _determineUserDocumentAndListen() async {
    setState(() {
      isLoading = true;
    });

    final authProvider = Provider.of<custom_auth_provider.AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      try {
        // Verifica se o documento existe na coleção 'empresas'
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _listenToUserDocument('empresas', user.uid);
        } else {
          // Se não existir em 'empresas', verifica em 'users'
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            _listenToUserDocument('users', user.uid);
          } else {
            print("Documento do usuário não encontrado nas coleções 'empresas' ou 'users'.");
            setState(() {
              isLoading = false;
            });
          }
        }
      } catch (e) {
        print("Erro ao recuperar as permissões do usuário: $e");
        setState(() {
          isLoading = false;
        });
      }
    } else {
      print("Usuário não está autenticado.");
      setState(() {
        isLoading = false;
      });
    }
  }

  void _listenToUserDocument(String collectionName, String userId) {
    _userDocSubscription = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(userId)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists) {
        _updatePermissions(userDoc);
      } else {
        print("Documento do usuário não encontrado na coleção '$collectionName'.");
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final userData = userDoc.data();

    setState(() {
      hasGerenciarParceirosAccess = userData?['gerenciarParceiros'] ?? false;
      hasGerenciarColaboradoresAccess = userData?['gerenciarColaboradores'] ?? false;
      hasConfigurarDashAccess = userData?['configurarDash'] ?? false;
      hasCriarFormAccess = userData?['criarForm'] ?? false;
      hasCriarCampanhaAccess = userData?['criarCampanha'] ?? false;
      isLoading = false;
    });
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Tenta buscar o documento do usuário na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          // Se encontrado na coleção 'users', armazena e exibe o nome do usuário
          final data = userDoc.data();
          if (data != null) {
            String userName = data['name'] ?? '';
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString('userName', userName);

            setState(() {
              this.userName = userName;
            });
          }
        } else {
          // Se não encontrado na coleção 'users', tenta buscar na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            final data = empresaDoc.data();
            if (data != null) {
              String userName = data['NomeEmpresa'] ?? '';
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('userName', userName);

              setState(() {
                this.userName = userName;
              });
            }
          } else {
            // Se não encontrado em nenhuma das coleções, exibe mensagem de erro
            showErrorDialog(context,
                'Documento do usuário não encontrado, aguarde e tente novamente mais tarde!.', 'Atenção');
          }
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
    }
  }

  void _navigateTo(BuildContext context, String routeName) {
    final isAdminPanel = routeName == '/admin';

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _getPageByRouteName(routeName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (isAdminPanel) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          } else {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);

            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          }
        },
      ),
    );
  }

  Widget _getPageByRouteName(String routeName) {
    switch (routeName) {
      case '/dashboard':
        return DashboardPage();
      case '/leads':
        return LeadsPage();
      case '/admin':
        return AdminPanelPage();
      default:
        return HomePage();
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider =
    Provider.of<custom_auth_provider.AuthProvider>(context);

    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isLoading
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bem-vindo ${userName ?? ''}',
                  style: TextStyle(
                      fontFamily: 'BrandingSF',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSecondary),
                ),
                SizedBox(height: 20),
                Card(
                  color: Theme.of(context).colorScheme.primary,
                  child: ListTile(
                    leading: Icon(Icons.show_chart),
                    title: Text(
                      'Relatórios de Vendas',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    textColor: Theme.of(context).colorScheme.outline,
                    iconColor: Theme.of(context).colorScheme.outline,
                    onTap: () async {
                      showErrorDialog(
                          context, "Função estará disponível em breve...", 'Aguarde');
                    },
                  ),
                ),
                SizedBox(height: 20),
                Card(
                  color: Theme.of(context).colorScheme.primary,
                  child: ListTile(
                    leading: Icon(Icons.person),
                    title: Text(
                      'Perfil de Usuário',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    textColor: Theme.of(context).colorScheme.outline,
                    iconColor: Theme.of(context).colorScheme.outline,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage()));
                    },
                  ),
                ),
                SizedBox(height: 20),
                Card(
                  color: Theme.of(context).colorScheme.primary,
                  child: ListTile(
                    leading: Icon(Icons.settings),
                    title: Text(
                      'Configurações',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    textColor: Theme.of(context).colorScheme.outline,
                    iconColor: Theme.of(context).colorScheme.outline,
                    onTap: () {
                      showErrorDialog(
                          context, "Função estará disponível em breve...", 'Aguarde');
                    },
                  ),
                ),
                SizedBox(height: 20),
                // Exibir o card do Painel Administrativo somente se pelo menos uma permissão for verdadeira
                if (hasGerenciarParceirosAccess ||
                    hasGerenciarColaboradoresAccess ||
                    hasConfigurarDashAccess ||
                    hasCriarFormAccess ||
                    hasCriarCampanhaAccess)
                  Card(
                    color: Theme.of(context).colorScheme.primary,
                    child: ListTile(
                      leading: Icon(Icons.admin_panel_settings),
                      title: Text(
                        'Painel Administrativo',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.outline),
                      ),
                      textColor: Theme.of(context).colorScheme.outline,
                      iconColor: Theme.of(context).colorScheme.outline,
                      onTap: () => _navigateTo(context, '/admin'),
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
