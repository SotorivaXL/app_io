import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/campaign/create_campaign.dart';
import 'package:app_io/features/screens/campaign/edit_campaign.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ManageCampaigns extends StatefulWidget {
  @override
  _ManageCampaignsState createState() => _ManageCampaignsState();
}

class _ManageCampaignsState extends State<ManageCampaigns> {
  bool hasGerenciarCampanhaAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  String? companyId;
  Map<String, dynamic>? empresaDocData;
  List<Map<String, dynamic>> campanhas = [];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _campanhasSubscription;

  @override
  void initState() {
    super.initState();
    _determineUserAndLoadCampaigns();

    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _campanhasSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _determineUserAndLoadCampaigns() async {
    setState(() {
      isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      showErrorDialog(context, 'Usuário não está logado.', 'Erro');
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      DocumentSnapshot<Map<String, dynamic>>? userDoc;

      // Verifica se o usuário é um "user"
      userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        // Usuário é um "user"
        if (userDoc.data()!.containsKey('createdBy')) {
          companyId = userDoc['createdBy'];
          empresaDocData = (await FirebaseFirestore.instance
              .collection('empresas')
              .doc(companyId)
              .get())
              .data();

          if (empresaDocData == null) {
            showErrorDialog(context, 'Empresa relacionada não encontrada.', 'Erro');
            setState(() {
              isLoading = false;
            });
            return;
          }
        } else {
          showErrorDialog(context, 'Campo "createdBy" não encontrado no documento do usuário.', 'Erro');
          setState(() {
            isLoading = false;
          });
          return;
        }
      } else {
        // Verifica se o usuário é uma "empresa"
        userDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          // Usuário é uma "empresa"
          companyId = user.uid;
          empresaDocData = userDoc.data();
        } else {
          showErrorDialog(context, 'Usuário não é "user" nem "empresa". Documento não encontrado.', 'Erro');
          setState(() {
            isLoading = false;
          });
          return;
        }
      }

      // Agora, companyId está definido. Verifica permissões.
      _listenToUserDocument();

    } catch (e) {
      print("Erro ao determinar usuário e carregar campanhas: $e");
      showErrorDialog(context, 'Erro ao determinar usuário e carregar campanhas.', 'Erro');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _listenToUserDocument() {
    if (companyId == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    // Assina o documento da empresa para verificar permissões
    _userDocSubscription = FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .snapshots()
        .listen((empresaDoc) {
      if (empresaDoc.exists) {
        _updatePermissions(empresaDoc);
      } else {
        showErrorDialog(context, 'Documento da empresa não encontrado.', 'Erro');
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> empresaDoc) {
    final empresaData = empresaDoc.data();

    if (!mounted) return;

    setState(() {
      hasGerenciarCampanhaAccess = empresaData?['criarCampanha'] ?? false;
      isLoading = false;
    });

    if (!hasGerenciarCampanhaAccess) {
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
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
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
      _loadCampanhasListener(companyId!);
    }
  }

  void _loadCampanhasListener(String empresaId) {
    _campanhasSubscription?.cancel();

    _campanhasSubscription = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('campanhas')
        .snapshots()
        .listen((snapshot) {
      List<Map<String, dynamic>> updatedCampanhas = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'nome_campanha': doc['nome_campanha'] ?? 'Nome não disponível',
          'descricao': doc['descricao'] ?? 'Descrição não disponível',
        };
      }).toList();

      setState(() {
        campanhas = updatedCampanhas;
      });
    });
  }

  Future<void> deleteCampaign(String campanhaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(companyId)
          .collection('campanhas')
          .doc(campanhaId)
          .delete();
      showErrorDialog(context, "Campanha excluída com sucesso!", "Sucesso");
    } catch (e) {
      print('Erro ao excluir campanha: $e');
      showErrorDialog(context, "Erro ao excluir campanha.", "Erro");
    }
  }

  void _showDeleteConfirmationDialog(String campanhaId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Excluir Campanha'),
          content: Text('Tem certeza que deseja excluir esta campanha?'),
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                'Excluir',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () async {
                Navigator.of(context).pop(); // Fecha o diálogo
                await deleteCampaign(campanhaId);
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // Começa de baixo para cima
          const end = Offset.zero;
          const curve = Curves.easeInOut; // Animação suave

          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: curve));
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

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarCampanhaAccess) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(
            child: Text(
              "Você não tem permissão para acessar esta página.",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
          ),
        ),
      );
    } else {
      return ConnectivityBanner(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
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
                                'Gerenciar Campanhas',
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
                              Icons.add,
                              color: Theme.of(context).colorScheme.onBackground,
                              size: 30,
                            ),
                            onPressed: () {
                              if (companyId != null) {
                                _navigateWithBottomToTopTransition(
                                  context,
                                  CreateCampaignPage(empresaId: companyId!),
                                );
                              } else {
                                showErrorDialog(
                                  context,
                                  'Empresa não encontrada.',
                                  'Atenção',
                                );
                              }
                            },
                            tooltip: 'Adicionar Campanha',
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
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Expanded(
                    child: campanhas.isEmpty
                        ? Center(
                      child: Text(
                        'Nenhuma campanha encontrada.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    )
                        : ListView.builder(
                      controller: _scrollController,
                      itemCount: campanhas.length,
                      itemBuilder: (context, index) {
                        final campanha = campanhas[index];
                        return Card(
                          elevation: 4,
                          color: Theme.of(context).colorScheme.secondary,
                          margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: ListTile(
                            title: Text(
                              campanha['nome_campanha'] ?? 'Campanha sem nome',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            subtitle: Text(
                              campanha['descricao'] ?? 'Descrição não disponível',
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
                                  icon: Icon(
                                    Icons.edit,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditCampaignPage(
                                          empresaId: companyId!,
                                          campanhaId: campanha['id'],
                                        ),
                                      ),
                                    ).then((value) {
                                      if (value == true) {
                                        setState(() {});
                                      }
                                    });
                                  },
                                  tooltip: 'Editar Campanha',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    _showDeleteConfirmationDialog(campanha['id']);
                                  },
                                  tooltip: 'Excluir Campanha',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
  }
}
