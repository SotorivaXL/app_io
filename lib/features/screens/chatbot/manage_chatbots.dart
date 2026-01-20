// lib/features/screens/chatbot/manage_chatbots.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'create_chatbot_funnel.dart';
import 'view_chatbot_funnel.dart';

class ManageChatbotsPage extends StatefulWidget {
  const ManageChatbotsPage({super.key});

  @override
  State<ManageChatbotsPage> createState() => _ManageChatbotsPageState();
}

class _ManageChatbotsPageState extends State<ManageChatbotsPage> {
  String? _empresaId;
  String? _selectedPhoneId;
  bool _resolving = true;
  String? _resolveError;

  // para AppBar no estilo da tela de colaboradores
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  StreamSubscription? _userDocSub;

  @override
  void initState() {
    super.initState();
    _resolveEmpresaId();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _goToViewBot({
    required String empresaId,
    required String botId,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewChatbotFunnelPage(
          empresaId: empresaId,
          botId: botId,
        ),
      ),
    );
  }

  Future<void> _resolveEmpresaId() async {
    setState(() {
      _resolving = true;
      _resolveError = null;
    });

    try {
      final authProvider =
      mounted ? Provider.of<AuthProvider>(context, listen: false) : null;
      final User? user = authProvider?.user ?? FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          _resolveError = 'Usuário não autenticado.';
          _resolving = false;
        });
        return;
      }

      final uid = user.uid;

      // 1) Tenta "empresas/{uid}"
      final empDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(uid)
          .get();

      if (empDoc.exists) {
        setState(() {
          _empresaId = uid;
          _resolving = false;
        });
        return;
      }

      // 2) Tenta "users/{uid}" e pega createdBy
      final usrDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (usrDoc.exists) {
        final data =
        (usrDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final createdBy = data['createdBy']?.toString();
        if (createdBy == null || createdBy.isEmpty) {
          setState(() {
            _resolveError =
            'Documento do usuário encontrado, mas sem "createdBy".';
            _resolving = false;
          });
          return;
        }
        setState(() {
          _empresaId = createdBy;
          _resolving = false;
        });
        return;
      }

      setState(() {
        _resolveError =
        'Documento não encontrado em "empresas" nem em "users".';
        _resolving = false;
      });
    } catch (e) {
      setState(() {
        _resolveError = 'Falha ao resolver empresaId: $e';
        _resolving = false;
      });
    }
  }

  Future<void> _showNotice({
    required String title,
    required String message,
    String buttonText = 'Ok',
  }) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (_) {
        final cs = theme.colorScheme;
        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondary,
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: cs.onSecondary,
                ),
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: cs.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Sheet de confirmação com 2 botões (Cancelar/Confirmar).
  Future<bool> _showConfirmSheet({
    required String title,
    required String message,
    String cancelText = 'Cancelar',
    String confirmText = 'Excluir',
  }) async {
    if (!mounted) return false;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bool? res = await showModalBottomSheet<bool>(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondary,
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: cs.onSecondary,
                ),
              ),
              const SizedBox(height: 24.0),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      child: Text(
                        cancelText,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: cs.onSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      child: Text(
                        confirmText,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: cs.outline,
                        ),
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

    return res == true;
  }

  Future<void> _activateBot({
    required String empresaId,
    required String phoneId,
    required String botId,
  }) async {
    final phoneRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    await phoneRef.set({
      'chatbot': {
        'enabled': true,
        'botId': botId,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      }
    }, SetOptions(merge: true));
  }

  Future<void> _deactivateBot({
    required String empresaId,
    required String phoneId,
  }) async {
    final phoneRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    await phoneRef.set({
      'chatbot': {
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      // Remove o botId quando desativar
      'chatbot.botId': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  void _goToCreateBot() {
    Navigator.of(context).pushNamed('/chatbots/create');
  }

  void _goToEditBot({
    required String empresaId,
    required String botId,
  }) {
    if (!kIsWeb) {
      _showNotice(
        title: 'Edição indisponível',
        message: 'A edição de chatbots está disponível apenas na versão Web.',
        buttonText: 'Ok',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateChatbotFunnelPage(chatbotId: botId),
      ),
    );
  }

  Future<void> _deleteBot({
    required String empresaId,
    required String botId,
    required String botName,
  }) async {
    final confirmed = await _showConfirmSheet(
      title: 'Excluir chatbot',
      message:
      'Tem certeza que deseja excluir o chatbot "$botName"? Esta ação não pode ser desfeita.',
      cancelText: 'Cancelar',
      confirmText: 'Excluir',
    );

    if (!confirmed) return;

    try {
      // Se o bot estiver ativo no phone selecionado, desativa antes
      if (_selectedPhoneId != null) {
        final phoneRef = FirebaseFirestore.instance
            .collection('empresas')
            .doc(empresaId)
            .collection('phones')
            .doc(_selectedPhoneId!);

        final phoneDoc = await phoneRef.get();
        final chatbotCfg = ((phoneDoc.data() ?? const {})['chatbot'] as Map?)
            ?.cast<String, dynamic>() ??
            {};
        final bool enabled = chatbotCfg['enabled'] == true;
        final String? activeBotId = chatbotCfg['botId']?.toString();

        if (enabled && activeBotId == botId) {
          await phoneRef.set({
            'chatbot': {
              'enabled': false,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': FirebaseAuth.instance.currentUser?.uid,
            },
            'chatbot.botId': FieldValue.delete(),
          }, SetOptions(merge: true));
        }
      }

      // Exclui o chatbot
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('chatbots')
          .doc(botId)
          .delete();

      if (!mounted) return;
      await _showNotice(
        title: 'Chatbot excluído',
        message: 'Chatbot "$botName" excluído com sucesso.',
        buttonText: 'Ok',
      );
    } catch (e) {
      if (!mounted) return;
      await _showNotice(
        title: 'Erro ao excluir',
        message: 'Falha ao excluir: $e',
        buttonText: 'Fechar',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // AppBar estilo "colaboradores"
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    // ▼▼▼ SOMENTE DESKTOP: largura máx. 1500, padding laterais 16, padding-top 35
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    Widget desktopWrap(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.only(top: 35),
            child: child,
          ),
        ),
      ),
    );
    // ▲▲▲

    if (_resolving) {
      return Scaffold(
        appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
        body: isDesktop
            ? desktopWrap(const Center(child: CircularProgressIndicator()))
            : const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolveError != null) {
      return Scaffold(
        appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
        body: isDesktop
            ? desktopWrap(
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _resolveError!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        )
            : Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _resolveError!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final empresaId = _empresaId!;
    return Scaffold(
      appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
      body: isDesktop
          ? desktopWrap(
        // mesma estrutura original, apenas envolvida pelo wrapper
        Column(
          children: [
            _PhonesSelector(
              empresaId: empresaId,
              selectedPhoneId: _selectedPhoneId,
              onChanged: (phoneId) {
                setState(() => _selectedPhoneId = phoneId);
              },
            ),
            const SizedBox(height: 16),
            if (_selectedPhoneId == null)
              const _EmptyHint(
                icon: Icons.phone_android,
                text:
                'Selecione um número (phone) para gerenciar qual chatbot ficará ativo.',
              )
            else
              Expanded(
                child: _ChatbotsList(
                  empresaId: empresaId,
                  phoneId: _selectedPhoneId!,
                  scrollController:
                  _scrollController, // ← faz a AppBar reagir
                  onActivate: (botId) async {
                    try {
                      await _activateBot(
                        empresaId: empresaId,
                        phoneId: _selectedPhoneId!,
                        botId: botId,
                      );
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Chatbot ativado',
                        message: 'Chatbot ativado para este número.',
                        buttonText: 'Ok',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Erro ao ativar',
                        message: 'Falha ao ativar chatbot: $e',
                        buttonText: 'Fechar',
                      );
                    }
                  },
                  onDeactivate: () async {
                    try {
                      await _deactivateBot(
                        empresaId: empresaId,
                        phoneId: _selectedPhoneId!,
                      );
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Chatbot desativado',
                        message: 'Chatbot desativado para este número.',
                        buttonText: 'Ok',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Erro ao desativar',
                        message: 'Falha ao desativar chatbot: $e',
                        buttonText: 'Fechar',
                      );
                    }
                  },
                  onCreateBot: _goToCreateBot,
                  onEditBot: (botId) =>
                      _goToEditBot(empresaId: empresaId, botId: botId),
                  onDeleteBot: (botId, botName) => _deleteBot(
                    empresaId: empresaId,
                    botId: botId,
                    botName: botName,
                  ),
                  onViewBot: (botId) =>
                      _goToViewBot(empresaId: empresaId, botId: botId),
                ),
              ),
          ],
        ),
      )
          : Padding(
        // MOBILE mantém exatamente a estrutura original
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _PhonesSelector(
              empresaId: empresaId,
              selectedPhoneId: _selectedPhoneId,
              onChanged: (phoneId) {
                setState(() => _selectedPhoneId = phoneId);
              },
            ),
            const SizedBox(height: 16),
            if (_selectedPhoneId == null)
              const _EmptyHint(
                icon: Icons.phone_android,
                text:
                'Selecione um número (phone) para gerenciar qual chatbot ficará ativo.',
              )
            else
              Expanded(
                child: _ChatbotsList(
                  empresaId: empresaId,
                  phoneId: _selectedPhoneId!,
                  scrollController:
                  _scrollController, // ← faz a AppBar reagir
                  onActivate: (botId) async {
                    try {
                      await _activateBot(
                        empresaId: empresaId,
                        phoneId: _selectedPhoneId!,
                        botId: botId,
                      );
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Chatbot ativado',
                        message: 'Chatbot ativado para este número.',
                        buttonText: 'Ok',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Erro ao ativar',
                        message: 'Falha ao ativar chatbot: $e',
                        buttonText: 'Fechar',
                      );
                    }
                  },
                  onDeactivate: () async {
                    try {
                      await _deactivateBot(
                        empresaId: empresaId,
                        phoneId: _selectedPhoneId!,
                      );
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Chatbot desativado',
                        message: 'Chatbot desativado para este número.',
                        buttonText: 'Ok',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      await _showNotice(
                        title: 'Erro ao desativar',
                        message: 'Falha ao desativar chatbot: $e',
                        buttonText: 'Fechar',
                      );
                    }
                  },
                  onCreateBot: _goToCreateBot,
                  onEditBot: (botId) =>
                      _goToEditBot(empresaId: empresaId, botId: botId),
                  onDeleteBot: (botId, botName) => _deleteBot(
                    empresaId: empresaId,
                    botId: botId,
                    botName: botName,
                  ),
                  onViewBot: (botId) =>
                      _goToViewBot(empresaId: empresaId, botId: botId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildStyledAppBar(
      double appBarHeight, double opacity, ColorScheme cs) {
    return PreferredSize(
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
                  // botão voltar + título
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new,
                                color: cs.onBackground, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              'Voltar',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: cs.onSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gerenciar Chatbots',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSecondary,
                        ),
                      ),
                    ],
                  ),
                  // ação à direita
                  if (kIsWeb)
                    IconButton(
                      tooltip: 'Criar chatbot',
                      icon: Icon(Icons.add, color: cs.onBackground, size: 30),
                      onPressed: _goToCreateBot,
                    ),
                ],
              ),
            ),
          ),
          surfaceTintColor: Colors.transparent,
          backgroundColor: cs.secondary,
        ),
      ),
    );
  }
}

