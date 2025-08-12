import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/apis/manage_apis.dart';
import 'package:app_io/features/screens/campaign/manage_campaigns.dart';
import 'package:app_io/features/screens/collaborator/manage_collaborators.dart';
import 'package:app_io/features/screens/company/manage_companies.dart';
import 'package:app_io/features/screens/configurations/dashboard_configurations.dart';
import 'package:app_io/features/screens/crm/whatsapp_chats.dart';
import 'package:app_io/features/screens/form/manage_forms.dart';
import 'package:app_io/features/screens/meeting_requests/meeting_requests.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../products/manage_products.dart';

class AdminPanelPage extends StatefulWidget {
  @override
  _AdminPanelPageState createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final _firestoreService = FirestoreService();
  bool hasGerenciarParceirosAccess = false;
  bool hasGerenciarColaboradoresAccess = false;
  bool hasExecutarAPIs = false;
  bool hasConfigurarDashAccess = false;
  bool hasCriarFormAccess = false;
  bool hasCriarCampanhaAccess = false;
  bool isLoading = true;
  bool hasGerenciarWhatsappAccess = false;
  bool hasGerenciarProdutosAccess = false;
  bool _isEmpresaUser =
      false; // Será true se o documento for encontrado em "empresas"

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;
  bool _hasShownPermissionRevokedDialog = false;

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
        // Tenta buscar o documento na coleção "empresas"
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore
            .instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _isEmpresaUser = true;
          _listenToUserDocument('empresas', user.uid);
        } else {
          // Se não estiver em "empresas", busca na coleção "users"
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            _isEmpresaUser = false;
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
      hasGerenciarColaboradoresAccess = userData?['gerenciarColaboradores'] ?? false;
      hasConfigurarDashAccess = userData?['configurarDash'] ?? false;
      hasCriarFormAccess = userData?['criarForm'] ?? false;
      hasCriarCampanhaAccess = userData?['criarCampanha'] ?? false;
      hasExecutarAPIs = userData?['executarAPIs'] ?? false;
      hasGerenciarProdutosAccess = userData?['gerenciarProdutos'] ?? false;
      hasGerenciarWhatsappAccess = userData?['gerenciarWhatsapp'] ?? false;

      isLoading = false;
    });

    if (!hasGerenciarParceirosAccess &&
        !hasGerenciarColaboradoresAccess &&
        !hasConfigurarDashAccess &&
        !hasCriarFormAccess &&
        !hasExecutarAPIs &&
        !hasCriarCampanhaAccess &&
        !hasGerenciarProdutosAccess) {
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
                        Navigator.of(context).pop();
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
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomTabBarPage()),
            );
          }
        });
      }
    } else {
      _hasShownPermissionRevokedDialog = false;
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

  Widget _buildCardOption(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      required bool isDesktop}) {
    return Card(
      color: Theme.of(context).colorScheme.secondary,
      margin: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24.0 : 16.0,
          vertical: isDesktop ? 12.0 : 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSecondary,
          size: isDesktop ? 40 : 30,
        ),
        title: Text(
          title,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isDesktop ? 22 : 19,
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
            fontSize: isDesktop ? 16 : 12,
            letterSpacing: 0,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Theme.of(context).colorScheme.onBackground,
          size: isDesktop ? 24 : 20,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: isDesktop
              ? Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: 1850),
                    padding: EdgeInsets.symmetric(horizontal: 50),
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
        !hasCriarCampanhaAccess &&
        !hasGerenciarWhatsappAccess &&
        !hasGerenciarProdutosAccess) {
      return ConnectivityBanner(
        child: Scaffold(
          body: isDesktop
              ? Container(
                  constraints: BoxConstraints(maxWidth: 1850),
                  padding: EdgeInsets.symmetric(horizontal: 50),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock,
                            size: isDesktop ? 120 : 100,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(height: isDesktop ? 30 : 20),
                          Text(
                            'Você não tem nenhuma permissão nesta tela.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Center(child: Container()),
        ),
      );
    } else {
      return ConnectivityBanner(
        child: Scaffold(
          body: isDesktop
              ? Container(
            constraints: const BoxConstraints(maxWidth: 1800),
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (hasGerenciarParceirosAccess)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar Parceiros',
                      subtitle: 'Gerenciar empresas parceiras',
                      icon: Icons.business,
                      onTap: () => _navigateWithFade(context, ManageCompanies()),
                      isDesktop: true,
                    ),
                  if (hasGerenciarColaboradoresAccess)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar Colaboradores',
                      subtitle: 'Gerenciar colaboradores da empresa',
                      icon: Icons.group,
                      onTap: () =>
                          _navigateWithFade(context, ManageCollaborators()),
                      isDesktop: true,
                    ),
                  if (hasCriarFormAccess)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar Formulários',
                      subtitle: 'Gerenciar formulários personalizados',
                      icon: Icons.article,
                      onTap: () => _navigateWithFade(context, ManageForms()),
                      isDesktop: true,
                    ),
                  if (hasCriarCampanhaAccess)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar Campanhas',
                      subtitle: 'Gerenciar campanhas da empresa',
                      icon: Icons.campaign,
                      onTap: () =>
                          _navigateWithFade(context, ManageCampaigns()),
                      isDesktop: true,
                    ),
                  if (hasExecutarAPIs)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar APIs',
                      subtitle: 'Gerenciar, criar, editar e executar APIs',
                      icon: Icons.api_rounded,
                      onTap: () => _navigateWithFade(context, ManageApis()),
                      isDesktop: true,
                    ),
                  if (hasConfigurarDashAccess)
                    _buildCardOption(
                      context,
                      title: 'Configurações de Dashboard',
                      subtitle: 'Configurações de BMs, anúncios e campanhas',
                      icon: Icons.dashboard_customize,
                      onTap: () => _navigateWithFade(
                          context, DashboardConfigurations()),
                      isDesktop: true,
                    ),
                  if (_isEmpresaUser)
                    _buildCardOption(
                      context,
                      title: 'Solicitações de Reunião',
                      subtitle: 'Solicitações de Reuniões abertas',
                      icon: Icons.comment,
                      onTap: () =>
                          _navigateWithFade(context, MeetingRequests()),
                      isDesktop: true,
                    ),
                  if (hasGerenciarWhatsappAccess)
                    _buildCardOption(
                      context,
                      title: 'Gerenciar WhatsApp',
                      subtitle: 'Gerenciar mensagens',
                      icon: Icons.message,
                      onTap: () => _navigateWithFade(context, WhatsAppChats()),
                      isDesktop: true,
                    ),
                  if (hasGerenciarProdutosAccess)
                    _buildCardOption(
                      context,
                      title   : 'Gerenciar Produtos',
                      subtitle: 'Criar, editar e excluir produtos',
                      icon    : Icons.inventory_2_outlined,
                      onTap   : () => _navigateWithFade(context, const ManageProducts()),
                      isDesktop: isDesktop,
                    ),
                  if (!hasGerenciarParceirosAccess &&
                      !hasGerenciarColaboradoresAccess &&
                      !hasConfigurarDashAccess &&
                      !hasCriarFormAccess &&
                      !hasExecutarAPIs &&
                      !hasCriarCampanhaAccess &&
                      !hasGerenciarProdutosAccess)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.lock,
                              size: 120,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 30),
                          Text(
                            'Você não tem nenhuma permissão nesta tela.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
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
                if (hasGerenciarParceirosAccess)
                  _buildCardOption(
                    context,
                    title: 'Gerenciar Parceiros',
                    subtitle: 'Gerenciar empresas parceiras',
                    icon: Icons.business,
                    onTap: () => _navigateWithFade(context, ManageCompanies()),
                    isDesktop: false,
                  ),
                if (hasGerenciarColaboradoresAccess)
                  _buildCardOption(
                    context,
                    title: 'Gerenciar Colaboradores',
                    subtitle: 'Gerenciar colaboradores da empresa',
                    icon: Icons.group,
                    onTap: () =>
                        _navigateWithFade(context, ManageCollaborators()),
                    isDesktop: false,
                  ),
                if (hasCriarFormAccess)
                  _buildCardOption(
                    context,
                    title: 'Gerenciar Formulários',
                    subtitle: 'Gerenciar formulários personalizados',
                    icon: Icons.article,
                    onTap: () => _navigateWithFade(context, ManageForms()),
                    isDesktop: false,
                  ),
                if (hasCriarCampanhaAccess)
                  _buildCardOption(
                    context,
                    title: 'Gerenciar Campanhas',
                    subtitle: 'Gerenciar campanhas da empresa',
                    icon: Icons.campaign,
                    onTap: () =>
                        _navigateWithFade(context, ManageCampaigns()),
                    isDesktop: false,
                  ),
                if (hasExecutarAPIs)
                  _buildCardOption(
                    context,
                    title: 'Gerenciar APIs',
                    subtitle: 'Gerenciar, criar, editar e executar APIs',
                    icon: Icons.api_rounded,
                    onTap: () => _navigateWithFade(context, ManageApis()),
                    isDesktop: false,
                  ),
                if (hasConfigurarDashAccess)
                  _buildCardOption(
                    context,
                    title: 'Configurações de Dashboard',
                    subtitle: 'Configurações de BMs, anúncios e campanhas',
                    icon: Icons.dashboard_customize,
                    onTap: () => _navigateWithFade(
                        context, DashboardConfigurations()),
                    isDesktop: false,
                  ),
                if (_isEmpresaUser)
                  _buildCardOption(
                    context,
                    title: 'Solicitações de Reunião',
                    subtitle: 'Solicitações de Reuniões abertas',
                    icon: Icons.comment,
                    onTap: () =>
                        _navigateWithFade(context, MeetingRequests()),
                    isDesktop: false,
                  ),
                if (hasGerenciarProdutosAccess)
                  _buildCardOption(
                    context,
                    title   : 'Gerenciar Produtos',
                    subtitle: 'Criar, editar e excluir produtos',
                    icon    : Icons.inventory_2_outlined,
                    onTap   : () => _navigateWithFade(context, const ManageProducts()),
                    isDesktop: isDesktop,
                  ),
                if (!hasGerenciarParceirosAccess &&
                    !hasGerenciarColaboradoresAccess &&
                    !hasConfigurarDashAccess &&
                    !hasCriarFormAccess &&
                    !hasExecutarAPIs &&
                    !hasCriarCampanhaAccess &&
                    !hasGerenciarProdutosAccess &&
                    !hasGerenciarWhatsappAccess)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(Icons.lock,
                            size: 100,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 20),
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
              ],
            ),
          )
        ),
      );
    }
  }
}
