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
  String? userName;
  String? userEmail;
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

          // Busca a permissão de 'copiarTelefones'
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

            // Busca a permissão de 'copiarTelefones'
            copiarTelefones = userData?['copiarTelefones'] ?? false;
          } else {
            showErrorDialog(context, 'Usuário não encontrado.', "Atenção");
            return;
          }
        }

        // Atualiza o nome do usuário no SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', userName ?? '');

        // Atualiza o estado da tela
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

    if (user != null) {
      // Escuta as mudanças no documento do usuário na coleção 'users'
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((userSnapshot) async {
        if (userSnapshot.exists) {
          final userData = userSnapshot.data();
          setState(() {
            userName = userData?['name'] ?? 'Nome não disponível';
            userEmail = user.email;
            role = userData?['role'] ?? 'Função não disponível';
            copiarTelefones = userData?['copiarTelefones'] ?? false;
          });
        } else {
          // Caso não esteja em 'users', escuta o documento na coleção 'empresas'
          FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .snapshots()
              .listen((empresaSnapshot) {
            if (empresaSnapshot.exists) {
              final empresaData = empresaSnapshot.data();
              setState(() {
                userName = empresaData?['NomeEmpresa'] ?? 'Nome não disponível';
                userEmail = user.email;
                cnpj = empresaData?['cnpj'] ?? 'CNPJ não disponível';
                contract = empresaData?['contract'] ?? 'Contrato não disponível';
                copiarTelefones = empresaData?['copiarTelefones'] ?? false;
              });
            } else {
              setState(() {
                copiarTelefones = false; // Revoga a permissão
              });
            }
          });
        }
      });
    }
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
                        backgroundColor: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            "Ativar/Desativar Notificações",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
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
            width: 90,
            height: 45,
            decoration: BoxDecoration(
              color: notificationsEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onPrimary,
              borderRadius: BorderRadius.circular(25),
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
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: Icon(
                      notificationsEnabled
                          ? Icons.notifications
                          : Icons.notifications_off,
                      color: notificationsEnabled
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                      size: 30,
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
        SnackBar(content: Text('Números de telefone copiados para a área de transferência!')),
      );
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao copiar para a área de transferência: $e')),
      );
    });
  }

  void _showCampaignsSheet(BuildContext context) async {
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

            // Popula a variável `campaignDocs`
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

          // Popula a variável `campaignDocs`
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
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedCampaign,
                    hint: Text(
                      'Selecione',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
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
                            fontSize: 16,
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
                  SizedBox(height: 20),
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
                        try {
                          final selectedDoc = campaignDocs.firstWhere(
                                  (doc) => doc.id == selectedCampaign,
                              orElse: () => throw Exception(
                                  'Documento não encontrado'));

                          final leadsSnapshot = await selectedDoc.reference
                              .collection('leads')
                              .get();

                          List<String> phones = leadsSnapshot.docs
                              .map((doc) =>
                          doc.data()['whatsapp'] as String?)
                              .where((phone) => phone != null)
                              .map((phone) => phone!
                              .replaceAll(RegExp(r'\s|-|\(|\)'), '')
                              .replaceAll(RegExp(r'^'), '55'))
                              .toList();

                          if (phones.isEmpty) {
                            showErrorDialog(context,
                                'Nenhum número de telefone encontrado.', 'Atenção');
                            return;
                          }

                          final phonesContent = phones.join('\n');
                          _copyToClipboard(context, phonesContent);
                          Navigator.pop(context);
                        } catch (e) {
                          showErrorDialog(context,
                              'Erro ao processar campanha: $e', 'Erro');
                        }
                      },
                      child: Text(
                        'Copiar Telefones',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
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
    return ConnectivityBanner(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: userName == null
                  ? CircularProgressIndicator()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(
                            Icons.camera_alt,
                            color: Theme.of(context).colorScheme.outline,
                            size: 40,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          '$userName',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextField(
                          readOnly: true,
                          enableInteractiveSelection: false,
                          controller: TextEditingController(
                              text: userEmail ?? 'Email não disponível'),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        if (cnpj != null) ...[
                          TextField(
                            readOnly: true,
                            controller: TextEditingController(
                                text: cnpj ?? 'CNPJ não disponível'),
                            decoration: InputDecoration(
                              labelText: 'CNPJ',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                              border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                              focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10)
                            ),
                            ),
                          ),
                          SizedBox(height: 20),
                          TextField(
                            readOnly: true,
                            enableInteractiveSelection: false,
                            controller: TextEditingController(
                                text: contract ?? 'Contrato não disponível'),
                            decoration: InputDecoration(
                              labelText: 'Final do contrato',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                        ],
                        if (role != null) ...[
                          TextField(
                            readOnly: true,
                            enableInteractiveSelection: false,
                            controller: TextEditingController(
                                text: role ?? 'Função não disponível'),
                            decoration: InputDecoration(
                              labelText: 'Função',
                              labelStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(10)
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: 30),
                        _buildNotificationToggle(),
                        SizedBox(height: 30),
                        if (copiarTelefones == true)
                          Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional(0, 0),
                                  child: Padding(
                                    padding:
                                    EdgeInsetsDirectional.fromSTEB(0, 20, 20, 0),
                                    child:
                                    _isLoading // Exibe a barra de progresso se estiver carregando
                                        ? ElevatedButton(
                                      onPressed: null,
                                      // Botão desabilitado durante o carregamento
                                      style: ElevatedButton.styleFrom(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 25, vertical: 15),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(25),
                                        ),
                                      ),
                                      child: SizedBox(
                                        width: 20,
                                        height:
                                        20, // Define o tamanho da ProgressBar
                                        child: CircularProgressIndicator(
                                          valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                          strokeWidth: 2.0,
                                        ),
                                      ),
                                    )
                                        : ElevatedButton.icon(
                                      onPressed: () => _showCampaignsSheet(context),
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
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        padding:
                                        EdgeInsetsDirectional.fromSTEB(
                                            30, 15, 30, 15),
                                        backgroundColor: Theme.of(context)
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
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
          ],
        ),
      ),
    );
  }
}