class _PhonesSelector extends StatelessWidget {
  const _PhonesSelector({
    required this.empresaId,
    required this.selectedPhoneId,
    required this.onChanged,
  });

  final String empresaId;
  final String? selectedPhoneId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('phones')
          .orderBy(FieldPath.documentId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Row(
            children: const [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Carregando números...'),
            ],
          );
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const _EmptyHint(
            icon: Icons.phonelink_erase,
            text:
            'Nenhum número cadastrado. Adicione um em Configurações > WhatsApp.',
          );
        }

        final items = snap.data!.docs.map((d) {
          final data =
          (d.data()..removeWhere((_, __) => false)).cast<String, dynamic>();
          final label = (data['label'] ?? data['phoneId'] ?? d.id).toString();
          return DropdownMenuItem<String>(
            value: d.id,
            child: Text(label),
          );
        }).toList();

        final effectiveSelected =
            selectedPhoneId ?? (items.isNotEmpty ? items.first.value : null);

        if (effectiveSelected != selectedPhoneId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onChanged(effectiveSelected);
          });
        }

        // === Select com o mesmo estilo do UsersTab (DropdownButton2) ===
        return DropdownButton2<String>(
          isExpanded: true,
          value: effectiveSelected,
          items: items,
          onChanged: onChanged,

          // botão
          buttonStyleData: ButtonStyleData(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // menu
          dropdownStyleData: DropdownStyleData(
            offset: const Offset(0, 4),
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  color: cs.shadow.withOpacity(.05),
                )
              ],
            ),
          ),

          underline: const SizedBox.shrink(),
          iconStyleData: const IconStyleData(
            iconEnabledColor: Colors.grey,
          ),
        );
      },
    );
  }
}

