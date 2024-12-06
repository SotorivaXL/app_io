import 'dart:io';
import 'package:app_io/auth/guard/auth_guard.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/data/models/LoginModel/login_page_model.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/features/screens/splash/splash_screen.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/connectivity_service.dart';
import 'package:app_io/util/themes/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialize o Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: false,
  );

  // Inicialize o serviço de conectividade
  final connectivityService = ConnectivityService();
  connectivityService.initialize();

  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  // Inicialize o Flutter Local Notifications
  await initializeLocalNotifications();

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

Future<void> initializeLocalNotifications() async {
  // Configuração para Android
  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

  // Configuração para iOS
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();

  // Configuração geral
  const InitializationSettings settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(settings);
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FirebaseMessaging? _firebaseMessaging;

  @override
  void initState() {
    super.initState();

    // Inicialize o FirebaseMessaging
    _initializeFirebaseMessaging();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.listenToAuthChanges();
  }

  void _initializeFirebaseMessaging() async {
    try {
      _firebaseMessaging = FirebaseMessaging.instance;

      // Solicitar permissão no iOS
      NotificationSettings settings = await _firebaseMessaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('Permissões de notificação: ${settings.authorizationStatus}');

      // Obter o token FCM e salvá-lo no Firestore
      _firebaseMessaging!.getToken().then((token) {
        if (token != null) {
          _saveTokenToFirestore(token);
        }
      });

      // Escutar atualizações de token
      _firebaseMessaging!.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
      });

      // Escutar notificações no foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Mensagem recebida no foreground: ${message.notification?.title}');
        if (message.notification != null) {
          _showNotification(
            message.notification!.title,
            message.notification!.body,
            message.data,
          );
        }
      });

      // Notificações quando o app é aberto a partir de uma notificação
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('Notificação clicada: ${message.data}');
        // Lógica ao abrir o app a partir da notificação
      });
    } catch (e) {
      print('Erro ao inicializar FirebaseMessaging: $e');
    }
  }

  void _saveTokenToFirestore(String token) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user != null) {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userDoc.update({'fcmToken': token});
      print('Token atualizado no Firestore: $token');
    }
  }

  void _showNotification(String? title, String? body, Map<String, dynamic> payload) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificações importantes',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    flutterLocalNotificationsPlugin.show(
      0, // ID da notificação
      title, // Título
      body, // Corpo
      platformDetails,
      payload: payload.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      home: SplashScreen(),
      routes: {
        '/tabBar': (context) => AuthGuard(child: CustomTabBarPage()),
        '/dashboard': (context) => AuthGuard(child: DashboardPage()),
        '/leads': (context) => AuthGuard(child: LeadsPage()),
        '/login': (context) => LoginPage(),
        '/admin': (context) => AuthGuard(child: AdminPanelPage()),
      },
      onGenerateRoute: (settings) {
        return null;
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
  }
}