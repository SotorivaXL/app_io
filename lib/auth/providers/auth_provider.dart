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

  AuthProvider() {
    // Evite chamar listenToAuthChanges várias vezes
    if (!_isListening) {
      listenToAuthChanges();
      _isListening = true;
    }
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
      // Autenticação no Firebase
      UserCredential userCredential = await _authRepository.signInWithEmail(email, password);
      _user = userCredential.user;

      // Referência ao documento do usuário na coleção 'users'
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      DocumentSnapshot userDoc = await userRef.get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        // Verifica se já existe um sessionId
        if (userData['sessionId'] != null) {
          // Se o sessionId já existir, bloqueie o login
          throw Exception('Outra sessão já está ativa nesta conta.');
        } else {
          // Caso contrário, continue com o login e salve o sessionId e o FCM Token
          await _saveSessionIdAndFcmToken();
          _sessionId = await getSessionId(); // Atualiza o _sessionId
          await _fetchPermissions(); // Carrega as permissões após o login
        }
      } else {
        // Caso o documento não exista na coleção 'users', realiza as operações necessárias
        await _saveSessionIdAndFcmToken();
        _sessionId = await getSessionId(); // Atualiza o _sessionId
        await _fetchPermissions(); // Carrega as permissões após o login
      }
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

  void listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      print('Auth state changed: ${user?.uid}');
      _user = user;

      if (_user != null) {
        _fetchPermissions();  // Carrega as permissões quando o estado de autenticação mudar
      } else {
        _hasLeadsAccess = false;  // Reseta as permissões se o usuário for desconectado
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
    if (_user != null) {
      String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        print('Erro: FCM Token está nulo.');
        return;
      }

      // Referência ao documento do usuário na coleção 'users'
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      DocumentSnapshot userDoc = await userRef.get();

      if (userDoc.exists) {
        // Se o documento existir na coleção 'users', salva o sessionId e o fcmToken
        await userRef.update({
          'sessionId': sessionId,
          'fcmToken': fcmToken,
        }).then((_) {
          print('SessionId e FCM Token salvos com sucesso na coleção users.');
        }).catchError((error) {
          print('Erro ao salvar sessionId e FCM Token na coleção users: $error');
        });
      } else {
        // Se o documento não existir na coleção 'users', verifica na coleção 'empresas'
        DocumentReference empresaRef = FirebaseFirestore.instance.collection('empresas').doc(_user!.uid);
        DocumentSnapshot empresaDoc = await empresaRef.get();

        if (empresaDoc.exists) {
          // Se o documento existir na coleção 'empresas', salva o sessionId e o fcmToken
          await empresaRef.update({
            'sessionId': sessionId,
            'fcmToken': fcmToken,
          }).then((_) {
            print('SessionId e FCM Token salvos com sucesso na coleção empresas.');
          }).catchError((error) {
            print('Erro ao salvar sessionId e FCM Token na coleção empresas: $error');
          });
        } else {
          // Se não existir em nenhuma das coleções, cria o documento na coleção 'users' e salva os dados lá
          await userRef.set({
            'sessionId': sessionId,
            'fcmToken': fcmToken,
          }).then((_) {
            print('Documento criado e sessionId e FCM Token salvos com sucesso na coleção users.');
          }).catchError((error) {
            print('Erro ao criar e salvar sessionId e FCM Token na coleção users: $error');
          });
        }
      }
    } else {
      print('Erro: Usuário está nulo.');
    }
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
}
