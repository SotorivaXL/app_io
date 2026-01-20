import 'dart:async';
import 'package:clean_kanban/ui/widgets/task_card.dart' as ck;
import 'package:clean_kanban/clean_kanban.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class TagItem {
  final String name;
  final Color color;
  const TagItem(this.name, this.color);
}

class LeadsKanbanPage extends StatefulWidget {
  const LeadsKanbanPage({super.key});

  @override
  State<LeadsKanbanPage> createState() => _LeadsKanbanPageState();
}

class _LeadStage {
  final String id;
  final String header;
  final String headerBgColorLight; // "#AARRGGBB"
  final String headerBgColorDark; // "#AARRGGBB"
  final String description;
  final List<String> checklist;

  const _LeadStage({
    required this.id,
    required this.header,
    required this.headerBgColorLight,
    required this.headerBgColorDark,
    required this.description,
    required this.checklist,
  });
}

class _LeadsKanbanPageState extends State<LeadsKanbanPage> {
  bool _isDragging = false;

  String _limit100(String s) {
    if (s.length <= 100) return s;
    return '${s.substring(0, 99)}…';
  }

  Map<String, TagItem> _tagMap = {};

  String _toHexArgb(Color c) {
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${h(c.alpha)}${h(c.red)}${h(c.green)}${h(c.blue)}';
  }

  final ScrollController _hScroll = ScrollController();

  static const double _columnWidth = 320.0;
  static const double columnGap = 14.0;
  static const double sidePadding = 12.0;

