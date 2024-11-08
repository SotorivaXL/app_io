import 'package:flutter/material.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Verifica o estado de autenticação
    if (authProvider.isAuthenticated) {
      return child; // Retorna o widget protegido
    } else {
      // Redireciona para a página de login se não autenticado
      return LoginPage();
    }
  }
}
