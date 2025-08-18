import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/company/add_company.dart';
import 'package:app_io/features/screens/company/edit_companies.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ManageCompanies extends StatefulWidget {
  @override
  _ManageCompaniesState createState() => _ManageCompaniesState();
}

class _ManageCompaniesState extends State<ManageCompanies> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  bool hasGerenciarParceirosAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;

  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  bool _getRight(Map<String, dynamic>? data, String key) {
    if (data == null) return false;
    if (data[key] == true) return true; // campo “flat” na raiz do doc
    final ar = data['accessRights'];
    if (ar is Map<String, dynamic> && ar[key] == true) return true; // dentro de accessRights
    return false;
  }

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
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore
            .instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _listenToUserDocument('empresas', user.uid);
        } else {
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            _listenToUserDocument('users', user.uid);
          } else {
            print("Documento do usuário não encontrado nas coleções 'empresas' ou 'users'.");
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
        print("Documento do usuário não encontrado na coleção '$collectionName'.");
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final data = userDoc.data();
    if (!mounted) return;

    setState(() {
      hasGerenciarParceirosAccess =
          _getRight(data, 'gerenciarParceiros'); // <- agora lê raiz OU accessRights
      isLoading = false;
    });

    if (!hasGerenciarParceirosAccess) {
      if (!_hasShownPermissionRevokedDialog) {
        _hasShownPermissionRevokedDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await showModalBottomSheet(
            context: context,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).primaryColor),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
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
                        Navigator.of(context).pop(); // Fechar o BottomSheet
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

          // Após o diálogo ser fechado, redirecionar o usuário
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomTabBarPage()),
            );
          }
        });
      }
    } else {
      _hasShownPermissionRevokedDialog = false; // Reseta caso a permissão volte
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // Começa de baixo para cima
          const end = Offset.zero;
          const curve = Curves.easeInOut; // Animação suave

          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> deleteCompany(String companyId) async {
    try {
      HttpsCallable callable =
      FirebaseFunctions.instance.httpsCallable('deleteCompany');
      final result = await callable.call(<String, dynamic>{
        'companyId': companyId,
      });

      if (result.data['success'] == true) {
        showErrorDialog(context,
            "Empresa e usuários vinculados excluídos com sucesso!", "Sucesso");
      } else {
        showErrorDialog(
            context, "Erro ao excluir empresa e usuários vinculados.", "Erro");
      }
    } on FirebaseFunctionsException catch (e) {
      print('Erro na Cloud Function: ${e.code} - ${e.message}');
      showErrorDialog(
          context, "Erro ao excluir empresa e usuários vinculados.", "Erro");
    } catch (e) {
      print('Erro desconhecido: $e');
      showErrorDialog(
          context, "Erro ao excluir empresa e usuários vinculados.", "Erro");
    }
  }

  void _showDeleteConfirmationDialog(String companyId, String userEmail) {
    showModalBottomSheet(
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
                'Excluir Parceiro',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 16.0),
              Text(
                'Você tem certeza que deseja excluir esta empresa? "ESTA AÇÃO NÃO PODE SER DESFEITA!"',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                      deleteCompany(companyId); // Excluir a empresa e o usuário
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Excluir',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    // Se o scrollController não tiver clientes, usamos 0.0 como offset
    final double offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    double computedAppBarHeight = (100.0 - (offset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (offset / 100)).clamp(0.0, 1.0);

    // Se for desktop, calcula também o tabBarHeight (se necessário)
    double tabBarHeight = (kBottomNavigationBarHeight - (offset / 2))
        .clamp(0.0, kBottomNavigationBarHeight)
        .ceilToDouble();

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarParceirosAccess) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Container(),
        ),
      );
    } else {
      final authProvider = Provider.of<AuthProvider>(context);
      final user = authProvider.user;
      final currentUserId = user?.uid;

      return ConnectivityBanner(
        child: GestureDetector(
          child: Scaffold(
            // Utiliza AnimatedBuilder para reconstruir apenas a AppBar com base no scroll
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(100.0),
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  // Se quiser manter o efeito de altura, podemos calcular currentHeight
                  final double currentOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                  final double currentHeight = (100.0 - (currentOffset / 2)).clamp(0.0, 100.0);

                  // Define a opacidade fixamente como 1.0
                  return AppBar(
                    toolbarHeight: currentHeight,
                    automaticallyImplyLeading: false,
                    flexibleSpace: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.arrow_back_ios_new,
                                        color: Theme.of(context).colorScheme.onBackground,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Voltar',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Parceiros',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.add_business,
                                color: Theme.of(context).colorScheme.onBackground,
                                size: 30,
                              ),
                              onPressed: () async {
                                _navigateWithBottomToTopTransition(context, AddCompany());
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                  );
                },
              ),
            ),

            // O restante do corpo permanece inalterado
            body: isDesktop
                ? Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: 1850),
                child: SafeArea(
                  top: true,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('empresas')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Erro ao carregar empresas'));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(child: Text('Nenhuma empresa encontrada'));
                      }

                      final companies = snapshot.data!.docs;

                      // Filtrar as empresas com base em isDevAccount e currentUserId
                      final filteredCompanies = companies.where((doc) {
                        final data = doc.data() as Map<String, dynamic>?;
                        final bool isDevAccount = data?['isDevAccount'] == true;
                        if (isDevAccount) return doc.id == currentUserId;
                        return true;
                      }).toList();

                      return ListView.builder(
                        controller: _scrollController,
                        itemCount: filteredCompanies.length,
                        itemBuilder: (context, index) {
                          final company = filteredCompanies[index];
                          final data = company.data() as Map<String, dynamic>;

                          bool asBool(dynamic v) => v == true;
                          int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

                          final String nomeEmpresa = (data['NomeEmpresa'] ?? '') as String;
                          final String contract    = (data['contract'] ?? '') as String;
                          final String email       = (data['email'] ?? '') as String;
                          final String cnpj        = (data['cnpj'] ?? '') as String;
                          final String founded     = (data['founded'] ?? '').toString();

                          final int countArtsValue   = asInt(data['countArtsValue']);
                          final int countVideosValue = asInt(data['countVideosValue']);

                          final bool dashboard              = _getRight(data, 'dashboard');
                          final bool leads                  = _getRight(data, 'leads');
                          final bool gerenciarColaboradores = _getRight(data, 'gerenciarColaboradores');
                          final bool configurarDash         = _getRight(data, 'configurarDash');
                          final bool criarCampanha          = _getRight(data, 'criarCampanha');
                          final bool criarForm              = _getRight(data, 'criarForm');
                          final bool copiarTelefones        = _getRight(data, 'copiarTelefones');
                          final bool alterarSenha           = _getRight(data, 'alterarSenha');
                          final bool executarAPIs           = _getRight(data, 'executarAPIs');
                          final bool gerenciarProdutos      = _getRight(data, 'gerenciarProdutos');

                          final String? photoUrl = data['photoUrl'] as String?;

                          return Card(
                            elevation: 4,
                            color: Theme.of(context).colorScheme.secondary,
                            margin: EdgeInsets.only(left: 10, right: 10, top: 20),
                            child: Container(
                              padding: EdgeInsets.all(10), // Aumenta o padding para desktop
                              child: ListTile(
                                contentPadding: EdgeInsets.all(8), // Aumenta o padding interno do ListTile
                                leading: CircleAvatar(
                                  radius: 30,
                                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                                  child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.business) : null,
                                ),
                                title: Text(
                                  nomeEmpresa,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18, // Aumenta o tamanho da fonte para desktop
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Contrato: $contract',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w400,
                                    fontSize: 16, // Aumenta o tamanho da fonte para desktop
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        color: Theme.of(context).colorScheme.onSecondary,
                                        size: 30,
                                      ),
                                      onPressed: () {
                                        _navigateWithBottomToTopTransition(
                                          context,
                                          EditCompanies(
                                            companyId: company.id,
                                            nomeEmpresa: nomeEmpresa,
                                            email: email,
                                            contract: contract,
                                            cnpj: cnpj,
                                            founded: founded,
                                            countArtsValue: countArtsValue,
                                            countVideosValue: countVideosValue,
                                            dashboard: dashboard,
                                            leads: leads,
                                            gerenciarColaboradores: gerenciarColaboradores,
                                            configurarDash: configurarDash,
                                            criarCampanha: criarCampanha,
                                            criarForm: criarForm,
                                            copiarTelefones: copiarTelefones,
                                            alterarSenha: alterarSenha,
                                            executarAPIs: executarAPIs,
                                            gerenciarProdutos: gerenciarProdutos,
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 30,
                                      ),
                                      onPressed: () {
                                        _showDeleteConfirmationDialog(
                                          company.id,
                                          email,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            )
                : SafeArea(
              top: true,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('empresas')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Erro ao carregar empresas'));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('Nenhuma empresa encontrada'));
                  }

                  final companies = snapshot.data!.docs;

                  final filteredCompanies = companies.where((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    final bool isDevAccount = data?['isDevAccount'] == true;
                    if (isDevAccount) return doc.id == currentUserId;
                    return true;
                  }).toList();

                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: filteredCompanies.length,
                    itemBuilder: (context, index) {
                      final company = filteredCompanies[index];
                      final data = company.data() as Map<String, dynamic>;

                      bool asBool(dynamic v) => v == true;
                      int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

                      final String nomeEmpresa = (data['NomeEmpresa'] ?? '') as String;
                      final String contract    = (data['contract'] ?? '') as String;
                      final String email       = (data['email'] ?? '') as String;
                      final String cnpj        = (data['cnpj'] ?? '') as String;
                      final String founded     = (data['founded'] ?? '').toString();

                      final int countArtsValue   = asInt(data['countArtsValue']);
                      final int countVideosValue = asInt(data['countVideosValue']);

                      final bool dashboard              = _getRight(data, 'dashboard');
                      final bool leads                  = _getRight(data, 'leads');
                      final bool gerenciarColaboradores = _getRight(data, 'gerenciarColaboradores');
                      final bool configurarDash         = _getRight(data, 'configurarDash');
                      final bool criarCampanha          = _getRight(data, 'criarCampanha');
                      final bool criarForm              = _getRight(data, 'criarForm');
                      final bool copiarTelefones        = _getRight(data, 'copiarTelefones');
                      final bool alterarSenha           = _getRight(data, 'alterarSenha');
                      final bool executarAPIs           = _getRight(data, 'executarAPIs');
                      final bool gerenciarProdutos      = _getRight(data, 'gerenciarProdutos');

                      final String? photoUrl = data['photoUrl'] as String?;

                      return Card(
                        elevation: 4,
                        color: Theme.of(context).colorScheme.secondary,
                        margin: EdgeInsets.only(top: 20),
                        child: Container(
                          padding: EdgeInsets.all(2), // Aumenta o padding para desktop
                          child: ListTile(
                            contentPadding: EdgeInsets.all(8), // Aumenta o padding interno do ListTile
                            leading: CircleAvatar(
                              radius: 30,
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                              child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.business) : null,
                            ),
                            title: Text(
                              nomeEmpresa,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 18, // Aumenta o tamanho da fonte para desktop
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            subtitle: Text(
                              'Contrato: $contract',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w400,
                                fontSize: 16, // Aumenta o tamanho da fonte para desktop
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                    size: 25,
                                  ),
                                  onPressed: () {
                                    _navigateWithBottomToTopTransition(
                                      context,
                                      EditCompanies(
                                        companyId: company.id,
                                        nomeEmpresa: nomeEmpresa,
                                        email: email,
                                        contract: contract,
                                        cnpj: cnpj,
                                        founded: founded,
                                        countArtsValue: countArtsValue,
                                        countVideosValue: countVideosValue,
                                        dashboard: dashboard,
                                        leads: leads,
                                        gerenciarColaboradores: gerenciarColaboradores,
                                        configurarDash: configurarDash,
                                        criarCampanha: criarCampanha,
                                        criarForm: criarForm,
                                        copiarTelefones: copiarTelefones,
                                        alterarSenha: alterarSenha,
                                        executarAPIs: executarAPIs,
                                        gerenciarProdutos: gerenciarProdutos,
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 25,
                                  ),
                                  onPressed: () {
                                    _showDeleteConfirmationDialog(
                                      company.id,
                                      email,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
  }
}