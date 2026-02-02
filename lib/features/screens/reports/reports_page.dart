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
import 'package:app_io/features/screens/crm/chat_detail.dart';
import 'dart:math' as math;

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
  int _boardEpoch = 0; // força recriar o provider/board
  final Map<String, String> _stageOverrides = {};

// cache do último "input" do board
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastFiltered = const [];
  Map<String, TagItem> _lastTagsMap = const {};
  String _lastHeaderBgHex = '';

  void _optimisticStage(String docId, String stageId) {
    _stageOverrides[docId] = stageId;
    _reloadBoardFromCache(); // ✅ atualiza UI na hora
  }

  Timer? _boardLoadDebounce;
  String _lastBoardSig = '';
  bool _suppressBoardReload = false;
  Timer? _suppressTimer;

  void _reloadBoardFromCache() {
    if (!_ready) return;
    if (_lastHeaderBgHex.isEmpty) return;

    final config = _buildBoardConfig(
      _lastFiltered,
      headerBgHex: _lastHeaderBgHex,
      tagsMap: _lastTagsMap,
    );

    _boardProvider.loadBoard(config: config);
  }


  String _limit100(String s) {
    if (s.length <= 100) return s;
    return '${s.substring(0, 99)}…';
  }

  Map<String, TagItem> _tagMap = {};

  StreamSubscription<BoardEvent>? _boardEventsSub;
  bool _dialogOpen = false;
  bool _forceReloadBoard = false;

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
    _boardLoadDebounce?.cancel();
    _suppressTimer?.cancel();
    _eventsSub?.cancel();
    _hScroll.dispose();
    super.dispose();
  }

  void _scheduleBoardLoad(Map<String, dynamic> config, String sig) {
    // ✅ se acabou de mover card, não recarrega agora (evita travadinha + null no web)
    if (_suppressBoardReload) return;

    if (sig == _lastBoardSig) return;
    _lastBoardSig = sig;

    _boardLoadDebounce?.cancel();
    _boardLoadDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (_suppressBoardReload) return;

      try {
        _boardProvider.loadBoard(config: config);
      } catch (_) {
        // evita spam no web
      }
    });
  }

  Future<void> _openLeadDialog({required String chatId}) async {
    if (_dialogOpen) return;
    _dialogOpen = true;

    try {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _LeadDetailsDialog(
          empresaId: _companyId,
          phoneId: _phoneId,
          chatId: chatId,

          stages: _stages, // ✅ passa a lista de colunas

          onOpenChat: (leadName, photoUrl) async {
            Navigator.of(context).pop();
            await _openChatFromKanban(chatId, leadName, photoUrl);
          },

          onEdit: (newName, newNote) async {
            await _updateLeadFromEdit(
              docId: chatId,
              newTitle: newName,
              newSubtitle: newNote,
            );
          },

          onEditValue: (value) async {
            await _updateLeadSaleValue(docId: chatId, saleValue: value);
          },

          onMoveStage: (stageId) async {
            await _updateLeadStage(docId: chatId, stageId: stageId);
          },
        ),
      );
    } finally {
      _dialogOpen = false;
    }
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
      final stage = (_stageOverrides[d.id] ?? (m['pipelineStage'] ?? 'entrada')).toString();
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

  String _signatureFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // assinatura por hash: muda quando muda stage/updatedAt (sem montar string gigante)
    int h = 17;

    for (final d in docs) {
      final m = d.data();
      final stage = (m['pipelineStage'] ?? 'entrada').toString();
      final updated = (m['pipelineUpdatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      h = 0x1fffffff & (h * 31 + d.id.hashCode);
      h = 0x1fffffff & (h * 31 + stage.hashCode);
      h = 0x1fffffff & (h * 31 + updated);
    }

    // inclui o search pra garantir reload quando muda o filtro
    h = 0x1fffffff & (h * 31 + _search.hashCode);

    return '$h';
  }

  // ====== sync Firestore a partir dos eventos do Kanban ======
  Future<void> _updateLeadStage({
    required String docId,
    required String stageId,
  }) async {
    if (!_ready) return;

    // ✅ impede qualquer loadBoard pendente de rodar logo após mover
    _boardLoadDebounce?.cancel();

    // ✅ aumenta o tempo de supressão (Firestore pode demorar >600ms pra ecoar)
    _suppressBoardReload = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(const Duration(milliseconds: 2000), () {
      _suppressBoardReload = false;
    });

    // move instantâneo no UI
    _moveTaskInBoardProviderNow(docId, stageId);

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

  String _signatureForBoard(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // ✅ ordena por ID pra assinatura não mudar quando o Firestore reordena a lista
    final sorted = [...docs]..sort((a, b) => a.id.compareTo(b.id));

    int h = 17;

    for (final d in sorted) {
      final m = d.data();

      final name = (m['name'] ?? m['contactName'] ?? '').toString();
      final lastMsg = (m['lastMsg'] ?? m['lastMessage'] ?? '').toString();
      final photo = (m['photoUrl'] ?? m['profilePic'] ?? m['contactPhoto'] ?? '').toString();

      h = 0x1fffffff & (h * 31 + d.id.hashCode);
      h = 0x1fffffff & (h * 31 + name.hashCode);
      h = 0x1fffffff & (h * 31 + lastMsg.hashCode);
      h = 0x1fffffff & (h * 31 + photo.hashCode);
    }

    h = 0x1fffffff & (h * 31 + _search.hashCode);
    return '$h';
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

  Future<void> _updateLeadSaleValue({
    required String docId,
    required double? saleValue,
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
      'saleValue': saleValue, // null remove (merge mantém, mas seta null)
      'pipelineUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  void _onBoardEvent(BoardEvent event) {
    // ✅ clique no card
    if (event is TaskTappedEvent) {
      _openLeadDialog(chatId: event.task.id); // ✅ abre o popup novo (_LeadDetailsDialog)
      return;
    }

    // mover
    if (event is TaskMovedEvent) {
      _updateLeadStage(docId: event.task.id, stageId: event.destination.id);
      return;
    }

    // editar (evento do kanban)
    if (event is TaskEditedEvent) {
      _updateLeadFromEdit(
        docId: event.newTask.id,
        newTitle: event.newTask.title,
        newSubtitle: event.newTask.subtitle,
      );
      return;
    }

    if (event is TaskRemovedEvent) {
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

  Future<void> _openChatFromKanban(String chatId, String name, String photo) async {
    // marca como aberto e zera contador (igual seu WhatsAppChats faz)
    final ref = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(chatId);

    await ref.set({
      'unreadCount': 0,
      'opened': true,
      'chatId': chatId,
    }, SetOptions(merge: true));

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetail(
          chatId: chatId,
          chatName: name,
          contactPhoto: photo,
        ),
      ),
    );
  }

  Future<void> _openEditLeadDialog(
      String docId, {
        required String initialName,
        required String initialNote,
      }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final noteCtrl = TextEditingController(text: initialNote);

    final cs = Theme.of(context).colorScheme;

  }

  void _moveTaskInBoardProviderNow(String taskId, String destStageId) {
    try {
      final board = _boardProvider.board;        // Board? (pode ser null)
      final columns = board?.columns;            // List<KanbanColumn>? (pode ser null)

      if (columns == null || columns.isEmpty) return;

      KanbanColumn? fromCol;
      Task? foundTask;

      for (final col in columns) {
        final idx = col.tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          fromCol = col;
          foundTask = col.tasks.removeAt(idx);
          break;
        }
      }

      if (foundTask == null) return;

      final destCol = columns.firstWhere(
            (c) => c.id == destStageId,
        orElse: () => fromCol ?? columns.first,
      );

      // coloca no topo da coluna destino
      destCol.tasks.insert(0, foundTask);

      // força UI atualizar
      _boardProvider.notifyListeners();
    } catch (_) {
      // se algo mudar na API interna do pacote, só ignora aqui
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final headerBgHex = _toHexArgb(cs.surface);

// Fundo do card: um pouco mais claro que a coluna pra destacar
    final cardBg = cs.surfaceContainerHigh;

    final kanbanTheme = KanbanTheme(
      boardBackgroundColor: Colors.transparent,
      boardBorderColor: Colors.transparent,
      boardBorderWidth: 0.0,
      columnTheme: KanbanColumnTheme(
        columnBackgroundColor: cs.surface,
        columnBorderColor: Colors.transparent,
        columnBorderWidth: 0.0,
        columnHeaderColor: primary,
        columnHeaderTextColor: cs.onSecondary,
        columnAddButtonBoxColor: primary,
        columnAddIconColor: cs.onPrimary,
      ),
      cardTheme: TaskCardTheme(
        cardBackgroundColor: cardBg,

        // dá um “recorte” leve no card sem ficar com borda branca
        cardBorderColor: cs.onSurface.withOpacity(.05),
        cardBorderWidth: 1.0,

        cardDividerColor: Colors.transparent,

        cardTitleColor: cs.onSecondary,
        cardSubtitleColor: cs.onSecondary.withOpacity(.72),

        // accent (barra lateral do card)
        cardMoveIconEnabledColor: primary,
        cardMoveIconDisabledColor: cs.onSecondary.withOpacity(.25),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar lead (nome, mensagem, telefone)',
                        hintStyle: TextStyle(color: cs.onSecondary),
                        prefixIcon: Icon(Icons.search, color: cs.onSecondary,),
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
                          final tagsMap = <String, TagItem>{};

                          if (tagSnap.hasData) {
                            for (final d in tagSnap.data!.docs) {
                              final m = d.data();

                              final name = (m['name'] ?? '').toString().trim();
                              final rawColor = m['color'];

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

                          // (opcional) mantém no state caso você use em outro lugar
                          _tagMap = tagsMap;

                          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _chatsStream(), // ✅ use .snapshots() (sem metadataChanges)
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

                              // cache (pra você usar em outros fluxos se precisar)
                              _lastFiltered = filtered;
                              _lastTagsMap = tagsMap;
                              _lastHeaderBgHex = headerBgHex;

                              final config = _buildBoardConfig(
                                filtered,
                                headerBgHex: headerBgHex,
                                tagsMap: tagsMap,
                              );

                              final sig = _signatureForBoard(filtered);
                              _scheduleBoardLoad(config, sig);

                              return ChangeNotifierProvider.value(
                                value: _boardProvider,
                                child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    final viewportW = constraints.maxWidth;

                                    final n = _stages.length;
                                    final contentW =
                                        (n * _columnWidth) + ((n - 1) * columnGap) + (sidePadding * 2);

                                    final boardW = math.max(viewportW, contentW);

                                    return Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerSignal: (signal) {
                                        if (signal is! PointerScrollEvent) return;
                                        if (!_hScroll.hasClients) return;

                                        final move = signal.scrollDelta.dx != 0
                                            ? signal.scrollDelta.dx
                                            : signal.scrollDelta.dy;

                                        final max = _hScroll.position.maxScrollExtent;
                                        final next = (_hScroll.offset + move).clamp(0.0, max);

                                        _hScroll.jumpTo(next);
                                      },
                                      child: Scrollbar(
                                        controller: _hScroll,
                                        thumbVisibility: true,
                                        child: SingleChildScrollView(
                                          controller: _hScroll,
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: boardW,
                                            child: BoardWidget(theme: kanbanTheme),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
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

/// Avatar simples para o popup (sem depender do WhatsAppChats)
class _LeadAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  const _LeadAvatar({required this.photoUrl, required this.name});

  String _initials(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join().toUpperCase();
    return letters.isEmpty ? '•' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (photoUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: cs.inverseSurface,
        foregroundImage: NetworkImage(photoUrl),
        child: null,
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: cs.inverseSurface,
      child: Text(
        _initials(name),
        style: TextStyle(color: cs.outline, fontSize: 14),
      ),
    );
  }
}

/// Chip de etapa (pipelineStage) — simples e útil no popup
class _StageChip extends StatelessWidget {
  final String stage;
  const _StageChip({required this.stage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(.35)),
      ),
      child: Text(
        stage,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _LeadDetailsDialog extends StatefulWidget {
  final String empresaId;
  final String phoneId;
  final String chatId;

  final Future<void> Function(String name, String photoUrl) onOpenChat;
  final Future<void> Function(String newName, String newNote) onEdit;
  final Future<void> Function(String stageId) onMoveStage;
  final Future<void> Function(double? value) onEditValue;

  final List<_LeadStage> stages;

  const _LeadDetailsDialog({
    required this.empresaId,
    required this.phoneId,
    required this.chatId,
    required this.onOpenChat,
    required this.onEdit,
    required this.onMoveStage,
    required this.onEditValue, // ✅ novo
    required this.stages,
  });

  @override
  State<_LeadDetailsDialog> createState() => _LeadDetailsDialogState();
}

class _LeadDetailsDialogState extends State<_LeadDetailsDialog> {
  bool _editingNote = false;
  bool _savingNote = false;
  bool _editingValue = false;
  bool _savingValue = false;

  late final TextEditingController _valueCtrl = TextEditingController();
  String _valueOriginal = '';

  late final TextEditingController _noteCtrl = TextEditingController();
  late final FocusNode _noteFocus = FocusNode();
  final GlobalKey _stagePillKey = GlobalKey();

  String _noteOriginal = '';

  @override
  void dispose() {
    _noteCtrl.dispose();
    _noteFocus.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$mi';
  }

  String _fmtAny(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) return _fmtDate(v.toDate());
    if (v is int) return _fmtDate(DateTime.fromMillisecondsSinceEpoch(v));
    if (v is num) return v.toString();
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  String _fmtMoney(dynamic v) {
    if (v == null) return '—';
    double? n;
    if (v is num) n = v.toDouble();
    if (v is String) {
      final s = v
          .replaceAll('.', '')
          .replaceAll(',', '.')
          .replaceAll(RegExp(r'[^0-9\.\-]'), '');
      n = double.tryParse(s);
    }
    if (n == null) return v.toString();
    final fixed = n.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
    );
    return 'R\$ $intPart,${parts[1]}';
  }

  double? _parseMoneyToDouble(String raw) {
    final s = raw
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9\.\-]'), '');

    if (s.trim().isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _enterValueEdit(String currentValueLabel) async {
    if (_savingValue) return;
    setState(() {
      _editingValue = true;
      _valueOriginal = currentValueLabel;
      _valueCtrl.text = currentValueLabel == '—' ? '' : currentValueLabel;
    });
  }

  Future<void> _cancelValueEdit() async {
    if (_savingValue) return;
    setState(() {
      _editingValue = false;
      _valueCtrl.text = _valueOriginal == '—' ? '' : _valueOriginal;
    });
  }

  Future<void> _saveValueEdit() async {
    if (_savingValue) return;

    final parsed = _parseMoneyToDouble(_valueCtrl.text);
    setState(() => _savingValue = true);

    try {
      await widget.onEditValue(parsed);
      if (!mounted) return;
      setState(() {
        _savingValue = false;
        _editingValue = false;
        _valueOriginal = parsed == null ? '—' : _fmtMoney(parsed);
        _valueCtrl.text = parsed == null ? '' : _fmtMoney(parsed);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingValue = false);
    }
  }

  Future<String?> _showStageDropdown(BuildContext context, String currentStageId) async {
    final keyCtx = _stagePillKey.currentContext;
    if (keyCtx == null) return null;

    final box = keyCtx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final cs = Theme.of(context).colorScheme;

    return await showMenu<String>(
      context: context,
      position: pos,
      elevation: 10,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: widget.stages.map((s) {
        final selected = s.id == currentStageId;
        return PopupMenuItem<String>(
          value: s.id,
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.header,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _enterEdit(String currentNote) async {
    if (_savingNote) return;
    setState(() {
      _editingNote = true;
      _noteOriginal = currentNote;
      _noteCtrl.text = currentNote;
    });

    // foca no campo após o rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _noteFocus.requestFocus();
    });
  }

  Future<void> _cancelEdit() async {
    if (_savingNote) return;
    setState(() {
      _editingNote = false;
      _noteCtrl.text = _noteOriginal;
    });
  }

  Future<void> _saveEdit(String name) async {
    if (_savingNote) return;

    final newNote = _noteCtrl.text.trim();
    setState(() => _savingNote = true);

    try {
      await widget.onEdit(name.isEmpty ? 'Contato' : name, newNote);
      if (!mounted) return;
      setState(() {
        _savingNote = false;
        _editingNote = false;
        _noteOriginal = newNote;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingNote = false);
      // opcional: manter edit aberto em erro
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final chatRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(widget.empresaId)
        .collection('phones')
        .doc(widget.phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: chatRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(22),
                child: SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final m = snap.data!.data() ?? {};

            final name =
            (m['name'] ?? m['contactName'] ?? 'Contato').toString().trim();
            final note = (m['pipelineNote'] ?? '').toString();
            final contactPhoto =
            (m['contactPhoto'] ?? m['photoUrl'] ?? '').toString();

            if (!_editingNote && _noteCtrl.text != note) {
              _noteCtrl.text = note;
              _noteOriginal = note;
            }

            final arrivalAt = (m['arrivalAt'] is Timestamp)
                ? (m['arrivalAt'] as Timestamp).toDate()
                : null;
            final attendingAt = (m['attendingAt'] is Timestamp)
                ? (m['attendingAt'] as Timestamp).toDate()
                : null;

            final lastMessage =
            (m['lastMessage'] ?? m['lastMsg'] ?? '').toString();
            final lastMessageTimeRaw = m['lastMessageTime'];
            final saleValueRaw = m['saleValue'];
            final saleValueLabel = _fmtMoney(saleValueRaw);

            if (!_editingValue) {
              final nextText = (saleValueLabel == '—') ? '' : saleValueLabel;
              if (_valueCtrl.text != nextText) {
                _valueCtrl.text = nextText;
                _valueOriginal = saleValueLabel;
              }
            }

            final grad = <Color>[cs.primary, cs.tertiary];

            final infoItems = <_InfoItem>[
              _InfoItem('Data de entrada', _fmtDate(arrivalAt)),
              if (attendingAt != null)
                _InfoItem('Atendendo desde', _fmtDate(attendingAt)),
              _InfoItem('Horário da última mensagem', _fmtAny(lastMessageTimeRaw)),
            ];

            final currentStageId = (m['pipelineStage'] ?? 'entrada').toString();
            final currentStageLabel = widget.stages
                .where((s) => s.id == currentStageId)
                .map((s) => s.header)
                .cast<String?>()
                .firstWhere((x) => x != null, orElse: () => null)
                ?? currentStageId;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ===== Header =====
                Container(
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                    border: Border(
                      bottom: BorderSide(color: cs.onSurface.withOpacity(.06)),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: cs.surfaceContainerHighest,
                        foregroundImage: contactPhoto.trim().isNotEmpty
                            ? NetworkImage(contactPhoto)
                            : null,
                        child: contactPhoto.trim().isEmpty
                            ? Icon(Icons.person,
                            color: cs.onSurface.withOpacity(.55))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Contato' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Pill(
                                  icon: Icons.local_fire_department_rounded,
                                  label: 'Atendimento',
                                  colors: grad,
                                  fg: cs.onSecondary,
                                  bd: cs.primary,
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final selected = await _showStageDropdown(context, currentStageId);
                                    if (!mounted) return;
                                    if (selected != null && selected != currentStageId) {
                                      await widget.onMoveStage(selected);
                                      setState(() {}); // só pra refletir o label no popup sem esperar stream
                                    }
                                  },
                                  child: Container(
                                    key: _stagePillKey,
                                    child: _Pill(
                                      icon: Icons.tag_rounded,
                                      label: '$currentStageLabel ▾', // opcional: indica dropdown
                                      colors: grad,
                                      fg: cs.onSecondary,
                                      bd: cs.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close,
                            color: cs.onSurface.withOpacity(.75)),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),

                // ===== Conteúdo =====
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      children: [
                        _InfoGrid(items: infoItems),
                        const SizedBox(height: 12),

                        _FieldBox(
                          title: 'Valor do orçamento',
                          topRight: _editingValue
                              ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Salvar',
                                splashRadius: 18,
                                icon: Icon(Icons.check_rounded,
                                    size: 20, color: cs.primary.withOpacity(.95)),
                                onPressed: _savingValue ? null : _saveValueEdit,
                              ),
                              IconButton(
                                tooltip: 'Cancelar',
                                splashRadius: 18,
                                icon: Icon(Icons.close_rounded,
                                    size: 20, color: cs.onSurface.withOpacity(.70)),
                                onPressed: _savingValue ? null : _cancelValueEdit,
                              ),
                            ],
                          )
                              : IconButton(
                            tooltip: 'Editar valor',
                            splashRadius: 18,
                            icon: Icon(Icons.edit_rounded,
                                size: 18, color: cs.onSurface.withOpacity(.70)),
                            onPressed: () => _enterValueEdit(saleValueLabel),
                          ),
                          child: _editingValue
                              ? TextField(
                            controller: _valueCtrl,
                            enabled: !_savingValue,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withOpacity(.45),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary.withOpacity(.35)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary.withOpacity(.25)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary.withOpacity(.55)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              hintText: 'Ex: 1500,00',
                            ),
                            style: TextStyle(color: cs.onSurface.withOpacity(.90)),
                          )
                              : Text(
                            saleValueLabel,
                            style: TextStyle(color: cs.onSurface.withOpacity(.88)),
                          ),
                        ),

                        _FieldBox(
                          title: 'Última mensagem',
                          child: Text(
                            lastMessage.trim().isEmpty ? '—' : lastMessage.trim(),
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.88),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ===== Observação com edição inline =====
                        _FieldBox(
                          title: 'Observação',
                          topRight: _editingNote
                              ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Salvar',
                                splashRadius: 18,
                                icon: Icon(Icons.check_rounded,
                                    size: 20,
                                    color: cs.primary.withOpacity(.95)),
                                onPressed: _savingNote
                                    ? null
                                    : () => _saveEdit(name),
                              ),
                              IconButton(
                                tooltip: 'Cancelar',
                                splashRadius: 18,
                                icon: Icon(Icons.close_rounded,
                                    size: 20,
                                    color: cs.onSurface.withOpacity(.70)),
                                onPressed: _savingNote ? null : _cancelEdit,
                              ),
                            ],
                          )
                              : IconButton(
                            tooltip: 'Editar observação',
                            splashRadius: 18,
                            icon: Icon(Icons.edit_rounded,
                                size: 18,
                                color: cs.onSurface.withOpacity(.70)),
                            onPressed: () => _enterEdit(note),
                          ),
                          child: _editingNote
                              ? TextField(
                            controller: _noteCtrl,
                            focusNode: _noteFocus,
                            enabled: !_savingNote,
                            maxLines: 4,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: cs.surfaceContainerHighest
                                  .withOpacity(.45),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withOpacity(.35),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withOpacity(.25),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withOpacity(.55),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.90),
                            ),
                          )
                              : Text(
                            note.trim().isEmpty ? '—' : note.trim(),
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.88),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ===== Botões =====
                        Row(
                          children: [
                            Expanded(
                              child: _GradientButton(
                                onPressed: () async {
                                  await widget.onOpenChat(
                                    name.isEmpty ? 'Contato' : name,
                                    contactPhoto,
                                  );
                                },
                                colors: grad,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_bubble_outline,
                                        size: 18, color: cs.onSecondary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Abrir conversa',
                                      style: TextStyle(
                                        color: cs.onSecondary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final Color fg;
  final Color bd;

  const _Pill({
    required this.icon,
    required this.label,
    required this.colors,
    required this.fg,
    required this.bd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd.withOpacity(.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
  }
}

class _InfoItem {
  final String title;
  final String value;
  _InfoItem(this.title, this.value);
}

class _InfoGrid extends StatelessWidget {
  final List<_InfoItem> items;
  const _InfoGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 520;
        final cells = items.map((it) => _InfoCell(item: it)).toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withOpacity(.06)),
          ),
          child: isNarrow
              ? Column(
            children: [
              for (int i = 0; i < cells.length; i++) ...[
                cells[i],
                if (i != cells.length - 1) const SizedBox(height: 10),
              ],
            ],
          )
              : Column(
            children: [
              for (int i = 0; i < cells.length; i += 2) ...[
                Row(
                  children: [
                    Expanded(child: cells[i]),
                    const SizedBox(width: 10),
                    Expanded(child: (i + 1 < cells.length) ? cells[i + 1] : const SizedBox.shrink()),
                  ],
                ),
                if (i + 2 < cells.length) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoCell extends StatelessWidget {
  final _InfoItem item;
  const _InfoCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (item.title.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSecondary.withOpacity(.80),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? topRight;

  const _FieldBox({
    required this.title,
    required this.child,
    this.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withOpacity(.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSecondary,
                  ),
                ),
              ),
              if (topRight != null) topRight!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EditResult {
  final String name;
  final String note;
  _EditResult(this.name, this.note);
}

class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final BorderRadius borderRadius;
  final List<Color> colors;
  final EdgeInsets padding;

  const _GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.colors,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : .55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
          ),
          borderRadius: borderRadius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onPressed,
            child: Padding(
              padding: padding,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
