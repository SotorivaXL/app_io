import 'package:flutter/material.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';

class Routes {
  static const String splash = '/';
  static const String login = '/login';
  static const String dashboard = '/dashboard';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      login: (context) => LoginPage(),
      dashboard: (context) => DashboardPage(),
    };
  }
}
