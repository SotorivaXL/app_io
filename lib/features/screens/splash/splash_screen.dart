import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _hasConnection = true;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _subscription = ConnectivityService()
        .connectivityStream
        .listen((List<ConnectivityResult> results) {
      bool previousConnection = _hasConnection;
      _hasConnection = results.isNotEmpty &&
          results.any((result) => result != ConnectivityResult.none);

      if (previousConnection != _hasConnection) {
        _updateConnectionStatus(_hasConnection);
      }
    });

    _initializeApp();
  }

  Future<void> _checkInitialConnection() async {
    List<ConnectivityResult> results =
    await ConnectivityService().checkConnectivity();
    _hasConnection = results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);

    _updateConnectionStatus(_hasConnection);
  }

  void _updateConnectionStatus(bool hasConnection) {
    if (!hasConnection && !_isDialogShowing) {
      _showNoInternetDialog();
    } else if (hasConnection && _isDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop();
      _isDialogShowing = false;
    }
  }

  void _showNoInternetDialog() {
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Sem conexão com a Internet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animação Lottie
                Lottie.asset(
                  'assets/animations/no_internet.json',
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
                // Se preferir usar um GIF:
                // Image.asset(
                //   'assets/animations/no_internet.gif',
                //   width: 150,
                //   height: 150,
                //   fit: BoxFit.contain,
                // ),
                SizedBox(height: 20),
                Text(
                  'Por favor, verifique sua conexão com a internet e tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _initializeApp() async {
    // Aguarde o tempo necessário para a SplashScreen (por exemplo, 3 segundos)
    await Future.delayed(Duration(seconds: 3));

    // Verifique o estado de autenticação
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Navegue para a tela apropriada
    if (authProvider.isAuthenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => CustomTabBarPage()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    if (_isDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop();
      _isDialogShowing = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Image.asset(
          'assets/images/icons/logoTransparente.png',
          fit: BoxFit.contain,
          width: 270,
          height: double.infinity,
        ),
      ),
    );
  }
}