import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:app_io/features/screens/collaborator/add_collaborators.dart';
import 'package:app_io/features/screens/collaborator/edit_collaborators.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:provider/provider.dart';

class ManageCollaborators extends StatefulWidget {
  @override
  _ManageCollaboratorsState createState() => _ManageCollaboratorsState();
}

class _ManageCollaboratorsState extends State<ManageCollaborators> {
  StreamSubscription<
      DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  bool hasGerenciarColaboradoresAccess = false;
  bool isLoading = true;
  bool _hasShownPermissionRevokedDialog = false;
  final FirestoreService _firestoreService = FirestoreService();
  String? _companyUid;

  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  Stream<List<Map<String, dynamic>>> _getUserCollaborators(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['uid'] = doc.id; // Adiciona o ID do documento (UID) ao map
          return data;
        }).toList());
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
    _determineUserDocumentAndListen();
  }

  void _openEditor(Map<String, dynamic> c) {
    _navigateWithBottomToTopTransition(
      context,
      EditCollaborators(
        collaboratorId: c['uid'] ?? '',
        name: c['name'] ?? '',
        email: c['email'] ?? '',
        role: c['role'] ?? '',
        birth: c['birth'] ?? '',

        // MÓDULOS (defaults compatíveis com a tela de add/editar)
        modChats: c['modChats'] ?? true,
        modIndicadores: c['modIndicadores'] ?? true,
        modPainel: c['modPainel'] ?? false,
        modRelatorios: c['modRelatorios'] ?? false,
        modConfig: c['modConfig'] ?? true,

        // PERMISSÕES INTERNAS (Painel)
        gerenciarParceiros: c['gerenciarParceiros'] ?? false,
        gerenciarColaboradores: c['gerenciarColaboradores'] ?? false,
        configurarDash: c['configurarDash'] ?? false,
        criarForm: c['criarForm'] ?? false,
        criarCampanha: c['criarCampanha'] ?? false,
        gerenciarProdutos:      c['gerenciarProdutos'] ?? false,

        // OUTROS
        leads: c['leads'] ?? false,
        copiarTelefones: c['copiarTelefones'] ?? false,
        executarAPIs: c['executarAPIs'] ?? false,
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'NA';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : first;
    return (first + last).toUpperCase();
  }

  Widget _avatar(Map<String, dynamic> c) {
    final url = (c['photoUrl'] ?? '').toString();
    final hasUrl = url.isNotEmpty;
    return CircleAvatar(
      radius: 30,
      backgroundImage: hasUrl ? NetworkImage(url) : null,
      child: hasUrl ? null : Text(_initials((c['name'] ?? 'N').toString())),
    );
  }

  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // Começa de baixo para cima
          const end = Offset.zero;
          const curve = Curves
              .easeInOut; // Usando easeInOut para uma animação suave

          final tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(
            milliseconds: 300), // Define a duração da animação
      ),
    );
  }

  Future<void> _deleteCollaborator(String uid) async {
    try {
      // Deleta o colaborador do Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // Deleta o colaborador do Firebase Authentication usando uma Cloud Function
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
          'deleteUser');
      await callable.call(<String, dynamic>{
        'uid': uid,
      });

      // Deleta a pasta do colaborador no Firebase Storage
      await _deleteStorageFolder(uid);

      // Notifica o sucesso
      showErrorDialog(context, "Colaborador excluído com sucesso!", "Sucesso");
    } catch (e) {
      print("Erro ao excluir colaborador: $e");
      showErrorDialog(context, "Falha ao excluir colaborador", "Atenção");
    }
  }

  void _showDeleteConfirmationDialog(String uid) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme
            .of(context)
            .primaryColor),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme
                .of(context)
                .colorScheme
                .background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Excluir Colaborador',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .onSecondary,
                ),
              ),
              SizedBox(height: 16.0),
              Text(
                'Você tem certeza que deseja excluir este colaborador? "ESTA AÇÃO NÃO PODE SER DESFEITA!"',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .onSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme
                          .of(context)
                          .colorScheme
                          .primary,
                      padding: EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme
                            .of(context)
                            .colorScheme
                            .outline,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                      _deleteCollaborator(uid); // Excluir o colaborador
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Excluir',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme
                            .of(context)
                            .colorScheme
                            .outline,
                      ),
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

  Future<void> _determineUserDocumentAndListen() async {
    setState(() => isLoading = true);

    final authProvider = Provider.of<appProvider.AuthProvider>(
        context, listen: false);
    final user = authProvider.user;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      // Tenta como empresa
      final empDoc = await FirebaseFirestore.instance.collection('empresas')
          .doc(user.uid)
          .get();
      if (empDoc.exists) {
        setState(() => _companyUid = user.uid);
        _listenToUserDocument('empresas', user.uid);
        return;
      }

      // Tenta como colaborador
      final usrDoc = await FirebaseFirestore.instance.collection('users').doc(
          user.uid).get();
      if (usrDoc.exists) {
        final createdBy = (usrDoc.data()?['createdBy'] ?? '') as String;
        setState(() =>
        _companyUid = createdBy.isNotEmpty ? createdBy : user.uid);
        _listenToUserDocument('users', user.uid);
        return;
      }

      // Nada encontrado
      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
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
        print(
            "Documento do usuário não encontrado na coleção '$collectionName'.");
      }
    });
  }

  void _updatePermissions(DocumentSnapshot<Map<String, dynamic>> userDoc) {
    final userData = userDoc.data();

    if (!mounted) return;

    setState(() {
      hasGerenciarColaboradoresAccess =
          userData?['gerenciarColaboradores'] ?? false;
      isLoading = false;
    });

    if (!hasGerenciarColaboradoresAccess) {
      if (!_hasShownPermissionRevokedDialog) {
        _hasShownPermissionRevokedDialog = true;

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          await showModalBottomSheet(
            context: context,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme
                  .of(context)
                  .primaryColor),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
            ),
            builder: (BuildContext context) {
              return Container(
                padding: EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme
                      .of(context)
                      .colorScheme
                      .background,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20.0)),
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
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onSecondary,
                      ),
                    ),
                    SizedBox(height: 16.0),
                    Text(
                      'Você não tem mais permissão para acessar esta tela.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24.0),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // Fechar o BottomSheet
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme
                            .of(context)
                            .colorScheme
                            .primary,
                        padding: EdgeInsets.symmetric(horizontal: 32,
                            vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      child: Text(
                        'Ok',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: Theme
                              .of(context)
                              .colorScheme
                              .outline,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );

          // Após o diálogo ser fechado, redirecionar o usuário
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CustomTabBarPage()),
            );
          }
        });
      }
    } else {
      _hasShownPermissionRevokedDialog =
      false; // Reseta a flag se a permissão voltar
    }
  }

  Future<void> _deleteStorageFolder(String uid) async {
    final folderRef = FirebaseStorage.instance.ref().child(uid);
    try {
      final listResult = await folderRef.listAll();
      // Apaga cada arquivo encontrado
      for (var item in listResult.items) {
        await item.delete();
      }
      // Se houver subpastas, pode-se iterar sobre elas também (opcional)
      for (var prefix in listResult.prefixes) {
        await _deleteStorageFolder(prefix.fullPath);
      }
    } catch (e) {
      print("Erro ao deletar pasta do Storage para o uid $uid: $e");
      rethrow;
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companyUid = _companyUid;
    final String userId = FirebaseAuth.instance.currentUser?.uid ??
        ''; // Obtém o UID do usuário logado

    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double tabBarHeight = (kBottomNavigationBarHeight - (_scrollOffset / 2))
        .clamp(0.0, kBottomNavigationBarHeight)
        .ceilToDouble();
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    // Definindo a física com base na visibilidade da AppBar e TabBar
    final pageViewPhysics = (appBarHeight > 0 && tabBarHeight > 0)
        ? AlwaysScrollableScrollPhysics()
        : NeverScrollableScrollPhysics();

    // ADICIONADO: Verifica se é Desktop
    final bool isDesktop = MediaQuery
        .of(context)
        .size
        .width > 1024; // <-- ADICIONADO

    return ConnectivityBanner(
      child: GestureDetector(
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
                                    color: Theme
                                        .of(context)
                                        .colorScheme
                                        .onBackground,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Voltar',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: Theme
                                          .of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Gerenciar Colaboradores',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Theme
                                    .of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                          ],
                        ),
                        // Stack na direita
                        Stack(
                          children: [
                            IconButton(
                              icon: Icon(Icons.person_add_alt_1_sharp,
                                  color: Theme
                                      .of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 30),
                              onPressed: () async {
                                _navigateWithBottomToTopTransition(
                                    context, AddCollaborators());
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                surfaceTintColor: Colors.transparent,
                backgroundColor: Theme
                    .of(context)
                    .colorScheme
                    .secondary,
              ),
            ),
          ),
          // ADICIONADO: Envolvemos o SafeArea em um Container com maxWidth no modo desktop
          body: isDesktop
              ? Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 1850),
              child: SafeArea(
                top: true,
                child: (companyUid == null)
                    ? Center(child: CircularProgressIndicator())
                    : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _getUserCollaborators(companyUid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(
                          'Erro ao carregar colaboradores: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(child: Text(
                          'Nenhum colaborador encontrado'));
                    }

                    final collaborators = snapshot.data!;
                    return ListView.builder(
                      controller: _scrollController,
                      physics: pageViewPhysics,
                      itemCount: collaborators.length,
                      itemBuilder: (context, index) {
                        final collaborator = collaborators[index];
                        return Card(
                          elevation: 4,
                          margin: EdgeInsets.only(top: 20, right: 15, left: 15),
                          // Aumentando a altura do ListTile
                          child: ListTile(
                            leading: _avatar(collaborator),
                            // ADICIONADO: aumenta o padding interno
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 20.0),
                            title: Text(
                              collaborator['name'] ?? 'Nome não disponível',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme
                                    .of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                            subtitle: Text(
                              collaborator['role'] ?? 'Cargo não disponível',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                color: Theme
                                    .of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme
                                      .of(context)
                                      .colorScheme
                                      .onSecondary),
                                  onPressed: () => _openEditor(collaborator),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    _showDeleteConfirmationDialog(
                                        collaborator['uid'] ?? '');
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          )
              : SafeArea(
            top: true,
            child: (companyUid == null)
                ? Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _getUserCollaborators(companyUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(
                      'Erro ao carregar colaboradores: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('Nenhum colaborador encontrado'));
                }

                final collaborators = snapshot.data!;
                return ListView.builder(
                  controller: _scrollController,
                  physics: pageViewPhysics,
                  itemCount: collaborators.length,
                  itemBuilder: (context, index) {
                    final collaborator = collaborators[index];
                    return Card(
                      elevation: 4,
                      margin: EdgeInsets.only(top: 20),
                      child: ListTile(
                        leading: _avatar(collaborator),
                        title: Text(
                          collaborator['name'] ?? 'Nome não disponível',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Theme
                                .of(context)
                                .colorScheme
                                .onSecondary,
                          ),
                        ),
                        subtitle: Text(
                          collaborator['role'] ?? 'Cargo não disponível',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            color: Theme
                                .of(context)
                                .colorScheme
                                .onSecondary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: Theme
                                  .of(context)
                                  .colorScheme
                                  .onSecondary),
                              onPressed: () => _openEditor(collaborator),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                _showDeleteConfirmationDialog(
                                    collaborator['uid'] ?? '');
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}