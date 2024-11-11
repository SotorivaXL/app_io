import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/home/home_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/util/CustomWidgets/CustomDropDown/custom_dropDown.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? selectedStatus; // Variável para armazenar o status selecionado

  @override
  void initState() {
    super.initState();
    _getUserData();
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Tenta buscar o documento do usuário na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          // Se encontrado na coleção 'users', armazena e exibe o nome do usuário
          final data = userDoc.data();
          if (data != null) {
            String userName = data['name'] ?? '';
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString('userName', userName);

            setState(() {
              this.userName = userName;
            });
          }
        } else {
          // Se não encontrado na coleção 'users', tenta buscar na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            final data = empresaDoc.data();
            if (data != null) {
              String userName = data['NomeEmpresa'] ?? '';
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('userName', userName);

              setState(() {
                this.userName = userName;
              });
            }
          } else {
            // Se não encontrado em nenhuma das coleções, exibe mensagem de erro
            showErrorDialog(context,
                'Documento do usuário não encontrado, aguarde e tente novamente mais tarde!.', 'Atenção');
          }
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
    }
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
        return HomePage();
    }
  }

  void _showLeadDetails(BuildContext context, Map<String, dynamic> leadData) {
    // Remover o campo 'redirect_url'
    leadData = Map<String, dynamic>.from(leadData); // Cria uma cópia dos dados para evitar modificações diretas
    leadData.remove('redirect_url');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Obter os dados principais nas ordens desejadas
        final String? dataEntrada = leadData.remove('data_entrada');
        final String? nome = leadData.remove('nome');
        final String? email = leadData.remove('email');
        final String? whatsapp = leadData.remove('whatsapp');

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
                if (dataEntrada != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      dataEntrada,
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
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(),
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid)
                  .get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (userSnapshot.hasError) {
                  return Center(
                      child: Text(
                          'Erro ao buscar o usuário: ${userSnapshot.error}'));
                }

                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final userDocument = userSnapshot.data!;
                  final empresaId = userDocument['createdBy'];

                  if (empresaId != null && empresaId.isNotEmpty) {
                    return _buildCampanhasStream(empresaId);
                  }
                }

                return _buildCampanhasStream(user!.uid);
              },
            ),
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
        if (campanhas.isEmpty) {
          return Center(child: Text('Nenhuma campanha disponível'));
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 10.0, top: 20.0, bottom: 20.0, right: 5.0),
                    child: CustomDropdownButton<String>(
                      value: selectedCampaignId,
                      items: campanhas.map((campanha) {
                        return DropdownMenuItem<String>(
                          value: campanha.id,
                          child: Text(campanha['nome_campanha']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCampaignId = value;
                          selectedCampaignName = campanhas.firstWhere(
                                  (campanha) =>
                              campanha.id == value)['nome_campanha'];
                        });
                      },
                      hint: 'Selecione uma campanha',
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(
                          left: 5.0, top: 20.0, bottom: 20.0, right: 10.0),
                      child: CustomDropdownButton<String>(
                          value: selectedStatus,
                          items: [
                            'Sem Filtros',
                            'Aguardando',
                            'Atendendo',
                            'Venda',
                            'Recusado'
                          ].map((status) {
                            return DropdownMenuItem<String>(
                              value: status,
                              child: Container(
                                child: Text(//
                                  status,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedStatus = value;
                            });
                          },
                          hint: 'Filtrar por status')),
                ),
              ],
            ),
            if (selectedCampaignId != null)
              Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('empresas')
                        .doc(empresaId)
                        .collection('campanhas')
                        .doc(selectedCampaignId)
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
                      final leads = snapshot.data?.docs ?? [];
                      if (leads.isEmpty) {
                        return Center(child: Text('Nenhum lead disponível'));
                      }

                      // Filtro de leads baseado no status
                      final filteredLeads = leads.where((lead) {
                        final data = lead.data() as Map<String, dynamic>;
                        final status = data['status'] ?? 'Aguardando';
                        return selectedStatus == null ||
                            selectedStatus == 'Sem Filtros' ||
                            status == selectedStatus;
                      }).toList();

                      return ListView.builder(
                        itemCount: filteredLeads.length,
                        itemBuilder: (context, index) {
                          final lead = filteredLeads[index];
                          final leadData =
                          Map<String, dynamic>.from(lead.data() as Map);

                          // Filtrar os campos 'empresa_id' e 'nome_campanha'
                          leadData.remove('empresa_id');
                          leadData.remove('nome_campanha');

                          // Formatar o timestamp e alterar o nome do campo
                          if (leadData.containsKey('timestamp') &&
                              leadData['timestamp'] != null) {
                            Timestamp timestamp = leadData['timestamp'];
                            DateTime dateTime = timestamp
                                .toDate()
                                .toLocal(); // Ajusta para o horário local
                            String formattedTime =
                            DateFormat('HH:mm').format(dateTime);
                            String formattedDate =
                            DateFormat('dd/MM/yyyy').format(dateTime);

                            // Remover o campo 'timestamp' original
                            leadData.remove('timestamp');

                            // Adicionar o novo campo com o nome desejado
                            leadData['data_entrada'] =
                            'Entrou às ${formattedTime} do dia ${formattedDate}';
                          }

                          // Adicionar o campo de status
                          final status = leadData['status'] ??
                              'Aguardando'; // Default para 'Aguardando'
                          final color = _getStatusColor(status);

                          return GestureDetector(
                            onTap: () {
                              _showLeadDetails(context, leadData);
                            },
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.9,
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
                                      // Exibe a Tag de Status
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 1, horizontal: 12),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                _showStatusSelectionDialog(
                                                    context,
                                                    lead.id,
                                                    empresaId,
                                                    selectedCampaignId!);
                                              },
                                              child: Chip(
                                                label: Text(
                                                  status,
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outline,
                                                    fontFamily: 'Poppins',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                backgroundColor: color,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius.circular(25),
                                                  side: BorderSide(
                                                    color: color, // Cor da borda
                                                    width: 2, // Largura da borda
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Exibe a Data de Entrada do Lead
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 1, horizontal: 12),
                                        child: Text(
                                          leadData['data_entrada'] ?? '',
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
                                      // Exibe o Nome da Pessoa
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 1, horizontal: 12),
                                        child: Text(
                                          leadData['nome'] ?? '',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 24,
                                            // Tamanho da fonte maior para o nome
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                        ),
                                      ),
                                      // Exibe o WhatsApp da Pessoa
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
                    },
                  )),
          ],
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
        Navigator.of(context).pop();
      },
    );
  }
}