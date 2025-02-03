// manage_apis.dart
import 'dart:async';

import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/features/screens/apis/add_api.dart';
import 'package:app_io/features/screens/apis/run_api.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ManageApis extends StatefulWidget {
  const ManageApis({super.key});

  @override
  State<ManageApis> createState() => _ManageApisState();
}

class _ManageApisState extends State<ManageApis> {
  bool isLoading = true;
  bool isDevAccount = false;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  // Caso o usuário seja encontrado na coleção "empresas", usaremos esse listener
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _empresaSub;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _empresaSub?.cancel();
    super.dispose();
  }

  void _handleScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  /// Verifica as permissões do usuário:
  /// - Se o documento for encontrado na coleção "users" (com id igual ao UID), o usuário NÃO tem permissão (isDevAccount = false).
  /// - Caso contrário, busca na coleção "empresas" e, se encontrado, utiliza o valor de 'isDevAccount'.
  ///   Se o documento da empresa existir, adiciona um listener para atualizar a permissão instantaneamente.
  Future<void> _checkPermissions() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      if (user == null) return;

      // Referências para as coleções (com conversores, se desejar)
      final usersRef = FirebaseFirestore.instance
          .collection('users')
          .withConverter<Map<String, dynamic>>(
        fromFirestore: (snapshot, _) => snapshot.data()!,
        toFirestore: (model, _) => model,
      );
      final empresasRef = FirebaseFirestore.instance
          .collection('empresas')
          .withConverter<Map<String, dynamic>>(
        fromFirestore: (snapshot, _) => snapshot.data()!,
        toFirestore: (model, _) => model,
      );

      // Primeiro, busca se o documento existe em "users"
      final DocumentSnapshot<Map<String, dynamic>> userDoc =
      await usersRef.doc(user.uid).get();

      if (userDoc.exists) {
        // Encontrado em "users": não tem permissão
        setState(() {
          isDevAccount = false;
          isLoading = false;
        });
      } else {
        // Busca na coleção "empresas"
        final DocumentReference<Map<String, dynamic>> empresaDocRef =
        empresasRef.doc(user.uid);
        final DocumentSnapshot<Map<String, dynamic>> empresaDoc =
        await empresaDocRef.get();

        if (empresaDoc.exists) {
          // Adiciona listener para que alterações em 'isDevAccount' sejam observadas instantaneamente
          _empresaSub = empresaDocRef.snapshots().listen((docSnap) {
            final data = docSnap.data();
            setState(() {
              isDevAccount = data?['isDevAccount'] ?? false;
            });
          });
          // Atualiza o estado inicial (caso já haja dados)
          final empresaData = empresaDoc.data();
          setState(() {
            isDevAccount = empresaData?['isDevAccount'] ?? false;
            isLoading = false;
          });
        } else {
          // Se não for encontrado em nenhuma coleção, assume que não há permissão
          setState(() {
            isDevAccount = false;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
      print('Erro ao verificar permissões: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                                  color:
                                  Theme.of(context).colorScheme.onBackground,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Voltar',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Gerenciar APIs',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Exibe o botão de adicionar API SOMENTE se o usuário tiver permissão (isDevAccount == true)
                      isDevAccount
                          ? IconButton(
                        icon: Icon(
                          Icons.add,
                          color:
                          Theme.of(context).colorScheme.onBackground,
                          size: 30,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => AddApi()),
                          );
                        },
                        tooltip: 'Adicionar API',
                      )
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
              surfaceTintColor: Colors.transparent,
              backgroundColor: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          controller: _scrollController,
          children: [
            // Card sempre visível
            _buildMetaApiInfoCard(context),
            // Exibe o card com os dados do Firestore somente se o usuário tiver permissão
            if (isDevAccount)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('APIs')
                    .snapshots(),
                builder: (context, snapshotStream) {
                  if (snapshotStream.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (snapshotStream.hasError) {
                    return const Center(
                        child: Text('Erro ao carregar APIs.'));
                  }
                  if (!snapshotStream.hasData ||
                      snapshotStream.data == null ||
                      snapshotStream.data!.docs.isEmpty) {
                    return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Nenhuma API encontrada.'),
                        ));
                  }

                  final apis = snapshotStream.data!.docs;
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: apis.length,
                    itemBuilder: (context, index) {
                      final apiDoc = apis[index];
                      final api =
                      apiDoc.data() as Map<String, dynamic>;
                      final apiName = api['name'] ?? 'Sem nome';
                      final description =
                          api['description'] ?? 'Sem descrição';

                      return _buildApiCard(
                        context,
                        apiDoc.id,
                        apiName,
                        description,
                        api,
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaApiInfoCard(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RunApi()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Expanded(
                    child: Text(
                      'API Meta Infos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Outros componentes, se necessário
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'API que carrega as BMs, Contas de Anúncio, Campanhas e Grupos de Anúncio da Meta Ads',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApiCard(BuildContext context, String docId, String name,
      String description, Map<String, dynamic> apiData) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                          Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.edit,
                      color: Theme.of(context).colorScheme.onSecondary,
                      onPressed: () =>
                          _navigateToEditScreen(context, docId, apiData),
                    ),
                    _buildActionButton(
                      icon: Icons.delete,
                      color: Colors.red,
                      onPressed: () => _confirmDelete(context, docId),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
        required Color color,
        required VoidCallback onPressed}) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      splashRadius: 25,
    );
  }

  void _navigateToEditScreen(
      BuildContext context, String docId, Map<String, dynamic> apiData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddApi(
          isEditing: true,
          existingDocId: docId,
          existingData: apiData,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Confirmar exclusão',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSecondary),
        ),
        content: Text(
          'Tem certeza que deseja excluir esta API?',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Excluir',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 16, color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('APIs').doc(docId).delete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API excluída com sucesso!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: ${e.toString()}')),
        );
      }
    }
  }
}