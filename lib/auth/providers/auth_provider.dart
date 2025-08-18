import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:app_io/auth/repositories/auth_repository.dart';

class AuthProvider with ChangeNotifier {
  final AuthRepository _authRepository = AuthRepository();
  User? _user;
  bool _isListening = false;

  // Variáveis para armazenar as permissões
  bool _hasLeadsAccess = false;

  // Getters para acessar as permissões
  bool get hasLeadsAccess => _hasLeadsAccess;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  String? _sessionId;

  Timer? _activityTimer; // Adicione esta variável

  AuthProvider() {
    if (!_isListening) {
      listenToAuthChanges();
      _isListening = true;
    }
  }

  // Método para iniciar o timer de atividade
  void _startActivityTimer() {
    // Atualiza a cada 1 minuto
    _activityTimer?.cancel();
    _activityTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      updateLastActivity();
    });
  }

  // Método para parar o timer de atividade
  void _stopActivityTimer() {
    _activityTimer?.cancel();
    _activityTimer = null;
  }

  Future<void> deleteUser(String uid) async {
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('deleteUser');
      await callable.call(<String, dynamic>{
        'uid': uid,
      });
      // Notifica a interface ou outros widgets que o usuário foi deletado
      notifyListeners();
    } catch (e) {
      print('Erro ao deletar usuário do Authentication: $e');
      throw e; // Repassa o erro para que possa ser tratado no local onde a função é chamada
    }
  }

  Future<void> _init() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      await _fetchPermissions();
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      // 1) Autentica
      final cred = await _authRepository.signInWithEmail(email, password);
      _user = cred.user;

      if (_user == null) {
        throw FirebaseAuthException(code: 'user-null', message: 'Falha ao autenticar');
      }

      // 2) Verifica sessão existente (em users OU empresas)
      final uid = _user!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final empRef  = FirebaseFirestore.instance.collection('empresas').doc(uid);
      final userDoc = await userRef.get();
      final empDoc  = await empRef.get();

      final sessionAlready =
          (userDoc.exists ? (userDoc.data()?['sessionId']) : null) ??
              (empDoc.exists  ? (empDoc.data()?['sessionId'])  : null);

      if (sessionAlready != null) {
        // opcional: desloga para não deixar authState inconsistido
        await FirebaseAuth.instance.signOut();
        _user = null;
        throw Exception('Outra sessão já está ativa nesta conta.');
      }

      // 3) Salva sessionId + FCM corretamente (sem criar doc fantasma)
      await _saveSessionIdAndFcmToken();

      // 4) Atualiza cache local e permissões
      _sessionId = await getSessionId();
      await _fetchPermissions();
    } catch (e) {
      print('Erro durante o login: $e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      // Remover o sessionId e FCM token
      await _removeSessionIdAndFcmToken();

      // Fazer logout no Firebase Auth
      await FirebaseAuth.instance.signOut();

      // Resetar o usuário localmente
      _user = null;
      _hasLeadsAccess = false;

      // Notificar que o usuário foi desconectado
      notifyListeners();
    } catch (e) {
      print('Erro ao fazer logout: $e');
      rethrow;
    }
  }

  Future<void> _removeSessionIdAndFcmToken() async {
    if (_user != null) {
      // Referência ao documento do usuário em 'users'
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      DocumentSnapshot userDoc = await userRef.get();

      if (userDoc.exists) {
        // Remove o sessionId e o FCM token do documento do usuário em 'users'
        await userRef.update({
          'sessionId': FieldValue.delete(),
          'fcmToken': FieldValue.delete(),
        });
      } else {
        // Referência ao documento da empresa em 'empresas'
        DocumentReference empresaRef = FirebaseFirestore.instance.collection('empresas').doc(_user!.uid);
        DocumentSnapshot empresaDoc = await empresaRef.get();

        if (empresaDoc.exists) {
          // Remove o sessionId e o FCM token do documento da empresa em 'empresas'
          await empresaRef.update({
            'sessionId': FieldValue.delete(),
            'fcmToken': FieldValue.delete(),
          });
        } else {
          print('Erro: Documento não encontrado nas coleções users ou empresas.');
        }
      }
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      UserCredential userCredential = await _authRepository.signUpWithEmail(email, password);
      _user = userCredential.user;
      print('User signed up: ${_user?.uid}');
      await _fetchPermissions();  // Carrega as permissões após o registro
    } catch (e) {
      print('Error during sign up: $e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  // Modificar o listener de autenticação para iniciar/parar o timer
  void listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      print('Auth state changed: ${user?.uid}');
      _user = user;

      if (_user != null) {
        _fetchPermissions();  // Carrega as permissões quando o estado de autenticação mudar
        _startActivityTimer(); // Inicia o timer de atividade
      } else {
        _hasLeadsAccess = false;  // Reseta as permissões se o usuário for desconectado
        _stopActivityTimer(); // Para o timer de atividade
      }

      notifyListeners();
    });
  }

  Future<void> _fetchPermissions() async {
    if (_user != null) {
      try {
        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('setCustomUserClaims');
        final result = await callable.call();

        final claims = result.data as Map<String, dynamic>?; // Garantia do tipo Map
        if (claims != null) {
          _hasLeadsAccess = claims['leads'] ?? false;
        }

        notifyListeners();
      } catch (e) {
        print("Erro ao buscar permissões: $e");
      }
    }
  }

  Future<void> _saveSessionIdAndFcmToken() async {
    if (_user == null) {
      print('Erro: Usuário está nulo.');
      return;
    }

    final uid = _user!.uid;
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) {
      print('FCM Token nulo; não vou gravar nada para evitar criar doc errado.');
      return;
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final empRef  = FirebaseFirestore.instance.collection('empresas').doc(uid);
    final userSnap = await userRef.get();
    final empSnap  = await empRef.get();

    if (empSnap.exists) {
      await empRef.set({'sessionId': sessionId, 'fcmToken': fcmToken}, SetOptions(merge: true));
      if (userSnap.exists) { // limpeza de ghost
        await userRef.delete().catchError((_) {});
      }
      return;
    }

    if (userSnap.exists) {
      await userRef.set({'sessionId': sessionId, 'fcmToken': fcmToken}, SetOptions(merge: true));
      return;
    }

    // NENHUM doc existe: não criar nada aqui!
    print('Nenhum doc em users/empresas para $uid. Ignorando criação para evitar doc fantasma.');
  }

  Future<String?> getSessionId() async {
    if (_user != null) {
      // Referência ao documento do usuário na coleção 'users'
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      DocumentSnapshot userDoc = await userRef.get();

      if (userDoc.exists) {
        Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
        return userData?['sessionId'];
      } else {
        // Se o documento não for encontrado na coleção 'users', verifica a coleção 'empresas'
        DocumentReference empresaRef = FirebaseFirestore.instance.collection('empresas').doc(_user!.uid);
        DocumentSnapshot empresaDoc = await empresaRef.get();

        if (empresaDoc.exists) {
          Map<String, dynamic>? empresaData = empresaDoc.data() as Map<String, dynamic>?;
          return empresaData?['sessionId'];
        } else {
          print('Erro: Documento não encontrado nas coleções users ou empresas.');
          return null;
        }
      }
    }
    return null;
  }

  // Getter para usar em outras partes do código
  String? get sessionId {
    return _sessionId; // _sessionId é uma propriedade que deve ser definida no seu código
  }

  Future<void> _deleteFcmToken() async {
    if (_user != null) {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(_user!.uid);

      // Verifica se o documento do usuário existe e apaga o token FCM
      final docSnapshot = await userDoc.get();
      if (docSnapshot.exists) {
        await userDoc.update({
          'fcmToken': FieldValue.delete(),
        });
      } else {
        // Acessa o documento da empresa na coleção 'empresas' usando o UID do usuário como o ID do documento
        final empresaDoc = FirebaseFirestore.instance.collection('empresas').doc(_user!.uid);

        // Verifica se o documento da empresa existe e apaga o token FCM
        final docSnapshot = await empresaDoc.get();
        if (docSnapshot.exists) {
          await empresaDoc.update({
            'fcmToken': FieldValue.delete(),
          });
          print('FCM Token removido do documento da empresa com ID: ${_user!.uid}');
        }
      }
    }
  }

  // Atualizar lastActivity
  Future<void> updateLastActivity() async {
    if (_user != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      final empresaRef = FirebaseFirestore.instance.collection('empresas').doc(_user!.uid);

      try {
        final userDoc = await userRef.get();
        if (userDoc.exists) {
          await userRef.update({
            'lastActivity': FieldValue.serverTimestamp(),
          });
        } else {
          final empresaDoc = await empresaRef.get();
          if (empresaDoc.exists) {
            await empresaRef.update({
              'lastActivity': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (e) {
        print('Erro ao atualizar lastActivity: $e');
      }
    }
  }

  @override
  void dispose() {
    _activityTimer?.cancel(); // Cancelar o timer quando o provider for descartado
    super.dispose();
  }
}
