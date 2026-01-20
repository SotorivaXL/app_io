import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'add_product.dart';
import 'edit_product.dart';

class ManageProducts extends StatefulWidget {
  const ManageProducts({Key? key}) : super(key: key);

  @override
  State<ManageProducts> createState() => _ManageProductsState();
}

class _ManageProductsState extends State<ManageProducts> {
  /* ───────- permissões dinâmicas ─────── */
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool hasGerenciarProdutos = false;
  bool _hasDialog = false;
  bool _loading = true;
  bool _loadingPerm   = true;   // aguardando stream de permissão
  bool _loadingCompId = true;   // aguardando resolver companyId
  String? _companyId;

  /* ───────- scroll p/ app-bar colapsável ─────── */
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _listenPermission();
    _resolveCompanyId();
  }

  void _listenPermission() async {
    final uid = context.read<AuthProvider>().user?.uid;

    // Evita loading infinito caso o uid ainda não esteja pronto:
    if (uid == null) {
      if (mounted) setState(() => _loadingPerm = false);
      return;
    }

    try {
      // Descobre onde está o doc do usuário (igual ao painel)
      final empDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(uid)
          .get();

      final String coll = empDoc.exists ? 'empresas' : 'users';

      _sub?.cancel();
      _sub = FirebaseFirestore.instance
          .collection(coll)
          .doc(uid)
          .snapshots()
          .listen((snap) {
        final ok = (snap.data()?['gerenciarProdutos'] ?? false) as bool;
        if (!mounted) return;
        setState(() {
          hasGerenciarProdutos = ok;
          _loadingPerm = false; // ✅ permissão resolvida
        });

        if (!ok && !_hasDialog) {
          _hasDialog = true;
          _showRevokedDialog();
        }
      }, onError: (_) {
        if (!mounted) return;
        setState(() => _loadingPerm = false);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPerm = false);
    }
  }

  Future<void> _resolveCompanyId() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;

    // 1. se UID é ele mesmo uma empresa
    final emp = await FirebaseFirestore.instance
        .collection('empresas').doc(uid).get();

    if (emp.exists) {
      _companyId = uid;
    } else {
      // 2. pega "createdBy" no doc do usuário
      final usr  = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final data = usr.data() ?? {};
      _companyId = (data['createdBy'] as String?)?.isNotEmpty == true
          ? data['createdBy'] as String
          : uid;
    }

    if (mounted) setState(() => _loadingCompId = false); // ✅ id resolvido
  }

  /* ───────- diálogo permissão removida ─────── */
  void _showRevokedDialog() async {
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side : BorderSide(color: Theme.of(context).primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SimpleBottom(
        title : 'Permissão Revogada',
        text  : 'Você não tem mais permissão para acessar esta tela.',
      ),
    );
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CustomTabBarPage()),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /* ───────- excluir produto ─────── */
  void _askDelete(String productId) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side : BorderSide(color: Theme.of(context).primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ConfirmBottom(
        onDelete: () async {
          Navigator.pop(context);
          try {
            await FirebaseFirestore.instance
                .collection('empresas')
                .doc(_companyId)
                .collection('produtos')
                .doc(productId)
                .delete();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Produto excluído com sucesso!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao excluir produto!'),
                behavior: SnackBarBehavior.floating,   // igual ao padrão que você já usa
              ),
            );
          }
        },
      ),
    );
  }

  /* ───────- animação push - bottom→top ─────── */
  void _pushSlide(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            SlideTransition(
              position: Tween(
                begin: const Offset(0, 1), end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.ease)),
              child: child,
            ),
      ),
    );
  }

  /* ───────- build ─────── */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final desktop = MediaQuery.of(context).size.width > 1024;

    if (_loadingPerm || _loadingCompId) {
      return ConnectivityBanner(
        child: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!hasGerenciarProdutos) {
      return ConnectivityBanner(child: const Scaffold());
    }

    return ConnectivityBanner(
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final double h = (100 - (_controller.hasClients ? _controller.offset / 2 : 0))
                  .clamp(56.0, 100.0)
                  .toDouble();
              return AppBar(
                toolbarHeight: h,
                automaticallyImplyLeading: false,
                backgroundColor: cs.secondary,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal:16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ← voltar + título
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:[
                            InkWell(
                              onTap: () => Navigator.pop(context),
                              child: Row(
                                children: [
                                  Icon(Icons.arrow_back_ios_new,size:18,color:cs.onBackground),
                                  const SizedBox(width:4),
                                  Text('Voltar',style: TextStyle(color:cs.onSecondary,fontSize:14)),
                                ],
                              ),
                            ),
                            const SizedBox(height:8),
                            Text('Produtos',style: TextStyle(
                                fontSize:22,fontWeight:FontWeight.w700,color:cs.onSecondary)),
                          ],
                        ),
                        // botão “+”
                        IconButton(
                          icon: Icon(Icons.add_box_outlined,color:cs.onBackground,size:30),
                          onPressed: () => _pushSlide(const AddProduct()),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        body: desktop
            ? Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1850),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.only(top: 35),
                child: // DESKTOP
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('empresas')
                      .doc(_companyId!)
                      .collection('produtos')
                  // opcional: ordena por createdAt se existir
                  // .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(child: Text('Nenhum produto cadastrado'));
                    }

                    return ListView.builder(
                      controller: _controller,
                      padding: const EdgeInsets.only(top: 20, left: 10, right: 10),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d     = docs[i];
                        final data  = d.data(); // Map<String, dynamic>

                        // ✅ Leitura segura (não lança se o campo não existir)
                        final nome      = (data['nome']      as String?) ?? '—';
                        final descricao = (data['descricao'] as String?) ?? '';
                        final url       = (data['foto']      as String?) ?? '';
                        final tipo      = (data['tipo']      as String?) ?? '—';

                        return Card(
                          color: cs.secondary,
                          margin: const EdgeInsets.only(bottom: 20),
                          elevation: 4,
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 30,
                              backgroundColor: cs.tertiary.withOpacity(.2),
                              backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
                              child: url.isEmpty
                                  ? Icon(Icons.image_not_supported, color: cs.tertiary, size: 30)
                                  : null,
                            ),
                            title: Text(
                              nome,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSecondary),
                            ),
                            subtitle: descricao.isNotEmpty
                                ? Text(
                              descricao,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: cs.onSecondary.withOpacity(.8)),
                            )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: cs.onSecondary, size: 30),
                                  onPressed: () => _pushSlide(
                                    EditProduct(
                                      prodId: d.id,
                                      data: data, // já é Map<String, dynamic>
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _askDelete(d.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                )
              ),
            ),
          ),
        )
            : // MOBILE
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('empresas')
              .doc(_companyId!)
              .collection('produtos')
          // .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text('Nenhum produto cadastrado'));
            }

            return ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.only(top: 20, left: 10, right: 10),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final d     = docs[i];
                final data  = d.data();

                final nome      = (data['nome']      as String?) ?? '—';
                final descricao = (data['descricao'] as String?) ?? '';
                final url       = (data['foto']      as String?) ?? '';
                final tipo      = (data['tipo']      as String?) ?? '—';

                return Card(
                  color: cs.secondary,
                  margin: const EdgeInsets.only(bottom: 20),
                  elevation: 4,
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: cs.tertiary.withOpacity(.2),
                      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
                      child: url.isEmpty
                          ? Icon(Icons.image_not_supported, color: cs.tertiary, size: 24)
                          : null,
                    ),
                    title: Text(
                      nome,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSecondary),
                    ),
                    subtitle: descricao.isNotEmpty
                        ? Text(
                      descricao,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSecondary.withOpacity(.8)),
                    )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: cs.onSecondary, size: 24),
                          onPressed: () => _pushSlide(
                            EditProduct(
                              prodId: d.id,
                              data: data,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _askDelete(d.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        )
      ),
    );
  }
}

/*──────────────── helpers (diálogos simples) ────────────────*/
class _SimpleBottom extends StatelessWidget {
  final String title, text;
  const _SimpleBottom({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,style: TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:cs.onSecondary)),
          const SizedBox(height:16),
          Text(text,textAlign:TextAlign.center,
              style: TextStyle(fontSize:16,color:cs.onSecondary)),
          const SizedBox(height:24),
          ElevatedButton(
            onPressed: ()=>Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal:32,vertical:12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('Ok',style: TextStyle(color:cs.outline)),
          ),
        ],
      ),
    );
  }
}

class _ConfirmBottom extends StatelessWidget {
  final VoidCallback onDelete;
  const _ConfirmBottom({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Excluir Produto',
              style: TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:cs.onSecondary)),
          const SizedBox(height:16),
          Text('Tem certeza? ESTA AÇÃO NÃO PODE SER DESFEITA!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize:16,color:cs.onSecondary)),
          const SizedBox(height:24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: ()=>Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal:32,vertical:12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Cancelar',style: TextStyle(color:cs.outline)),
              ),
              ElevatedButton(
                onPressed: onDelete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal:32,vertical:12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Excluir',style: TextStyle(color:Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}