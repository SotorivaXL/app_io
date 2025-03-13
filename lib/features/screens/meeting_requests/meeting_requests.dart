import 'package:app_io/features/screens/meeting_requests/request_metting.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MeetingRequests extends StatefulWidget {
  const MeetingRequests({super.key});

  @override
  State<MeetingRequests> createState() => _MeetingRequestsState();
}

class _MeetingRequestsState extends State<MeetingRequests> {
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  // Variáveis de filtro (apenas para usuários especiais)
  String _selectedUrgencyFilter = "Todos";
  String _selectedCompanyFilter = "Todos";

  // Recupera o nome da empresa do usuário logado (documento com id igual ao uid)
  Future<String?> _getCompanyName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final empresaDoc =
    await FirebaseFirestore.instance.collection('empresas').doc(uid).get();
    if (empresaDoc.exists) {
      return empresaDoc.get('NomeEmpresa');
    }
    return null;
  }

  // Método para navegação com transição de baixo para cima
  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          final tween =
          Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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

  // Retorna a cor da tag com base na urgência
  Color getUrgencyColor(String urgency) {
    switch (urgency) {
      case 'Urgente':
        return Color(0xFFc10808);
      case 'Muito Alta':
        return Color(0xffff6a2d);
      case 'Alta':
        return Color(0xffea8700);
      case 'Media':
        return Color(0xffdfa808);
      case 'Baixa':
        return Color(0xFF9300ff);
      case 'Muito Baixa':
        return Color(0xFFb754ff);
      default:
        return Colors.grey;
    }
  }

  // Função para remover a solicitação com opção de desfazer
  Future<void> _deleteRequest(String docId, Map<String, dynamic> requestData) async {
    await FirebaseFirestore.instance.collection('meetingRequests').doc(docId).delete();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        content: Text(
          "Solicitação atendida",
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        action: SnackBarAction(
          label: "Desfazer",
          textColor: Theme.of(context).colorScheme.onSecondary,
          onPressed: () async {
            await FirebaseFirestore.instance
                .collection('meetingRequests')
                .doc(docId)
                .set(requestData);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 1024;
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    return ConnectivityBanner(
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
                            'Solicitações de Reunião',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Botão para adicionar nova solicitação
                      IconButton(
                        icon: Icon(
                          Icons.add,
                          color: Theme.of(context).colorScheme.onBackground,
                          size: 30,
                        ),
                        onPressed: () {
                          _navigateWithBottomToTopTransition(context, RequestMetting());
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
        body: FutureBuilder<String?>(
          future: _getCompanyName(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return Center(child: Text("Empresa não encontrada."));
            }
            final companyName = snapshot.data;
            // Usuário especial vê todas as solicitações
            final bool isSpecialUser = companyName == "IO Marketing Digital" || companyName == "IO Marketing Dev";

            // Se especial, query sem filtro; caso contrário, filtra pela empresa do usuário.
            final Stream<QuerySnapshot> requestStream = isSpecialUser
                ? FirebaseFirestore.instance.collection('meetingRequests').snapshots()
                : FirebaseFirestore.instance
                .collection('meetingRequests')
                .where('nomeEmpresa', isEqualTo: companyName)
                .snapshots();

            return StreamBuilder<QuerySnapshot>(
              stream: requestStream,
              builder: (context, meetingSnapshot) {
                if (meetingSnapshot.hasError) {
                  return Center(
                    child: Text(
                      "Erro ao carregar solicitações: ${meetingSnapshot.error}",
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                  );
                }
                if (meetingSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (!meetingSnapshot.hasData || meetingSnapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      "Nenhuma solicitação encontrada.",
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                  );
                }
                // Recupera todos os documentos
                final allRequests = meetingSnapshot.data!.docs;

                // Se for usuário especial, gera a lista de empresas distintas com solicitações abertas
                List<String> distinctCompanies = [];
                if (isSpecialUser) {
                  distinctCompanies = allRequests.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['nomeEmpresa'] as String? ?? "";
                  }).toSet().toList();
                  distinctCompanies.sort();
                  distinctCompanies.insert(0, "Todos");
                }

                // Aplica os filtros em memória
                List<dynamic> filteredRequests = allRequests;
                if (_selectedUrgencyFilter != "Todos") {
                  filteredRequests = filteredRequests.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['urgencia'] == _selectedUrgencyFilter;
                  }).toList();
                }
                if (isSpecialUser && _selectedCompanyFilter != "Todos") {
                  filteredRequests = filteredRequests.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['nomeEmpresa'] == _selectedCompanyFilter;
                  }).toList();
                }

                // Ordena os resultados pela prioridade da urgência
                final urgencyPriority = {
                  'Urgente': 0,
                  'Muito Alta': 1,
                  'Alta': 2,
                  'Media': 3,
                  'Baixa': 4,
                  'Muito Baixa': 5,
                };
                filteredRequests.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final rankA = urgencyPriority[dataA['urgencia']] ?? 100;
                  final rankB = urgencyPriority[dataB['urgencia']] ?? 100;
                  return rankA.compareTo(rankB);
                });

                return Column(
                  children: [
                    // Exibe os filtros apenas para usuários especiais
                    if (isSpecialUser)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                        child: Row(
                          children: [
                            // Filtro por urgência
                            Expanded(
                              child: DropdownButtonFormField2<String>(
                                isExpanded: true,
                                value: _selectedUrgencyFilter,
                                dropdownStyleData: DropdownStyleData(
                                  maxHeight: 200,
                                  direction: DropdownDirection.right,
                                ),
                                items: [
                                  "Todos",
                                  "Urgente",
                                  "Muito Alta",
                                  "Alta",
                                  "Media",
                                  "Baixa",
                                  "Muito Baixa"
                                ].map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedUrgencyFilter = newValue!;
                                  });
                                },
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
                            const SizedBox(width: 16),
                            // Filtro por empresa
                            Expanded(
                              child: DropdownButtonFormField2<String>(
                                isExpanded: true,
                                dropdownStyleData: DropdownStyleData(
                                  maxHeight: 200,
                                  // Se quiser forçar para sempre abrir para baixo, use:
                                  direction: DropdownDirection.left,
                                ),
                                value: _selectedCompanyFilter,
                                items: distinctCompanies.map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value, style: TextStyle(fontFamily: 'Poppins')),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedCompanyFilter = newValue!;
                                  });
                                },
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
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: filteredRequests.length,
                        itemBuilder: (context, index) {
                          final doc = filteredRequests[index];
                          final requestData = doc.data() as Map<String, dynamic>;
                          final motivo = requestData['motivo'] ?? '';
                          final assunto = requestData['assunto'] ?? '';
                          final urgencia = requestData['urgencia'] ?? '';
                          final requestCompany = requestData['nomeEmpresa'] ?? '';
                          final dataReuniao = requestData['dataReuniao'] != null
                              ? (requestData['dataReuniao'] as Timestamp).toDate()
                              : null;
                          final formattedDate = dataReuniao != null
                              ? DateFormat('dd/MM/yyyy').format(dataReuniao)
                              : '';
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Coluna com as informações
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Tag de urgência
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: getUrgencyColor(urgencia),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            urgencia,
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        // Se for usuário especial, mostra o nome da empresa solicitante
                                        if (isSpecialUser) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            requestCompany,
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context).colorScheme.onSecondary,
                                            ),
                                          ),
                                        ],
                                        SizedBox(height: 8),
                                        // Motivo
                                        Text(
                                          motivo,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        // Assunto
                                        Text(
                                          assunto,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        // Data
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Coluna com o botão (double-check para special, delete para os demais)
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isSpecialUser ? Icons.done_all : Icons.delete,
                                          color: isSpecialUser ? Theme.of(context).colorScheme.tertiary : Colors.red,
                                          size: 30,
                                        ),
                                        onPressed: () async {
                                          final docId = doc.id;
                                          final requestDataBackup = Map<String, dynamic>.from(requestData);
                                          await FirebaseFirestore.instance
                                              .collection('meetingRequests')
                                              .doc(docId)
                                              .delete();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Theme.of(context).colorScheme.primary,
                                              content: Text(
                                                "Solicitação atendida",
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  color: Theme.of(context).colorScheme.onSecondary,
                                                ),
                                              ),
                                              action: SnackBarAction(
                                                label: "Desfazer",
                                                textColor: Theme.of(context).colorScheme.onSecondary,
                                                onPressed: () async {
                                                  await FirebaseFirestore.instance
                                                      .collection('meetingRequests')
                                                      .doc(docId)
                                                      .set(requestDataBackup);
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}