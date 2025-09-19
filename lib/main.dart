import 'package:http/http.dart' as http;
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
import 'features/screens/chatbot/create_chatbot.dart';
import 'features/screens/chatbot/create_chatbot_funnel.dart';
import 'features/screens/crm/chat_detail.dart';
import 'firebase_options.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

//
// ===================== Utils: Avatar em círculo =====================
//
Future<Uint8List?> _roundAvatar(String url) async {
  final data = await _downloadBytes(url);
  if (data == null) return null;

  final src = img.decodeImage(data);
  if (src == null) return null;

  final size   = src.width < src.height ? src.width : src.height;
  final circle = img.Image(width: size, height: size);

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
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) return resp.bodyBytes;
  } catch (_) {}
  return null; // erro → devolve null
}

//
// ===================== Navegação global =====================
//
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point') // handler de background (somente mobile/desktop)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // logs/analytics apenas; não faça navegação aqui
}

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
  const Locale('en', ''),
  const Locale('pt', 'BR'),
  ...flc.CountryLocalizations.supportedLocales.map(Locale.new),
}.toList();

//
// ===================== main() =====================
//
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ATT (somente iOS nativo)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    await _forceAppTrackingPermission();
  }

  // Firebase (todas as plataformas)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firestore: sem persistência local (opcional)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // Conectividade (seu serviço interno)
  final connectivityService = ConnectivityService();
  connectivityService.initialize();

  // Travar orientação em retrato (apenas iOS/Android)
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // Notificações locais: NÃO no Web
  if (!kIsWeb) {
    await initializeLocalNotifications();

    // Permissão em Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final enabled = await androidImpl.areNotificationsEnabled();
        if (enabled == false) {
          try {
            await (androidImpl as dynamic).requestPermission();
          } catch (_) {
            try {
              await (androidImpl as dynamic).requestNotificationsPermission();
            } catch (_) {}
          }
        }
      }
    }
  }

  // App Check: por enquanto, só iOS (sem reCAPTCHA no Web)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await FirebaseAppCheck.instance.activate(
        appleProvider: AppleProvider.appAttest,
      );
    } catch (_) {}
  }

  // FCM background handler: NÃO no Web (requer SW/VAPID)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Se o app foi aberto por notificação: NÃO no Web enquanto sem SW/VAPID
  if (!kIsWeb) {
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) _handleMessage(initialMsg);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
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

//
// ===================== iOS ATT =====================
//
Future<void> _forceAppTrackingPermission() async {
  print('Solicitando permissão de rastreamento...');
  var status = await AppTrackingTransparency.trackingAuthorizationStatus;
  while (status == TrackingStatus.notDetermined) {
    status = await AppTrackingTransparency.requestTrackingAuthorization();
    print('Status da permissão ATT: $status');
  }
}

//
// ===================== Local Notifications (não Web) =====================
//
Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings initSettingsAndroid =
  AndroidInitializationSettings('ic_stat_ioconnect');

  const DarwinInitializationSettings initSettingsIOS = DarwinInitializationSettings();

  const InitializationSettings initSettings = InitializationSettings(
    android: initSettingsAndroid,
    iOS: initSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) {
      final data = Uri.splitQueryString(resp.payload ?? '');
      if (data['openChat'] == 'true') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ChatDetail(
              chatId: data['chatId'] ?? '',
              chatName: data['chatName'] ?? 'Contato',
              contactPhoto: data['contactPhoto'] ?? '',
            ),
          ),
        );
      }
    },
  );
}

//
// ===================== App =====================
//
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
      // Sem SW/VAPID → não inicializa FCM no Web
      if (kIsWeb) return;

      _firebaseMessaging = FirebaseMessaging.instance;

      // iOS: solicitar permissão
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _firebaseMessaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        print('Permissões de notificação: ${settings.authorizationStatus}');
      }

      // Token e refresh
      final token = await _firebaseMessaging!.getToken();
      if (token != null) _saveTokenToFirestore(token);

      _firebaseMessaging!.onTokenRefresh.listen(_saveTokenToFirestore);

      // Mensagens em foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Mensagem recebida no foreground: ${message.notification?.title}');
        if (message.notification != null && !kIsWeb) {
          _showNotification(
            message.notification!.title,
            message.notification!.body,
            message.data,
          );
        }
      });

      // Se abrir por notificação (já registrado no main para initial/opened)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('Notificação clicada: ${message.data}');
      });
    } catch (e) {
      print('Erro ao inicializar FirebaseMessaging: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    final usersRef =
    FirebaseFirestore.instance.collection('users').doc(user.uid);
    final usersSnap = await usersRef.get();

    if (usersSnap.exists) {
      final createdBy =
      (usersSnap.data()?['createdBy'] ?? '').toString().trim();
      if (createdBy.isNotEmpty) {
        await usersRef.set({
          'fcmToken': token,
          'lastActivity': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }
    }

    await FirebaseFirestore.instance
        .collection('empresas')
        .doc(user.uid)
        .set({
      'fcmToken': token,
      'lastActivity': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _showNotification(
      String? title, String? body, Map<String, dynamic> payload) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificações importantes',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_stat_ioconnect',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      details,
      payload: Uri(queryParameters: payload).query,
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
        flc.CountryLocalizations.delegate,
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
        '/chatbots/create': (_) => const CreateChatbotFunnelPage(),
      },
      onGenerateRoute: (settings) => null,
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Erro 404')),
            body: const Center(child: Text('Página não encontrada!')),
          ),
        );
      },
    );
  }
}