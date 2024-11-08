import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:app_io/features/screens/home/home_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? userName;
  bool hasLeadsAccess = false;
  bool hasDashboardAccess = false;

  @override
  void initState() {
    super.initState();
    _getUserData();
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
  Widget build(BuildContext context) {
    final authProvider = Provider.of<appAuthProvider.AuthProvider>(context);

    return ConnectivityBanner(
      child: Scaffold(
        body: Center(
          child: Text(
            'Em breve, as funções desta página estarão disponíveis.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