class _ChatbotsList extends StatelessWidget {
  const _ChatbotsList({
    required this.empresaId,
    required this.phoneId,
    required this.onActivate,
    required this.onDeactivate,
    required this.onCreateBot,
    required this.onEditBot,
    required this.onDeleteBot,
    required this.onViewBot,
    this.scrollController,
  });

  final void Function(String) onViewBot;
  final String empresaId;
  final String phoneId;
  final Future<void> Function(String) onActivate;
  final Future<void> Function() onDeactivate;
  final VoidCallback onCreateBot;
  final void Function(String) onEditBot;
  final Future<void> Function(String botId, String botName) onDeleteBot;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final phoneDocRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    final botsColRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('chatbots')
        .orderBy(FieldPath.documentId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: phoneDocRef.snapshots(),
      builder: (context, phoneSnap) {
        if (phoneSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!phoneSnap.hasData || !(phoneSnap.data?.exists ?? false)) {
          return const _EmptyHint(
            icon: Icons.sms_failed_outlined,
            text: 'Phone não encontrado ou sem dados.',
          );
        }

        final Map<String, dynamic> phoneData =
        (phoneSnap.data!.data() ?? <String, dynamic>{})
            .cast<String, dynamic>();

        final Map<String, dynamic> chatbotCfg =
            (phoneData['chatbot'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};

        final bool enabled = chatbotCfg['enabled'] == true;
        final String? activeBotId = chatbotCfg['botId']?.toString();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: botsColRef.snapshots(),
          builder: (context, botsSnap) {
            if (botsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!botsSnap.hasData || botsSnap.data!.docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _EmptyHint(
                        icon: Icons.smart_toy_outlined,
                        text: 'Nenhum chatbot cadastrado ainda.',
                      ),
                      const SizedBox(height: 12),
                      // depois
                      if (kIsWeb)
                        ElevatedButton.icon(
                          onPressed: onCreateBot,
                          icon: const Icon(Icons.add),
                          label: const Text('Criar chatbot'),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'A criação de chatbots está disponível apenas na versão web.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            final docs = botsSnap.data!.docs;
            final cs = Theme.of(context).colorScheme;

            return ListView.separated(
              controller: scrollController,
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = docs[i];
                final botId = d.id;
                final botData = (d.data()).cast<String, dynamic>();
                final title = (botData['name'] ?? 'Sem nome').toString();
                final subtitle =
                (botData['description'] ?? 'Sem descrição').toString();

                final isActive = enabled && activeBotId == botId;

                return Card(
                  child: ListTile(
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: const Icon(Icons.smart_toy_outlined),
                    iconColor: cs.onSecondary,
                    title: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondary,
                      ),
                    ),
                    subtitle: Text(
                      subtitle,
                      style: TextStyle(color: cs.onSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<int>(
                          tooltip: 'Ações',
                          color: cs.secondary, // fundo do menu no mesmo tom dos cards
                          icon: Icon(Icons.more_vert, color: cs.onSecondary),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 1,
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined, size: 20, color: cs.onSecondary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Visualizar',
                                    style: TextStyle(color: cs.onSecondary),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 2,
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 20, color: cs.onSecondary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Editar',
                                    style: TextStyle(color: cs.onSecondary),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 3,
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 20, color: cs.onSecondary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Excluir',
                                    style: TextStyle(color: cs.onSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            switch (value) {
                              case 1:
                                onViewBot(botId);
                                break;
                              case 2:
                                onEditBot(botId);
                                break;
                              case 3:
                                onDeleteBot(botId, title);
                                break;
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        // Toggle pequeno à direita do menu
                        Transform.scale(
                          scale: 0.82,
                          child: Switch(
                            value: isActive,
                            onChanged: (v) async {
                              if (v) {
                                await onActivate(botId);
                              } else if (isActive) {
                                await onDeactivate();
                              }
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            thumbColor: MaterialStateProperty.all(cs.onSurface),
                            trackColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.selected)) return cs.primary;
                              return cs.surfaceVariant;
                            }),
                            trackOutlineColor: MaterialStateProperty.resolveWith((states) {
                              if (states.contains(MaterialState.selected)) {
                                return cs.primary.withOpacity(0.6);
                              }
                              return cs.outlineVariant;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              text,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}