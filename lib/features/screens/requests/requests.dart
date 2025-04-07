import 'package:app_io/features/screens/requests/request_metting.dart';
import 'package:app_io/features/screens/requests/request_recording.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class Requests extends StatefulWidget {
  const Requests({super.key});

  @override
  State<Requests> createState() => _RequestsState();
}

class _RequestsState extends State<Requests> {
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  // Filtro de evento (Reunião ou Gravação). "Todos" exibe tudo.
  String _selectedEventFilter = "Todos";

  // Filtro de empresa (apenas para usuários especiais)
  String _selectedCompanyFilter = "Todos";

  // Variável para controlar a exibição dos botões extras na AppBar
  bool _showExtraButtons = false;

  Future<void> _launchMaps(double lat, double lng) async {
    final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  /// Retorna o nome da empresa do usuário logado (documento com id == uid).
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

  /// Consulta a coleção `empresas` para obter o `photoUrl` com base no nome da empresa.
  Future<String?> _getCompanyPhotoUrl(String nomeEmpresa) async {
    final query = await FirebaseFirestore.instance
        .collection('empresas')
        .where('NomeEmpresa', isEqualTo: nomeEmpresa)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      return data['photoUrl'] as String?;
    }
    return null;
  }

  /// Navegação com transição de baixo para cima
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
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// Remove a solicitação com opção de desfazer via SnackBar
  Future<void> _deleteRequest(String docId, Map<String, dynamic> requestData) async {
    await FirebaseFirestore.instance.collection('requests').doc(docId).delete();

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
                .collection('requests')
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                            'Solicitações',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Área dos botões na AppBar (os botões extras aparecem à esquerda do botão add)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_showExtraButtons) ...[
                            IconButton(
                              icon: const Icon(
                                  Icons.meeting_room,
                                size: 25,
                              ),
                              color: Theme.of(context).colorScheme.onBackground,
                              onPressed: () {
                                _navigateWithBottomToTopTransition(
                                  context,
                                  const RequestMetting(),
                                );
                                setState(() {
                                  _showExtraButtons = false;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.emergency_recording,
                                size: 25,
                              ),
                              color: Theme.of(context).colorScheme.onBackground,
                              onPressed: () {
                                _navigateWithBottomToTopTransition(
                                  context,
                                  const RequestRecording(),
                                );
                                setState(() {
                                  _showExtraButtons = false;
                                });
                              },
                            ),
                          ],
                          // Botão de add principal
                          IconButton(
                            icon: const Icon(
                                Icons.add,
                              size: 30,
                            ),
                            color: Theme.of(context).colorScheme.onBackground,
                            onPressed: () {
                              setState(() {
                                _showExtraButtons = !_showExtraButtons;
                              });
                            },
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
          ),
        ),
        body: FutureBuilder<String?>(
          future: _getCompanyName(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(child: Text("Empresa não encontrada."));
            }
            final companyName = snapshot.data;

            // Usuário especial vê todas as solicitações
            final bool isSpecialUser = companyName == "IO Marketing Digital" ||
                companyName == "IO Marketing Dev";

            // Query: se especial, sem filtro; caso contrário, filtra pela empresa do usuário.
            final Stream<QuerySnapshot> requestStream = isSpecialUser
                ? FirebaseFirestore.instance.collection('requests').snapshots()
                : FirebaseFirestore.instance
                .collection('requests')
                .where('nomeEmpresa', isEqualTo: companyName)
                .snapshots();

            return StreamBuilder<QuerySnapshot>(
              stream: requestStream,
              builder: (context, meetingSnapshot) {
                if (meetingSnapshot.hasError) {
                  return Center(
                    child: Text(
                      "Erro ao carregar solicitações: ${meetingSnapshot.error}",
                      style: const TextStyle(fontFamily: 'Poppins'),
                    ),
                  );
                }
                if (meetingSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!meetingSnapshot.hasData || meetingSnapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Nenhuma solicitação encontrada.",
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                  );
                }

                // Recupera todos os documentos
                final allRequests = meetingSnapshot.data!.docs;

                // Se for usuário especial, gera a lista de empresas distintas
                List<String> distinctCompanies = [];
                if (isSpecialUser) {
                  distinctCompanies = allRequests
                      .map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['nomeEmpresa'] as String? ?? "";
                  })
                      .toSet()
                      .toList();
                  distinctCompanies.sort();
                  distinctCompanies.insert(0, "Todos");
                }

                // Aplica filtros em memória
                List<dynamic> filteredRequests = allRequests;

                // Filtro por tipo de evento (Reunião ou Gravação)
                if (_selectedEventFilter != "Todos") {
                  filteredRequests = filteredRequests.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['tipoSolicitacao'] == _selectedEventFilter;
                  }).toList();
                }

                // Filtro por empresa (caso usuário especial)
                if (isSpecialUser && _selectedCompanyFilter != "Todos") {
                  filteredRequests = filteredRequests.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['nomeEmpresa'] == _selectedCompanyFilter;
                  }).toList();
                }

                // Filtra registros com base na data/hora atual - 24 horas
                final DateTime now = DateTime.now();
                filteredRequests = filteredRequests.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final tipoSolicitacao = data['tipoSolicitacao'] ?? '';
                  if (tipoSolicitacao == 'Reunião') {
                    final Timestamp? ts = data['dataReuniao'];
                    if (ts != null) {
                      final dateReuniao = ts.toDate();
                      if (now.difference(dateReuniao).inHours >= 24) {
                        return false;
                      }
                    }
                  } else if (tipoSolicitacao == 'Gravação') {
                    final Timestamp? tsFim = data['dataGravacaoFim'];
                    if (tsFim != null) {
                      final dateGravacaoFim = tsFim.toDate();
                      if (now.difference(dateGravacaoFim).inHours >= 24) {
                        return false;
                      }
                    }
                  }
                  return true;
                }).toList();

                return Column(
                  children: [
                    // Filtros (apenas para usuários especiais)
                    if (isSpecialUser)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                        child: Row(
                          children: [
                            // Filtro por tipo de evento
                            Expanded(
                              child: DropdownButtonFormField2<String>(
                                isExpanded: true,
                                value: _selectedEventFilter,
                                dropdownStyleData: const DropdownStyleData(
                                  maxHeight: 200,
                                  direction: DropdownDirection.right,
                                ),
                                items: ["Todos", "Reunião", "Gravação"].map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(
                                      value,
                                      style: const TextStyle(fontFamily: 'Poppins'),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedEventFilter = newValue!;
                                  });
                                },
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                                dropdownStyleData: const DropdownStyleData(
                                  maxHeight: 200,
                                  direction: DropdownDirection.left,
                                ),
                                value: _selectedCompanyFilter,
                                items: distinctCompanies.map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(
                                      value,
                                      style: const TextStyle(fontFamily: 'Poppins'),
                                    ),
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
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                          final requestCompany = requestData['nomeEmpresa'] ?? '';
                          final dataReuniao = requestData['dataReuniao'] != null
                              ? (requestData['dataReuniao'] as Timestamp).toDate()
                              : null;
                          final dateTime = dataReuniao != null
                              ? DateFormat('dd/MM/yyyy HH:mm').format(dataReuniao)
                              : '';

                          // Tipo de evento (Reunião ou Gravação)
                          final tipoEvento = requestData['tipoEvento'] ?? '';

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Builder(
                                builder: (context) {
                                  final tipoSolicitacao = requestData['tipoSolicitacao'] ?? '';
                                  // Se for Reunião, usa layout de reunião
                                  if (tipoSolicitacao == 'Reunião') {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Chip com o tipo da solicitação
                                        Chip(
                                          backgroundColor: Colors.blue.shade100,
                                          label: Text(
                                            '${tipoSolicitacao}'.toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.blue.shade800,
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: BorderSide(width: 0, color: Colors.transparent),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (isSpecialUser) ...[
                                          FutureBuilder<String?>(
                                            future: _getCompanyPhotoUrl(requestCompany),
                                            builder: (context, snapshotPhoto) {
                                              if (snapshotPhoto.connectionState == ConnectionState.waiting) {
                                                return Row(
                                                  children: [
                                                    const CircleAvatar(
                                                      radius: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                    const SizedBox(width: 8),
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
                                                );
                                              }
                                              if (!snapshotPhoto.hasData || snapshotPhoto.data == null) {
                                                return Row(
                                                  children: [
                                                    const CircleAvatar(
                                                      radius: 16,
                                                      child: Icon(Icons.person),
                                                    ),
                                                    const SizedBox(width: 8),
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
                                                );
                                              }
                                              final photoUrl = snapshotPhoto.data!;
                                              return Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundImage: NetworkImage(photoUrl),
                                                  ),
                                                  const SizedBox(width: 8),
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
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        Text(
                                          motivo,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          assunto,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dateTime,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  // Se for Gravação, usa layout específico para gravação
                                  else if (tipoSolicitacao == 'Gravação') {
                                    // Obtenha os valores necessários
                                    final descricao = requestData['descricao'] ?? '';
                                    final precisaRoteiro = (requestData['precisaRoteiro'] ?? false) ? "Sim" : "Não";
                                    final local = requestData['local']; // Deve ser um GeoPoint
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Chip no topo com o tipo de solicitação
                                        Chip(
                                          backgroundColor: Theme.of(context).colorScheme.onInverseSurface,
                                          label: Text(
                                            '${tipoSolicitacao}'.toUpperCase(),
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: BorderSide(width: 0, color: Colors.transparent),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (isSpecialUser) ...[
                                          FutureBuilder<String?>(
                                            future: _getCompanyPhotoUrl(requestCompany),
                                            builder: (context, snapshotPhoto) {
                                              if (snapshotPhoto.connectionState == ConnectionState.waiting) {
                                                return Row(
                                                  children: [
                                                    const CircleAvatar(
                                                      radius: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                    const SizedBox(width: 8),
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
                                                );
                                              }
                                              if (!snapshotPhoto.hasData || snapshotPhoto.data == null) {
                                                return Row(
                                                  children: [
                                                    const CircleAvatar(
                                                      radius: 16,
                                                      child: Icon(Icons.person),
                                                    ),
                                                    const SizedBox(width: 8),
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
                                                );
                                              }
                                              final photoUrl = snapshotPhoto.data!;
                                              return Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundImage: NetworkImage(photoUrl),
                                                  ),
                                                  const SizedBox(width: 8),
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
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        Text(
                                          descricao,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Precisa Roteiro: $precisaRoteiro",
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Container com o mapa
                                        if (local != null && local is GeoPoint)
                                          GestureDetector(
                                            onTap: () {
                                              _launchMaps(local.latitude, local.longitude);
                                            },
                                            child: Container(
                                              height: 150,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: GoogleMap(
                                                  initialCameraPosition: CameraPosition(
                                                    target: LatLng(local.latitude, local.longitude),
                                                    zoom: 15,
                                                  ),
                                                  markers: {
                                                    Marker(
                                                      markerId: const MarkerId('location'),
                                                      position: LatLng(local.latitude, local.longitude),
                                                    ),
                                                  },
                                                  zoomControlsEnabled: false,
                                                  myLocationButtonEnabled: false,
                                                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{}.toSet(),
                                                  // Desabilita toques para que o gesto seja capturado pelo GestureDetector
                                                  onTap: (_) {
                                                    _launchMaps(local.latitude, local.longitude);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  }
                                  // Caso não seja nenhum dos dois, exibe um layout padrão
                                  else {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          motivo,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          assunto,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dateTime,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                },
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
        backgroundColor: Theme.of(context).colorScheme.background,
      ),
    );
  }
}