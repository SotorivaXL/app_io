import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class DashboardConfigurations extends StatefulWidget {
  const DashboardConfigurations({super.key});

  @override
  State<DashboardConfigurations> createState() => _DashboardConfigurationsState();
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

  final List<Map<String, String>> _metricsOptions = [
    {'id': 'visualizacoes_pagina', 'name': 'Visualizações da Página'},
    {'id': 'registros_consluidos', 'name': 'Registros na Concluídos'},
    {'id': 'visitas_perfil', 'name': 'Visitas ao perfil'},
    {'id': 'seguidores', 'name': 'Seguidores'},
    {'id': 'conversas_iniciadas', 'name': 'Conversas Iniciadas'},
    {'id': 'custo_resultado', 'name': 'Custo por Resultado'},
  ];

  List<String> _selectedMetrics = [];
  String? _selectedCampaign;
  List<Map<String, dynamic>> _campaignsList = [];

  DateTime? _selectedDate;
  final TextEditingController _dateController = TextEditingController();

  Map<String, TextEditingController> _metricsControllers = {};

  Future<List<Map<String, dynamic>>> _fetchBMs() async {
    final dashboardCollection = FirebaseFirestore.instance.collection('dashboard');
    final snapshot = await dashboardCollection.get();
    return snapshot.docs.map((doc) => {'id': doc.id, 'name': doc['name']}).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchContasAnuncioPorBM(String bmId) async {
    final dashboardDoc = FirebaseFirestore.instance.collection('dashboard').doc(bmId);
    final contasSnapshot = await dashboardDoc.collection('contasAnuncio').get();
    return contasSnapshot.docs.map((subDoc) => {'id': subDoc.id, 'name': subDoc['name']}).toList();
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
      if (contaSelecionada != null && !contasAnuncioList.any((c) => c['id'] == contaSelecionada)) {
        contaSelecionada = null;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchEmpresas() async {
    final empresasCollection = FirebaseFirestore.instance.collection('empresas');
    final snapshot = await empresasCollection.get();
    return snapshot.docs.map((doc) => {'id': doc.id, 'NomeEmpresa': doc['NomeEmpresa']}).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchCampaigns(String bmId, String contaId) async {
    final contaDoc = FirebaseFirestore.instance
        .collection('dashboard')
        .doc(bmId)
        .collection('contasAnuncio')
        .doc(contaId);

    final campaignsSnap = await contaDoc.collection('campanhas').get();
    return campaignsSnap.docs.map((doc) {
      final data = doc.data();
      return {
        'id': data['id'],
        'name': data['name'],
        'docId': doc.id,
      };
    }).toList();
  }

  Future<void> _loadCampaignsIfNeeded() async {
    if (contaSelecionada != null && bmSelecionada != null) {
      final campaigns = await _fetchCampaigns(bmSelecionada!, contaSelecionada!);
      setState(() {
        _campaignsList = campaigns;
        if (campaigns.isEmpty) {
          _selectedCampaign = null;
        }
      });
    }
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

    if (bmSelecionada == null || contaSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Por favor, selecione BM e conta de anúncio."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (_selectedMetrics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Por favor, selecione ao menos uma métrica."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    bool needsCampaign = _selectedMetrics.contains('visitas_perfil') ||
        _selectedMetrics.contains('seguidores') ||
        _selectedMetrics.contains('conversas_iniciadas');

    if (needsCampaign && _selectedCampaign == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Por favor, selecione uma campanha para as métricas escolhidas."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Por favor, selecione uma data."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    for (var metric in _selectedMetrics) {
      if (_metricsControllers[metric]?.text.trim().isEmpty ?? true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Por favor, preencha o valor para ${_getMetricName(metric)}."),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
    }

    final dataToSave = {
      'BMs': bmSelecionada != null ? [bmSelecionada] : [],
      'contasAnuncio': contaSelecionada != null ? [contaSelecionada] : [],
    };

    try {
      await FirebaseFirestore.instance.collection('empresas').doc(empresaSelecionada).set(dataToSave, SetOptions(merge: true));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Falha ao salvar configurações da empresa: $e"),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    String dataFormatada = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    List<String> campaignMetrics = [];

    for (var m in _selectedMetrics) {
      campaignMetrics.add(m);
    }

    if (campaignMetrics.isNotEmpty && _selectedCampaign != null) {
      final selectedCampaignDoc = _campaignsList.firstWhere((c) => c['id'] == _selectedCampaign, orElse: () => {});
      if (selectedCampaignDoc.isNotEmpty) {
        final campaignDocId = selectedCampaignDoc['docId'];

        final insightsCampanhaRef = FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmSelecionada)
            .collection('contasAnuncio')
            .doc(contaSelecionada)
            .collection('campanhas')
            .doc(campaignDocId)
            .collection('insights_campanhas')
            .doc(dataFormatada);

        Map<String, dynamic> campaignData = {};
        for (var cm in campaignMetrics) {
          campaignData[cm] = _metricsControllers[cm]?.text.trim();
        }

        campaignData['data'] = dataFormatada;

        await insightsCampanhaRef.set(campaignData, SetOptions(merge: true));
      }
    }

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
  }

  String _getMetricName(String metricId) {
    return _metricsOptions.firstWhere((element) => element['id'] == metricId, orElse: () => {'name': metricId})['name']!;
  }

  Future<void> _loadAnunciosParaEmpresa(String empresaId) async {
    final empresaDoc = await FirebaseFirestore.instance.collection('empresas').doc(empresaId).get();

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
        DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
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
                        Navigator.of(context).pop();
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
    _dateController.dispose();
    for (var controller in _metricsControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: Locale('pt', 'BR'),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            // 1. Remover a linha de separação
            dividerColor: Colors.transparent,
            dividerTheme: DividerThemeData(
              color: Colors.transparent,
              thickness: 0,
            ),

            // 2. Definir as cores específicas no ColorScheme
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,        // Mantém a cor primária existente
              secondary: Theme.of(context).colorScheme.secondary,    // Mantém a cor secundária existente
              onPrimary: Theme.of(context).colorScheme.onSecondary, // Define o texto selecionado como onSecondary
              surface: Theme.of(context).colorScheme.background,     // Mantém a cor de superfície existente
              onSurface: Theme.of(context).colorScheme.onBackground, // Mantém a cor do texto de superfície existente
            ),

            // 3. Definir o fundo do diálogo
            dialogBackgroundColor: Theme.of(context).colorScheme.secondary,

            // 4. Ajustar o TextTheme para garantir que o texto principal use onSecondary
            textTheme: Theme.of(context).textTheme.copyWith(
              headlineLarge: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSecondary, // Texto principal (data selecionada) como onSecondary
              ),
              bodyLarge: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSecondary, // Texto dos dias do calendário como onSecondary
              ),
              labelLarge: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSecondary, // Outros textos, se necessário
              ),
            ),

            // 5. Garantir que os ícones também usem onSecondary
            iconTheme: Theme.of(context).iconTheme.copyWith(
              color: Theme.of(context).colorScheme.onSecondary, // Ícones como onSecondary
            ),

            // 6. Definir a cor dos botões "OK" e "Cancelar" para onSecondary
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSecondary, // Cor do texto dos botões
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (mounted) { // Verificação para garantir que o widget ainda está montado
        setState(() {
          _selectedDate = picked;
          _dateController.text = DateFormat('dd/MM/yyyy').format(picked);
        });
      }
    }
  }

  void _onMetricsDropdownChanged(String? value) {
    if (value != null && !_selectedMetrics.contains(value)) {
      setState(() {
        _selectedMetrics.add(value);
        _metricsControllers[value] = TextEditingController();
      });
    }
    Future.microtask(() {
      setState(() {});
    });
  }

  bool get needsCampaign => _selectedMetrics.contains('visitas_perfil') ||
      _selectedMetrics.contains('seguidores') ||
      _selectedMetrics.contains('conversas_iniciadas');

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    bool showDateAndInputs = _selectedMetrics.isNotEmpty;

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
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
                        Flexible(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            menuMaxHeight: 200,
                            value: empresaSelecionada,
                            items: snapshot.data!.map((empresa) {
                              return DropdownMenuItem<String>(
                                value: empresa['id'],
                                child: Text(
                                  empresa['NomeEmpresa'],
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
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
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
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
                        Flexible(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            menuMaxHeight: 200,
                            value: bmSelecionada,
                            items: snapshot.data!.map((bm) {
                              return DropdownMenuItem<String>(
                                value: bm['id'],
                                child: Text(
                                  bm['name'],
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
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
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
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
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Flexible(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        menuMaxHeight: 200,
                        value: contaSelecionada,
                        items: contasAnuncioList.map((conta) {
                          return DropdownMenuItem<String>(
                            value: conta['id'],
                            child: Text(
                              conta['name'],
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          if (value != null) {
                            setState(() {
                              contaSelecionada = value;
                              _selectedMetrics.clear();
                              _metricsControllers.forEach((key, c) => c.dispose());
                              _metricsControllers.clear();
                              _selectedCampaign = null;
                              _campaignsList.clear();
                              _selectedDate = null;
                              _dateController.clear();
                            });
                            await _loadCampaignsIfNeeded();
                          }
                        },
                        hint: Text(
                          'Selecione a conta de anúncio',
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                if (contaSelecionada != null) ...[
                  Text(
                    "Selecione as métricas:",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          menuMaxHeight: 200,
                          value: null,
                          items: _metricsOptions.map((metric) {
                            return DropdownMenuItem<String>(
                              value: metric['id'],
                              child: Text(
                                metric['name']!,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
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
                              _onMetricsDropdownChanged(value);
                              _loadCampaignsIfNeeded();
                            }
                          },
                          hint: Text(
                            'Selecione as métricas',
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: _selectedMetrics.map((m) {
                      return Chip(
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        label: Text(
                          _getMetricName(m),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        side: BorderSide(color: Colors.transparent),
                        onDeleted: () {
                          setState(() {
                            _selectedMetrics.remove(m);
                            _metricsControllers[m]?.dispose();
                            _metricsControllers.remove(m);
                          });
                          _loadCampaignsIfNeeded();
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16.0),
                if (_campaignsList.isNotEmpty) ...[
                  Text(
                    "Selecione a campanha:",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          menuMaxHeight: 200,
                          value: _selectedCampaign,
                          items: _campaignsList.map((camp) {
                            return DropdownMenuItem<String>(
                              value: camp['id'],
                              child: Text(
                                camp['name'],
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
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
                              _selectedCampaign = value;
                            });
                          },
                          hint: Text(
                            'Selecione a campanha',
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                ],
                if (showDateAndInputs) ...[
                  Text(
                    "Selecione a data:",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: UnderlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Selecione uma data',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      suffixIcon: Icon(
                          Icons.date_range,
                          color: Theme.of(context).colorScheme.onBackground
                      ),
                    ),
                    onTap: _pickDate, // Ao clicar no campo todo, abre o date picker
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    "Preencha os valores para cada métrica selecionada:",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _selectedMetrics.map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: TextFormField(
                          controller: _metricsControllers[m],
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          textAlignVertical: TextAlignVertical.center,
                          textAlign: TextAlign.left,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.done, // Define a ação do botão como "Done"
                          inputFormatters: [
                            // Permite apenas dígitos (0-9), vírgula (,) e ponto (.)
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          onEditingComplete: () {
                            FocusScope.of(context).unfocus(); // Fecha o teclado quando "Done" é pressionado
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                            border: UnderlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            hintText: 'Valor para ${_getMetricName(m)}',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}