  // ====== etapas do seu Kanban ======
  static const List<_LeadStage> _stages = [
    _LeadStage(
      id: 'entrada',
      header: 'Entrada',
      headerBgColorLight: '#6B00E3',
      headerBgColorDark: '#6B00E3',
      description: 'Leads novos vindos de qualquer origem.',
      checklist: [
        'Registrar nome, empresa e contato',
        'Identificar origem do lead',
        'Registrar breve contexto (se houver)',
      ],
    ),
    _LeadStage(
      id: 'qualificacao',
      header: 'Qualificação',
      headerBgColorLight: '#FF8E24AA',
      headerBgColorDark: '#FF6A1B9A',
      description: 'Avaliar rapidamente se o lead tem fit real com a IO.',
      checklist: [
        'Verificar faturamento mínimo',
        'Nicho/segmento aceitável',
        'Demanda coerente com a IO',
        'Registrar dados importantes',
      ],
    ),
    _LeadStage(
      id: 'primeiro_contato',
      header: 'Primeiro Contato',
      headerBgColorLight: '#FF43A047',
      headerBgColorDark: '#FF2E7D32',
      description: 'Lead respondeu e já está em conversa inicial.',
      checklist: [
        'Responder o lead',
        'Acordar formato de atendimento (call/áudio)',
        'Confirmar dados essenciais',
      ],
    ),
    _LeadStage(
      id: 'diagnostico',
      header: 'Diagnóstico',
      headerBgColorLight: '#FFFB8C00',
      headerBgColorDark: '#FFEF6C00',
      description: 'Reunião de entendimento da empresa, momento e dores.',
      checklist: [
        'Realizar reunião ou call',
        'Levantar desafios + objetivos',
        'Ver necessidade real',
        'Validar disponibilidade financeira',
      ],
    ),
    _LeadStage(
      id: 'proposta_em_producao',
      header: 'Proposta em Produção',
      headerBgColorLight: '#FFFDD835',
      headerBgColorDark: '#FFF9A825',
      description: 'Criando proposta personalizada (como a IO sempre faz).',
      checklist: [
        'Definir plano recomendado',
        'Estruturar escopo',
        'Inserir diferenciais IO',
        'Submeter para validação interna',
      ],
    ),
    _LeadStage(
      id: 'proposta_enviada',
      header: 'Proposta Enviada',
      headerBgColorLight: '#FF6D4C41',
      headerBgColorDark: '#FF5D4037',
      description: 'Proposta enviada e aguardando análise do lead.',
      checklist: [
        'Confirmar recebimento',
        'Agendar follow-up',
        'Disponibilizar canal para dúvidas',
      ],
    ),
    _LeadStage(
      id: 'negociacao',
      header: 'Negociação',
      headerBgColorLight: '#FF039BE5',
      headerBgColorDark: '#FF0277BD',
      description: 'Ajustes, dúvidas e tratativas finais.',
      checklist: [
        'Validar objeções',
        'Ajustar detalhes finais',
        'Alinhar início',
        'Propor fechamento',
      ],
    ),
    _LeadStage(
      id: 'followup_1',
      header: 'Follow-up 1',
      headerBgColorLight: '#FF7E57C2',
      headerBgColorDark: '#FF5E35B1',
      description: 'Primeiro lembrete após 24–48h sem resposta.',
      checklist: [
        'Enviar follow-up cordial',
        'Reforçar pontos principais da proposta',
        'Garantir que o lead tenha tudo que precisa',
      ],
    ),
    _LeadStage(
      id: 'followup_2',
      header: 'Follow-up 2',
      headerBgColorLight: '#FFE53935',
      headerBgColorDark: '#FFC62828',
      description: 'Segundo contato direto, pedindo posição objetiva.',
      checklist: [
        'Mensagem curta e clara',
        'Perguntar decisão',
        'Confirmar se faz sentido seguir',
      ],
    ),
    _LeadStage(
      id: 'recuperacao',
      header: 'Recuperação',
      headerBgColorLight: '#FFFF7043',
      headerBgColorDark: '#FFF4511E',
      description:
          'Lead sumido há 7–15 dias. Estratégia para resgatar interesse.',
      checklist: [
        'Enviar case forte',
        'Reforçar diferenciais (certificações, time, ANCINE)',
        'Oferecer IO Start (se fizer sentido)',
        'Reativar conversa',
      ],
    ),
    _LeadStage(
      id: 'lead_frio_aguardar',
      header: 'Lead Frio / Aguardar',
      headerBgColorLight: '#FF8D6E63',
      headerBgColorDark: '#FF6D4C41',
      description: 'Lead que pediu para esperar / falar depois.',
      checklist: [
        'Registrar motivo',
        'Criar tarefa automática para retomada futura',
        'Manter o lead aquecido eventualmente',
      ],
    ),
    _LeadStage(
      id: 'fechamento',
      header: 'Fechamento',
      headerBgColorLight: '#FF00C853',
      headerBgColorDark: '#FF00A152',
      description: 'Lead aceitou e está formalizando.',
      checklist: [
        'Enviar contrato',
        'Gerar cobrança',
        'Confirmar dados oficiais',
        'Agendar reunião de onboarding',
      ],
    ),
    _LeadStage(
      id: 'onboarding',
      header: 'Onboarding',
      headerBgColorLight: '#FF2E7D32',
      headerBgColorDark: '#FF1B5E20',
      description: 'Cliente em implantação.',
      checklist: [
        'Reunião inicial',
        'Coleta de acessos',
        'Definição de metas e cronograma',
        'Inserir no Operation',
      ],
    ),
    _LeadStage(
      id: 'cliente_ativo',
      header: 'Cliente Ativo',
      headerBgColorLight: '#FF1565C0',
      headerBgColorDark: '#FF0D47A1',
      description: 'Cliente rodando oficialmente com a IO.',
      checklist: [
        'Acompanhamento normal pelo Operation',
        'Comunicação direta com o gerente responsável',
      ],
    ),
    _LeadStage(
      id: 'perdido_desqualificado',
      header: 'Perdido / Desqualificado',
      headerBgColorLight: '#FF424242',
      headerBgColorDark: '#FF212121',
      description:
          'Sem fit, desistiu ou não respondeu após todos os follow-ups.',
      checklist: [
        'Registrar motivo da perda',
        'Classificar tipo de perda (preço, timing, fit, concorrência)',
        'Avaliar se vale remarketing futuro',
      ],
    ),
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>> _tagsStream() {
    if (!_ready) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('tags')
        .snapshots();
  }

  // ====== utils ======
  final _fmt = DateFormat('dd/MM/yy - HH:mm');

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  String _truncate(String s, {int max = 100}) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }

  String _formatPhoneFromChatId(String chatId) {
    var phone = chatId;
    if (phone.contains('@')) phone = phone.split('@')[0];
    final digits = _digits(phone);

    if (digits.startsWith('55') && digits.length > 4) {
      final rest = digits.substring(2);
      final ddd = rest.length >= 2 ? rest.substring(0, 2) : '';
      final local = rest.length >= 2 ? rest.substring(2) : rest;
      if (local.length <= 4) return '+55 $ddd $local';
      final p1 = local.substring(0, local.length - 4);
      final p2 = local.substring(local.length - 4);
      return '+55 $ddd $p1-$p2';
    }

    if (digits.length > 10) {
      final country = digits.substring(0, digits.length - 10);
      final ddd = digits.substring(digits.length - 10, digits.length - 8);
      final rest = digits.substring(digits.length - 8);
      final p1 = rest.substring(0, rest.length - 4);
      final p2 = rest.substring(rest.length - 4);
      return '+$country $ddd $p1-$p2';
    }

    return phone;
  }

