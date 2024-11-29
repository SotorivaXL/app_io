import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as app_io_auth;
import 'package:app_io/data/models/LoginModel/login_page_model.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _passwordVisibility = false;
  bool _rememberMe = false;
  Future<void>? _loginFuture;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    final authProvider = Provider.of<app_io_auth.AuthProvider>(context, listen: false);
    authProvider.listenToAuthChanges();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _loadSavedCredentials() async {
    final email = await _secureStorage.read(key: 'email');
    final password = await _secureStorage.read(key: 'password');
    final rememberMe = await _secureStorage.read(key: 'rememberMe') == 'true';

    setState(() {
      _emailController.text = email ?? '';
      _passwordController.text = password ?? '';
      _rememberMe = rememberMe;
    });
  }

  void _saveCredentials(String email, String password) async {
    if (_rememberMe) {
      await _secureStorage.write(key: 'email', value: email);
      await _secureStorage.write(key: 'password', value: password);
      await _secureStorage.write(key: 'rememberMe', value: 'true');
    } else {
      await _secureStorage.deleteAll(); // Remove todos os dados
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final authProvider = Provider.of<app_io_auth.AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // Verifica o sessionId antes de autenticar
      final usersCollection = FirebaseFirestore.instance.collection('users');
      final companiesCollection = FirebaseFirestore.instance.collection('empresas');

      QuerySnapshot userQuerySnapshot = await usersCollection.where('email', isEqualTo: email).get();

      if (userQuerySnapshot.docs.isEmpty) {
        userQuerySnapshot = await companiesCollection.where('email', isEqualTo: email).get();
      }

      if (userQuerySnapshot.docs.isNotEmpty) {
        final userDoc = userQuerySnapshot.docs.first;
        final userData = userDoc.data() as Map<String, dynamic>?;
        final currentSessionId = userData?['sessionId'];
        final emailVerified = userData?['emailVerified'] ?? false;
        final newSessionId = authProvider.sessionId;

        if (currentSessionId != null && currentSessionId != newSessionId) {
          _showErrorDialog(context, 'Esta conta já está ativa em outro dispositivo. Por favor, desconecte-se de lá antes de continuar.');
          return;
        }

        // Verifique se o e-mail foi validado
        if (!emailVerified) {
          final verificationCode = _generateVerificationCode();

          // Enviar código de verificação para o e-mail
          await _sendVerificationEmail(email, verificationCode);

          // Mostra a tela de inserção do código
          final userEnteredCode = await _promptForVerificationCode();

          if (userEnteredCode != verificationCode) {
            _showErrorDialog(context, 'Código de verificação incorreto. Tente novamente.');
            return;
          }

          // Atualiza o campo "emailVerified" no Firestore após o código ser validado corretamente
          await userDoc.reference.update({'emailVerified': true});
        }
      }

      // Faça login do usuário
      await authProvider.signIn(email, password);

      if (authProvider.isAuthenticated) {
        final user = FirebaseAuth.instance.currentUser;

        if (user != null) {
          final token = await user.getIdToken();

          if (token == null) {
            _showErrorDialog(context, 'Ocorreu um erro ao obter o token.');
            return;
          }

          final userDocRef = usersCollection.doc(user.uid);
          final companyDocRef = companiesCollection.doc(user.uid);

          final userDocExists = (await userDocRef.get()).exists;
          final companyDocExists = (await companyDocRef.get()).exists;

          if (!userDocExists && companyDocExists) {
            await companyDocRef.update({'sessionId': authProvider.sessionId});
          } else if (!userDocExists && !companyDocExists) {
            await userDocRef.set({'sessionId': authProvider.sessionId, 'email': email});
          } else if (userDocExists) {
            await userDocRef.update({'sessionId': authProvider.sessionId});
          }

          await _updateFcmToken();

          _saveCredentials(email, password);

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: Duration(milliseconds: 500),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              pageBuilder: (context, animation, secondaryAnimation) => CustomTabBarPage(),
            ),
          );
        }
      }
    } catch (e) {
      if (e is FirebaseException) {
        _showErrorDialogFirebase(context, e);
      } else {
        _showErrorDialog(context, 'Ocorreu um erro inesperado.');
      }
    }
  }

  Future<void> sendEmail(String toEmail, String subject, String content, {bool isHtml = false}) async {
    const sendGridApiKey = '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'; // Substitua pela sua chave de API do SendGrid
    const sendGridUrl = 'https://api.sendgrid.com/v3/mail/send';

    final response = await http.post(
      Uri.parse(sendGridUrl),
      headers: {
        'Authorization': 'Bearer $sendGridApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'personalizations': [
          {
            'to': [
              {'email': toEmail}
            ],
            'subject': subject,
          }
        ],
        'from': {'email': 'suporte.ioconnect@iomarketing.com.br'}, // Substitua pelo seu e-mail verificado no SendGrid
        'content': [
          {
            'type': isHtml ? 'text/html' : 'text/plain',
            'value': content,
          }
        ],
      }),
    );

    if (response.statusCode != 202) {
      throw Exception('Erro ao enviar e-mail: ${response.body}');
    }
  }

  String _generateVerificationCode() {
    final random = Random();
    return List.generate(6, (index) => random.nextInt(10)).join(); // Gera um código de 6 dígitos
  }

  Future<void> _sendVerificationEmail(String email, String code) async {
    // Coleções do Firestore
    final usersCollection = FirebaseFirestore.instance.collection('users');
    final companiesCollection = FirebaseFirestore.instance.collection('empresas');

    // Buscando o documento correspondente
    QuerySnapshot userQuerySnapshot = await usersCollection.where('email', isEqualTo: email).get();
    String userName = 'usuário';

    if (userQuerySnapshot.docs.isEmpty) {
      userQuerySnapshot = await companiesCollection.where('email', isEqualTo: email).get();
      if (userQuerySnapshot.docs.isNotEmpty) {
        final companyData = userQuerySnapshot.docs.first.data() as Map<String, dynamic>?;
        userName = companyData?['NomeEmpresa'] ?? 'usuário';
      }
    } else {
      final userData = userQuerySnapshot.docs.first.data() as Map<String, dynamic>?;
      userName = userData?['name'] ?? 'usuário';
    }

    // Envio do e-mail com o nome e token estilizado
    await sendEmail(
      email,
      'Verificação de email necessária',
      '''
    <p>Prezado(a), <strong>$userName</strong>!</p>
    <p>Segue seu token de verificação: <strong style="font-size: 18px;">$code</strong>.</p>
    <p>Para sua segurança, insira este código no app para completar o acesso à sua conta.</p>
    ''',
      isHtml: true,
    );
  }

  Future<String?> _promptForVerificationCode() async {
    String? code;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        final codeController = TextEditingController();
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(
            'Verificação de E-mail',
            textAlign: TextAlign.center,
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
          content: TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Digite o código de verificação',
              hintStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.tertiary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.tertiary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              errorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              focusedErrorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 10)
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(codeController.text);
              },
              child: Text(
                'Verificar',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.tertiary
                ),
              ),
            ),
          ],
        );
      },
    ).then((value) {
      code = value;
    });

    return code;
  }

  Future<void> _updateFcmToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null && FirebaseAuth.instance.currentUser != null) {
      try {
        // Atualiza o token na coleção 'users'
        await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).update({
          'fcmToken': token,
        });
        print('FCM Token atualizado com sucesso para o usuário ${FirebaseAuth.instance.currentUser!.uid}.');
      } catch (error) {
        print('Erro ao atualizar o FCM Token: $error');
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      backgroundColor: Theme.of(context).colorScheme.background,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ocorreu um erro',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Entendi',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showErrorDialogFirebase(BuildContext context, FirebaseException e) {
    // Mapeia erros do Firebase para mensagens em português
    String errorMessage;
    String titleMessage;
    switch (e.code) {
      case 'invalid-email':
        errorMessage = 'O endereço de e-mail fornecido é inválido. Verifique e tente novamente.';
        titleMessage = 'E-mail inválido';
        break;
      case 'user-disabled':
        errorMessage = 'A conta foi desativada. Entre em contato com o suporte.';
        titleMessage = 'Login não permitido';
        break;
      case 'user-not-found':
        errorMessage = 'Não há registro de usuário com esse e-mail. Verifique e tente novamente.';
        titleMessage = 'Login não permitido';
        break;
      case 'wrong-password':
        errorMessage = 'A senha fornecida está incorreta. Tente novamente.';
        titleMessage = 'Senha inválida';
        break;
      case 'email-already-in-use':
        errorMessage = 'Já existe uma conta com esse e-mail. Tente fazer login ou use um e-mail diferente.';
        titleMessage = 'E-mail existente';
        break;
      case 'weak-password':
        errorMessage = 'A senha fornecida é muito fraca. Escolha uma senha mais forte.';
        titleMessage = 'Senha inválida';
        break;
      case 'operation-not-allowed':
        errorMessage = 'Essa operação não está permitida. Entre em contato com o suporte.';
        titleMessage = 'Operação não permitida';
        break;
      case 'invalid-credential':
        errorMessage = 'E-mail ou senha incorretos, verifique e faça login novamente!.';
        titleMessage = 'E-mail ou senha inválidos';
        break;
      case 'invalid-verification-code':
        errorMessage = 'Código de verificação é inválido!.';
        titleMessage = 'Código inválido';
        break;
      case 'invalid-verification-id':
        errorMessage = 'A verificação não é valida, tente novamente.';
        titleMessage = 'Verificação inválida';
        break;
      case 'channel-error':
        errorMessage = 'Por favor, preencha todos os campos.';
        titleMessage = 'Campo(s) vázios';
        break;
      default:
        errorMessage = 'Ocorreu um erro inesperado. Tente novamente mais tarde.';
        titleMessage = 'ocorreu um erro';
        break;
    }

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      backgroundColor: Theme.of(context).colorScheme.background,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleMessage,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 10),
              Text(
                errorMessage,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Entendi',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String getThemeBasedValue(BuildContext context) {
    // Verifica se o tema atual é claro ou escuro
    bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // Retorna "dark" se o tema for escuro, ou "light" se for claro
    return isDarkTheme ? 'assets/images/icons/logoDark.png' : 'assets/images/icons/logoLight.png';
  }


  @override
  Widget build(BuildContext context) {
    final loginModel = Provider.of<LoginPageModel>(context);
    double screenWidth = MediaQuery.of(context).size.width;
    double textFieldWidth = screenWidth > 480 ? screenWidth * 0.5 : screenWidth;
    double horizontalPadding = screenWidth > 480 ? 0 : 20;
    String theme = getThemeBasedValue(context);

    return GestureDetector(
      onTap: () => loginModel.unfocusNode.canRequestFocus
          ? FocusScope.of(context).requestFocus(loginModel.unfocusNode)
          : FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Theme.of(context).colorScheme.background,
        body: SafeArea(
          top: true,
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 50),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 50),
                      child: Image.asset(theme, width: 400,),
                    ),
                    // LOGIN text - remains centered
                    Text(
                      'Bem-vindo(a) de volta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontFamily: 'BrandingSF',
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    SizedBox(height: 50),
                    // EMAIL TextFormField
                    Container(
                      width: textFieldWidth,
                      child: TextFormField(
                        controller: _emailController,
                        obscureText: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Digite seu e-mail',
                          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          labelText: 'E-mail',
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).primaryColor,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          contentPadding: EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
                        ),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        textAlign: TextAlign.start,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            _showErrorDialog(context, "Por favor, insira seu email");
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(height: 30),
                    // SENHA TextFormField
                    Container(
                      width: textFieldWidth,
                      child: TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_passwordVisibility,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'Digite sua senha',
                          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          labelText: 'Senha',
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.tertiary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          contentPadding: EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
                          suffixIcon: InkWell(
                            onTap: () => setState(
                                  () => _passwordVisibility = !_passwordVisibility,
                            ),
                            focusNode: FocusNode(skipTraversal: true),
                            hoverColor: Color(0x20933FFC),
                            borderRadius: BorderRadius.circular(25),
                            child: Icon(
                              _passwordVisibility
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Theme.of(context).colorScheme.inverseSurface,
                              size: 20,
                            ),
                          ),
                        ),
                        onFieldSubmitted: (value) {
                          _loginFuture = _login();
                        },
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        textAlign: TextAlign.start,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            _showErrorDialog(context, "Por favor, insira sua senha");
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(height: 30),
                    // LOGIN Button
                    FutureBuilder<void>(
                      future: _loginFuture,
                      builder: (context, snapshot) {
                        return Container(
                          width: textFieldWidth, // Define a largura do botão igual à largura do TextFormField
                          child: snapshot.connectionState == ConnectionState.waiting
                              ? ElevatedButton(
                            onPressed: null, // Desabilita o botão enquanto carrega
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: SizedBox(
                              width: 20,
                              height: 20, // Define o tamanho da ProgressBar
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.outline),
                                strokeWidth: 2.0,
                              ),
                            ),
                          )
                              : ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                FocusScope.of(context).unfocus();
                                _loginFuture = _login();
                              });
                            },
                            icon: Icon(
                              Icons.login_outlined,
                              color: Theme.of(context).colorScheme.outline,
                              size: 20,
                            ),
                            label: Text(
                              'ENTRAR',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                        ),
                        Text(
                          'Lembrar de mim',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}