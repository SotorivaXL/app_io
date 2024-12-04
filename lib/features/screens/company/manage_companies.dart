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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;
  bool hasGerenciarParceirosAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;

  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
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
        // Verifica se o documento existe na coleção 'empresas'
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore
            .instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          _listenToUserDocument('empresas', user.uid);
        } else {
          // Se não existir em 'empresas', verifica em 'users'
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
      _hasShownPermissionRevokedDialog =
          false; // Reseta a flag se a permissão voltar
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

          final tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double tabBarHeight = (kBottomNavigationBarHeight - (_scrollOffset / 2))
        .clamp(0.0, kBottomNavigationBarHeight)
        .ceilToDouble();
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    // Definindo a física com base na visibilidade da AppBar e TabBar
    final pageViewPhysics = (appBarHeight > 0 && tabBarHeight > 0)
        ? AlwaysScrollableScrollPhysics()
        : NeverScrollableScrollPhysics();

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarParceirosAccess) {
      // Opcionalmente, você pode retornar uma tela vazia ou uma mensagem
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
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(appBarHeight),
              child: Opacity(
                opacity: opacity,
                child: AppBar(
                  toolbarHeight: appBarHeight,
                  automaticallyImplyLeading: false,
                  flexibleSpace: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Botão de voltar e título
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
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Voltar',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 16,
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
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ],
                          ),
                          // Stack na direita
                          Stack(
                            children: [
                              IconButton(
                                icon: Icon(Icons.add_business,
                                    color: Theme.of(context).colorScheme.onBackground,
                                    size: 30),
                                onPressed: () async {
                                  _navigateWithBottomToTopTransition(context, AddCompany());
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
            body: SafeArea(
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
                  final filteredCompanies = companies.where((company) {
                    final isDevAccount = company['isDevAccount'] ?? false;
                    final companyId = company.id;

                    if (isDevAccount == true) {
                      if (companyId == currentUserId) {
                        return true; // Incluir a empresa
                      } else {
                        return false; // Excluir a empresa
                      }
                    } else {
                      return true; // Incluir a empresa
                    }
                  }).toList();

                  return ListView.builder(
                    itemCount: filteredCompanies.length,
                    itemBuilder: (context, index) {
                      final company = filteredCompanies[index];
                      final nomeEmpresa = company['NomeEmpresa'];
                      final contract = company['contract'];

                      return Card(
                        elevation: 4,
                        color: Theme.of(context).colorScheme.secondary,
                        margin: EdgeInsets.only(left: 10, right: 10, top: 20),
                        child: ListTile(
                          title: Text(
                            nomeEmpresa,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          subtitle: Text(
                            'Contrato: $contract',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary),
                                onPressed: () {
                                  _navigateWithBottomToTopTransition(
                                    context,
                                    EditCompanies(
                                      companyId: company.id,
                                      nomeEmpresa: nomeEmpresa,
                                      email: company['email'],
                                      contract: contract,
                                      cnpj: company['cnpj'],
                                      founded: company['founded'],
                                      countArtsValue: company['countArtsValue'],
                                      countVideosValue:
                                          company['countVideosValue'],
                                      dashboard: company['dashboard'],
                                      leads: company['leads'],
                                      gerenciarColaboradores:
                                          company['gerenciarColaboradores'],
                                      configurarDash: company['configurarDash'],
                                      criarCampanha: company['criarCampanha'],
                                      criarForm: company['criarForm'],
                                      copiarTelefones: company['copiarTelefones'],
                                      alterarSenha: company['alterarSenha'],
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  _showDeleteConfirmationDialog(
                                      company.id, company['email']);
                                },
                              ),
                            ],
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
