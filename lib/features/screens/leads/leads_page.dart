import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/LeadCard/lead_card.dart';
import 'package:app_io/util/utils.dart';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class LeadsPage extends StatefulWidget {
  @override
  _LeadsPageState createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  String? userName;
  bool hasLeadsAccess = false;
  bool hasDashboardAccess = false;
  String? selectedCampaignId;
  String? selectedCampaignName;
  String? selectedStatus;
  bool isScrollingDown = false;
  List<Map<String, dynamic>> allLeads = [];
  String? empresaId;
  bool isLoading = true;
  int totalLeads = 0; // Inicialmente zero
  bool areLeadsLoaded = false;
  List<Map<String, dynamic>> leadsData = [];
  String _searchQuery = ''; // Variável de pesquisa

  final ScrollController _scrollController = ScrollController();

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getUserData().then((_) {
      if (empresaId != null) {
        _loadLeads(empresaId!);
      }
    });
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteLead(BuildContext context, String empresaId,
      String campaignId, String leadId, Map<String, dynamic> leadData) async {
    print('Iniciando deleção do lead: $leadId');

    try {
      print('Confirmado deletar lead: $leadId');
      // Deletar o lead do Firestore
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .collection('leads')
          .doc(leadId)
          .delete();

      print('Lead deletado com sucesso: $leadId');

      // Atualizar o total de leads, se necessário
      await _updateTotalLeads();
    } catch (e) {
      print('Erro ao deletar o lead: $e');
    }
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      if (!isScrollingDown) {
        setState(() {
          isScrollingDown = true;
        });
      }
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      if (isScrollingDown) {
        setState(() {
          isScrollingDown = false;
        });
      }
    }
  }

  void _filterLeads() {
    setState(() {
      if (_searchQuery.isEmpty) {
        // Quando não há pesquisa, reseta os dados e o total
        leadsData = List<Map<String, dynamic>>.from(allLeads);
      } else {
        // Filtra os leads com base na pesquisa
        leadsData = allLeads
            .where((lead) => (lead['nome']?.toLowerCase() ?? '').contains(_searchQuery))
            .toList();
      }
      totalLeads = leadsData.length; // Atualiza o total com base em leadsData
    });
  }

  Widget _buildSearchIcon() {
    return _searchQuery.isNotEmpty
        ? IconButton(
      icon: Icon(Icons.close),
      onPressed: () {
        setState(() {
          _searchQuery = '';
          leadsData = List<Map<String, dynamic>>.from(allLeads); // Reset leadsData
        });
      },
    )
        : Icon(Icons.search);
  }

  Future<void> _loadLeads(String empresaId) async {
    final allLeads = await _getAllLeadsStream(empresaId).first;
    setState(() {
      this.allLeads = allLeads; // Salva todos os leads
      leadsData = List<Map<String, dynamic>>.from(allLeads); // Exibe todos os leads inicialmente
      totalLeads = leadsData.length; // Inicializa o total de leads
      areLeadsLoaded = true;
    });
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        String? foundEmpresaId;

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          foundEmpresaId = userDoc['createdBy'];
        }

        if (foundEmpresaId == null) {
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            foundEmpresaId = user.uid;
          }
        }

        if (foundEmpresaId != null) {
          setState(() {
            empresaId = foundEmpresaId;
          });
        } else {
          showErrorDialog(context, 'Documento não encontrado.', 'Atenção');
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      } finally {
        // Aguarde pelo menos 1 segundo antes de remover o carregamento
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) { // Verifica se o widget ainda está montado
            setState(() {
              isLoading = false;
            });
          }
        });
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
      setState(() {
        isLoading = false;
      });
    }
  }

  Stream<List<Map<String, dynamic>>> _getAllLeadsStream(
      String empresaId) async* {
    final campaignsSnapshot = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('campanhas')
        .get();

    List<Stream<List<Map<String, dynamic>>>> leadStreams =
    campaignsSnapshot.docs.map((campaignDoc) {
      return campaignDoc.reference
          .collection('leads')
          .snapshots()
          .map((leadsSnapshot) {
        return leadsSnapshot.docs.map((leadDoc) {
          Map<String, dynamic> leadData = leadDoc.data();
          leadData['leadId'] = leadDoc.id;
          leadData['campaignId'] = campaignDoc.id;
          leadData['empresaId'] = empresaId;

          // Tratar campos nulos
          leadData['timestamp'] = leadData['timestamp'] ?? Timestamp.now();
          leadData['status'] = leadData['status'] ?? 'Aguardando';

          return leadData;
        }).toList();
      });
    }).toList();

    yield* StreamZip(leadStreams).map((listOfLeadLists) {
      final allLeads = listOfLeadLists.expand((leads) => leads).toList();
      allLeads.sort((a, b) {
        Timestamp timestampA = a['timestamp'];
        Timestamp timestampB = b['timestamp'];
        return timestampB.compareTo(timestampA);
      });
      return allLeads;
    });
  }

  void _showLeadDetails(BuildContext context, Map<String, dynamic> leadData,
      Function(String) onStatusChanged) {
    print('Exibindo detalhes do lead: ${leadData['leadId']}');

    // Cria uma cópia completa dos dados para restauração posterior
    final Map<String, dynamic> originalLeadData =
    Map<String, dynamic>.from(leadData);

    // Variáveis para exibição
    String? formattedDate;
    if (originalLeadData['timestamp'] != null &&
        originalLeadData['timestamp'] is Timestamp) {
      final timestamp = originalLeadData['timestamp'] as Timestamp;
      final dateTime = timestamp.toDate();
      formattedDate =
      'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
    }

    final String? nome = originalLeadData['nome'];
    final String? email = originalLeadData['email'];
    final String? whatsapp = originalLeadData['whatsapp'];
    String status = originalLeadData['status'] ?? 'Aguardando';

    final String? leadId = originalLeadData['leadId'];
    final String? empresaId = originalLeadData['empresaId'];
    final String? campaignId = originalLeadData['campaignId'];

    if (leadId == null || empresaId == null || campaignId == null) {
      showErrorDialog(
        context,
        'Dados incompletos para exibir os detalhes do lead.',
        'Erro',
      );
      return;
    }

    // Filtro das variáveis que não devem ser exibidas
    final Map<String, dynamic> filteredLeadData = {
      for (var entry in originalLeadData.entries)
        if (entry.key != 'redirect_url' &&
            entry.key != 'empresa_id' &&
            entry.key != 'nome' &&
            entry.key != 'email' &&
            entry.key != 'nome_campanha' &&
            entry.key != 'timestamp' &&
            entry.key != 'whatsapp' &&
            entry.key != 'leadId' &&
            entry.key != 'campaignId' &&
            entry.key != 'empresaId' &&
            entry.key != 'status')
          entry.key: entry.value
    };

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              backgroundColor: Theme.of(context).colorScheme.secondary,
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.all(16.0),
              title: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        top: 20.0, left: 20.0, right: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalhes do Lead',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Theme.of(context).colorScheme.onBackground,
                            overflow: TextOverflow.ellipsis,
                          ),
                          maxLines: 1,
                        ),
                        if (formattedDate != null)
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSecondary,
                              overflow: TextOverflow.ellipsis,
                            ),
                            maxLines: 1,
                          ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: () {
                            _showStatusSelectionDialog(
                              context,
                              leadId,
                              empresaId,
                              campaignId,
                                  (newStatus) {
                                FirebaseFirestore.instance
                                    .collection('empresas')
                                    .doc(empresaId)
                                    .collection('campanhas')
                                    .doc(campaignId)
                                    .collection('leads')
                                    .doc(leadId)
                                    .update({'status': newStatus}).then((_) {
                                  Navigator.of(context)
                                      .pop(); // Fecha o popup automaticamente
                                  onStatusChanged(
                                      newStatus); // Atualiza o card sem recarregar
                                }).catchError((e) {
                                  showErrorDialog(context,
                                      'Erro ao atualizar status: $e', 'Erro');
                                });
                              },
                            );
                          },
                          child: Chip(
                            label: Text(
                              status,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                overflow: TextOverflow.ellipsis,
                              ),
                              maxLines: 1,
                            ),
                            backgroundColor: _getStatusColor(status),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                              side: BorderSide(
                                color: _getStatusColor(status),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nome != null)
                        _buildDetailRow('Nome', nome, context, maxLines: 1),
                      if (email != null)
                        _buildDetailRow('E-mail', email, context, maxLines: 1),
                      if (whatsapp != null)
                        _buildDetailRow('WhatsApp', whatsapp, context,
                            maxLines: 1),
                      ...filteredLeadData.entries.map((entry) {
                        return _buildDetailRow(
                            entry.key, entry.value.toString(), context);
                      }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    print(
                        'Botão "Deletar Lead" pressionado para o lead: $leadId');
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: Text('Confirmar Deleção'),
                          content: Text(
                            'Tem certeza de que deseja deletar este lead?',
                            style:
                            TextStyle(fontFamily: 'Poppins', fontSize: 16),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                print(
                                    'Deleção cancelada para o lead: $leadId');
                                Navigator.pop(
                                    dialogContext); // Fecha o popup de confirmação
                              },
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                print(
                                    'Usuário confirmou deleção para o lead: $leadId');
                                Navigator.pop(
                                    dialogContext); // Fecha o popup de confirmação
                                Navigator.pop(
                                    context); // Fecha o popup de detalhes
                                _deleteLead(context, empresaId, campaignId,
                                    leadId, originalLeadData);
                              },
                              child: Text(
                                'Deletar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onError,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Text(
                    'Deletar Lead',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    print('Botão "Fechar" pressionado para o lead: $leadId');
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Fechar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, BuildContext context,
      {int maxLines = 2}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSecondary,
              overflow: TextOverflow.ellipsis,
            ),
            maxLines: 1,
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSecondary,
              overflow: TextOverflow.ellipsis,
            ),
            maxLines: maxLines,
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        body: isLoading
            ? CustomScrollView(
          slivers: [
            _buildShimmerEffect(),
          ],
        )
            : (empresaId == null
            ? Center(child: Text('Erro: Empresa não encontrada.'))
            : _buildCampanhasStream(empresaId!)),
      ),
    );
  }

  Future<void> _updateTotalLeads() async {
    try {
      int leadsCount = 0;

      // Referência à coleção de campanhas
      CollectionReference campanhasRef = FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas');

      QuerySnapshot campanhasSnapshot = await campanhasRef.get();

      for (var campanha in campanhasSnapshot.docs) {
        // Se uma campanha específica estiver selecionada, ignore as outras
        if (selectedCampaignId != null && campanha.id != selectedCampaignId) {
          continue;
        }

        CollectionReference leadsRef = campanha.reference.collection('leads');

        if (selectedStatus != null && selectedStatus != 'Sem Filtros') {
          if (selectedStatus == 'Aguardando') {
            // Contar leads com status 'Aguardando'
            QuerySnapshot leadsSnapshotAguardando =
            await leadsRef.where('status', isEqualTo: 'Aguardando').get();

            // Contar leads sem o campo 'status'
            QuerySnapshot leadsSnapshotSemStatus =
            await leadsRef.where('status', isEqualTo: null).get();

            leadsCount += leadsSnapshotAguardando.docs.length +
                leadsSnapshotSemStatus.docs.length;
          } else {
            // Contar leads com status igual ao selecionado
            QuerySnapshot leadsSnapshot =
            await leadsRef.where('status', isEqualTo: selectedStatus).get();

            leadsCount += leadsSnapshot.docs.length;
          }
        } else {
          // Sem filtro de status: contar todos os leads
          QuerySnapshot leadsSnapshot = await leadsRef.get();
          leadsCount += leadsSnapshot.docs.length;
        }
      }

      setState(() {
        totalLeads = leadsCount;
      });
    } catch (e) {
      print('Erro ao atualizar total de leads: $e');
      // Opcional: Exibir uma mensagem de erro para o usuário
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar total de leads: $e')),
      );
    }
  }

  Future<void> _loadCampaignLeads(String empresaId, String campaignId) async {
    final campaignLeads = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('campanhas')
        .doc(campaignId)
        .collection('leads')
        .orderBy('timestamp', descending: true)
        .get();

    setState(() {
      leadsData = campaignLeads.docs.map((doc) {
        Map<String, dynamic> leadData = doc.data();
        leadData['leadId'] = doc.id;
        leadData['campaignId'] = campaignId;
        leadData['empresaId'] = empresaId;
        return leadData;
      }).toList();
      areLeadsLoaded = true;
    });

    await _updateTotalLeads(); // Atualiza totalLeads com base nos filtros atuais
  }

  Widget _buildCampanhasStream(String empresaId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro ao carregar campanhas: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData ||
            snapshot.connectionState == ConnectionState.waiting) {
          return CustomScrollView(
            slivers: [
              _buildShimmerEffect(),
            ],
          );
        }

        final campanhas = snapshot.data?.docs ?? [];

        if (campanhas.isEmpty) {
          return Center(
            child: Text(
              'Nenhuma campanha disponível',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              expandedHeight: 130, // Aumentado para acomodar o campo de pesquisa
              backgroundColor: Theme.of(context).colorScheme.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: Theme.of(context).colorScheme.background,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Campo de pesquisa com texto ao lado direito
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController, // Usa o controlador para manter o texto
                              onChanged: (value) {
                                _searchQuery = value.toLowerCase(); // Atualiza a variável de pesquisa
                              },
                              onSubmitted: (value) {
                                setState(() {
                                  _filterLeads(); // Executa a pesquisa ao pressionar Enter
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Pesquisar leads',
                                hintStyle: TextStyle(
                                  color: Theme.of(context).colorScheme.onSecondary,
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.secondary,
                                contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                                border: UnderlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(_searchQuery.isNotEmpty ? Icons.close : Icons.search),
                                  color: Theme.of(context).colorScheme.onSecondary,
                                  onPressed: () {
                                    if (_searchQuery.isNotEmpty) {
                                      setState(() {
                                        _searchQuery = '';
                                        _searchController.clear(); // Limpa o texto da barra
                                        leadsData = List<Map<String, dynamic>>.from(allLeads); // Reseta os leads
                                        totalLeads = leadsData.length; // Atualiza o total de leads
                                      });
                                    } else {
                                      setState(() {
                                        _filterLeads(); // Executa a pesquisa ao clicar no botão de busca
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 30), // Espaço entre a SearchBar e o texto
                          Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Column(
                              children: [
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '$totalLeads', // Exibe o total atualizado dinamicamente
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Ícones de filtro e campanha
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              PopupMenuButton<String>(
                                color: Theme.of(context).colorScheme.secondary,
                                icon: Icon(Icons.campaign, size: 30),
                                offset: Offset(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                onSelected: (value) async {
                                  setState(() {
                                    isLoading = true; // Ativa o Shimmer
                                    selectedCampaignId =
                                    value == 'Todas' ? null : value;
                                    selectedCampaignName = value == 'Todas'
                                        ? 'Todas'
                                        : campanhas.firstWhere((campanha) =>
                                    campanha.id == value)['nome_campanha'];
                                    leadsData.clear(); // Limpa os leads visíveis
                                  });

                                  if (selectedCampaignId != null) {
                                    await _loadCampaignLeads(
                                        empresaId, selectedCampaignId!);
                                  } else {
                                    await _loadLeads(
                                        empresaId); // Carrega todos os leads
                                  }

                                  await _updateTotalLeads(); // Atualiza totalLeads com base nos filtros atuais

                                  setState(() {
                                    isLoading = false; // Desativa o Shimmer
                                  });
                                },
                                itemBuilder: (context) {
                                  return [
                                    PopupMenuItem<String>(
                                      value: 'Todas',
                                      child: Text(
                                        'Todas',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondary,
                                        ),
                                      ),
                                    ),
                                    ...campanhas.map((campanha) {
                                      return PopupMenuItem<String>(
                                        value: campanha.id,
                                        child: Text(
                                          campanha['nome_campanha'],
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ];
                                },
                              ),
                              SizedBox(width: 4),
                              Text(
                                (selectedCampaignName == null ||
                                    selectedCampaignName == 'Todas')
                                    ? ''
                                    : selectedCampaignName!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                (selectedStatus == null ||
                                    selectedStatus == 'Sem Filtros')
                                    ? ''
                                    : selectedStatus!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color:
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                softWrap: false,
                              ),
                              SizedBox(width: 4),
                              PopupMenuButton<String>(
                                color: Theme.of(context).colorScheme.secondary,
                                icon: Icon(Icons.filter_list, size: 30),
                                offset: Offset(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                onSelected: (value) async {
                                  setState(() {
                                    selectedStatus = value;
                                    isLoading = true; // Ativa o Shimmer
                                  });

                                  await _updateTotalLeads(); // Atualiza totalLeads com base nos filtros atuais

                                  setState(() {
                                    isLoading = false; // Desativa o Shimmer
                                  });
                                },
                                itemBuilder: (context) => [
                                  'Sem Filtros',
                                  'Aguardando',
                                  'Atendendo',
                                  'Venda',
                                  'Recusado'
                                ].map((status) {
                                  return PopupMenuItem<String>(
                                    value: status,
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            selectedCampaignId != null
                ? _buildLeadsStream(empresaId, selectedCampaignId!)
                : _buildAllLeadsView(empresaId),
          ],
        );
      },
    );
  }

  Widget _buildShimmerEffect() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          return Shimmer.fromColors(
            baseColor: Theme.of(context).colorScheme.onSecondaryContainer,
            highlightColor: Theme.of(context).colorScheme.onTertiaryContainer,
            child: Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
              child: Container(
                height: 100.0,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
          );
        },
        childCount: 6, // Número de placeholders
      ),
    );
  }

  Widget _buildLeadsStream(String empresaId, String campaignId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .collection('leads')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
              child:
              Center(child: Text('Erro ao carregar os leads: ${snapshot.error}')));
        }

        if (!snapshot.hasData ||
            snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerEffect(); // Exibe o Shimmer durante o carregamento
        }

        final leads = snapshot.data?.docs ?? [];

        if (leads.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Nenhum lead disponível',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        // Filtrar leads com base no status e na pesquisa
        final filteredLeads = leads.where((lead) {
          final data = lead.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'Aguardando';
          final nome = data['nome']?.toLowerCase() ?? '';

          return (selectedStatus == null ||
              selectedStatus == 'Sem Filtros' ||
              status == selectedStatus) &&
              nome.contains(_searchQuery);
        }).toList();

        if (filteredLeads.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Nenhum lead encontrado para a pesquisa atual',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final lead = filteredLeads[index];
              final leadData = Map<String, dynamic>.from(lead.data() as Map);
              leadData['leadId'] = lead.id;
              leadData['empresaId'] = empresaId;
              leadData['campaignId'] = campaignId;
              leadData['status'] =
                  leadData['status'] ?? 'Aguardando'; // Define status padrão

              return LeadCard(
                leadData: leadData,
                onTap: (data) => _showLeadDetails(
                  context,
                  data,
                      (newStatus) async {
                    setState(() {
                      leadData['status'] = newStatus;
                    });

                    // Atualizar o status no Firestore
                    await FirebaseFirestore.instance
                        .collection('empresas')
                        .doc(empresaId)
                        .collection('campanhas')
                        .doc(campaignId)
                        .collection('leads')
                        .doc(lead.id)
                        .update({'status': newStatus});

                    await _updateTotalLeads(); // Atualiza o total após a alteração
                  },
                ),
                onStatusChanged: (newStatus) async {
                  setState(() {
                    leadData['status'] = newStatus;
                  });

                  // Atualizar o status no Firestore
                  await FirebaseFirestore.instance
                      .collection('empresas')
                      .doc(empresaId)
                      .collection('campanhas')
                      .doc(campaignId)
                      .collection('leads')
                      .doc(lead.id)
                      .update({'status': newStatus});

                  await _updateTotalLeads(); // Atualiza o total após a alteração
                },
                statusColor: _getStatusColor(leadData['status'] ?? 'Aguardando'),
              );
            },
            childCount: filteredLeads.length,
          ),
        );
      },
    );
  }

  Widget _buildAllLeadsView(String empresaId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getAllLeadsStream(empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerEffect(); // Exibe o Shimmer enquanto carrega
        }

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Center(
              child: Text('Erro ao carregar os leads: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Nenhum lead disponível',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        final allLeads = snapshot.data!;
        final filteredLeads = allLeads.where((leadData) {
          final data = leadData as Map<String, dynamic>;
          final status = data['status'] ?? 'Aguardando';
          final nome = data['nome']?.toLowerCase() ?? '';

          return (selectedStatus == null ||
              selectedStatus == 'Sem Filtros' ||
              status == selectedStatus) &&
              (selectedCampaignId == null ||
                  leadData['campaignId'] == selectedCampaignId) &&
              nome.contains(_searchQuery);
        }).toList();

        if (filteredLeads.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Nenhum lead encontrado para a pesquisa atual',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final leadData = filteredLeads[index];
              return _buildLeadItem(leadData);
            },
            childCount: filteredLeads.length,
          ),
        );
      },
    );
  }

  Widget _buildLeadItem(Map<String, dynamic> leadData) {
    final data = leadData as Map<String, dynamic>;
    final status = data['status'] ?? 'Aguardando';
    final timestamp = leadData['timestamp'] ?? Timestamp.now();
    final nome = leadData['nome'] ?? 'Nome não disponível';

    return LeadCard(
      leadData: {
        ...leadData,
        'status': status,
        'timestamp': timestamp,
        'nome': nome,
      },
      onTap: (data) => _showLeadDetails(
        context,
        data,
            (newStatus) {
          setState(() {
            leadData['status'] = newStatus;
          });
        },
      ),
      onStatusChanged: (newStatus) {
        setState(() {
          leadData['status'] = newStatus;
        });
      },
      statusColor: _getStatusColor(status),
    );
  }

  int _compareStatus(String status1, String status2) {
    const order = ['Aguardando', 'Atendendo', 'Venda', 'Recusado'];
    return order.indexOf(status1).compareTo(order.indexOf(status2));
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'aguardando':
        return Colors.grey;
      case 'atendendo':
        return Colors.blue;
      case 'venda':
        return Colors.green;
      case 'recusado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showStatusSelectionDialog(
      BuildContext context,
      String leadId,
      String empresaId,
      String campaignId,
      Function(String) onStatusChanged,
      ) {
    final statusOptions = ['Aguardando', 'Atendendo', 'Venda', 'Recusado'];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(
            'Selecionar Status',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: statusOptions.map((status) {
              return ListTile(
                title: Text(
                  status,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(status),
                ),
                onTap: () {
                  onStatusChanged(status);
                  Navigator.of(context).pop(); // Fecha o diálogo
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(BuildContext context, String status, String leadId,
      String empresaId, String campanhaId) {
    return ListTile(
      title: Text(
        status,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSecondary,
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: _getStatusColor(status),
      ),
      onTap: () {
        FirebaseFirestore.instance
            .collection('empresas')
            .doc(empresaId)
            .collection('campanhas')
            .doc(campanhaId)
            .collection('leads')
            .doc(leadId)
            .update({'status': status});
        Navigator.of(context).pop(); // Fecha o diálogo após a atualização
      },
    );
  }
}