  bool _docMatchesSearch(Map<String, dynamic> m, String query) {
    if (query.trim().isEmpty) return true;

    final q = query.trim().toLowerCase();
    final name = (m['name'] ?? m['contactName'] ?? '').toString().toLowerCase();
    final last =
        (m['lastMsg'] ?? m['lastMessage'] ?? '').toString().toLowerCase();
    final chatId = (m['chatId'] ?? '').toString();
    final phoneDigits = _digits(chatId);

    return name.contains(q) ||
        last.contains(q) ||
        phoneDigits.contains(_digits(q));
  }

  // ====== estado (ctx empresa/phone) ======
  late String _companyId;
  late String _phoneId;
  bool _ready = false;

  String _search = '';

  // ====== kanban provider + eventos ======
  final BoardProvider _boardProvider = BoardProvider();
  StreamSubscription<BoardEvent>? _eventsSub;

  // Controle simples pra não ficar “recarregando” o board a cada rebuild
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _initIds();

    _eventsSub = EventNotifier().subscribe(_onBoardEvent);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _hScroll.dispose();
    super.dispose();
  }

  Future<(String companyId, String? phoneId)> _resolvePhoneCtx() async {
    final fs = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    String companyId = uid;
    String? phoneId;

    final uSnap = await fs.collection('users').doc(uid).get();
    if (uSnap.exists) {
      final u = uSnap.data() ?? {};
      companyId = (u['createdBy'] as String?)?.isNotEmpty == true
          ? u['createdBy'] as String
          : uid;
      phoneId = u['defaultPhoneId'] as String?;
    }

    if (phoneId == null) {
      final eSnap = await fs.collection('empresas').doc(companyId).get();
      if (eSnap.exists) {
        phoneId = eSnap.data()?['defaultPhoneId'] as String?;
      }
    }

    if (phoneId == null) {
      final ph = await fs
          .collection('empresas')
          .doc(companyId)
          .collection('phones')
          .limit(1)
          .get();

      if (ph.docs.isNotEmpty) {
        phoneId = ph.docs.first.id;

        if (uSnap.exists) {
          await fs.collection('users').doc(uid).set(
            {'defaultPhoneId': phoneId},
            SetOptions(merge: true),
          );
        } else {
          await fs.collection('empresas').doc(companyId).set(
            {'defaultPhoneId': phoneId},
            SetOptions(merge: true),
          );
        }
      }
    }

    return (companyId, phoneId);
  }

  Future<void> _initIds() async {
    final (companyId, phoneId) = await _resolvePhoneCtx();
    _companyId = companyId;
    _phoneId = phoneId ?? '';

    if (!mounted) return;
    setState(() => _ready = _phoneId.isNotEmpty);
  }

  // ====== streams ======
  Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream() {
    if (!_ready) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        // Você pode ajustar ordering/limit conforme performance
        .snapshots();
  }

  // ====== build do config do kanban ======
  Map<String, dynamic> _buildBoardConfig(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
        required String headerBgHex,
        required Map<String, TagItem> tagsMap,
      }) {
    // agrupa por stage
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        byStage = {
      for (final s in _stages)
        s.id: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    };

    for (final d in docs) {
      final m = d.data();
      final stage = (m['pipelineStage'] ?? 'entrada').toString();
      final normalizedStage = byStage.containsKey(stage) ? stage : 'entrada';
      byStage[normalizedStage]!.add(d);
    }

    int _tsScore(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final m = d.data();

      final ts = (m['pipelineUpdatedAt'] as Timestamp?) ??
          (m['updatedAt'] as Timestamp?) ??
          (m['createdAt'] as Timestamp?);

      final dt = ts?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dt.millisecondsSinceEpoch;
    }

    for (final s in _stages) {
      byStage[s.id]!.sort((a, b) => _tsScore(b).compareTo(_tsScore(a)));
    }

    // transforma docs -> tasks
    List<Map<String, dynamic>> makeTasks(
        List<QueryDocumentSnapshot<Map<String, dynamic>>> list) {
      return list.map((doc) {
        final m = doc.data();
        final id = doc.id;
        final tagIds = (m['tags'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? const <String>[];

        final tagsMeta = tagIds
            .where((tagId) => tagsMap.containsKey(tagId))
            .map((tagId) {
          final t = tagsMap[tagId]!;
          return <String, dynamic>{
            'id': tagId,
            'name': t.name,
            'color': t.color.value, // ✅ salva como int (4284955319)
          };
        })
            .toList();

        // Nome (title) — sempre com fallback
        final rawName = (m['name'] ?? m['contactName'] ?? '').toString().trim();
        final safeName = rawName.isNotEmpty ? rawName : 'Sem nome';
        final title = _limit100(_truncate(safeName, max: 100));

        // Foto (ajuste os campos se o seu nome for outro)
        final photoUrl =
            (m['photoUrl'] ?? m['profilePic'] ?? m['contactPhoto'] ?? '')
                .toString()
                .trim();

        // Data que chegou (arrivalAt -> createdAt)
        final arrivalTs =
            (m['arrivalAt'] as Timestamp?) ?? (m['createdAt'] as Timestamp?);
        final arrivedAt = arrivalTs?.toDate();

        // Última mensagem
        final lastMsg =
            (m['lastMsg'] ?? m['lastMessage'] ?? '').toString().trim();

        ck.TaskMetaStore.setMeta(
          id,
          photoUrl: photoUrl,
          arrivedAt: arrivedAt,
          lastMsg: lastMsg,
          tags: tagsMeta,
        );

        final lastShort =
            _truncate(lastMsg.isNotEmpty ? lastMsg : '—', max: 80);
        final subtitle = 'tags';

        return {
          'id': id,
          'title': title,
          'subtitle': subtitle,
        };
      }).toList();
    }

    final columns = _stages.map((s) {
      return <String, dynamic>{
        'id': s.id,
        'header': s.header,
        'limit': null,
        'canAddTask': false, // leads vêm do Firestore, não “cria card” por aqui
        'headerBgColorLight': headerBgHex,
        'headerBgColorDark': headerBgHex,
        'tasks': makeTasks(byStage[s.id]!),
      };
    }).toList();

    return {'columns': columns};
  }

  String _signatureFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // assinatura simples: quantidade + soma “por etapa”
    final counts = <String, int>{for (final s in _stages) s.id: 0};
    for (final d in docs) {
      final st = (d.data()['pipelineStage'] ?? 'entrada').toString();
      counts[counts.containsKey(st) ? st : 'entrada'] =
          (counts[counts.containsKey(st) ? st : 'entrada'] ?? 0) + 1;
    }
    return '${docs.length}|${counts.entries.map((e) => '${e.key}:${e.value}').join(',')}';
  }

  // ====== sync Firestore a partir dos eventos do Kanban ======
  Future<void> _updateLeadStage({
    required String docId,
    required String stageId,
  }) async {
    if (!_ready) return;

    final ref = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(docId);

    await ref.set({
      'pipelineStage': stageId,
      'pipelineUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _updateLeadFromEdit({
    required String docId,
    required String newTitle,
    required String newSubtitle,
  }) async {
    if (!_ready) return;

    final ref = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(docId);

    await ref.set({
      // você pode decidir se quer atualizar só "name" ou também "contactName"
      'name': newTitle.trim(),
      'pipelineNote': newSubtitle.trim(),
      'pipelineUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _onBoardEvent(BoardEvent event) {
    // IMPORTANTE: os ids dos tasks são doc.id do Firestore
    if (event is TaskMovedEvent) {
      _updateLeadStage(docId: event.task.id, stageId: event.destination.id);
      return;
    }

    if (event is TaskEditedEvent) {
      _updateLeadFromEdit(
        docId: event.newTask.id,
        newTitle: event.newTask.title,
        newSubtitle: event.newTask.subtitle,
      );
      return;
    }

    if (event is TaskRemovedEvent) {
      // “Excluir card” => manda para Perdido/Desqualificado (você pode trocar a regra)
      _updateLeadStage(docId: event.task.id, stageId: 'perdido_desqualificado');
      return;
    }
  }

  // ====== UI ======
  void _showStagesHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Etapas do Kanban (IO)'),
        content: SizedBox(
          width: 700,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _stages.length,
            separatorBuilder: (_, __) => const Divider(height: 18),
            itemBuilder: (_, i) {
              final s = _stages[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.header,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(s.description),
                  const SizedBox(height: 6),
                  ...s.checklist.map((c) => Text('• $c')),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final headerBgHex = _toHexArgb(cs.surface);

// Fundo do card: um pouco mais claro que a coluna pra destacar
    final cardBg = cs.tertiaryContainer;

    final kanbanTheme = KanbanTheme(
      boardBackgroundColor: Colors.transparent,
      boardBorderColor: Colors.transparent,
      boardBorderWidth: 0.0,
      columnTheme: KanbanColumnTheme(
        columnBackgroundColor: cs.surface,
        columnBorderColor: Colors.transparent,
        columnBorderWidth: 0.0,
        columnHeaderColor: primary,
        columnHeaderTextColor: cs.onSurface,
        columnAddButtonBoxColor: primary,
        columnAddIconColor: cs.onPrimary,
      ),
      cardTheme: TaskCardTheme(
        cardBackgroundColor: cardBg,

        // dá um “recorte” leve no card sem ficar com borda branca
        cardBorderColor: cs.onSurface.withOpacity(.08),
        cardBorderWidth: 1.0,

        cardDividerColor: Colors.transparent,

        // ✅ texto com contraste correto
        cardTitleColor: cs.onSurface,
        cardSubtitleColor: cs.onSurface.withOpacity(.72),

        // accent (barra lateral do card)
        cardMoveIconEnabledColor: primary,
        cardMoveIconDisabledColor: cs.onSurface.withOpacity(.25),
      ),
    );

    if (!_ready) {
      return Scaffold(
        body: Center(
          child: Text(
            'Nenhum número configurado para esta empresa.\n'
            'Adicione um telefone em Configurações > Números.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onBackground.withOpacity(.85)),
          ),
        ),
      );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pageWidth = kIsWeb ? constraints.maxWidth : 1700.0;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: pageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Search com padding 16px dos lados
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar lead (nome, mensagem, telefone)',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ✅ Kanban sem padding direito (só alinhado à esquerda)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 16),
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _tagsStream(),
                        builder: (context, tagSnap) {
                          // ✅ Monta o mapa de tags no MESMO padrão do WhatsAppChats (TagItem)
                          final tagsMap = <String, TagItem>{};

                          if (tagSnap.hasData) {
                            for (final d in tagSnap.data!.docs) {
                              final m = d.data();

                              final name = (m['name'] ?? '').toString().trim();
                              final rawColor = m['color'];

                              // ✅ color pode vir como int/num/string numérica
                              final intColor = rawColor is int
                                  ? rawColor
                                  : rawColor is num
                                  ? rawColor.toInt()
                                  : int.tryParse(rawColor?.toString() ?? '');

                              final color = Color(intColor ?? 0xFF9E9E9E);

                              if (name.isNotEmpty) {
                                tagsMap[d.id] = TagItem(name, color);
                              }
                            }
                          }

                          // (opcional) salva no state se você usa em outro lugar
                          _tagMap = tagsMap;

                          // ✅ Agora renderiza o kanban (chats)
                          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _chatsStream(),
                            builder: (_, snap) {
                              if (snap.hasError) {
                                return Center(
                                  child: Text(
                                    'Erro ao carregar leads: ${snap.error}',
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              if (!snap.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final allDocs = snap.data!.docs;
                              final filtered = allDocs
                                  .where((d) => _docMatchesSearch(d.data(), _search))
                                  .toList();

                              final config = _buildBoardConfig(
                                filtered,
                                headerBgHex: headerBgHex,
                                tagsMap: tagsMap, // ✅ PASSA AQUI
                              );

                              final sig = _signatureFromDocs(filtered);

                              if (_lastSignature != sig) {
                                _lastSignature = sig;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _boardProvider.loadBoard(config: config);
                                });
                              }

                              return ChangeNotifierProvider.value(
                                value: _boardProvider,
                                child: Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerSignal: (signal) {
                                    if (signal is! PointerScrollEvent) return;
                                    if (!_hScroll.hasClients) return;

                                    final delta = signal.scrollDelta;
                                    final move = delta.dx != 0 ? delta.dx : delta.dy;

                                    final max = _hScroll.position.maxScrollExtent;
                                    final next = (_hScroll.offset + move).clamp(0.0, max);

                                    _hScroll.jumpTo(next);
                                  },
                                  child: Scrollbar(
                                    controller: _hScroll,
                                    thumbVisibility: true,
                                    child: PrimaryScrollController(
                                      controller: _hScroll,
                                      child: BoardWidget(theme: kanbanTheme),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      )
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
