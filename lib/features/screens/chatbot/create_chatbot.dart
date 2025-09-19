import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum NodeKind { message, delay }

enum WaitUnit { minutes, hours, days }

class FunnelNode {
  FunnelNode({
    required this.id,
    required this.title,
    this.message = '',
    this.kind = NodeKind.message,
    this.waitValue = 15,
    this.waitUnit = WaitUnit.minutes,
    this.attachments = const {},
    this.sent = 0,
    this.scheduled = 0,
    this.canceled = 0,
    this.position = const Offset(200, 200),
  });

  final String id;
  String title;
  String message;
  NodeKind kind;

  int waitValue;
  WaitUnit waitUnit;

  // “botões” do topo (Arquivo/Boleto/Contato/…)
  Set<String> attachments;

  // métricas do card
  int sent;
  int scheduled;
  int canceled;

  Offset position; // posição no canvas
}

FunnelNode? _selectedNode;

final List<FunnelNode> _nodes = [
  FunnelNode(
    id: 'n1',
    title: '[MSG 1 - Saudação — Texto]',
    message: '{Saudação} {PrimeiroNome}, blz?',
    position: const Offset(360, 260),
    attachments: {'typing'},
  ),
  FunnelNode(
    id: 'n2',
    title: 'MSG 2 - Apresentação - Texto ou Áudio',
    message: '{Atendente} aqui! 👋',
    position: const Offset(720, 260),
  ),
];

class CreateChatbotPage extends StatefulWidget {
  const CreateChatbotPage({Key? key}) : super(key: key);

  @override
  State<CreateChatbotPage> createState() => _CreateChatbotPageState();
}

/* =====================  MODELOS  ===================== */

enum ReplyBlockType { message, submenu }

class _SubmenuItem {
  _SubmenuItem({this.key = '', this.label = ''});
  String key;
  String label;
}

class _Submenu {
  _Submenu({
    this.title = 'Escolha uma opção',
    List<_SubmenuItem>? items,
  }) : items = items ?? [ _SubmenuItem(key: '1', label: 'Opção 1') ];

  String title;
  List<_SubmenuItem> items;
}

class _ReplyBlock {
  _ReplyBlock.message({String text = ''})
      : type = ReplyBlockType.message,
        message = text,
        submenu = null;

  _ReplyBlock.submenu({_Submenu? submenu})
      : type = ReplyBlockType.submenu,
        message = '',
        submenu = submenu ?? _Submenu();

  ReplyBlockType type;
  String message;
  _Submenu? submenu;
}

class _MenuOptionModel {
  _MenuOptionModel({
    required this.keyText,
    required this.label,
    this.handoffAfter = false,
    List<_ReplyBlock>? blocks,
    this.expanded = false,
  }) : blocks = blocks ?? [ _ReplyBlock.message(text: 'Ok!') ];

  String keyText;
  String label;
  bool handoffAfter;
  bool expanded;
  List<_ReplyBlock> blocks;
}

/* =====================  PÁGINA  ===================== */

class _CreateChatbotPageState extends State<CreateChatbotPage> {
  final _formKey = GlobalKey<FormState>();

  String? _empresaId;
  bool _resolving = true;
  String? _resolveError;

  // Básico
  final _nameCtrl = TextEditingController(text: '');
  final _descCtrl = TextEditingController(text: '');
  final _greetingCtrl = TextEditingController(text: 'Olá! 👋 Como posso ajudar?');
  final _menuTextCtrl = TextEditingController(text: 'Escolha uma opção:');
  final _fallbackCtrl = TextEditingController(text: 'Não entendi. Responda com um número.');

  // Opções do menu raiz
  final List<_MenuOptionModel> _options = [
    _MenuOptionModel(keyText: '1', label: 'Falar com atendente', handoffAfter: true, blocks: [
      _ReplyBlock.message(text: 'Certo! Vou te encaminhar.'),
    ]),
    _MenuOptionModel(keyText: '2', label: 'Horários', handoffAfter: false, blocks: [
      _ReplyBlock.message(text: 'Atendemos de seg a sex, 9h às 18h.'),
    ]),
  ];

