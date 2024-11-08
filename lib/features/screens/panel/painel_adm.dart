import 'package:app_io/features/screens/dasboard/dashboard_configurations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/campaign/create_campaign.dart';
import 'package:app_io/features/screens/collaborator/manage_collaborators.dart';
import 'package:app_io/features/screens/company/manage_companies.dart';
import 'package:app_io/features/screens/form/create_form.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:provider/provider.dart';

class AdminPanelPage extends StatefulWidget {
  @override
  _AdminPanelPageState createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final FirestoreService _firestoreService = FirestoreService();
  bool hasGerenciarParceirosAccess = false;
  bool hasGerenciarColaboradoresAccess = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _getUserPermissions();
  }

  Future<void> _getUserPermissions() async {
    setState(() {
      isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      try {
        // Tenta buscar o documento na coleção "empresas"
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        // Se o documento não existir em "empresas", busca em "users"
        if (!userDoc.exists) {
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        }

        if (userDoc.exists) {
          final userData = userDoc.data();

          setState(() {
            hasGerenciarParceirosAccess =
                userData?['gerenciarParceiros'] ?? false;
            hasGerenciarColaboradoresAccess =
                userData?['gerenciarColaboradores'] ?? false;
            isLoading = false;
          });
        } else {
          print("Documento do usuário não encontrado nas coleções 'empresas' ou 'users'.");
          setState(() {
            isLoading = false;
          });
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Painel ADM'),
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'BrandingSF',
          fontWeight: FontWeight.w900,
          fontSize: 26,
            color: Theme.of(context).colorScheme.outline
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.outline,
      ),
      body: SafeArea(
        top: true,
        child: isLoading
            ? Center(
                child: CircularProgressIndicator(),
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
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding:
                                EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
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
                            padding:
                                EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onTap: () async {
                                _navigateWithFade(
                                    context, ManageCollaborators());
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                        if (hasGerenciarParceirosAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding:
                                EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                        if (hasGerenciarParceirosAccess)
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding:
                                EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                            child: InkWell(
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onTap: () async {
                                // Substitua "empresaId" pelo ID real da empresa
                                _navigateWithFade(context,
                                    CreateCampaignPage(empresaId: 'empresaId'));
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 20,
                                ),
                                dense: false,
                              ),
                            ),
                          ),
                        ),
                        if (hasGerenciarParceirosAccess)
                          Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                              child: InkWell(
                                splashColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onBackground,
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
                        !hasGerenciarColaboradoresAccess)
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
    );
  }
}
