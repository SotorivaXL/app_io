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
    final authProvider =
    Provider.of<app_io_auth.AuthProvider>(context, listen: false);
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
      await authProvider.signIn(email, password);

      if (!authProvider.isAuthenticated) {
        _showErrorDialog(context, 'Falha ao autenticar. Tente novamente.');
        return;
      }

      // opcional: provider já salvou o FCM; manter não faz mal
      await _updateFcmToken();

      _saveCredentials(email, password);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          pageBuilder: (context, animation, secondaryAnimation) =>
              CustomTabBarPage(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      _showErrorDialogFirebase(context, e);
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  Future<void> _updateFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final empRef   = FirebaseFirestore.instance.collection('empresas').doc(uid);
    final empSnap = await empRef.get();
    final userSnap = await usersRef.get();

    try {
      if (empSnap.exists) {
        await empRef.update({'fcmToken': token});
      } else if (userSnap.exists) {
        await usersRef.update({'fcmToken': token});
      } else {
        debugPrint('Sem doc para salvar fcmToken; evitando criar doc fantasma.');
      }
    } catch (e) {
      print('Erro ao atualizar o FCM Token: $e');
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
        errorMessage =
        'O endereço de e-mail fornecido é inválido. Verifique e tente novamente.';
        titleMessage = 'E-mail inválido';
        break;
      case 'user-disabled':
        errorMessage =
        'A conta foi desativada. Entre em contato com o suporte.';
        titleMessage = 'Login não permitido';
        break;
      case 'user-not-found':
        errorMessage =
        'Não há registro de usuário com esse e-mail. Verifique e tente novamente.';
        titleMessage = 'Login não permitido';
        break;
      case 'wrong-password':
        errorMessage = 'A senha fornecida está incorreta. Tente novamente.';
        titleMessage = 'Senha inválida';
        break;
      case 'email-already-in-use':
        errorMessage =
        'Já existe uma conta com esse e-mail. Tente fazer login ou use um e-mail diferente.';
        titleMessage = 'E-mail existente';
        break;
      case 'weak-password':
        errorMessage =
        'A senha fornecida é muito fraca. Escolha uma senha mais forte.';
        titleMessage = 'Senha inválida';
        break;
      case 'operation-not-allowed':
        errorMessage =
        'Essa operação não está permitida. Entre em contato com o suporte.';
        titleMessage = 'Operação não permitida';
        break;
      case 'invalid-credential':
        errorMessage =
        'E-mail ou senha incorretos, verifique e faça login novamente!.';
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
        errorMessage =
        'Ocorreu um erro inesperado. Tente novamente mais tarde.';
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
    return isDarkTheme
        ? 'assets/images/icons/logoDark.png'
        : 'assets/images/icons/logoLight.png';
  }

  @override
  Widget build(BuildContext context) {
    final loginModel = Provider.of<LoginPageModel>(context);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 1024;

    // ✅ Largura máxima consistente para campos, botão e checkbox
    final double formMaxWidth = isDesktop
        ? 520
        : min(screenWidth - 40, 520); // mantém respiro lateral no mobile

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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 50),
                      child: Image.asset(
                        theme,
                        width: isDesktop ? 400 : min(320, screenWidth * .8),
                      ),
                    ),
                    // LOGIN text - remains centered
                    Text(
                      'Bem-vindo(a) de volta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                        fontFamily: 'BrandingSF',
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    const SizedBox(height: 50),
                    // EMAIL TextFormField
                    SizedBox(
                      width: formMaxWidth,
                      child: TextFormField(
                        controller: _emailController,
                        obscureText: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Digite seu e-mail',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
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
                          contentPadding:
                          const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
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
                            _showErrorDialog(
                                context, "Por favor, insira seu email");
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    // SENHA TextFormField
                    SizedBox(
                      width: formMaxWidth,
                      child: TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_passwordVisibility,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'Digite sua senha',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
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
                          contentPadding:
                          const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 16),
                          suffixIcon: InkWell(
                            onTap: () => setState(
                                  () => _passwordVisibility = !_passwordVisibility,
                            ),
                            focusNode: FocusNode(skipTraversal: true),
                            hoverColor: const Color(0x20933FFC),
                            borderRadius: BorderRadius.circular(25),
                            child: Icon(
                              _passwordVisibility
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color:
                              Theme.of(context).colorScheme.inverseSurface,
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
                            _showErrorDialog(
                                context, "Por favor, insira sua senha");
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    // LOGIN Button
                    FutureBuilder<void>(
                      future: _loginFuture,
                      builder: (context, snapshot) {
                        return SizedBox(
                          width: formMaxWidth, // ✅ mesma largura dos campos
                          child: snapshot.connectionState ==
                              ConnectionState.waiting
                              ? ElevatedButton(
                            onPressed: null,
                            // Desabilita o botão enquanto carrega
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 25, vertical: 15),
                              backgroundColor:
                              Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context)
                                        .colorScheme
                                        .primary),
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
                              color:
                              Theme.of(context).colorScheme.outline,
                              size: 20,
                            ),
                            label: Text(
                              'ENTRAR',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 25, vertical: 15),
                              backgroundColor:
                              Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: formMaxWidth, // ✅ alinha o checkbox com os campos
                      child: CheckboxListTile(
                        title: Text(
                          'Lembrar de mim',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSecondary
                          ),
                        ),
                        side: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 2
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: Theme.of(context).primaryColor,
                        checkColor: Theme.of(context).colorScheme.outline,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5.0),
                        ),
                        dense: true,
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                      ),
                    )
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