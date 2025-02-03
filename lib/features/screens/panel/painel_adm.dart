import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/campaign/manage_campaigns.dart';
import 'package:app_io/features/screens/collaborator/manage_collaborators.dart';
import 'package:app_io/features/screens/company/manage_companies.dart';
import 'package:app_io/features/screens/configurations/dashboard_configurations.dart';
import 'package:app_io/features/screens/form/manage_forms.dart';
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
  bool hasExecutarAPIs = false;
  bool hasConfigurarDashAccess = false;
  bool hasCriarFormAccess = false; // Atualizado
  bool hasCriarCampanhaAccess = false; // Atualizado
  bool isLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;
  bool _hasShownPermissionRevokedDialog =
      false; // Flag para controlar a exibição do modal

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
        // Verifica se o documento do usuário existe na coleção 'empresas'
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore
            .instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _listenToUserDocument('empresas', user.uid);
        } else {
          // Se não estiver em 'empresas', verifica na coleção 'users'
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            _listenToUserDocument('users', user.uid);
          } else {
            print(
                "Documento do usuário não encontrado nas coleções 'empresas' ou 'users'.");
            setState(() {
              isLoading = false;
            });
          }
        }
      } catch (e) {
        print("Erro ao recuperar as permissões do usuário: $e");
        setState(() {
          isLoading = false;
        });
      }
    } else {
      print("Usuário não está autenticado.");
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
        print(
            "Documento do usuário não encontrado na coleção '$collectionName'.");
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final userData = userDoc.data();

    if (!mounted) return;

    setState(() {
      hasGerenciarParceirosAccess = userData?['gerenciarParceiros'] ?? false;
      hasGerenciarColaboradoresAccess =
          userData?['gerenciarColaboradores'] ?? false;
      hasConfigurarDashAccess = userData?['configurarDash'] ?? false;
      hasCriarFormAccess = userData?['criarForm'] ?? false; // Atualizado
      hasCriarCampanhaAccess = userData?['criarCampanha'] ?? false; // Atualizado
      hasExecutarAPIs = userData?['executarAPIs'] ?? false; // Atualizado
      isLoading = false;
    });

    // Verifica se todas as permissões estão falsas
    if (!hasGerenciarParceirosAccess &&
        !hasGerenciarColaboradoresAccess &&
        !hasConfigurarDashAccess &&
        !hasCriarFormAccess &&
        !hasExecutarAPIs &&
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
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20.0)),
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
                        Navigator.of(context).pop(); // Fechar o BottomSheet
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding:
                            EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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

          // Após o modal ser fechado, redireciona o usuário
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomTabBarPage()),
            );
          }
        });
      }
    } else {
      _hasShownPermissionRevokedDialog =
          false; // Reseta a flag se as permissões forem restauradas
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

    // Detecta se o dispositivo é desktop com base na largura da tela
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: isDesktop
              ? Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 1850, // Define a largura máxima para desktop
              ),
              padding: EdgeInsets.symmetric(horizontal: 50), // 50px de padding nas laterais
              child: Center(child: CircularProgressIndicator()),
            ),
          )
              : Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarParceirosAccess &&
        !hasGerenciarColaboradoresAccess &&
        !hasConfigurarDashAccess &&
        !hasCriarFormAccess &&
        !hasExecutarAPIs &&
        !hasCriarCampanhaAccess) {
      // Opcionalmente, você pode retornar uma tela vazia ou uma mensagem
      return ConnectivityBanner(
        child: Scaffold(
          body: isDesktop
              ? Container(
            constraints: BoxConstraints(
              maxWidth: 1850, // Define a largura máxima para desktop
            ),
            padding: EdgeInsets.symmetric(horizontal: 50), // 50px de padding nas laterais
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock,
                      size: isDesktop ? 120 : 100, // Aumentado para desktop
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(height: isDesktop ? 30 : 20), // Aumentado para desktop
                    Text(
                      'Você não tem nenhuma permissão nesta tela.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isDesktop ? 22 : 18, // Aumentado para desktop
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
              : Center(child: Container()), // Mantém o comportamento original para mobile
        ),
      );
    } else {
      return ConnectivityBanner(
          child: Scaffold(
            body: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(10, 20, 10, 0),
              child: isDesktop
                  ? Container(
                constraints: BoxConstraints(
                  maxWidth: 1800, // Define a largura máxima para desktop
                ),
                padding:
                EdgeInsets.symmetric(horizontal: 50), // 50px de padding nas laterais
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
                            _buildCardOption(
                              context,
                              title: 'Gerenciar Parceiros',
                              subtitle: 'Gerenciar empresas parceiras',
                              icon: Icons.business,
                              onTap: () async {
                                _navigateWithFade(context, ManageCompanies());
                              },
                              isDesktop: isDesktop, // Passa isDesktop
                            ),
                          if (hasGerenciarColaboradoresAccess)
                            _buildCardOption(
                              context,
                              title: 'Gerenciar Colaboradores',
                              subtitle: 'Gerenciar colaboradores da empresa',
                              icon: Icons.group,
                              onTap: () async {
                                _navigateWithFade(
                                    context, ManageCollaborators());
                              },
                              isDesktop: isDesktop, // Passa isDesktop
                            ),
                          if (hasCriarFormAccess)
                            _buildCardOption(
                              context,
                              title: 'Gerenciar Formulários',
                              subtitle: 'Gerenciar formulários personalizados',
                              icon: Icons.article,
                              onTap: () async {
                                _navigateWithFade(context, ManageForms()); // Navega para a nova página
                              },
                              isDesktop: isDesktop, // Passa isDesktop
                            ),
                          if (hasCriarCampanhaAccess)
                            _buildCardOption(
                              context,
                              title: 'Gerenciar Campanhas',
                              subtitle: 'Gerenciar campanhas da empresa',
                              icon: Icons.campaign,
                              onTap: () async {
                                _navigateWithFade(context, ManageCampaigns()); // Navega para a nova página
                              },
                              isDesktop: isDesktop, // Passa isDesktop
                            ),
                          if (hasExecutarAPIs)
                            _buildCardOption(
                              context,
                              title: 'Gerenciar APIs',
                              subtitle: 'Gerenciar, criar, editar e executar APIs',
                              icon: Icons.api_rounded,
                              onTap: () async {
                                _navigateWithFade(context, ManageApis()); // Navega para a nova página
                              },
                            ),
                          if (hasConfigurarDashAccess)
                            _buildCardOption(
                              context,
                              title: 'Configurações de Dashboard',
                              subtitle:
                              'Configurações de BMs, anúncios e campanhas',
                              icon: Icons.dashboard_customize,
                              onTap: () async {
                                _navigateWithFade(context,
                                    DashboardConfigurations());
                              },
                              isDesktop: isDesktop, // Passa isDesktop
                            ),
                        ],
                      ),
                      if (!hasGerenciarParceirosAccess &&
                          !hasGerenciarColaboradoresAccess &&
                          !hasConfigurarDashAccess &&
                          !hasCriarFormAccess &&
                          !hasCriarCampanhaAccess)
                        Align(
                          alignment: Alignment.topCenter, // Alinha ao topo
                          child: Padding(
                            padding: const EdgeInsets.only(top: 20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: isDesktop ? 120 : 100, // Aumentado para desktop
                                  color:
                                  Theme.of(context).colorScheme.primary,
                                ),
                                SizedBox(height: isDesktop ? 30 : 20), // Aumentado para desktop
                                Text(
                                  'Você não tem nenhuma permissão nesta tela.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isDesktop ? 22 : 18, // Aumentado para desktop
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
                  : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      scrollDirection: Axis.vertical,
                      children: [
                        if (hasGerenciarParceirosAccess)
                          _buildCardOption(
                            context,
                            title: 'Gerenciar Parceiros',
                            subtitle: 'Gerenciar empresas parceiras',
                            icon: Icons.business,
                            onTap: () async {
                              _navigateWithFade(context, ManageCompanies());
                            },
                            isDesktop: isDesktop, // Passa isDesktop
                          ),
                        if (hasGerenciarColaboradoresAccess)
                          _buildCardOption(
                            context,
                            title: 'Gerenciar Colaboradores',
                            subtitle: 'Gerenciar colaboradores da empresa',
                            icon: Icons.group,
                            onTap: () async {
                              _navigateWithFade(
                                  context, ManageCollaborators());
                            },
                            isDesktop: isDesktop, // Passa isDesktop
                          ),
                        if (hasCriarFormAccess)
                          _buildCardOption(
                            context,
                            title: 'Gerenciar Formulários',
                            subtitle: 'Gerenciar formulários personalizados',
                            icon: Icons.article,
                            onTap: () async {
                              _navigateWithFade(
                                  context, ManageForms()); // Navega para a nova página
                            },
                            isDesktop: isDesktop, // Passa isDesktop
                          ),
                        if (hasCriarCampanhaAccess)
                          _buildCardOption(
                            context,
                            title: 'Gerenciar Campanhas',
                            subtitle: 'Gerenciar campanhas da empresa',
                            icon: Icons.campaign,
                            onTap: () async {
                              _navigateWithFade(
                                  context, ManageCampaigns()); // Navega para a nova página
                            },
                            isDesktop: isDesktop, // Passa isDesktop
                          ),
                        if (hasConfigurarDashAccess)
                          _buildCardOption(
                            context,
                            title: 'Configurações de Dashboard',
                            subtitle:
                            'Configurações de BMs, anúncios e campanhas',
                            icon: Icons.dashboard_customize,
                            onTap: () async {
                              _navigateWithFade(
                                  context, DashboardConfigurations());
                            },
                            isDesktop: isDesktop, // Passa isDesktop
                          ),
                      ],
                    ),
                    if (!hasGerenciarParceirosAccess &&
                        !hasGerenciarColaboradoresAccess &&
                        !hasConfigurarDashAccess &&
                        !hasCriarFormAccess &&
                        !hasCriarCampanhaAccess)
                      Align(
                        alignment: Alignment.topCenter, // Alinha ao topo
                        child: Padding(
                          padding: const EdgeInsets.only(top: 20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock,
                                size: isDesktop ? 120 : 100,
                                // Aumentado para desktop
                                color:
                                Theme.of(context).colorScheme.primary,
                              ),
                              SizedBox(height: isDesktop ? 30 : 20),
                              // Aumentado para desktop
                              Text(
                                'Você não tem nenhuma permissão nesta tela.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isDesktop ? 22 : 18,
                                  // Aumentado para desktop
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ));
    }
  }

  Widget _buildCardOption(BuildContext context,
      {required String title,
        required String subtitle,
        required IconData icon,
        required VoidCallback onTap,
        required bool isDesktop}) { // Adicionado o parâmetro isDesktop
    return Card(
      color: Theme.of(context).colorScheme.secondary, // Cor secundária
      margin: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24.0 : 16.0, vertical: isDesktop ? 12.0 : 8.0), // Ajuste de margin
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSecondary,
          size: isDesktop ? 40 : 30, // Aumentado para desktop
        ),
        title: Text(
          title,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isDesktop ? 22 : 19, // Aumentado para desktop
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        subtitle: Text(
          subtitle,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: isDesktop ? 16 : 12, // Aumentado para desktop
            letterSpacing: 0,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Theme.of(context).colorScheme.onBackground,
          size: isDesktop ? 24 : 20, // Aumentado para desktop
        ),
        onTap: onTap,
      ),
    );
  }
}
