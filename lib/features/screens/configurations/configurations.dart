import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _empresaSub;
  String? userName;
  String? userEmail;
  String? userPhotoUrl; // Nova variável para a URL da foto do usuário
  Map<String, dynamic>? userData;
  String? cnpj;
  String? contract;
  String? role;
  bool notificationsEnabled = true;
  bool isDarkMode = false;
  bool _isLoading = false;
  bool? copiarTelefones;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> campaignDocs = [];

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _listenToUserData();
    _loadPreferences();
    _getUserData(); // Carrega os dados do usuário inicialmente
  }



  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName');
    });
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Primeiro busca o documento na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          userData = userDoc.data();
          userName = userData?['name'] ?? 'Nome não disponível';
          userEmail = user.email;
          role = userData?['role'] ?? 'Função não disponível';
          // Tenta recuperar a foto do usuário
          userPhotoUrl = userData?['photoUrl'];
          copiarTelefones = userData?['copiarTelefones'] ?? false;
        } else {
          // Caso não encontre, busca na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            userData = empresaDoc.data();
            userName = userData?['NomeEmpresa'] ?? 'Nome não disponível';
            userEmail = user.email;
            cnpj = userData?['cnpj'] ?? 'CNPJ não disponível';
            contract = userData?['contract'] ?? 'Contrato não disponível';
            userPhotoUrl = userData?['photoUrl'];
            copiarTelefones = userData?['copiarTelefones'] ?? false;
          } else {
            showErrorDialog(context, 'Usuário não encontrado.', "Atenção");
            return;
          }
        }

        // Atualiza o nome do usuário no SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', userName ?? '');

        setState(() {});
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', "Erro");
      }
    } else {
      showErrorDialog(context, 'Usuário não está autenticado.', "Atenção");
    }
  }

  void _listenToUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Cancela listener antigo, se existir
    _userSub?.cancel();
    _empresaSub?.cancel();

    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;              // ← proteção extra

      if (snap.exists) {
        final data = snap.data();
        setState(() {
          userName  = data?['name'] ?? 'Nome não disponível';
          role      = data?['role'] ?? 'Função não disponível';
          copiarTelefones = data?['copiarTelefones'] ?? false;
        });
        // se já tínhamos um listener em empresas, podemos encerrá-lo
        _empresaSub?.cancel();
        _empresaSub = null;
      } else {
        // Caso não exista em 'users', escuta em 'empresas'
        _empresaSub ??= FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .snapshots()
            .listen((empresaSnap) {
          if (!mounted) return;
          if (empresaSnap.exists) {
            final data = empresaSnap.data();
            setState(() {
              userName  = data?['NomeEmpresa'] ?? 'Nome não disponível';
              cnpj      = data?['cnpj'] ?? 'CNPJ não disponível';
              contract  = data?['contract'] ?? 'Contrato não disponível';
              copiarTelefones = data?['copiarTelefones'] ?? false;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _empresaSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _updatePreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', notificationsEnabled);
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  void _showLogoutConfirmationDialog() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      backgroundColor: Theme.of(context).colorScheme.background,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirmar Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Tem certeza que deseja sair?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancelar',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondary)),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final authProvider =
                          Provider.of<appAuthProvider.AuthProvider>(context,
                              listen: false);
                      await authProvider.signOut();
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: Text('Sair',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationToggle(bool isDesktop) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            "Ativar/Desativar Notificações",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isDesktop ? 20 : 16, // Aumenta para desktop
              color: Theme.of(context).colorScheme.surfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              notificationsEnabled = !notificationsEnabled;
              _updatePreferences();
            });
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 300),
            width: isDesktop ? 110 : 90,
            height: isDesktop ? 55 : 45,
            decoration: BoxDecoration(
              color: notificationsEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onPrimary,
              borderRadius: BorderRadius.circular(isDesktop ? 30 : 25),
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  offset: Offset(0, 4),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: Duration(milliseconds: 300),
                  alignment: notificationsEnabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(
                      notificationsEnabled
                          ? Icons.notifications
                          : Icons.notifications_off,
                      color: notificationsEnabled
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                      size: isDesktop ? 32 : 25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(BuildContext context, String content) {
    Clipboard.setData(ClipboardData(text: content)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Números de telefone copiados para a área de transferência!')),
      );
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao copiar para a área de transferência: $e')),
      );
    });
  }

  void _showCampaignsSheet(BuildContext context, bool isDesktop) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showErrorDialog(context, 'Usuário não autenticado.', 'Erro');
      return;
    }

    String? companyDocId;

    try {
      // Identifica o documento da empresa associado ao usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final createdBy = userDoc.data()?['createdBy'];

        if (createdBy != null) {
          final companyDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(createdBy)
              .get();

          if (companyDoc.exists) {
            companyDocId = createdBy;
            final campaignsSnapshot =
                await companyDoc.reference.collection('campanhas').get();

            // Popula a variável campaignDocs
            setState(() {
              campaignDocs = campaignsSnapshot.docs;
            });
          }
        }
      } else {
        final companyDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (companyDoc.exists) {
          companyDocId = user.uid;
          final campaignsSnapshot =
              await companyDoc.reference.collection('campanhas').get();

          // Popula a variável campaignDocs
          setState(() {
            campaignDocs = campaignsSnapshot.docs;
          });
        }
      }

      if (campaignDocs.isEmpty) {
        showErrorDialog(context, 'Nenhuma campanha encontrada.', 'Atenção');
        return;
      }
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar campanhas: $e', 'Erro');
      return;
    }

    // Exibe o modal após carregar as campanhas
    showModalBottomSheet(
      backgroundColor: Theme.of(context).colorScheme.background,
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        String? selectedCampaign;

        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecione uma Campanha',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isDesktop ? 24 : 20,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  SizedBox(height: isDesktop ? 20 : 16),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedCampaign,
                    hint: Text(
                      'Selecione',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isDesktop ? 18 : 16,
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    items: campaignDocs.map((doc) {
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(
                          doc.data()['nome_campanha'] as String,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isDesktop ? 18 : 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      SchedulerBinding.instance.addPostFrameCallback((_) {
                        setState(() {
                          selectedCampaign = value;
                        });
                      });
                    },
                    dropdownColor: Theme.of(context).colorScheme.background,
                  ),
                  SizedBox(height: isDesktop ? 30 : 20),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        side: BorderSide(
                          color: Colors.transparent,
                          width: 1,
                        ),
                      ),
                      onPressed: selectedCampaign == null
                          ? null
                          : () async {
                              setState(() {
                                _isLoading = true;
                              });
                              try {
                                final selectedDoc = campaignDocs.firstWhere(
                                    (doc) => doc.id == selectedCampaign,
                                    orElse: () => throw Exception(
                                        'Documento não encontrado'));

                                final leadsSnapshot = await selectedDoc
                                    .reference
                                    .collection('leads')
                                    .get();

                                List<String> phones = leadsSnapshot.docs
                                    .map((doc) =>
                                        doc.data()['whatsapp'] as String?)
                                    .where((phone) => phone != null)
                                    .map((phone) => phone!
                                        .replaceAll(RegExp(r'\s|-|👦|👦'), '')
                                        .replaceAll(RegExp(r'^'), '55'))
                                    .toList();

                                if (phones.isEmpty) {
                                  showErrorDialog(
                                      context,
                                      'Nenhum número de telefone encontrado.',
                                      'Atenção');
                                  setState(() {
                                    _isLoading = false;
                                  });
                                  return;
                                }

                                final phonesContent = phones.join('\n');
                                _copyToClipboard(context, phonesContent);
                                Navigator.pop(context);
                              } catch (e) {
                                showErrorDialog(context,
                                    'Erro ao processar campanha: $e', 'Erro');
                              } finally {
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            },
                      child: _isLoading
                          ? SizedBox(
                              width: isDesktop ? 24 : 20,
                              height: isDesktop ? 24 : 20,
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2.0,
                              ),
                            )
                          : Text(
                              'Copiar Telefones',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isDesktop ? 20 : 18,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    return ConnectivityBanner(
      child: Scaffold(
        bottomNavigationBar: isDesktop
            ? null
            : Container(
                color: Theme.of(context).colorScheme.error,
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                child: InkWell(
                  onTap: _showLogoutConfirmationDialog,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.exit_to_app, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
        body: isDesktop
            ? Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: 1850),
                  padding: EdgeInsets.symmetric(horizontal: 50),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar e Nome do Usuário
                        Center(
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 65,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                backgroundImage: userPhotoUrl != null
                                    ? NetworkImage(userPhotoUrl!)
                                    : null,
                                child: userPhotoUrl == null
                                    ? Icon(
                                        Icons.camera_alt,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        size: 50,
                                      )
                                    : null,
                              ),
                              SizedBox(height: 30),
                              Text(
                                '$userName',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceVariant,
                                ),
                              ),
                              SizedBox(height: 30),
                            ],
                          ),
                        ),

                        // Formulário com Labels Separadas
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Campo de Email
                            Text(
                              'Email',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            SizedBox(height: 12),
                            TextField(
                              readOnly: true,
                              enableInteractiveSelection: false,
                              controller: TextEditingController(
                                text: userEmail ?? 'Email não disponível',
                              ),
                              style: TextStyle(
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor:
                                    Theme.of(context).colorScheme.secondary,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            SizedBox(height: 30),

                            // Campo de CNPJ (se existir)
                            if (cnpj != null) ...[
                              Text(
                                'CNPJ',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                readOnly: true,
                                enableInteractiveSelection: false,
                                controller: TextEditingController(
                                    text: cnpj ?? 'CNPJ não disponível'),
                                style: TextStyle(
                                  fontSize: 18,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor:
                                      Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              SizedBox(height: 30),
                              Text(
                                'Final do Contrato',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                readOnly: true,
                                enableInteractiveSelection: false,
                                controller: TextEditingController(
                                    text:
                                        contract ?? 'Contrato não disponível'),
                                style: TextStyle(
                                  fontSize: 18,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor:
                                      Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              SizedBox(height: 30),
                            ],

                            // Campo de Função (se existir)
                            if (role != null) ...[
                              Text(
                                'Função',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                readOnly: true,
                                enableInteractiveSelection: false,
                                controller: TextEditingController(
                                    text: role ?? 'Função não disponível'),
                                style: TextStyle(
                                  fontSize: 18,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor:
                                      Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              SizedBox(height: 30),
                            ],
                            SizedBox(height: 40),
                            _buildNotificationToggle(isDesktop),
                            SizedBox(height: 40),

                            if (copiarTelefones == true)
                              Align(
                                alignment: AlignmentDirectional.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                          0, 0, 20, 0),
                                      child: _isLoading
                                          ? ElevatedButton(
                                              onPressed: null,
                                              style: ElevatedButton.styleFrom(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 35,
                                                  vertical: 20,
                                                ),
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(25),
                                                ),
                                              ),
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    Colors.white,
                                                  ),
                                                  strokeWidth: 2.0,
                                                ),
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showCampaignsSheet(
                                                      context, isDesktop),
                                              icon: Icon(
                                                Icons.copy_all,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline,
                                                size: 30,
                                              ),
                                              label: Text(
                                                'Copiar telefones',
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                padding: EdgeInsetsDirectional
                                                    .fromSTEB(35, 20, 35, 20),
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                elevation: 3,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(25),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.transparent,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _showLogoutConfirmationDialog,
                                      icon: Icon(
                                        Icons.exit_to_app,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        size: 30,
                                      ),
                                      label: Text(
                                        'Logout',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        padding: EdgeInsetsDirectional.fromSTEB(
                                            35, 20, 35, 20),
                                        backgroundColor:
                                            Theme.of(context).colorScheme.error,
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(25),
                                        ),
                                        side: BorderSide(
                                          color: Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: userName == null
                      ? Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar e Nome do Usuário
                            Center(
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 55,
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    backgroundImage: userPhotoUrl != null
                                        ? NetworkImage(userPhotoUrl!)
                                        : null,
                                    child: userPhotoUrl == null
                                        ? Icon(
                                            Icons.camera_alt,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                            size: 40,
                                          )
                                        : null,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    '$userName',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceVariant,
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                ],
                              ),
                            ),

                            // Formulário com Labels Separadas
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Campo de Email
                                Text(
                                  'Email',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                ),
                                SizedBox(height: 8),
                                TextField(
                                  readOnly: true,
                                  enableInteractiveSelection: false,
                                  controller: TextEditingController(
                                    text: userEmail ?? 'Email não disponível',
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).colorScheme.secondary,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),

                                SizedBox(height: 20),

                                // Campo de CNPJ (se existir)
                                if (cnpj != null) ...[
                                  Text(
                                    'CNPJ',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextField(
                                    readOnly: true,
                                    enableInteractiveSelection: false,
                                    controller: TextEditingController(
                                        text: cnpj ?? 'CNPJ não disponível'),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Final do Contrato',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextField(
                                    readOnly: true,
                                    enableInteractiveSelection: false,
                                    controller: TextEditingController(
                                        text: contract ??
                                            'Contrato não disponível'),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                ],

                                // Campo de Função (se existir)
                                if (role != null) ...[
                                  Text(
                                    'Função',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextField(
                                    readOnly: true,
                                    enableInteractiveSelection: false,
                                    controller: TextEditingController(
                                        text: role ?? 'Função não disponível'),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                ],
                                SizedBox(height: 30),
                                _buildNotificationToggle(false),
                                SizedBox(height: 30),
                                // Botão de copiar telefones
                                if (copiarTelefones == true)
                                  Align(
                                    alignment: AlignmentDirectional.center,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Padding(
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  0, 20, 20, 0),
                                          child: _isLoading
                                              ? ElevatedButton(
                                                  onPressed: null,
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 25,
                                                            vertical: 20),
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              25),
                                                    ),
                                                  ),
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        Colors.white,
                                                      ),
                                                      strokeWidth: 2.0,
                                                    ),
                                                  ),
                                                )
                                              : ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _showCampaignsSheet(
                                                          context, false),
                                                  icon: Icon(
                                                    Icons.copy_all,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outline,
                                                    size: 25,
                                                  ),
                                                  label: Text(
                                                    'Copiar telefones',
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      letterSpacing: 0,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .outline,
                                                    ),
                                                  ),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    padding:
                                                        EdgeInsetsDirectional
                                                            .fromSTEB(
                                                                30, 15, 30, 15),
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                    elevation: 3,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              25),
                                                    ),
                                                    side: BorderSide(
                                                      color: Colors.transparent,
                                                      width: 1,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
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
