import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _getUserData();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        String? foundEmpresaId;

        // Primeiro, tenta buscar o usuário na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          // Se encontrado em 'users', obtém o ID da empresa a partir do campo 'createdBy'
          foundEmpresaId = userDoc['createdBy'];
        }

        // Se o usuário não estiver na coleção 'users', tenta buscá-lo na coleção 'empresas'
        if (foundEmpresaId == null) {
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            // Usa o próprio UID do usuário como 'empresaId' se o documento for encontrado em 'empresas'
            foundEmpresaId = user.uid;
          }
        }

        // Define o 'empresaId' no estado e interrompe o carregamento
        if (foundEmpresaId != null) {
          setState(() {
            empresaId = foundEmpresaId;
            isLoading = false;
          });
        } else {
          showErrorDialog(context, 'Documento não encontrado.', 'Atenção');
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
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
          leadData['leadId'] =
              leadDoc.id; // Inclui o ID do documento como 'leadId'
          leadData['campaignId'] = campaignDoc.id; // Inclui o ID da campanha
          leadData['empresaId'] = empresaId; // Inclui o ID da empresa
          return leadData;
        }).toList();
      });
    }).toList();

    yield* StreamZip(leadStreams).map((listOfLeadLists) {
      final allLeads = listOfLeadLists.expand((leads) => leads).toList();
      allLeads.sort((a, b) {
        // Ordena os leads pela data (decrescente)
        Timestamp timestampA = a['timestamp'];
        Timestamp timestampB = b['timestamp'];
        return timestampB.compareTo(timestampA);
      });
      return allLeads;
    });
  }

  void _navigateTo(BuildContext context, String routeName) {
    final isAdminPanel = routeName == '/admin';

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _getPageByRouteName(routeName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (isAdminPanel) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          } else {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            var tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);

            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          }
        },
      ),
    );
  }

  Widget _getPageByRouteName(String routeName) {
    switch (routeName) {
      case '/dashboard':
        return DashboardPage();
      case '/leads':
        return LeadsPage();
      case '/admin':
        return AdminPanelPage();
      default:
        return CustomTabBarPage();
    }
  }

  void _showLeadDetails(BuildContext context, Map<String, dynamic> leadData) {
    // Cria uma cópia dos dados para evitar modificações diretas
    leadData = Map<String, dynamic>.from(leadData);

    // Formatação do campo timestamp, caso exista
    String? formattedDate;
    if (leadData['timestamp'] != null && leadData['timestamp'] is Timestamp) {
      final timestamp = leadData['timestamp'] as Timestamp;
      final dateTime = timestamp.toDate();
      formattedDate =
      'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
      leadData.remove('timestamp'); // Remove o campo para evitar exibição duplicada
    }

    // Definindo os campos fixos
    final String? nome = leadData.remove('nome');
    final String? email = leadData.remove('email');
    final String? whatsapp = leadData.remove('whatsapp');
    String status = leadData['status'] ?? 'Aguardando'; // Status inicial
    final Color statusColor = _getStatusColor(status);

    // IDs necessários para manipulação do status
    final String? leadId = leadData.remove('leadId');
    final String? empresaId = leadData.remove('empresaId');
    final String? campaignId = leadData.remove('campaignId');

    // Verificação de identificadores necessários
    if (leadId == null || empresaId == null || campaignId == null) {
      showErrorDialog(
        context,
        'Dados incompletos para exibir os detalhes do lead.',
        'Erro',
      );
      return;
    }

    // Remove campos desnecessários
    leadData.remove('empresa_id');
    leadData.remove('nome_campanha');
    leadData.remove('leadId');
    leadData.remove('campaignId');
    leadData.remove('redirect_url');
    leadData.remove('status');

    // Exibição do popup
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
              titlePadding: EdgeInsets.zero, // Remove padding padrão do título
              contentPadding: const EdgeInsets.all(16.0),
              title: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 48.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalhes do Lead',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Theme.of(context).colorScheme.onSecondary,
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
                                    .update({'status': newStatus});

                                setState(() {
                                  status = newStatus;
                                });
                              },
                            );
                          },
                          child: Chip(
                            label: Text(
                              status,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSecondary,
                                fontFamily: 'Poppins',
                                fontSize: 12,
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
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nome != null)
                      _buildDetailRow('Nome', nome, context, maxLines: 1),
                    if (email != null)
                      _buildDetailRow('E-mail', email, context, maxLines: 1),
                    if (whatsapp != null)
                      _buildDetailRow('WhatsApp', whatsapp, context, maxLines: 1),
                    const SizedBox(height: 20),
                    ...leadData.entries.map((entry) {
                      return _buildDetailRow(
                        _capitalize(entry.key),
                        entry.value.toString(),
                        context,
                        maxLines: 1,
                      );
                    }).toList(),
                  ],
                ),
              ),
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

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _openWhatsAppWithMessage(String phoneNumber, String empresaId,
      String campaignId, String leadId) async {
    try {
      // Busca a mensagem padrão da campanha
      final campaignDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .get();

      if (!campaignDoc.exists) {
        showErrorDialog(context, 'Campanha não encontrada.', 'Erro');
        return;
      }

      // Obtém a mensagem padrão da campanha
      String message = campaignDoc.data()?['mensagem_padrao'] ?? '';

      // Busca o lead pelo ID correto
      print('Buscando lead com ID: $leadId');
      final leadDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .collection('leads')
          .doc(leadId) // Certifique-se de passar o leadId aqui
          .get();

      if (!leadDoc.exists) {
        showErrorDialog(context, 'Lead não encontrado.', 'Erro');
        return;
      }

      // Processa o nome do cliente (primeiro nome e nome completo)
      String? nomeClienteCompleto = leadDoc.data()?['nome'];
      String? nomeCliente = nomeClienteCompleto?.split(' ')?.first;

      // Dados do usuário logado
      final user = FirebaseAuth.instance.currentUser;
      String? userName;
      String? empresaName;

      if (user != null) {
        // Verifica se o usuário está na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name']?.split(' ')?.first;

          // Busca o nome da empresa associada ao usuário (caso 'createdBy' esteja definido)
          final createdBy = userDoc.data()?['createdBy'];
          if (createdBy != null) {
            final empresaDoc = await FirebaseFirestore.instance
                .collection('empresas')
                .doc(createdBy)
                .get();
            empresaName = empresaDoc.data()?['NomeEmpresa'];
          }
        } else {
          // Caso o usuário esteja na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();
          if (empresaDoc.exists) {
            userName = empresaDoc.data()?['NomeEmpresa']?.split(' ')?.first;
            empresaName = empresaDoc.data()?['NomeEmpresa'];
          }
        }
      }

      // Substitui as variáveis na mensagem
      message = message
          .replaceAll('{nome_cliente}', nomeCliente ?? '')
          .replaceAll('{nome_cliente_completo}', nomeClienteCompleto ?? '')
          .replaceAll('{nome_usuario}', userName ?? '')
          .replaceAll('{nome_empresa}', empresaName ?? '');

      // Limpa o número de telefone
      final cleanedPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');

      if (cleanedPhone.length >= 10) {
        // URL para abrir o WhatsApp com a mensagem
        final url = kIsWeb
            ? 'https://wa.me/$cleanedPhone?text=${Uri.encodeComponent(message)}'
            : 'whatsapp://send?phone=$cleanedPhone&text=${Uri.encodeComponent(message)}';

        if (await canLaunch(url)) {
          await launch(url);
        } else {
          showErrorDialog(
            context,
            'Não foi possível abrir o WhatsApp. Verifique se o WhatsApp está instalado ou tente novamente mais tarde!',
            'Atenção',
          );
        }
      } else {
        showErrorDialog(
          context,
          'Número de telefone inválido.',
          'Atenção',
        );
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Erro ao abrir o WhatsApp: $e',
        'Erro',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se ainda estiver carregando, mostra um indicador de carregamento
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (empresaId == null) {
      return Center(child: Text('Erro: Empresa não encontrada.'));
    }

    return ConnectivityBanner(
      child: Scaffold(
        body: SafeArea(
          top: true,
          child: _buildCampanhasStream(empresaId!),
        ),
      ),
    );
  }

  Widget _buildCampanhasStream(String empresaId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        final campanhas = snapshot.data?.docs ?? [];

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              expandedHeight: 70,
              backgroundColor: Theme.of(context).colorScheme.background,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: Theme.of(context).colorScheme.background,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
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
                            onSelected: (value) {
                              setState(() {
                                selectedCampaignId =
                                    value == 'Todas' ? null : value;
                                selectedCampaignName = value == 'Todas'
                                    ? 'Todas'
                                    : campanhas.firstWhere((campanha) =>
                                        campanha.id == value)['nome_campanha'];
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
                              color: Theme.of(context).colorScheme.onSecondary,
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
                              color: Theme.of(context).colorScheme.onSecondary,
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
                            onSelected: (value) {
                              setState(() {
                                selectedStatus = value;
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
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                selectedCampaignId != null
                    ? _buildLeadsStream(empresaId, selectedCampaignId!)
                    : _buildAllLeadsView(empresaId),
              ]),
            ),
          ],
        );
      },
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        List<DocumentSnapshot> leads = snapshot.data?.docs ?? [];

        // Aplicando o filtro de status manualmente nos dados após a query
        if (selectedStatus != null && selectedStatus != 'Sem Filtros') {
          leads = leads.where((lead) {
            final leadData = lead.data() as Map<String, dynamic>;
            return leadData['status'] == selectedStatus;
          }).toList();
        }

        if (leads.isEmpty) {
          return Center(child: Text('Nenhum lead disponível'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: leads.length,
          itemBuilder: (context, index) {
            final lead = leads[index];
            final leadData = Map<String, dynamic>.from(lead.data() as Map);
            leadData['leadId'] = lead.id;
            leadData['empresaId'] = empresaId;
            leadData['campaignId'] = campaignId;

            return _buildLeadItem(leadData);
          },
        );
      },
    );
  }

  Widget _buildAllLeadsView(String empresaId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getAllLeadsStream(empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Erro ao carregar os leads: ${snapshot.error}'));
        }

        final allLeads = snapshot.data ?? [];
        final filteredLeads = allLeads.where((leadData) {
          final status = leadData['status'] ?? 'Aguardando';
          return selectedStatus == null ||
              selectedStatus == 'Sem Filtros' ||
              status == selectedStatus;
        }).toList();

        if (filteredLeads.isEmpty) {
          return Center(child: Text('Nenhum lead disponível'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: filteredLeads.length,
          itemBuilder: (context, index) {
            final leadData = filteredLeads[index];
            return _buildLeadItem(leadData);
          },
        );
      },
    );
  }

  Widget _buildLeadItem(Map<String, dynamic> leadData) {
    final leadId = leadData['leadId'] ?? '';
    final empresaId = leadData['empresaId'] ?? '';
    final campaignId = leadData['campaignId'] ?? '';

    // Verificação de dados obrigatórios
    if (leadId.isEmpty || empresaId.isEmpty || campaignId.isEmpty) {
      print(
          'Identificadores ausentes ao tentar renderizar lead: leadId = $leadId, empresaId = $empresaId, campaignId = $campaignId');
      return Container(); // Retorna um container vazio se os IDs não forem válidos
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .collection('leads')
          .doc(leadId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Erro ao carregar o lead: ${snapshot.error}'));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(child: Text('Lead não encontrado.'));
        }

        // Extrair os dados do lead
        final leadData = snapshot.data!.data() as Map<String, dynamic>;
        final status = leadData['status'] ?? 'Aguardando';
        final color = _getStatusColor(status);

        // Formatação da data
        String formattedDate = '';
        if (leadData['timestamp'] != null &&
            leadData['timestamp'] is Timestamp) {
          final timestamp = leadData['timestamp'] as Timestamp;
          final dateTime = timestamp.toDate();
          formattedDate =
          'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
        }

        return GestureDetector(
          onTap: () {
            print(
                'Abrindo detalhes do lead: leadId=$leadId, empresaId=$empresaId, campaignId=$campaignId');
            _showLeadDetails(
              context,
              {
                ...leadData, // Inclui todos os dados do lead
                'leadId': leadId,
                'empresaId': empresaId,
                'campaignId': campaignId,
              },
            );
          },
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(10, 0, 10, 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: Theme.of(context).colorScheme.shadow,
                    offset: Offset(0, 0),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status do Lead
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 1, horizontal: 12),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _showStatusSelectionDialog(
                                context,
                                leadId,
                                empresaId,
                                campaignId,
                                    (newStatus) {
                                  // Atualiza o status no Firestore
                                  FirebaseFirestore.instance
                                      .collection('empresas')
                                      .doc(empresaId)
                                      .collection('campanhas')
                                      .doc(campaignId)
                                      .collection('leads')
                                      .doc(leadId)
                                      .update({'status': newStatus});
                                },
                              );
                            },
                            child: Chip(
                              label: Text(
                                status,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline,
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              backgroundColor: color,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                                side: BorderSide(
                                  color: color,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Data de Entrada
                    if (formattedDate.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 1, horizontal: 12),
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                    // Nome do Lead
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 1, horizontal: 12),
                      child: Text(
                        leadData['nome'] ?? 'Nome não disponível',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                    // Informações do WhatsApp
                    if (leadData.containsKey('whatsapp') &&
                        leadData['whatsapp'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 1, horizontal: 12),
                        child: Row(
                          children: [
                            IconButton(
                              icon: FaIcon(
                                FontAwesomeIcons.whatsapp,
                                color:
                                Theme.of(context).colorScheme.onBackground,
                                size: 25,
                              ),
                              onPressed: () {
                                final phoneNumber =
                                leadData['whatsapp'] as String?;
                                print(
                                    'WhatsApp Data: phone=$phoneNumber, empresaId=$empresaId, campaignId=$campaignId, leadId=$leadId');

                                if (phoneNumber != null) {
                                  _openWhatsAppWithMessage(phoneNumber,
                                      empresaId, campaignId, leadId);
                                } else {
                                  showErrorDialog(context,
                                      'Número de telefone inválido.', 'Erro');
                                }
                              },
                            ),
                            GestureDetector(
                              onTap: () {
                                final phoneNumber =
                                leadData['whatsapp'] as String?;
                                print(
                                    'WhatsApp Data: phone=$phoneNumber, empresaId=$empresaId, campaignId=$campaignId, leadId=$leadId');

                                if (phoneNumber != null) {
                                  _openWhatsAppWithMessage(phoneNumber,
                                      empresaId, campaignId, leadId);
                                } else {
                                  showErrorDialog(context,
                                      'Número de telefone inválido.', 'Erro');
                                }
                              },
                              child: Text(
                                leadData['whatsapp'] ?? '',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
