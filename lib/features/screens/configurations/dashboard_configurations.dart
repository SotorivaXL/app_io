import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart'; // Reintroduza este import
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

  String? bmSelecionada;
  String? contaSelecionada;

  String? empresaSelecionada;
  List<Map<String, dynamic>> contasAnuncioList = [];

  double _scrollOffset = 0.0;
  bool _isLoading = false;

  Future<List<Map<String, dynamic>>> _fetchBMs() async {
    final dashboardCollection = FirebaseFirestore.instance.collection('dashboard');
    final snapshot = await dashboardCollection.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, 'name': doc['name']})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchContasAnuncioPorBM(String bmId) async {
    final dashboardDoc = FirebaseFirestore.instance.collection('dashboard').doc(bmId);
    final contasSnapshot = await dashboardDoc.collection('contasAnuncio').get();
    return contasSnapshot.docs
        .map((subDoc) => {'id': subDoc.id, 'name': subDoc['name']})
        .toList();
  }

  Future<void> _updateContasAnuncioList() async {
    if (bmSelecionada == null) {
      setState(() {
        contasAnuncioList = [];
        contaSelecionada = null;
      });
      return;
    }

    final newContasAnuncioList = await _fetchContasAnuncioPorBM(bmSelecionada!);

    setState(() {
      contasAnuncioList = newContasAnuncioList;
      if (contaSelecionada != null &&
          !contasAnuncioList.any((c) => c['id'] == contaSelecionada)) {
        contaSelecionada = null;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchEmpresas() async {
    final empresasCollection = FirebaseFirestore.instance.collection('empresas');
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

    final dataToSave = {
      'BMs': bmSelecionada != null ? [bmSelecionada] : [],
      'contasAnuncio': contaSelecionada != null ? [contaSelecionada] : [],
    };

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

  Future<void> _loadAnunciosParaEmpresa(String empresaId) async {
    final empresaDoc = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .get();

    if (empresaDoc.exists) {
      final data = empresaDoc.data()!;
      final bmIds = List<String>.from(data['BMs'] ?? []);
      final contaIds = List<String>.from(data['contasAnuncio'] ?? []);

      bmSelecionada = bmIds.isNotEmpty ? bmIds.first : null;
      await _updateContasAnuncioList();
      contaSelecionada = contaIds.isNotEmpty ? contaIds.first : null;
    } else {
      setState(() {
        bmSelecionada = null;
        contaSelecionada = null;
        contasAnuncioList = [];
      });
    }

    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
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
                        'Dashboard Config.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                  Stack(
                    children: [
                      _isLoading
                          ? CircularProgressIndicator()
                          : IconButton(
                        icon: Icon(Icons.save_as_sharp,
                            color:
                            Theme.of(context).colorScheme.onBackground,
                            size: 30),
                        onPressed: _isLoading ? null : _saveAnuncios,
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
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchEmpresas(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<String>(
                            value: empresaSelecionada,
                            items: snapshot.data!.map((empresa) {
                              return DropdownMenuItem<String>(
                                value: empresa['id'],
                                child: Text(
                                  empresa['NomeEmpresa'],
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
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
                            hint: Text(
                              'Selecionar Empresa',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              border: UnderlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            // Ajuste via IconStyleData
                            iconStyleData: IconStyleData(
                              icon: Icon(Icons.arrow_drop_down),
                              iconSize: 24,
                              iconEnabledColor: Theme.of(context).colorScheme.onBackground,
                            ),
                            // Ajuste via DropdownStyleData
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 200, // Altura máxima do menu
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
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
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<String>(
                            value: bmSelecionada,
                            items: snapshot.data!.map((bm) {
                              return DropdownMenuItem<String>(
                                value: bm['id'],
                                child: Text(
                                  bm['name'],
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  bmSelecionada = value;
                                  _updateContasAnuncioList();
                                });
                              }
                            },
                            hint: Text(
                              'Selecione a BM',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              border: UnderlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            iconStyleData: IconStyleData(
                              icon: Icon(Icons.arrow_drop_down),
                              iconSize: 24,
                              iconEnabledColor: Theme.of(context).colorScheme.onBackground,
                            ),
                            // Ajuste via DropdownStyleData
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 200, // Altura máxima do menu
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),

                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField2<String>(
                        value: contaSelecionada,
                        items: contasAnuncioList.map((conta) {
                          return DropdownMenuItem<String>(
                            value: conta['id'],
                            child: Text(
                              conta['name'],
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              contaSelecionada = value;
                            });
                          }
                        },
                        hint: Text(
                          'Selecione a conta de anúncio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          border: UnderlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        iconStyleData: IconStyleData(
                          icon: Icon(Icons.arrow_drop_down),
                          iconSize: 24,
                          iconEnabledColor: Theme.of(context).colorScheme.onBackground,
                        ),
                        // Ajuste via DropdownStyleData
                        dropdownStyleData: DropdownStyleData(
                          maxHeight: 200, // Altura máxima do menu
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}