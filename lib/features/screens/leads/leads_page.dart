import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      if (!isScrollingDown) {
        setState(() {
          isScrollingDown = true;
        });
      }
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
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
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final createdBy = userDoc['createdBy'];
          if (createdBy != null) {
            setState(() {
              _getAllLeadsStream(createdBy); // Busca leads da empresa
            });
          }
        } else {
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            setState(() {
              _getAllLeadsStream(user.uid); // Busca leads do próprio usuário
            });
          } else {
            showErrorDialog(context, 'Documento não encontrado.', 'Atenção');
          }
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
    }
  }

  Stream<List<Map<String, dynamic>>> _getAllLeadsStream(String empresaId) async* {
    final campaignsSnapshot = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('campanhas')
        .get();

    List<Stream<List<Map<String, dynamic>>>> leadStreams = campaignsSnapshot.docs.map((campaignDoc) {
      return campaignDoc.reference.collection('leads')
          .snapshots().map((leadsSnapshot) {
        return leadsSnapshot.docs.map((leadDoc) {
          Map<String, dynamic> leadData = leadDoc.data();
          leadData['leadId'] = leadDoc.id;
          leadData['campaignId'] = campaignDoc.id;
          leadData['empresaId'] = empresaId;
          return leadData;
        }).toList();
      });
    }).toList();

    yield* StreamZip(leadStreams).map((listOfLeadLists) {
      final allLeads = listOfLeadLists.expand((leads) => leads).toList();
      // Ordenando todos os leads pela data de forma decrescente
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

  void _showLeadDetails(BuildContext context, Map<String, dynamic> leadData) {
    // Cria uma cópia dos dados para evitar modificações diretas
    leadData = Map<String, dynamic>.from(leadData);

    // Remove campos desnecessários
    leadData.remove('empresa_id');
    leadData.remove('nome_campanha');
    leadData.remove('redirect_url');

    // Formatando o campo timestamp, caso exista
    String? formattedDate;
    if (leadData['timestamp'] != null && leadData['timestamp'] is Timestamp) {
      final timestamp = leadData['timestamp'] as Timestamp;
      final dateTime = timestamp.toDate();
      formattedDate = 'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
      leadData.remove('timestamp'); // Remove o campo para evitar exibição duplicada
    }

    // Definindo os campos a serem exibidos
    final String? nome = leadData.remove('nome');
    final String? email = leadData.remove('email');
    final String? whatsapp = leadData.remove('whatsapp');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(
            'Detalhes do Lead',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formattedDate != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      formattedDate,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                if (nome != null)
                  _buildInfoText('Nome', nome, context),
                if (email != null)
                  _buildInfoText('Email', email, context),
                if (whatsapp != null)
                  _buildInfoText('Whatsapp', whatsapp, context),
                SizedBox(height: 16),
                ...leadData.entries.map((entry) {
                  return _buildInfoText(
                      _capitalize(entry.key), entry.value.toString(), context);
                }).toList(),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Fechar',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoText(String label, String value, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _openWhatsAppNative(String phoneNumber) async {
    final cleanedPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');

    if (cleanedPhone.length >= 10) {
      if (kIsWeb) {
        // Para Web, abra o link do WhatsApp diretamente
        final url = 'https://wa.me/$cleanedPhone';
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          showErrorDialog(
            context,
            'Não foi possível abrir o WhatsApp. Tente novamente mais tarde!',
            'Atenção',
          );
        }
      } else {
        // Para Android/iOS, use o MethodChannel como antes
        const platform = MethodChannel('com.iomarketing.whatsapp');

        try {
          await platform.invokeMethod('openWhatsApp', {'phone': cleanedPhone});
        } on PlatformException catch (e) {
          showErrorDialog(
            context,
            'Erro ao abrir o WhatsApp: ${e.message}',
            'Erro',
          );
        }
      }
    } else {
      showErrorDialog(
        context,
        'Número de telefone inválido.',
        'Atenção',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<appAuthProvider.AuthProvider>(context, listen: false);
    final user = authProvider.user;

    return ConnectivityBanner(
      child: Scaffold(
        body: SafeArea(
          top: true,
          child: FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (userSnapshot.hasError) {
                return Center(child: Text('Erro ao buscar o usuário: ${userSnapshot.error}'));
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userDocument = userSnapshot.data!;
                final empresaId = userDocument['createdBy'] ?? user!.uid;

                return _buildCampanhasStream(empresaId);
              }
              return Center(child: Text('Erro: Usuário não encontrado'));
            },
          ),
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
              expandedHeight: 70, // Reduzindo a altura expandida
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
                            icon: Icon(Icons.campaign, size: 30), // Ícone menor
                            offset: Offset(0, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            onSelected: (value) {
                              setState(() {
                                selectedCampaignId = value == 'Todas' ? null : value;
                                selectedCampaignName = value == 'Todas'
                                    ? 'Todas'
                                    : campanhas.firstWhere((campanha) => campanha.id == value)['nome_campanha'];
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
                          SizedBox(width: 4), // Menor espaçamento entre o botão e o texto
                          Text(
                            (selectedCampaignName == null || selectedCampaignName == 'Todas') ? '' : selectedCampaignName!,
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
                            (selectedStatus == null || selectedStatus == 'Sem Filtros') ? '' : selectedStatus!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          SizedBox(width: 4), // Menor espaçamento entre o texto e o botão
                          PopupMenuButton<String>(
                            color: Theme.of(context).colorScheme.secondary,
                            icon: Icon(Icons.filter_list, size: 30), // Ícone menor
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
          return Center(child: Text('Erro ao carregar os leads: ${snapshot.error}'));
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

    if (leadId.isEmpty || empresaId.isEmpty || campaignId.isEmpty) {
      print('Identificadores ausentes ao tentar renderizar lead: leadId = $leadId, empresaId = $empresaId, campaignId = $campaignId');
      return Container(); // Retorne um container vazio se os IDs não estiverem corretos
    }

    // Utilize um StreamBuilder para observar diretamente o status do lead
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
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar o lead'));
        }

        final leadData = snapshot.data!.data() as Map<String, dynamic>;
        final status = leadData['status'] ?? 'Aguardando';
        final color = _getStatusColor(status);

        String formattedDate = '';
        if (leadData['timestamp'] != null && leadData['timestamp'] is Timestamp) {
          final timestamp = leadData['timestamp'] as Timestamp;
          final dateTime = timestamp.toDate();
          formattedDate = 'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
        }

        return GestureDetector(
          onTap: () => _showLeadDetails(context, leadData),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 12),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (leadId.isNotEmpty && empresaId.isNotEmpty && campaignId.isNotEmpty) {
                                _showStatusSelectionDialog(context, leadId, empresaId, campaignId);
                              } else {
                                print('Identificadores ausentes ao tentar alterar o status: leadId = $leadId, empresaId = $empresaId, campaignId = $campaignId');
                              }
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 12),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 12),
                      child: Text(
                        leadData['nome'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                    if (leadData.containsKey('whatsapp'))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: FaIcon(
                                FontAwesomeIcons.whatsapp,
                                color: Theme.of(context).colorScheme.onBackground,
                                size: 25,
                              ),
                              onPressed: () => _openWhatsAppNative(leadData['whatsapp'] ?? ''),
                            ),
                            SizedBox(width: 0),
                            GestureDetector(
                              onTap: () => _openWhatsAppNative(leadData['whatsapp'] ?? ''),
                              child: Text(
                                leadData['whatsapp'] ?? '',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSecondary,
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

  void _showStatusSelectionDialog(BuildContext context, String leadId,
      String empresaId, String campanhaId) {
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
            children: [
              _buildStatusOption(
                  context, 'Aguardando', leadId, empresaId, campanhaId),
              _buildStatusOption(
                  context, 'Atendendo', leadId, empresaId, campanhaId),
              _buildStatusOption(
                  context, 'Venda', leadId, empresaId, campanhaId),
              _buildStatusOption(
                  context, 'Recusado', leadId, empresaId, campanhaId),
            ],
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