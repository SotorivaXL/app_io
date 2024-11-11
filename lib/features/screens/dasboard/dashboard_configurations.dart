import 'dart:async';

import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:provider/provider.dart';

class DashboardConfigurations extends StatefulWidget {
  const DashboardConfigurations({super.key});

  @override
  State<DashboardConfigurations> createState() =>
      _DashboardConfigurationsState();
}

class _DashboardConfigurationsState extends State<DashboardConfigurations> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  bool hasConfigurarDashAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;
  final FirestoreService _firestoreService = FirestoreService();

  final Map<String, dynamic> anuncios = {
    'BMs': [],
    'contasAnuncio': [],
  };

  String? empresaSelecionada;
  List<Map<String, dynamic>> contasAnuncioList = [];

  Future<List<Map<String, dynamic>>> _fetchBMs() async {
    final dashboardCollection =
    FirebaseFirestore.instance.collection('dashboard');
    final snapshot = await dashboardCollection.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, 'name': doc['name']})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchContasAnuncioPorBM(
      String bmId) async {
    final dashboardDoc =
    FirebaseFirestore.instance.collection('dashboard').doc(bmId);
    final contasSnapshot =
    await dashboardDoc.collection('contasAnuncio').get();
    return contasSnapshot.docs
        .map((subDoc) => {'id': subDoc.id, 'name': subDoc['name']})
        .toList();
  }

  Future<void> _updateContasAnuncioList() async {
    List<Map<String, dynamic>> newContasAnuncioList = [];

    // Coletar futures para buscar as contas de anúncio de todas as BMs selecionadas
    List<Future<List<Map<String, dynamic>>>> futures = [];

    for (var bm in anuncios['BMs']) {
      String bmId = bm['id'];
      futures.add(_fetchContasAnuncioPorBM(bmId));
    }

    // Aguardar todas as buscas terminarem
    List<List<Map<String, dynamic>>> results = await Future.wait(futures);

    // Combinar todas as contas de anúncio
    for (var contas in results) {
      newContasAnuncioList.addAll(contas);
    }

    // Remover duplicatas
    final ids = <String>{};
    newContasAnuncioList =
        newContasAnuncioList.where((conta) => ids.add(conta['id'])).toList();

    if (mounted) {
      setState(() {
        contasAnuncioList = newContasAnuncioList;
        // Atualizar 'anuncios['contasAnuncio']' para remover contas que não estão mais disponíveis
        final availableIds =
        newContasAnuncioList.map((conta) => conta['id']).toSet();
        anuncios['contasAnuncio'] = anuncios['contasAnuncio']
            .where((conta) => availableIds.contains(conta['id']))
            .toList();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchEmpresas() async {
    final empresasCollection =
    FirebaseFirestore.instance.collection('empresas');
    final snapshot = await empresasCollection.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, 'NomeEmpresa': doc['NomeEmpresa']})
        .toList();
  }

  Future<void> _saveAnuncios() async {
    if (empresaSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Por favor, selecione uma empresa.",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ),
      );
      return;
    }

    // Preparar dados para salvar
    final dataToSave = {
      'BMs': anuncios['BMs'].map((bm) => bm['id']).toList(),
      'contasAnuncio':
      anuncios['contasAnuncio'].map((conta) => conta['id']).toList(),
    };

    // Salvar no Firestore no documento do usuário selecionado
    try {
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaSelecionada)
          .set(dataToSave, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Configurações salvas com sucesso!",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Falha ao salvar configurações: $e"),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Função adicionada para carregar as configurações salvas
  Future<void> _loadAnunciosParaEmpresa(String empresaId) async {
    final empresaDoc = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .get();

    if (empresaDoc.exists) {
      final data = empresaDoc.data()!;
      final bmIds = List<String>.from(data['BMs'] ?? []);
      final contaIds = List<String>.from(data['contasAnuncio'] ?? []);

      // Fetch all BMs
      final allBMs = await _fetchBMs();
      final bmMap = {for (var bm in allBMs) bm['id']: bm['name']};

      // Atualizar anuncios['BMs']
      setState(() {
        anuncios['BMs'] = bmIds
            .map((id) => {'id': id, 'name': bmMap[id] ?? 'BM desconhecida'})
            .toList();
      });

      // Atualizar contasAnuncioList com base nas BMs selecionadas
      await _updateContasAnuncioList();

      // Criar um mapa de contasAnuncio disponíveis
      final contaMap = {for (var conta in contasAnuncioList) conta['id']: conta['name']};

      // Atualizar anuncios['contasAnuncio']
      setState(() {
        anuncios['contasAnuncio'] = contaIds
            .map((id) => {'id': id, 'name': contaMap[id] ?? 'Conta desconhecida'})
            .toList();
      });
    } else {
      // Se não houver configurações salvas para a empresa
      setState(() {
        anuncios['BMs'] = [];
        anuncios['contasAnuncio'] = [];
        contasAnuncioList = [];
      });
    }
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

    final authProvider = Provider.of<appProvider.AuthProvider>(context, listen: false);
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
    final userData = userDoc.data();

    if (!mounted) return;

    setState(() {
      hasConfigurarDashAccess = userData?['configurarDash'] ?? false;
      isLoading = false;
    });

    if (!hasConfigurarDashAccess) {
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
      _hasShownPermissionRevokedDialog = false; // Reseta a flag se a permissão voltar
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defina a largura desejada para os menus suspensos
    const double dropdownWidth = 200.0;

    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Dashboard Config.',
            style: TextStyle(
              fontFamily: 'Branding SF',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: Theme.of(context).colorScheme.outline,
              size: 24,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize
                  .min, // Definindo Column para ocupar apenas o espaço necessário
              children: [
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchEmpresas(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const CircularProgressIndicator();
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<String>(
                            items: snapshot.data!.map((empresa) {
                              return DropdownMenuItem<String>(
                                value: empresa['id'] as String,
                                child: Text(empresa['NomeEmpresa']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                empresaSelecionada = value;
                                if (empresaSelecionada != null) {
                                  _loadAnunciosParaEmpresa(empresaSelecionada!);
                                }
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Selecionar Empresa',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color:
                                Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              errorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              focusedErrorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                            ),
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 200.0,
                              width: dropdownWidth,
                              decoration: BoxDecoration(
                                color:
                                Theme.of(context).colorScheme.background,
                              ),
                            ),
                            menuItemStyleData: const MenuItemStyleData(
                              padding:
                              EdgeInsets.symmetric(horizontal: 16.0),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16.0),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchBMs(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const CircularProgressIndicator();
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<String>(
                            items: snapshot.data!.map((bm) {
                              return DropdownMenuItem<String>(
                                value: bm['id'] as String,
                                child: Text(
                                  bm['name'],
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  // Verifica se a BM já está selecionada
                                  if (!anuncios['BMs']
                                      .any((bm) => bm['id'] == value)) {
                                    anuncios['BMs'].add({
                                      'id': value,
                                      'name': snapshot.data!
                                          .firstWhere(
                                              (bm) => bm['id'] == value)['name'],
                                    });
                                    // Atualiza a lista de contas de anúncio
                                    _updateContasAnuncioList();
                                  }
                                });
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Selecione as BMs',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color:
                                Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              errorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                              focusedErrorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7.0),
                              ),
                            ),
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 200.0,
                              width: dropdownWidth,
                              decoration: BoxDecoration(
                                color:
                                Theme.of(context).colorScheme.background,
                              ),
                            ),
                            menuItemStyleData: const MenuItemStyleData(
                              padding:
                              EdgeInsets.symmetric(horizontal: 16.0),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Wrap(
                  spacing: 8.0, // Espaçamento horizontal entre os chips
                  runSpacing: 4.0, // Espaçamento vertical entre as linhas
                  children: anuncios['BMs']
                      .map<Widget>((bm) => Chip(
                    backgroundColor:
                    Theme.of(context).colorScheme.tertiary,
                    side: BorderSide.none,
                    label: Text(bm['name']),
                    onDeleted: () {
                      setState(() {
                        anuncios['BMs'].remove(bm);
                        // Atualiza a lista de contas de anúncio
                        _updateContasAnuncioList();
                      });
                    },
                  ))
                      .toList(),
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField2<String>(
                        items: contasAnuncioList.map((conta) {
                          return DropdownMenuItem<String>(
                            value: conta['id'] as String,
                            child: Text(
                              conta['name'],
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color:
                                Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              // Verifica se a conta já está selecionada
                              if (!anuncios['contasAnuncio']
                                  .any((conta) => conta['id'] == value)) {
                                anuncios['contasAnuncio'].add({
                                  'id': value,
                                  'name': contasAnuncioList
                                      .firstWhere((conta) =>
                                  conta['id'] == value)['name'],
                                });
                              }
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Selecione as contas de anúncio',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2),
                            borderRadius: BorderRadius.circular(7.0),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.tertiary,
                                width: 2),
                            borderRadius: BorderRadius.circular(7.0),
                          ),
                          errorBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                                width: 2),
                            borderRadius: BorderRadius.circular(7.0),
                          ),
                          focusedErrorBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                                width: 2),
                            borderRadius: BorderRadius.circular(7.0),
                          ),
                        ),
                        isExpanded: true,
                        dropdownStyleData: DropdownStyleData(
                          maxHeight: 200.0,
                          width: dropdownWidth,
                          decoration: BoxDecoration(
                            color:
                            Theme.of(context).colorScheme.background,
                          ),
                        ),
                        menuItemStyleData: const MenuItemStyleData(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8.0, // Espaçamento horizontal entre os chips
                  runSpacing: 4.0, // Espaçamento vertical entre as linhas
                  children: anuncios['contasAnuncio']
                      .map<Widget>((conta) => Chip(
                    backgroundColor:
                    Theme.of(context).colorScheme.tertiary,
                    side: BorderSide.none,
                    label: Text(conta['name']),
                    onDeleted: () {
                      setState(() {
                        anuncios['contasAnuncio'].remove(conta);
                      });
                    },
                  ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _saveAnuncios,
                  label: Text(
                    'Salvar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  icon: Icon(
                    Icons.save_alt,
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  style: ElevatedButton.styleFrom(
                    padding:
                    EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
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