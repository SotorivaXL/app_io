import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/form/create_form.dart';
import 'package:app_io/features/screens/form/edit_form.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ManageForms extends StatefulWidget {
  @override
  _ManageFormsState createState() => _ManageFormsState();
}

class _ManageFormsState extends State<ManageForms> {
  // Variáveis de estado
  bool hasGerenciarFormAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  String? selectedEmpresaId;
  String? selectedEmpresaName;
  String? selectedCampaignId;
  String? selectedCampaignName;

  List<Map<String, dynamic>> empresas = [];
  List<Map<String, dynamic>> campanhas = [];
  List<Map<String, dynamic>> forms = [];

  // Subscriptions
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _empresasSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _campanhasSubscription;
  // Mapa para gerenciar múltiplos listeners de formulários
  Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _formSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _determineUserDocumentAndListen();
    _loadEmpresas();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _empresasSubscription?.cancel();
    _campanhasSubscription?.cancel();
    _formSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    super.dispose();
  }

  // Método para carregar empresas e configurar listener
  Future<void> _loadEmpresas() async {
    try {
      _empresasSubscription = FirebaseFirestore.instance.collection('empresas').snapshots().listen((snapshot) {
        List<Map<String, dynamic>> updatedEmpresas = snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'NomeEmpresa': doc['NomeEmpresa'] ?? 'Nome não disponível',
          };
        }).toList();

        setState(() {
          empresas = updatedEmpresas;
        });
      });
    } catch (e) {
      print('Erro ao carregar empresas: $e');
      showErrorDialog(context, 'Erro ao carregar empresas.', 'Erro');
    }
  }

  // Método para carregar campanhas e configurar listener
  void _loadCampanhasListener(String empresaId) {
    // Cancelar qualquer listener anterior
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
        };
      }).toList();

      setState(() {
        campanhas = updatedCampanhas;
        // Limpar formulários quando a campanha muda
        forms = [];
      });

      if (selectedCampaignId == null) {
        // "Todas as Campanhas" está selecionado, configurar listeners para todos os formulários
        _setupAllFormsListeners();
      } else {
        // Campanha específica está selecionada, configurar listener apenas para essa campanha
        _setupSingleFormListener(selectedCampaignId!);
      }
    });
  }

  // Método para configurar listeners para todos os formulários de todas as campanhas
  void _setupAllFormsListeners() {
    // Cancelar todos os listeners de formulários existentes
    _formSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    _formSubscriptions.clear();
    forms.clear();

    for (var campanha in campanhas) {
      String campanhaId = campanha['id'];
      String campanhaNome = campanha['nome_campanha'];

      StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subscription =
      FirebaseFirestore.instance
          .collection('empresas')
          .doc(selectedEmpresaId)
          .collection('campanhas')
          .doc(campanhaId)
          .collection('forms')
          .snapshots()
          .listen((snapshot) {
        snapshot.docChanges.forEach((change) {
          if (change.type == DocumentChangeType.added) {
            setState(() {
              forms.add({
                'id': change.doc.id,
                'form_name': change.doc['form_name'] ?? 'Formulário sem nome',
                'campanha_id': campanhaId,
                'campanha_nome': campanhaNome,
              });
            });
          } else if (change.type == DocumentChangeType.modified) {
            setState(() {
              int index = forms.indexWhere((form) => form['id'] == change.doc.id && form['campanha_id'] == campanhaId);
              if (index != -1) {
                forms[index]['form_name'] = change.doc['form_name'] ?? 'Formulário sem nome';
              }
            });
          } else if (change.type == DocumentChangeType.removed) {
            setState(() {
              forms.removeWhere((form) => form['id'] == change.doc.id && form['campanha_id'] == campanhaId);
            });
          }
        });
      });

      _formSubscriptions[campanhaId] = subscription;
    }
  }

  // Método para configurar listener para uma única campanha
  void _setupSingleFormListener(String campanhaId) {
    // Cancelar todos os listeners de formulários existentes
    _formSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    _formSubscriptions.clear();
    forms.clear();

    // Configurar listener apenas para a campanha selecionada
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subscription =
    FirebaseFirestore.instance
        .collection('empresas')
        .doc(selectedEmpresaId)
        .collection('campanhas')
        .doc(campanhaId)
        .collection('forms')
        .snapshots()
        .listen((snapshot) {
      snapshot.docChanges.forEach((change) {
        if (change.type == DocumentChangeType.added) {
          setState(() {
            forms.add({
              'id': change.doc.id,
              'form_name': change.doc['form_name'] ?? 'Formulário sem nome',
              'campanha_id': campanhaId,
              'campanha_nome': selectedCampaignName ?? 'Campanha desconhecida',
            });
          });
        } else if (change.type == DocumentChangeType.modified) {
          setState(() {
            int index = forms.indexWhere((form) => form['id'] == change.doc.id && form['campanha_id'] == campanhaId);
            if (index != -1) {
              forms[index]['form_name'] = change.doc['form_name'] ?? 'Formulário sem nome';
            }
          });
        } else if (change.type == DocumentChangeType.removed) {
          setState(() {
            forms.removeWhere((form) => form['id'] == change.doc.id && form['campanha_id'] == campanhaId);
          });
        }
      });
    });

    _formSubscriptions[campanhaId] = subscription;
  }

  // Método para determinar o documento do usuário e verificar permissões
  Future<void> _determineUserDocumentAndListen() async {
    setState(() {
      isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user != null) {
      try {
        // Verifica se o documento existe na coleção 'empresas'
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
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

  // Método para ouvir o documento do usuário
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

  // Método para atualizar permissões
  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final userData = userDoc.data();

    if (!mounted) return;

    setState(() {
      hasGerenciarFormAccess = userData?['criarForm'] ?? false;
      isLoading = false;
    });

    if (!hasGerenciarFormAccess) {
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
                        backgroundColor:
                        Theme.of(context).colorScheme.secondary,
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

  // Método para deletar um formulário
  Future<void> deleteForm(String empresaId, String campanhaId, String formId) async {
    try {
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campanhaId)
          .collection('forms')
          .doc(formId)
          .delete();
      showErrorDialog(context, "Formulário excluído com sucesso!", "Sucesso");
    } catch (e) {
      print('Erro ao excluir formulário: $e');
      showErrorDialog(context, "Erro ao excluir formulário.", "Erro");
    }
  }

  // Método para mostrar o diálogo de confirmação de exclusão
  void _showDeleteConfirmationDialog(String empresaId, String campanhaId, String formId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Excluir Formulário'),
          content: Text('Tem certeza que deseja excluir este formulário?'),
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
                await deleteForm(empresaId, campanhaId, formId);
              },
            ),
          ],
        );
      },
    );
  }

  // Método para navegar com animação de transição de baixo para cima
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

  // Método para selecionar uma campanha
  void _selectCampaign(String campanhaId, String campanhaNome) {
    setState(() {
      selectedCampaignId = campanhaId;
      selectedCampaignName = campanhaNome;
      forms = [];
    });
    _setupSingleFormListener(campanhaId);
  }

  @override
  Widget build(BuildContext context) {
    // Definição de 'isDesktop' com base na largura da tela
    bool isDesktop = MediaQuery.of(context).size.width > 1024;

    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    if (isLoading) {
      return ConnectivityBanner(
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (!hasGerenciarFormAccess) {
      // Retornar uma tela vazia ou uma mensagem
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
                                      color:
                                      Theme.of(context).colorScheme.onBackground,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Voltar',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 14,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Gerenciar Formulários',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ],
                          ),
                          // Botão para adicionar novo formulário
                          IconButton(
                            icon: Icon(
                              Icons.add,
                              color:
                              Theme.of(context).colorScheme.onBackground,
                              size: 30,
                            ),
                            onPressed: () {
                              _navigateWithBottomToTopTransition(context, CreateForm());
                            },
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
              child: isDesktop
                  ? Align(
                alignment: Alignment.topCenter,
                child: Container(
                  constraints: BoxConstraints(maxWidth: 1850),
                  padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Dropdown de Empresas
                      Padding(
                        padding:
                        EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        child: DropdownButtonFormField<String>(
                          isExpanded:
                          true, // Permite que o dropdown ocupe toda a largura disponível
                          alignment:
                          Alignment.center, // Alinha o conteúdo centralmente
                          value: selectedEmpresaId,
                          onChanged: (val) async {
                            if (val != null) {
                              setState(() {
                                selectedEmpresaId = val;
                                selectedEmpresaName = empresas
                                    .firstWhere((empresa) => empresa['id'] == val)['NomeEmpresa'];
                                selectedCampaignId = null;
                                selectedCampaignName = null;
                                campanhas.clear();
                                forms.clear();
                              });
                              _loadCampanhasListener(val);
                            }
                          },
                          items: empresas.map((empresa) {
                            return DropdownMenuItem<String>(
                              value: empresa['id'],
                              child: Center(
                                child: Text(
                                  empresa['NomeEmpresa'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isDesktop ? 18 : 16, // Aumento da fonte
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            contentPadding:
                            EdgeInsets.symmetric(vertical: isDesktop ? 20.0 : 10.0, horizontal: 16.0), // Aumento da altura
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            hintText: 'Selecione a empresa...',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                              fontWeight: FontWeight.w500,
                              color:
                              Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          dropdownColor:
                          Theme.of(context).colorScheme.background,
                          selectedItemBuilder: (BuildContext context) {
                            return empresas.map((empresa) {
                              return Center(
                                child: Text(
                                  empresa['NomeEmpresa'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isDesktop ? 18 : 16, // Aumento da fonte
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              );
                            }).toList();
                          },
                          hint: Center(
                            child: Text(
                              'Selecione a empresa...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                fontWeight: FontWeight.w600,
                                color:
                                Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          ),
                          icon: SizedBox
                              .shrink(), // Remove o ícone de seta
                          iconSize:
                          0, // Garante que nenhum espaço seja reservado para o ícone
                        ),
                      ),

                      // Filtro de Campanhas
                      if (selectedEmpresaId != null && campanhas.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            height: isDesktop ? 60 : 50, // Aumento da altura
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              alignment: Alignment.center,
                              value: selectedCampaignId ?? 'Todas',
                              onChanged: (val) {
                                if (val == 'Todas') {
                                  setState(() {
                                    selectedCampaignId = null;
                                    selectedCampaignName = null;
                                    forms.clear();
                                  });
                                  _setupAllFormsListeners();
                                } else {
                                  final campanha = campanhas.firstWhere((campanha) => campanha['id'] == val);
                                  setState(() {
                                    selectedCampaignId = campanha['id'];
                                    selectedCampaignName = campanha['nome_campanha'];
                                    forms.clear();
                                  });
                                  _setupSingleFormListener(campanha['id']);
                                }
                              },
                              items: [
                                // Opção "Todas as Campanhas"
                                DropdownMenuItem<String>(
                                  value: 'Todas',
                                  child: Center(
                                    child: Text(
                                      'Todas as Campanhas',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                        fontWeight: FontWeight.w500,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                // Itens das campanhas
                                ...campanhas.map((campanha) {
                                  return DropdownMenuItem<String>(
                                    value: campanha['id'] as String,
                                    child: Center(
                                      child: Text(
                                        campanha['nome_campanha'],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                          fontWeight: FontWeight.w500,
                                          color:
                                          Theme.of(context).colorScheme.onSecondary,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.secondary,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: isDesktop ? 20.0 : 10.0, horizontal: 0), // Aumento da altura
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                hintText: 'Selecione a campanha',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                  fontWeight: FontWeight.w500,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                              dropdownColor:
                              Theme.of(context).colorScheme.background,
                              selectedItemBuilder: (BuildContext context) {
                                return [
                                  // Opção "Todas as Campanhas"
                                  Center(
                                    child: Text(
                                      'Todas as Campanhas',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                        fontWeight: FontWeight.w500,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  ),
                                  // Itens das campanhas
                                  ...campanhas.map((campanha) {
                                    return Center(
                                      child: Text(
                                        campanha['nome_campanha'],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                          fontWeight: FontWeight.w500,
                                          color:
                                          Theme.of(context).colorScheme.onSecondary,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ];
                              },
                              hint: Center(
                                child: Text(
                                  'Selecione a campanha',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isDesktop ? 18 : 15, // Aumento da fonte
                                    fontWeight: FontWeight.w500,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              ),
                              icon: SizedBox.shrink(),
                              iconSize: 0,
                            ),
                          ),
                        ),

                      // Espaçamento adicional entre os selects e a lista de formulários
                      SizedBox(height: isDesktop ? 30.0 : 20.0),

                      // Lista de Formulários
                      Expanded(
                        child: selectedEmpresaId == null
                            ? Center(
                          child: Text(
                            'Selecione uma empresa para ver os formulários.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isDesktop ? 18 : 16, // Aumento da fonte
                              color:
                              Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        )
                            : forms.isEmpty
                            ? Center(
                          child: Text(
                            'Nenhum formulário encontrado.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isDesktop ? 18 : 16, // Aumento da fonte
                              color:
                              Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        )
                            : ListView.builder(
                          itemCount: forms.length,
                          itemBuilder: (context, index) {
                            final form = forms[index];
                            return Card(
                              color: Theme.of(context).colorScheme.secondary,
                              margin: EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: ListTile(
                                title: Text(
                                  form['form_name'] ?? 'Formulário sem nome',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isDesktop ? 18 : 16, // Aumento da fonte
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Campanha: ${form['campanha_nome']}',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w400,
                                    fontSize: isDesktop ? 15 : 14, // Aumento da fonte
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
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
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditFormPage(
                                              empresaId: selectedEmpresaId!,
                                              campanhaId: form['campanha_id'],
                                              formId: form['id'],
                                            ),
                                          ),
                                        ).then((value) {
                                          if (value == true) {
                                            // Atualiza a lista se retornou true
                                            setState(() {});
                                          }
                                        });
                                      },
                                      tooltip: 'Editar Formulário',
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () {
                                        _showDeleteConfirmationDialog(
                                          selectedEmpresaId!,
                                          form['campanha_id'],
                                          form['id'],
                                        );
                                      },
                                      tooltip: 'Excluir Formulário',
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
              )
                  : Container(
                // Layout para dispositivos não-desktop (mobile/tablet)
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Dropdown de Empresas
                    Padding(
                      padding:
                      EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                      child: DropdownButtonFormField<String>(
                        isExpanded:
                        true, // Permite que o dropdown ocupe toda a largura disponível
                        alignment:
                        Alignment.center, // Alinha o conteúdo centralmente
                        value: selectedEmpresaId,
                        onChanged: (val) async {
                          if (val != null) {
                            setState(() {
                              selectedEmpresaId = val;
                              selectedEmpresaName = empresas
                                  .firstWhere((empresa) => empresa['id'] == val)['NomeEmpresa'];
                              selectedCampaignId = null;
                              selectedCampaignName = null;
                              campanhas.clear();
                              forms.clear();
                            });
                            _loadCampanhasListener(val);
                          }
                        },
                        items: empresas.map((empresa) {
                          return DropdownMenuItem<String>(
                            value: empresa['id'],
                            child: Center(
                              child: Text(
                                empresa['NomeEmpresa'],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          contentPadding:
                          EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          hintText: 'Selecione a empresa...',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        dropdownColor:
                        Theme.of(context).colorScheme.background,
                        selectedItemBuilder: (BuildContext context) {
                          return empresas.map((empresa) {
                            return Center(
                              child: Text(
                                empresa['NomeEmpresa'],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            );
                          }).toList();
                        },
                        hint: Center(
                          child: Text(
                            'Selecione a empresa...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color:
                              Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ),
                        icon: SizedBox
                            .shrink(), // Remove o ícone de seta
                        iconSize:
                        0, // Garante que nenhum espaço seja reservado para o ícone
                      ),
                    ),

                    // Filtro de Campanhas
                    if (selectedEmpresaId != null && campanhas.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          height: 50,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            alignment: Alignment.center,
                            value: selectedCampaignId ?? 'Todas',
                            onChanged: (val) {
                              if (val == 'Todas') {
                                setState(() {
                                  selectedCampaignId = null;
                                  selectedCampaignName = null;
                                  forms.clear();
                                });
                                _setupAllFormsListeners();
                              } else {
                                final campanha = campanhas.firstWhere((campanha) => campanha['id'] == val);
                                setState(() {
                                  selectedCampaignId = campanha['id'];
                                  selectedCampaignName = campanha['nome_campanha'];
                                  forms.clear();
                                });
                                _setupSingleFormListener(campanha['id']);
                              }
                            },
                            items: [
                              // Opção "Todas as Campanhas"
                              DropdownMenuItem<String>(
                                value: 'Todas',
                                child: Center(
                                  child: Text(
                                    'Todas as Campanhas',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              // Itens das campanhas
                              ...campanhas.map((campanha) {
                                return DropdownMenuItem<String>(
                                  value: campanha['id'] as String,
                                  child: Center(
                                    child: Text(
                                      campanha['nome_campanha'],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 10.0, horizontal: 0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              hintText: 'Selecione a campanha',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color:
                                Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            dropdownColor:
                            Theme.of(context).colorScheme.background,
                            selectedItemBuilder: (BuildContext context) {
                              return [
                                // Opção "Todas as Campanhas"
                                Center(
                                  child: Text(
                                    'Todas as Campanhas',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                  ),
                                ),
                                // Itens das campanhas
                                ...campanhas.map((campanha) {
                                  return Center(
                                    child: Text(
                                      campanha['nome_campanha'],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ];
                            },
                            hint: Center(
                              child: Text(
                                'Selecione a campanha',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ),
                            icon: SizedBox.shrink(),
                            iconSize: 0,
                          ),
                        ),
                      ),

                    // Espaçamento adicional entre os selects e a lista de formulários
                    SizedBox(height: 20.0),

                    // Lista de Formulários
                    Expanded(
                      child: selectedEmpresaId == null
                          ? Center(
                        child: Text(
                          'Selecione uma empresa para ver os formulários.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      )
                          : forms.isEmpty
                          ? Center(
                        child: Text(
                          'Nenhum formulário encontrado.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      )
                          : ListView.builder(
                        itemCount: forms.length,
                        itemBuilder: (context, index) {
                          final form = forms[index];
                          return Card(
                            color: Theme.of(context).colorScheme.secondary,
                            margin: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: ListTile(
                              title: Text(
                                form['form_name'] ?? 'Formulário sem nome',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isDesktop ? 17 : 16, // Aumento da fonte
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                              ),
                              subtitle: Text(
                                'Campanha: ${form['campanha_nome']}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w400,
                                  fontSize: isDesktop ? 15 : 14, // Aumento da fonte
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
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
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditFormPage(
                                            empresaId: selectedEmpresaId!,
                                            campanhaId: form['campanha_id'],
                                            formId: form['id'],
                                          ),
                                        ),
                                      ).then((value) {
                                        if (value == true) {
                                          // Atualiza a lista se retornou true
                                          setState(() {});
                                        }
                                      });
                                    },
                                    tooltip: 'Editar Formulário',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      _showDeleteConfirmationDialog(
                                        selectedEmpresaId!,
                                        form['campanha_id'],
                                        form['id'],
                                      );
                                    },
                                    tooltip: 'Excluir Formulário',
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
        ),
      );
    }
  }
}