  // AppBar dinâmica
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _resolveEmpresaId();
    _scrollController.addListener(() {
      setState(() => _scrollOffset = _scrollController.offset);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _greetingCtrl.dispose();
    _menuTextCtrl.dispose();
    _fallbackCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /* ----------------- infra: resolver empresa ----------------- */
  Future<void> _resolveEmpresaId() async {
    setState(() { _resolving = true; _resolveError = null; });

    try {
      final authProvider = mounted ? Provider.of<AuthProvider>(context, listen: false) : null;
      final User? user = authProvider?.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() { _resolveError = 'Usuário não autenticado.'; _resolving = false; });
        return;
      }

      final uid = user.uid;
      final empDoc = await FirebaseFirestore.instance.collection('empresas').doc(uid).get();
      if (empDoc.exists) {
        setState(() { _empresaId = uid; _resolving = false; });
        return;
      }

      final usrDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (usrDoc.exists) {
        final data = (usrDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final createdBy = data['createdBy']?.toString();
        if (createdBy == null || createdBy.isEmpty) {
          setState(() { _resolveError = 'Documento do usuário encontrado, mas sem "createdBy".'; _resolving = false; });
          return;
        }
        setState(() { _empresaId = createdBy; _resolving = false; });
        return;
      }

      setState(() { _resolveError = 'Documento não encontrado em "empresas" nem em "users".'; _resolving = false; });
    } catch (e) {
      setState(() { _resolveError = 'Falha ao resolver empresaId: $e'; _resolving = false; });
    }
  }

  // ↓ agora só recebe hint
  InputDecoration _decGeneral(BuildContext context, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
  }

  InputDecoration _decCard(BuildContext context, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.background, // inputs dentro dos cards com bg
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
  }

  PreferredSizeWidget _buildStyledAppBar(ColorScheme cs) {
    final double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    final double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

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
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new, color: cs.onBackground, size: 18),
                            const SizedBox(width: 4),
                            Text('Voltar', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: cs.onSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Novo Chatbot',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Salvar',
                    icon: Icon(Icons.save, color: cs.onBackground, size: 30),
                    onPressed: _save,
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

  /* ----------------- ações de UI ----------------- */

  void _addOption() {
    final nextKey = (_options.length + 1).toString();
    setState(() {
      _options.add(_MenuOptionModel(
        keyText: nextKey, label: '', handoffAfter: false, expanded: true,
        blocks: [ _ReplyBlock.message(text: '') ],
      ));
    });
  }

  void _removeOption(int index) {
    setState(() => _options.removeAt(index));
  }

  void _addMessageBlock(_MenuOptionModel opt) {
    setState(() => opt.blocks.add(_ReplyBlock.message(text: '')));
  }

  void _addSubmenuBlock(_MenuOptionModel opt) {
    setState(() => opt.blocks.add(_ReplyBlock.submenu()));
  }

  void _removeBlock(_MenuOptionModel opt, int blockIndex) {
    setState(() => opt.blocks.removeAt(blockIndex));
  }

  /* ----------------- salvar (gera steps) ----------------- */

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_empresaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível obter empresaId.')));
      return;
    }

    // valida chaves numéricas e duplicadas (apenas nível raiz)
    if (_options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione ao menos uma opção.')));
      return;
    }
    final keys = _options.map((o) => o.keyText.trim()).toList();
    final hasEmptyKey = keys.any((k) => k.isEmpty);
    final hasNonNumericKey = keys.any((k) => !RegExp(r'^\d+$').hasMatch(k));
    final hasDupKey = keys.toSet().length != keys.length;

    if (hasEmptyKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Existem opções com tecla vazia.')));
      return;
    }
    if (hasNonNumericKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('As teclas do menu devem ser números (1, 2, 3, ...).')));
      return;
    }
    if (hasDupKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Existem teclas duplicadas no menu principal.')));
      return;
    }

    final empresaId = _empresaId!;
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final greeting = _greetingCtrl.text.trim();
    final menuText = _menuTextCtrl.text.trim();
    final fallbackMsg = _fallbackCtrl.text.trim();

    final List<Map<String, dynamic>> steps = [];

    // START (menu raiz)
    final startOptions = <Map<String, dynamic>>[];

    for (int i = 0; i < _options.length; i++) {
      final opt = _options[i];

      // id do primeiro bloco desta opção (ou um step "final" se não houver blocos)
      String firstStepId;
      if (opt.blocks.isEmpty) {
        firstStepId = 'opt_${i+1}_final';
        steps.add({
          'id': firstStepId,
          'type': 'message',
          'text': 'Ok!',
          'next': opt.handoffAfter ? 'end' : 'start',
        });
      } else {
        firstStepId = _blockId(i, 0, opt.blocks[0].type);
      }

      startOptions.add({
        'key': opt.keyText.trim(),
        'label': opt.label.trim().isEmpty ? 'Opção ${opt.keyText.trim()}' : opt.label.trim(),
        'next': firstStepId,
      });

      // gerar os blocos desta opção
      for (int j = 0; j < opt.blocks.length; j++) {
        final blk = opt.blocks[j];
        final id = _blockId(i, j, blk.type);
        final bool isLast = j == opt.blocks.length - 1;

        // próximo destino
        final String nextId = isLast
            ? (opt.handoffAfter ? 'end' : 'start')
            : _blockId(i, j+1, opt.blocks[j+1].type);

        if (blk.type == ReplyBlockType.message) {
          steps.add({
            'id': id,
            'type': 'message',
            'text': (blk.message.trim().isEmpty ? 'Ok!' : blk.message.trim()),
            'next': nextId,
          });
        } else {
          // submenu
          final submenu = blk.submenu!;
          final menuOptions = submenu.items.map((it) => {
            'key': (it.key.trim().isEmpty ? '1' : it.key.trim()),
            'label': (it.label.trim().isEmpty ? 'Opção ${it.key.trim().isEmpty ? '1' : it.key.trim()}' : it.label.trim()),
            'next': isLast ? (opt.handoffAfter ? 'end' : 'start') : nextId,
          }).toList();

          steps.add({
            'id': id,
            'type': 'menu',
            'text': submenu.title.trim().isEmpty ? 'Escolha uma opção' : submenu.title.trim(),
            'options': menuOptions,
          });
        }
      }
    }

    // step start
    steps.insert(0, {
      'id': 'start',
      'type': 'menu',
      'text': menuText.isEmpty ? 'Escolha uma opção:' : menuText,
      'options': startOptions,
    });

    // step end
    steps.add({ 'id': 'end', 'type': 'end' });

    final payload = {
      'name': name,
      'description': desc,
      'greeting': greeting.isEmpty ? 'Olá! 👋' : greeting,
      'startStepId': 'start',
      'steps': steps,
      'fallback': {
        'message': fallbackMsg.isEmpty ? 'Não entendi. Responda com um número.' : fallbackMsg,
        'maxRetries': 2,
        'onFail': 'handoff',
      },
      'officeHours': { 'enabled': false },
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
    };

    try {
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('chatbots')
          .add(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chatbot criado com sucesso.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao salvar: $e')));
    }
  }

  String _blockId(int optIndex, int blockIndex, ReplyBlockType t) {
    final oi = optIndex + 1;
    final bi = blockIndex + 1;
    return t == ReplyBlockType.message ? 'opt_${oi}_msg_${bi}' : 'opt_${oi}_menu_${bi}';
  }

  /* ----------------- BUILD ----------------- */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_resolving) {
      return Scaffold(appBar: _buildStyledAppBar(cs), body: const Center(child: CircularProgressIndicator()));
    }
    if (_resolveError != null) {
      return Scaffold(
        appBar: _buildStyledAppBar(cs),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_resolveError!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildStyledAppBar(cs),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // ======= Seção 1: Informações básicas =======
              Text('Informações básicas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: _decGeneral(context, hint: 'Nome do chatbot *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: _decGeneral(context, hint: 'Descrição'),
                minLines: 1, maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _greetingCtrl,
                decoration: _decGeneral(context, hint: 'Saudação'),
                minLines: 1, maxLines: 3,
              ),

              const SizedBox(height: 24),

              // ======= Seção 2: Menus e Respostas =======
              Row(
                children: [
                  Text('Menus e Respostas', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: cs.onBackground.withOpacity(.1))),
                ],
              ),
              const SizedBox(height: 8),

              // Título do menu
              TextFormField(
                controller: _menuTextCtrl,
                decoration: _decGeneral(context, hint: 'Título do menu'),
                minLines: 1, maxLines: 2,
              ),
              const SizedBox(height: 12),

              // LISTA DE OPÇÕES (colapsáveis)
              ..._options.asMap().entries.map((entry) {
                final idx = entry.key;
                final opt = entry.value;

                return _OptionCard(
                  option: opt,
                  onToggleExpanded: () => setState(() => opt.expanded = !opt.expanded),
                  onRemove: () => _removeOption(idx),
                  onAddMessage: () => _addMessageBlock(opt),
                  onAddSubmenu: () => _addSubmenuBlock(opt),
                  decCard: ({String? hint}) => _decCard(context, hint: hint),
                  onChangedKey: (v) => setState(() => opt.keyText = v),
                  onChangedLabel: (v) => setState(() => opt.label = v),
                  onChangedHandoff: (v) => setState(() => opt.handoffAfter = v),
                  onRemoveBlock: (bIndex) => _removeBlock(opt, bIndex),
                  onChangeBlockMessage: (bIndex, v) => setState(() => opt.blocks[bIndex].message = v),
                  onSubmenuTitleChanged: (bIndex, v) => setState(() => opt.blocks[bIndex].submenu!.title = v),
                  onSubmenuAddItem: (bIndex) => setState(() => opt.blocks[bIndex].submenu!.items.add(_SubmenuItem(key: '', label: ''))),
                  onSubmenuRemoveItem: (bIndex, iIndex) => setState(() => opt.blocks[bIndex].submenu!.items.removeAt(iIndex)),
                  onSubmenuItemChanged: (bIndex, iIndex, {String? key, String? label}) => setState(() {
                    final it = opt.blocks[bIndex].submenu!.items[iIndex];
                    if (key != null) it.key = key;
                    if (label != null) it.label = label;
                  }),
                );
              }),

              // Adicionar opção
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar opção'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    backgroundColor: cs.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onBackground,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text('Fallback', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fallbackCtrl,
                decoration: _decGeneral(context, hint: 'Mensagem de erro (entrada inválida)'),
                minLines: 1, maxLines: 3,
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===============  WIDGET do card colapsável  =============== */

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.onToggleExpanded,
    required this.onRemove,
    required this.onAddMessage,
    required this.onAddSubmenu,
    required this.decCard,
    required this.onChangedKey,
    required this.onChangedLabel,
    required this.onChangedHandoff,
    required this.onRemoveBlock,
    required this.onChangeBlockMessage,
    required this.onSubmenuTitleChanged,
    required this.onSubmenuAddItem,
    required this.onSubmenuRemoveItem,
    required this.onSubmenuItemChanged,
  });

  final _MenuOptionModel option;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRemove;
  final VoidCallback onAddMessage;
  final VoidCallback onAddSubmenu;

