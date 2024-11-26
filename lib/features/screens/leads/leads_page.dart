import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/CustomWidgets/LeadCard/lead_card.dart';
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
import 'package:shimmer/shimmer.dart';
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

  bool areLeadsLoaded = false;
  List<Map<String, dynamic>> leadsData = [];

  final ScrollController _scrollController = ScrollController();

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

  Future<void> _loadLeads(String empresaId) async {
    final allLeads = await _getAllLeadsStream(empresaId).first;
    setState(() {
      leadsData = allLeads;
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
        // Aguarde pelo menos 5 segundos antes de remover o carregamento
        Future.delayed(Duration(seconds: 5), () {
          setState(() {
            isLoading = false;
          });
        });
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
      setState(() {
        isLoading = false;
      });
    }
  }

  Stream<List<Map<String, dynamic>>> _getAllLeadsStream(String empresaId) async* {
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

  void _showLeadDetails(BuildContext context, Map<String, dynamic> leadData, Function(String) onStatusChanged) {
    // Cria uma cópia dos dados para evitar modificações diretas
    leadData = Map<String, dynamic>.from(leadData);

    String? formattedDate;
    if (leadData['timestamp'] != null && leadData['timestamp'] is Timestamp) {
      final timestamp = leadData['timestamp'] as Timestamp;
      final dateTime = timestamp.toDate();
      formattedDate =
      'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
      leadData.remove('timestamp');
    }

    final String? nome = leadData.remove('nome');
    final String? email = leadData.remove('email');
    final String? whatsapp = leadData.remove('whatsapp');
    String status = leadData['status'] ?? 'Aguardando';

    final String? leadId = leadData['leadId'];
    final String? empresaId = leadData['empresaId'];
    final String? campaignId = leadData['campaignId'];

    if (leadId == null || empresaId == null || campaignId == null) {
      showErrorDialog(
        context,
        'Dados incompletos para exibir os detalhes do lead.',
        'Erro',
      );
      return;
    }

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
                                    .update({'status': newStatus}).then((_) {
                                  Navigator.of(context).pop(); // Fecha o popup automaticamente
                                  onStatusChanged(newStatus); // Atualiza o card sem recarregar
                                }).catchError((e) {
                                  showErrorDialog(context, 'Erro ao atualizar status: $e', 'Erro');
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
    if (isLoading) {
      return Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.onSecondaryContainer,
        highlightColor: Theme.of(context).colorScheme.onTertiaryContainer,
        child: ListView.builder(
          physics: NeverScrollableScrollPhysics(),
          itemCount: 6, // Número de placeholders
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
              child: Container(
                height: 100.0,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            );
          },
        ),
      );
    }

    if (empresaId == null) {
      return Center(child: Text('Erro: Empresa não encontrada.'));
    }

    return ConnectivityBanner(
      child: Scaffold(
        body: SafeArea(
          top: true,
          child: isLoading || !areLeadsLoaded
              ? _buildShimmerEffect()
              : _buildCampanhasStream(empresaId!),
        ),
      ),
    );
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

        if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerEffect(); // Exibe o Shimmer enquanto carrega
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
              expandedHeight: 70,
              backgroundColor: Theme.of(context).colorScheme.background,
              surfaceTintColor: Colors.transparent,
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
                            onSelected: (value) async {
                              setState(() {
                                isLoading = true; // Ativa o Shimmer
                                selectedCampaignId = value == 'Todas' ? null : value;
                                selectedCampaignName = value == 'Todas'
                                    ? 'Todas'
                                    : campanhas.firstWhere((campanha) =>
                                campanha.id == value)['nome_campanha'];
                                leadsData.clear(); // Limpa os leads visíveis
                              });

                              if (selectedCampaignId != null) {
                                await _loadCampaignLeads(empresaId, selectedCampaignId!);
                              } else {
                                await _loadLeads(empresaId); // Carrega todos os leads
                              }

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
                                      color: Theme.of(context).colorScheme.onSecondary,
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
                                        color: Theme.of(context).colorScheme.onSecondary,
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
                                    color: Theme.of(context).colorScheme.onSecondary,
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

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.onSecondaryContainer,
      highlightColor: Theme.of(context).colorScheme.onTertiaryContainer,
      child: ListView.builder(
        physics: NeverScrollableScrollPhysics(),
        itemCount: 6, // Número de placeholders
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
            child: Container(
              height: 100.0,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
          );
        },
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
          return Center(child: Text('Erro ao carregar os leads: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerEffect(); // Exibe o Shimmer durante o carregamento
        }

        final leads = snapshot.data?.docs ?? [];

        if (leads.isEmpty) {
          return Center(
            child: Text(
              'Nenhum lead disponível',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
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

            return LeadCard(
              leadData: leadData,
              onTap: (data) => _showLeadDetails(
                context,
                data,
                    (newStatus) {
                  leadData['status'] = newStatus; // Atualiza localmente
                },
              ),
              onStatusChanged: (newStatus) {
                FirebaseFirestore.instance
                    .collection('empresas')
                    .doc(empresaId)
                    .collection('campanhas')
                    .doc(campaignId)
                    .collection('leads')
                    .doc(lead.id)
                    .update({'status': newStatus});
              },
              statusColor: _getStatusColor(leadData['status'] ?? 'Aguardando'),
            );
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
          return _buildShimmerEffect(); // Exibe o Shimmer enquanto carrega
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Erro ao carregar os leads: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'Nenhum lead disponível',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        final allLeads = snapshot.data!;
        final filteredLeads = allLeads.where((leadData) {
          final status = leadData['status'] ?? 'Aguardando';
          return selectedStatus == null ||
              selectedStatus == 'Sem Filtros' ||
              status == selectedStatus;
        }).toList();

        if (filteredLeads.isEmpty) {
          return Center(
            child: Text(
              'Nenhum lead disponível para os filtros selecionados',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: ClampingScrollPhysics(),
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
    final status = leadData['status'] ?? 'Aguardando';
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
