import 'dart:io';
import 'dart:typed_data';
import 'package:app_io/auth/guard/auth_guard.dart';
import 'package:app_io/auth/login/login_page.dart';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/data/models/LoginModel/login_page_model.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/features/screens/splash/splash_screen.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/notifications/push_service.dart';
import 'package:app_io/util/services/connectivity_service.dart';
import 'package:app_io/util/themes/app_theme.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fl_country_code_picker/fl_country_code_picker.dart' as flc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'features/screens/crm/chat_detail.dart';
import 'firebase_options.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes, kIsWeb;

Future<Uint8List?> _roundAvatar(String url) async {
  final data = await _downloadBytes(url);
  if (data == null) return null;

  final src = img.decodeImage(data);
  if (src == null) return null;

  final size   = src.width < src.height ? src.width : src.height;
  final circle = img.Image(width: size, height: size);

  // desenha só os pixels dentro do raio
  final cx = size / 2, cy = size / 2, r2 = cx * cx;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= r2) {
        circle.setPixel(x, y, src.getPixel(x, y));
      } else {
        circle.setPixelRgba(x, y, 0, 0, 0, 0); // transparente
      }
    }
  }
  return Uint8List.fromList(img.encodePng(circle));
}

Future<Uint8List?> _downloadBytes(String url) async {
  try {
    final req  = await HttpClient().getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode == 200) {
      // helper do Flutter que junta todos os chunks
      return consolidateHttpClientResponseBytes(resp);
    }
  } catch (_) {}
  return null;                           // erro → só devolve null
}

// 1.1 – chave global para podermos navegar fora de widgets
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 1.2 – handler que o Android/iOS chama quando a notificação chega
@pragma('vm:entry-point')                      // <- não remova
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // aqui você grava logs ou analytics; **não** faça navegação
}

// 1.3 – função que vai abrir a tela certa quando o usuário tocar na notificação
void _handleMessage(RemoteMessage message) {
  final d = message.data;
  if (d['openChat'] == 'true' && d['chatId'] != null) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatDetail(
          chatId: d['chatId']!,
          chatName: d['chatName'] ?? 'Contato',
          contactPhoto: d['contactPhoto'] ?? '',
        ),
      ),
    );
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

final List<Locale> appSupportedLocales = <Locale>{
  const Locale('en', ''),          // Inglês
  const Locale('pt', 'BR'),        // Português-Brasil
  ...flc.CountryLocalizations.supportedLocales           // ← lista de Strings
      .map(Locale.new),                               //   → Locale
}.toList();

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

  if (!kIsWeb && Platform.isAndroid) {
    final androidImpl = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final enabled = await androidImpl.areNotificationsEnabled();
      if (enabled == false) {
        try { await (androidImpl as dynamic).requestPermission(); } catch (_) {
          try { await (androidImpl as dynamic).requestNotificationsPermission(); } catch (_) {}
        }
      }
    }
  }

  // Ativa o Firebase App Check usando o provedor App Attest para iOS
  await FirebaseAppCheck.instance.activate(
    appleProvider: AppleProvider.appAttest,
  );
  // 2.1 – registra o handler de background (obrigatório)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

// 2.2 – se o app estava **fechado** e foi aberto tocando na notificação
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) _handleMessage(initialMsg);

// 2.3 – se o app estava em background e o usuário tocou na notificação
  FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

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
  // ícone 24 × 24 branco gerado e colocado em drawable
  const AndroidInitializationSettings initSettingsAndroid =
  AndroidInitializationSettings('ic_stat_ioconnect');

  const DarwinInitializationSettings initSettingsIOS =
  DarwinInitializationSettings();

  const InitializationSettings initSettings = InitializationSettings(
    android: initSettingsAndroid,
    iOS:     initSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    // callback dispara se o usuário tocar na notificação local
    onDidReceiveNotificationResponse: (resp) {
      // payload foi salvo como String ⇒ vira Map
      final data = Uri.splitQueryString(resp.payload ?? '');
      if (data['openChat'] == 'true') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatDetail(
              chatId:       data['chatId'] ?? '',
              chatName:     data['chatName'] ?? 'Contato',
              contactPhoto: data['contactPhoto'] ?? '',
            ),
          ),
        );
      }
    },
  );
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

  Future<void> _saveTokenToFirestore(String token) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final usersSnap = await usersRef.get();

    // Se já existe doc em /users E tem createdBy => é colaborador
    if (usersSnap.exists) {
      final createdBy = (usersSnap.data()?['createdBy'] ?? '').toString().trim();
      if (createdBy.isNotEmpty) {
        await usersRef.set({
          'fcmToken': token,
          'lastActivity': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return; // não grava em /empresas nesse caso
      }
    }

    // Dono/empresa (sem createdBy): grava APENAS em /empresas/{uid}
    await FirebaseFirestore.instance.collection('empresas').doc(user.uid).set({
      'fcmToken': token,
      'lastActivity': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _showNotification(String? title, String? body,
      Map<String, dynamic> payload) {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'high_importance_channel',
      'Notificações importantes',
      importance: Importance.max,
      priority : Priority.high,
      icon     : 'ic_stat_ioconnect',   // <- aqui
    );

    const NotificationDetails details =
    NotificationDetails(android: androidDetails,
        iOS: const DarwinNotificationDetails());

    flutterLocalNotificationsPlugin.show(
      0, title, body, details,
      payload: Uri(queryParameters: payload).query,   // mantém padrão
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IO Connect',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        flc.CountryLocalizations.delegate,          // ← picker
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
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