// _OptionCard
  final InputDecoration Function({String? hint}) decCard;

  final ValueChanged<String> onChangedKey;
  final ValueChanged<String> onChangedLabel;
  final ValueChanged<bool> onChangedHandoff;

  final void Function(int blockIndex) onRemoveBlock;
  final void Function(int blockIndex, String value) onChangeBlockMessage;

  final void Function(int blockIndex) onSubmenuAddItem;
  final void Function(int blockIndex, int itemIndex) onSubmenuRemoveItem;
  final void Function(int blockIndex, int itemIndex,
      {String? key, String? label}) onSubmenuItemChanged;

  final void Function(int blockIndex, String value) onSubmenuTitleChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.secondary,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // header compacto (estilo “input”)
            GestureDetector(
              onTap: onToggleExpanded,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: cs.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label.isEmpty ? 'Sem título' : option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onBackground.withOpacity(.9), fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(option.expanded ? Icons.expand_less : Icons.expand_more, color: cs.onBackground),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Remover',
                      splashRadius: 18,
                      icon: const Icon(Icons.remove),
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
            ),

            if (option.expanded) ...[
              const SizedBox(height: 12),

              // Tecla
              TextFormField(
                initialValue: option.keyText,
                decoration: decCard(hint: 'Tecla (número)'),
                keyboardType: TextInputType.number,
                onChanged: onChangedKey,
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Obrigatório';
                  if (!RegExp(r'^\d+$').hasMatch(t)) return 'Somente números';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Rótulo
              TextFormField(
                initialValue: option.label,
                decoration: decCard(hint: 'Rótulo (nome da opção)'),
                onChanged: onChangedLabel,
              ),
              const SizedBox(height: 12),

              // Blocos (respostas / submenus)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int b = 0; b < option.blocks.length; b++) ...[
                    _BlockCard(
                      block: option.blocks[b],
                      decCard: decCard,
                      onRemove: () => onRemoveBlock(b),
                      onChangeMessage: (v) => onChangeBlockMessage(b, v),
                      onSubmenuTitleChanged: (v) => onSubmenuTitleChanged(b, v),
                      onSubmenuAddItem: () => onSubmenuAddItem(b),
                      onSubmenuRemoveItem: (i) => onSubmenuRemoveItem(b, i),
                      onSubmenuItemChanged: (i, {String? key, String? label}) =>
                          onSubmenuItemChanged(b, i, key: key, label: label),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // botões adicionar
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAddMessage,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar resposta'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: cs.background,
                            foregroundColor: cs.onBackground,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAddSubmenu,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar submenu'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: cs.background,
                            foregroundColor: cs.onBackground,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),
              // Toggle “encerrar…”
              Row(
                children: [
                  Expanded(
                    child: Text('Encerrar e passar para atendente após responder',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
                  ),
                  Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: option.handoffAfter,
                      onChanged: onChangedHandoff,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      thumbColor: MaterialStateProperty.all(Theme.of(context).colorScheme.onSurface),
                      trackColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.primary;
                        }
                        return Theme.of(context).colorScheme.surfaceVariant;
                      }),
                      trackOutlineColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.primary.withOpacity(0.6);
                        }
                        return Theme.of(context).colorScheme.outlineVariant;
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.decCard,
    required this.onRemove,
    required this.onChangeMessage,
    required this.onSubmenuTitleChanged,
    required this.onSubmenuAddItem,
    required this.onSubmenuRemoveItem,
    required this.onSubmenuItemChanged,
  });

  final _ReplyBlock block;
