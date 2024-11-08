import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/campaign/create_campaign.dart';
import 'package:app_io/features/screens/collaborator/manage_collaborators.dart';
import 'package:app_io/features/screens/company/manage_companies.dart';
import 'package:app_io/features/screens/dasboard/dashboard_configurations.dart';
import 'package:app_io/features/screens/form/create_form.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminPanelPage extends StatefulWidget {
  @override
  _AdminPanelPageState createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final FirestoreService _firestoreService = FirestoreService();
  bool hasGerenciarParceirosAccess = false;
  bool hasGerenciarColaboradoresAccess = false;
  bool hasConfigurarDashAccess = false;
  bool hasCriarFormAccess = false;
  bool hasCriarCampanhaAccess = false;
  bool isLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  bool _hasShownPermissionRevokedDialog = false; // Flag to control modal display

  @override
  void initState() {
    super.initState();
    _determineUserDocumentAndListen();
  }

  Future<void> _determineUserDocumentAndListen() async {
    setState(() {
      isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      try {
        // Check if the user document exists in 'empresas' collection
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _listenToUserDocument('empresas', user.uid);
        } else {
          // If not in 'empresas', check 'users' collection
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            _listenToUserDocument('users', user.uid);
          } else {
            print("User document not found in 'empresas' or 'users' collections.");
            setState(() {
              isLoading = false;
            });
          }
        }
      } catch (e) {
        print("Error retrieving user permissions: $e");
        setState(() {
          isLoading = false;
        });
      }
    } else {
      print("User is not authenticated.");
      setState(() {
        isLoading = false;
      });
    }
  }

  void _listenToUserDocument(String collectionName, String userId) {
    _userDocSubscription = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(userId)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists) {
        _updatePermissions(userDoc);
      } else {
        print("User document not found in collection '$collectionName'.");
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final userData = userDoc.data();

    if (!mounted) return;

    setState(() {
      hasGerenciarParceirosAccess = userData?['gerenciarParceiros'] ?? false;
      hasGerenciarColaboradoresAccess = userData?['gerenciarColaboradores'] ?? false;
      hasConfigurarDashAccess = userData?['configurarDash'] ?? false;
      hasCriarFormAccess = userData?['criarForm'] ?? false;
      hasCriarCampanhaAccess = userData?['criarCampanha'] ?? false;
      isLoading = false;
    });

    // Check if all permissions are false
    if (!hasGerenciarParceirosAccess &&
        !hasGerenciarColaboradoresAccess &&
        !hasConfigurarDashAccess &&
        !hasCriarFormAccess &&
        !hasCriarCampanhaAccess) {
      if (!_hasShownPermissionRevokedDialog) {
        _hasShownPermissionRevokedDialog = true;

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          await showModalBottomSheet(
            context: context,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).primaryColor),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
            ),
            builder: (BuildContext context) {
              return Container(
                padding: EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Permissão Revogada',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    SizedBox(height: 16.0),
                    Text(
                      'Você não tem mais permissão para acessar esta tela.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24.0),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // Close the BottomSheet
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      child: Text(
                        'Ok',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );

          // After the modal is dismissed, redirect the user
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomTabBarPage()),
            );
          }
        });
      }
    } else {
      _hasShownPermissionRevokedDialog = false; // Reset the flag if permissions are restored
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  void _navigateWithFade(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarParceirosAccess &&
        !hasGerenciarColaboradoresAccess &&
        !hasConfigurarDashAccess &&
        !hasCriarFormAccess &&
        !hasCriarCampanhaAccess) {
      // Optionally, you can return an empty screen or a message
      return ConnectivityBanner(
        child: Scaffold(
          body: Container(),
        ),
      );
    } else {
      return ConnectivityBanner(
        child: Scaffold(
          appBar: AppBar(
            title: Text('Painel ADM'),
            centerTitle: true,
            titleTextStyle: TextStyle(
                fontFamily: 'BrandingSF',
                fontWeight: FontWeight.w900,
                fontSize: 26,
                color: Theme.of(context).colorScheme.outline),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.outline,
          ),
          body: SafeArea(
            top: true,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    scrollDirection: Axis.vertical,
                    children: [
                      if (hasGerenciarParceirosAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              onTap: () async {
                                _navigateWithFade(context, ManageCompanies());
                              },
                              child: ListTile(
                                title: Text(
                                  'Gerenciar Parceiros',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'BrandingSF',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 22,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Gerenciar empresas parceiras',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                      if (hasGerenciarColaboradoresAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              onTap: () async {
                                _navigateWithFade(context, ManageCollaborators());
                              },
                              child: ListTile(
                                title: Text(
                                  'Gerenciar Colaboradores',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'BrandingSF',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Gerenciar colaboradores da empresa',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                      if (hasCriarFormAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              onTap: () async {
                                _navigateWithFade(context, CreateForm());
                              },
                              child: ListTile(
                                title: Text(
                                  'Criar Formulário',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'BrandingSF',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Criar um formulário personalizado para web',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                      if (hasCriarCampanhaAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              onTap: () async {
                                _navigateWithFade(context, CreateCampaignPage(empresaId: 'empresaId'));
                              },
                              child: ListTile(
                                title: Text(
                                  'Criar Campanha',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'BrandingSF',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Criar uma campanha para a empresa',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                      if (hasConfigurarDashAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              onTap: () async {
                                _navigateWithFade(context, DashboardConfigurations());
                              },
                              child: ListTile(
                                title: Text(
                                  'Configurações de Dashboard',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'BrandingSF',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Configurações de BMs, anuncios e campanhas',
                                  textAlign: TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!hasGerenciarParceirosAccess &&
                      !hasGerenciarColaboradoresAccess &&
                      !hasConfigurarDashAccess &&
                      !hasCriarFormAccess &&
                      !hasCriarCampanhaAccess)
                    Center(
                      child: Container(
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock,
                                size: 100,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              SizedBox(height: 20),
                              Text(
                                'Você não tem nenhuma permissão nesta tela.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
}