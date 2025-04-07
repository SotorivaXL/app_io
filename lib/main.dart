import 'dart:io' show Platform;
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
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Solicita a permissão de rastreamento para iOS (ATT)
  if (!kIsWeb && Platform.isIOS) {
    await _forceAppTrackingPermission();
  }

  // Inicializa o Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Desabilita a persistência local no Firestore (caso necessário)
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: false,
  );

  // Inicializa o serviço de conectividade
  final connectivityService = ConnectivityService();
  connectivityService.initialize();

  // Define orientação do app para retrato
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  // Inicializa as notificações locais
  await initializeLocalNotifications();

  // Ativa o Firebase App Check usando o provedor App Attest para iOS
  await FirebaseAppCheck.instance.activate(
    appleProvider: AppleProvider.appAttest,
  );

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

Future<void> _forceAppTrackingPermission() async {
  print('Solicitando permissão de rastreamento...');
  var status = await AppTrackingTransparency.trackingAuthorizationStatus;

  // Força a exibição se a permissão não foi decidida
  while (status == TrackingStatus.notDetermined) {
    status = await AppTrackingTransparency.requestTrackingAuthorization();
    print('Status da permissão ATT: $status');
  }
}

Future<void> initializeLocalNotifications() async {
  // Configuração para Android
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  // Configuração para iOS
  const DarwinInitializationSettings iosSettings =
  DarwinInitializationSettings();

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
    _initializeFirebaseMessaging();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.listenToAuthChanges();
  }

  void _initializeFirebaseMessaging() async {
    try {
      _firebaseMessaging = FirebaseMessaging.instance;

      // Solicitar permissão no iOS para notificações
      if (!kIsWeb && Platform.isIOS) {
        NotificationSettings settings = await _firebaseMessaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        print('Permissões de notificação: ${settings.authorizationStatus}');
      }

      // Obter o token FCM e salvar no Firestore
      _firebaseMessaging!.getToken().then((token) {
        if (token != null) {
          _saveTokenToFirestore(token);
        }
      });

      // Atualizações de token
      _firebaseMessaging!.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
      });

      // Escutar notificações em primeiro plano
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
      0,
      title,
      body,
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
      onGenerateRoute: (settings) => null,
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