// _BlockCard
  final InputDecoration Function({String? hint}) decCard;

  final VoidCallback onRemove;
  final ValueChanged<String> onChangeMessage;

  final ValueChanged<String> onSubmenuTitleChanged;
  final VoidCallback onSubmenuAddItem;
  final void Function(int itemIndex) onSubmenuRemoveItem;
  final void Function(int itemIndex, {String? key, String? label}) onSubmenuItemChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.background,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                block.type == ReplyBlockType.message ? Icons.chat_bubble_outline : Icons.menu_open_rounded,
                color: cs.onBackground.withOpacity(.8),
              ),
              const SizedBox(width: 8),
              Text(
                block.type == ReplyBlockType.message ? 'Resposta' : 'Submenu',
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onBackground.withOpacity(.9)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Remover',
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (block.type == ReplyBlockType.message) ...[
            TextFormField(
              initialValue: block.message,
              decoration: decCard(hint: 'Mensagem'),
              minLines: 1,
              maxLines: 4,
              onChanged: onChangeMessage,
            ),
          ] else ...[
            TextFormField(
              initialValue: block.submenu!.title,
              decoration: decCard(hint: 'Título do submenu'),
              onChanged: onSubmenuTitleChanged,
            ),
            const SizedBox(height: 8),

            // itens do submenu
            Column(
              children: [
                for (int i = 0; i < block.submenu!.items.length; i++) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: cs.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        TextFormField(
                          initialValue: block.submenu!.items[i].label,
                          decoration: decCard(hint: 'Rótulo do item'),
                          onChanged: (v) => onSubmenuItemChanged(i, label: v),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: block.submenu!.items[i].key,
                          decoration: decCard(hint: 'Tecla (número)'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => onSubmenuItemChanged(i, key: v),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Remover item',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => onSubmenuRemoveItem(i),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onSubmenuAddItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar item do submenu'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: cs.secondary,
                      foregroundColor: cs.onBackground,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}