import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

final _flnp = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point') // obrigatório p/ background
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // se precisar, trate payload aqui
}

class PushService {
  static Future<void> init() async {
    // iOS/mac: como exibir quando estiver em foreground
    // iOS/macOS: como exibir em foreground
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

// Inicializa local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _flnp.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit));

// ANDROID 13+: pedir permissão (compatível com várias versões do plugin)
    final androidImpl = _flnp
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      // (opcional) garantir canal
      await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'high_importance_channel', 'Notificações importantes',
            importance: Importance.max,
          ));

      final enabled = await androidImpl.areNotificationsEnabled();
      if (enabled == false) {
        // tenta API nova…
        try {
          await (androidImpl as dynamic).requestPermission();
        } catch (_) {
          // …ou a API antiga (algumas versões do plugin)
          try {
            await (androidImpl as dynamic).requestNotificationsPermission();
          } catch (_) {}
        }
      }
    }

// iOS/macOS: solicitar permissão do sistema
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
  }

    static Future<void> _saveFcmToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final userSnap = await usersRef.get();

    final bool isCollaborator = userSnap.exists &&
        ((userSnap.data()?['createdBy'] ?? '').toString().isNotEmpty);

    final docRef = isCollaborator
        ? usersRef                                      // colaboradores → users/{uid}
        : FirebaseFirestore.instance.collection('empresas').doc(uid); // dono → empresas/{uid}

    await docRef.set({
      'fcmToken': token,
      'lastActivity': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}