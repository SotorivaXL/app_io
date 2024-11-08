import 'dart:io';
import 'package:app_io/auth/guard/auth_guard.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/data/models/LoginModel/login_page_model.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/home/home_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/features/screens/profile/profile_page.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/themes/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: false,
  );

  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    await FirebaseMessaging.instance.subscribeToTopic('leads');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LoginPageModel()),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.listenToAuthChanges();

    _initializeFirebaseMessaging();
  }

  void _initializeFirebaseMessaging() async {
    // Request permission for iOS
    await _firebaseMessaging.requestPermission();

    // Get the token for this device and save it to Firestore
    _firebaseMessaging.getToken().then((token) {
      if (token != null) {
        _saveTokenToFirestore(token);
      }
    });

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveTokenToFirestore(newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Mensagem recebida: ${message.notification?.title}');
      _showNotification(message.notification!.title, message.notification!.body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message clicked!');
      // Handle the logic when a notification is clicked and the app is opened
    });
  }

  void _saveTokenToFirestore(String token) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user != null) {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userDoc.update({
        'fcmToken': token,
      });
      print('Token atualizado no Firestore: $token');
    }
  }

  void _showNotification(String? title, String? body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title ?? 'Notification'),
        content: Text(body ?? 'You have received a new message.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        print('isAuthenticated: ${authProvider.isAuthenticated}');
        return MaterialApp(
          title: 'IO Connect',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [
            const Locale('en', ''), // Inglês
            const Locale('pt', 'BR'), // Português Brasil
          ],
          home: authProvider.isAuthenticated ? CustomTabBarPage() : LoginPage(),
          routes: {
            '/tabBar': (context) => AuthGuard(child: CustomTabBarPage()),
            '/home': (context) => AuthGuard(child: HomePage()),
            '/dashboard': (context) => AuthGuard(child: DashboardPage()),
            '/leads': (context) => AuthGuard(child: LeadsPage()),
            '/login': (context) => LoginPage(),
            '/admin': (context) => AuthGuard(child: AdminPanelPage()),
          },
          onGenerateRoute: (settings) {
            return null; // Deixe como null para usar `onUnknownRoute`
          },
          onUnknownRoute: (settings) {
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  title: Text('Erro 404'),
                ),
                body: Center(
                  child: Text('Página não encontrada!'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
