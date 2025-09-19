import 'dart:async';
import 'dart:math' as math;

import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class CreateChatbotFunnelPage extends StatefulWidget {
  const CreateChatbotFunnelPage({Key? key, this.chatbotId}) : super(key: key);

  final String? chatbotId;

  @override
  State<CreateChatbotFunnelPage> createState() => _CreateChatbotPageState();
}

/* ===========================================================
 *                     MODELOS DO FLUXO
 * =========================================================== */

enum NodeType { start, message, menu, handoff, end }

enum WaitUnit { minutes, hours, days }

// --- TAGS (etiquetas) da empresa ---
// Coloque ISTO no TOPO DO ARQUIVO (nível de arquivo), fora de _CreateChatbotPageState:
class _Tag {
  final String id;
  final String name;
  final Color color;

  _Tag({required this.id, required this.name, required this.color});
}

class FunnelNode {
  FunnelNode({
    required this.id,
    required this.type,
    required this.pos,
    this.title = '',
    Map<String, dynamic>? data,
  }) : data = data ?? {};

  String id;
  NodeType type;
  Offset pos; // posição no canvas
  String title;
  Map<String, dynamic> data;

  FunnelNode copyWith({
    String? id,
    NodeType? type,
    Offset? pos,
    String? title,
    Map<String, dynamic>? data,
  }) {
    return FunnelNode(
      id: id ?? this.id,
      type: type ?? this.type,
      pos: pos ?? this.pos,
      title: title ?? this.title,
      data: data ?? Map<String, dynamic>.from(this.data),
    );
  }
}

class LinkEdge {
  LinkEdge({
    required this.fromNodeId,
    required this.fromPort, // ex.: 'out', 'onReply', 'onTimeout', 'opt:1'
    required this.toNodeId, // entrada única do nó-alvo (sempre 'in')
  });

  String fromNodeId;
  String fromPort;
  String toNodeId;

  Map<String, dynamic> toJson() => {
        'fromNodeId': fromNodeId,
        'fromPort': fromPort,
        'toNodeId': toNodeId,
      };

  static LinkEdge fromJson(Map<String, dynamic> j) => LinkEdge(
        fromNodeId: j['fromNodeId'],
        fromPort: j['fromPort'],
        toNodeId: j['toNodeId'],
      );
}

/* ===========================================================
 *                         PÁGINA
 * =========================================================== */

class _CreateChatbotPageState extends State<CreateChatbotFunnelPage> {
  final _formKey = GlobalKey<FormState>();

  final GlobalKey _rightPanelKey = GlobalKey();

  _Tag? _tagById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final t in _tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool _saving = false;
  String? _empresaId;
  bool _resolving = true;
  String? _resolveError;
  int _anchorsVersion = 0;
  LinkEdge? _hoverEdge; // aresta atualmente sob o mouse
  Offset?
      _hoverEdgeWorld; // ponto na curva (em coords do mundo) para posicionar o botão
  static const double _edgeHitEnterPx = 16.0; // entrar no hover
  static const double _edgeHitExitPx = 22.0; // sair do hover (histerese)

  // --- edição ---
  String? _chatbotId;

  bool get _isEditing => _chatbotId != null;

  bool _loadingChatbot = false;
  String? _loadError;

  List<_Tag> _tags = [];
  bool _loadingTags = false;
  String? _tagsError;

  Color _colorFrom(dynamic raw) {
    try {
      if (raw is int) {
        final v = raw <= 0xFFFFFF ? (0xFF000000 | raw) : raw;
        return Color(v);
      }
      if (raw is String) {
        var s = raw.trim();
        if (s.startsWith('#')) s = s.substring(1);
        if (s.startsWith('0x')) s = s.substring(2);
        var v = int.parse(s, radix: 16);
        if (v <= 0xFFFFFF) v |= 0xFF000000;
        return Color(v);
      }
    } catch (_) {}
    return Colors.grey;
  }

  void _handleGlobalPointerDown(PointerDownEvent e) {
    // Só faz algo se o painel estiver aberto
    if (_selectedNodeId == null) return;

    final ctx = _rightPanelKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;

    // Se clicou FORA do painel, fecha-o
    if (!rect.contains(e.position)) {
      setState(() => _selectedNodeId = null);
    }
  }

  Future<void> _showNotice({
    required String title,
    required String message,
    String buttonText = 'Ok',
  }) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondary,
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                message,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: theme.colorScheme.onSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
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
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tagPickerField(FunnelNode n) {
    final String sel = (n.data['tagId'] ?? '').toString();

    return _Labeled(
      'Quando o contato chegar aqui, aplicar etiqueta',
      DropdownButtonFormField<String>(
        value: sel.isEmpty ? '' : sel,
        // <- String sempre
        isExpanded: true,
        decoration: _dec(context, 'Selecionar etiqueta'),
        items: [
          const DropdownMenuItem<String>(
            value: '', // <- NUNCA use null aqui
            child: Text('Nenhuma'),
          ),
          ..._tags.map((t) => DropdownMenuItem<String>(
                // <- <String> explícito
                value: t.id,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: EdgeInsets.only(right: 8),
                      decoration:
                          BoxDecoration(color: t.color, shape: BoxShape.circle),
                    ),
                    Text(t.name),
                  ],
                ),
              )),
        ],
        onChanged: (val) => setState(() {
          n.data['tagId'] = (val ?? '').toString(); // <- salva como String
        }),
      ),
    );
  }

  Future<void> _loadTags() async {
    if (_empresaId == null) return;
    setState(() {
      _loadingTags = true;
      _tagsError = null;
    });
    try {
      final qs = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(_empresaId)
          .collection('tags')
          .get();

      final list = <_Tag>[];
      for (final doc in qs.docs) {
        final d = (doc.data() ?? <String, dynamic>{});
        final name = (d['name'] ?? '').toString();
        final color = _colorFrom(d['color']);
        list.add(_Tag(id: doc.id, name: name, color: color));
      }
      list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _tags = list;
        _loadingTags = false;
      });
    } catch (e) {
      setState(() {
        _tagsError = 'Falha ao carregar etiquetas: $e';
        _loadingTags = false;
      });
    }
  }

  // world -> canvas (tela)
  Offset _worldToCanvas(Offset world) {
    final m = _canvasController.value;
    final v = vm.Vector3(world.dx, world.dy, 0);
    final r = m.transform3(v);
    return Offset(r.x, r.y);
  }

// mesmo cálculo do painter: centro do "port" (saida/entrada)
  Offset _portCenterWorld(FunnelNode n, String port, {required bool isOut}) {
    // 1) usa anchor local reportado (preciso)
    if (isOut) {
      final local = _outAnchors[n.id]?[port];
      if (local != null) return n.pos + local;
    }

    // 2) fallback geométrico
    const w = _CreateChatbotPageState.nodeWidth;
    const h = _CreateChatbotPageState.baseNodeHeight;
    final x = n.pos.dx + (isOut ? w : 0);
    double y = n.pos.dy + h * .5;

    if (n.type == NodeType.message && isOut) {
      y = port == 'onTimeout' ? (n.pos.dy + 100) : (n.pos.dy + 60);
    } else if (n.type == NodeType.menu && isOut) {
      final List opts = (n.data['options'] as List?) ?? [];
      if (opts.isNotEmpty) {
        final idx = opts.indexWhere((o) => 'opt:${o['key']}' == port);
        if (idx >= 0) y = n.pos.dy + 56 + 18.0 * (idx.clamp(0, 4));
      }
      if (port == 'onTimeout') y = n.pos.dy + 100;
    }
    return Offset(x, y);
  }

// ponto mais próximo em um segmento AB
  ({Offset point, double dist}) _closestOnSegment(
      Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return (point: a, dist: (p - a).distance);
    double t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / ab2;
    t = t.clamp(0.0, 1.0);
    final q = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (point: q, dist: (p - q).distance);
  }

// aproxima a curva bézier por amostragem e retorna ponto/ distância
  ({Offset point, double dist}) _nearestOnCubic({
    required Offset p,
    required Offset p0,
    required Offset c1,
    required Offset c2,
    required Offset p1,
    int samples = 48,
  }) {
    Offset bez(double t) {
      final u = 1 - t;
      final tt = t * t, uu = u * u;
      final uuu = uu * u, ttt = tt * t;
      final x =
          uuu * p0.dx + 3 * uu * t * c1.dx + 3 * u * tt * c2.dx + ttt * p1.dx;
      final y =
          uuu * p0.dy + 3 * uu * t * c1.dy + 3 * u * tt * c2.dy + ttt * p1.dy;
      return Offset(x, y);
    }

    var bestDist = double.infinity;
    Offset bestPoint = p0;
    Offset prev = p0;
    for (int i = 1; i <= samples; i++) {
      final t = i / samples;
      final cur = bez(t);
      final res = _closestOnSegment(p, prev, cur);
      if (res.dist < bestDist) {
        bestDist = res.dist;
        bestPoint = res.point;
      }
      prev = cur;
    }
    return (point: bestPoint, dist: bestDist);
  }

  Map<String, dynamic> _deepCloneMap(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (v is Map) {
        out[k] = _deepCloneMap(Map<String, dynamic>.from(v as Map));
      } else if (v is List) {
        out[k] = _deepCloneList(v);
      } else if (v is Offset) {
        out[k] = Offset(v.dx, v.dy); // segurança p/ tipos imutáveis simples
      } else {
        out[k] = v; // String, num, bool, null, etc.
      }
    });
    return out;
  }

  List _deepCloneList(List src) {
    return src.map((e) {
      if (e is Map) return _deepCloneMap(Map<String, dynamic>.from(e));
      if (e is List) return _deepCloneList(e);
      if (e is Offset) return Offset(e.dx, e.dy);
      return e;
    }).toList();
  }

  NodeType _nodeTypeFromName(String s) {
    switch (s) {
      case 'start':
        return NodeType.start;
      case 'menu':
        return NodeType.menu;
      case 'handoff':
        return NodeType.handoff;
      case 'end':
        return NodeType.end;
      default:
        return NodeType.message;
    }
  }

  Offset _toOffset(dynamic pos) {
    if (pos is Map) {
      final m = pos.cast<String, dynamic>();
      return Offset(
        (m['x'] as num?)?.toDouble() ?? 100,
        (m['y'] as num?)?.toDouble() ?? 100,
      );
    }
    return const Offset(100, 100);
  }

  // Básico
  final _nameCtrl = TextEditingController(text: '');
  final _descCtrl = TextEditingController(text: '');
  final _fallbackCtrl =
      TextEditingController(text: 'Não entendi. Responda com um número.');

  // Canvas & seleção
  final _canvasController = TransformationController();
  final _scroll = ScrollController();
  String? _selectedNodeId;

  // ligação pendente (drag)
  String? _pendingFromNodeId;
  String? _pendingFromPort;
  Offset? _dragWorld; // cursor do drag em coords do "mundo"

  // Grafo na memória
  final Map<String, FunnelNode> _nodes = {};
  final List<LinkEdge> _edges = [];
  final Map<String, Map<String, Offset>> _outAnchors =
      {}; // nodeId -> {port: worldOffset}

  // key do canvas p/ converter global -> world
  final _canvasKey = GlobalKey();

  // layout / tamanhos
  static const nodeWidth = 300.0;
  static const baseNodeHeight = 120.0;

  // Mundo virtual gigante
  static const Size _worldSize = Size(8000, 6000);

  @override
  void initState() {
    super.initState();
    _chatbotId = widget.chatbotId;
    _canvasController.addListener(_onMatrixChanged);
    _resolveEmpresaId();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _fallbackCtrl.dispose();
    _scroll.dispose();
    _canvasController.removeListener(_onMatrixChanged);
    super.dispose();
  }

  String? _nodeIdAtWorld(Offset world, {double pad = 24}) {
    for (final n in _nodes.values) {
      final r = Rect.fromLTWH(n.pos.dx, n.pos.dy, nodeWidth, baseNodeHeight)
          .inflate(pad);
      if (r.contains(world)) return n.id;
    }
    return null;
  }

  void _onMatrixChanged() {
    if (_hoverEdge != null || _hoverEdgeWorld != null) {
      setState(() {
        _hoverEdge = null;
        _hoverEdgeWorld = null;
      });
    }
    // Se estiver arrastando uma aresta, comente a linha abaixo pra não interromper o drag.
    // setState(() => _dragWorld = null);
  }

  Offset _globalToWorld(Offset global) {
    final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    // Já retorna no espaço do child (seu "mundo"), considerando pan/zoom.
    return box.globalToLocal(global);
  }

// Agora gravamos o OFFSET LOCAL da bolinha (relativo ao nó).
  void _recordOutAnchor(String nodeId, String port, Offset localInNode) {
    final prev = _outAnchors[nodeId]?[port];
    if (prev == null || (prev - localInNode).distanceSquared > 0.25) {
      setState(() {
        (_outAnchors[nodeId] ??= {})[port] = localInNode; // <- LOCAL
        _anchorsVersion++; // força repaint do painter
      });
    }
  }

  Future<void> _maybeLoadOrBootstrap() async {
    if (!mounted) return;

    if (_empresaId == null) return;

    if (_isEditing) {
      await _loadExistingChatbot();
    } else {
      _nodes.clear();
      _edges.clear();
      _bootstrapFlow();
    }
  }

  Future<void> _loadExistingChatbot() async {
    if (_empresaId == null || _chatbotId == null) return;
    setState(() {
      _loadingChatbot = true;
      _loadError = null;
    });

    try {
      final ref = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_empresaId)
          .collection('chatbots')
          .doc(_chatbotId);

      final snap = await ref.get();
      if (!snap.exists) {
        setState(() {
          _loadError = 'Chatbot não encontrado.';
          _loadingChatbot = false;
        });
        return;
      }

      final data = (snap.data() ?? {}) as Map<String, dynamic>;

      // Preenche os campos básicos
      _nameCtrl.text = (data['name'] ?? '').toString();
      _descCtrl.text = (data['description'] ?? '').toString();
      _fallbackCtrl.text = ((data['fallback']?['message']) ??
              'Não entendi. Responda com um número.')
          .toString();

      // Reconstrói o grafo salvo
      _nodes.clear();
      _edges.clear();
      final flow = (data['flow'] ?? {}) as Map<String, dynamic>;
      final List rawNodes = (flow['nodes'] ?? []) as List;
      for (final raw in rawNodes) {
        final m = (raw as Map).cast<String, dynamic>();
        final node = FunnelNode(
          id: (m['id'] ?? _genId()).toString(),
          type: _nodeTypeFromName((m['type'] ?? 'message').toString()),
          pos: _toOffset(m['pos']),
          title: (m['title'] ?? '').toString(),
          data: Map<String, dynamic>.from((m['data'] ?? {}) as Map),
        );
        _nodes[node.id] = node;
      }

      final List rawEdges = (flow['edges'] ?? []) as List;
      _edges.addAll(rawEdges
          .map((e) => LinkEdge.fromJson((e as Map).cast<String, dynamic>())));

      setState(() {
        _loadingChatbot = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Falha ao carregar: $e';
        _loadingChatbot = false;
      });
    }
  }

  Widget _tagPicker(ColorScheme cs, FunnelNode n) {
    final current = (n.data['tagId'] ?? '').toString();

    return _Labeled(
      'Etiqueta automática (opcional)',
      DropdownButtonFormField<String>(
        value: current.isEmpty ? '' : current, // <- String
        decoration: _dec(context, '', dense: true),
        items: [
          const DropdownMenuItem<String>(
            value: '', // <- String vazia
            child: Text('— Nenhuma —'),
          ),
          ..._tags.map((t) => DropdownMenuItem<String>(
                value: t.id,
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: t.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(t.name),
                  ],
                ),
              )),
        ],
        onChanged: (v) => setState(() => n.data['tagId'] = v ?? ''),
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
      final User? user =
          authProvider?.user ?? FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          _resolveError = 'Usuário não autenticado.';
          _resolving = false;
        });
        return;
      }

      final uid = user.uid;

      // 1) empresas/{uid}
      final empDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(uid)
          .get();

      if (empDoc.exists) {
        setState(() {
          _empresaId = uid;
          _resolving = false;
        });
        await Future.wait([
          _maybeLoadOrBootstrap(),
          _loadTags(),
        ]);
        return;
      }

      // 2) users/{uid} -> createdBy
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
        await Future.wait([
          _maybeLoadOrBootstrap(),
          _loadTags(),
        ]);
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

  /* -----------------------------------------------------------
   *                      FLOW INICIAL
   * ----------------------------------------------------------- */

  double get _currentScale => _canvasController.value.getMaxScaleOnAxis();

  Offset _clampToWorld(Offset p,
      {double w = nodeWidth, double h = baseNodeHeight}) {
    final maxX = _worldSize.width - w;
    final maxY = _worldSize.height - h;
    return Offset(
      p.dx.clamp(0.0, maxX),
      p.dy.clamp(0.0, maxY),
    );
  }

  bool _hitAnyNode(Offset worldPoint) {
    for (final n in _nodes.values) {
      final rect = Rect.fromLTWH(n.pos.dx, n.pos.dy, nodeWidth, baseNodeHeight);
      if (rect.contains(worldPoint)) return true;
    }
    return false;
  }

  void _bootstrapFlow() {
    final start = _newNode(
      type: NodeType.message,
      pos: const Offset(100, 100),
      title: 'MSG 1 — Saudação — Texto',
      data: {
        'text': 'Olá! 👋 Como posso ajudar?',
        'attachments': <String>{'typing'}.toList(),
        'waitValue': 10,
        'waitUnit': WaitUnit.minutes.name,
      },
    );
    _nodes[start.id] = start;

    final end = _newNode(
      type: NodeType.end,
      pos: const Offset(900, 120),
      title: 'MSG — Encerramento',
    );
    _nodes[end.id] = end;

    // Dois caminhos SEMPRE: respondeu / não respondeu
    _edges.addAll([
      LinkEdge(fromNodeId: start.id, fromPort: 'onReply', toNodeId: end.id),
      LinkEdge(fromNodeId: start.id, fromPort: 'onTimeout', toNodeId: end.id),
    ]);

    setState(() {});
  }

  String _genId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(99999)}';

  FunnelNode _newNode({
    required NodeType type,
    required Offset pos,
    String? title,
    Map<String, dynamic>? data,
  }) {
    return FunnelNode(
      id: _genId(),
      type: type,
      pos: pos,
      title: title ?? _defaultTitle(type),
      data: data ?? _defaultData(type),
    );
  }

  String _defaultTitle(NodeType t) {
    switch (t) {
      case NodeType.message:
        return 'Mensagem — Texto';
      case NodeType.menu:
        return 'Menu';
      case NodeType.handoff:
        return 'Encerrar/Handoff';
      case NodeType.end:
        return 'Fim';
      case NodeType.start:
        return 'Início';
    }
  }

  Map<String, dynamic> _defaultData(NodeType t) {
    switch (t) {
      case NodeType.message:
        return {
          'text': 'Escreva sua mensagem aqui.',
          'waitValue': 10,
          'waitUnit': WaitUnit.minutes.name,
          'var': '',
          'tagId': '', // <<< NOVO
        };
      case NodeType.menu:
        return {
          'prompt': 'Escolha uma opção:',
          'options': [
            {'key': '1', 'label': 'Opção 1'},
          ],
          'waitValue': 10,
          'waitUnit': WaitUnit.minutes.name,
          'var': '',
          'tagId': '', // <<< NOVO
        };
      case NodeType.handoff:
        return {
          'text':
              'Estamos transferindo seu atendimento para um atendente. Por favor, aguarde.',
          'tagId': '', // <<< NOVO
        };
      case NodeType.end:
        return {
          'text': 'Encerrando seu atendimento. Obrigado por falar com a gente!',
          'tagId': '', // <<< NOVO
        };
      case NodeType.start:
        return {};
    }
  }

  /* -----------------------------------------------------------
   *                     AÇÕES DE CANVAS
   * ----------------------------------------------------------- */

  void _addNode(NodeType t) {
    final size = MediaQuery.of(context).size;
    final worldCenter = _globalToWorld(Offset(size.width / 2, size.height / 2));
    final node = _newNode(type: t, pos: worldCenter.translate(-150, -60));
    setState(() => _nodes[node.id] = node);
  }

  void _removeNode(String nodeId) {
    setState(() {
      _nodes.remove(nodeId);
      _edges.removeWhere((e) => e.fromNodeId == nodeId || e.toNodeId == nodeId);
      if (_selectedNodeId == nodeId) _selectedNodeId = null;
    });
  }

  void _duplicateNode(String nodeId) {
    final original = _nodes[nodeId];
    if (original == null) return;

    final copy = original.copyWith(
      id: _genId(),
      pos: _clampToWorld(original.pos + const Offset(40, 40)),
      title: original.title,
      data: _deepCloneMap(original.data),
    );

    setState(() {
      _nodes[copy.id] = copy;
      _selectedNodeId = copy.id;
    });
  }

  void _startLink(String nodeId, String fromPort) {
    setState(() {
      _pendingFromNodeId = nodeId;
      _pendingFromPort = fromPort;
    });
  }

  void _finishLink(String toNodeId) {
    if (_pendingFromNodeId == null || _pendingFromPort == null) return;
    if (_pendingFromNodeId == toNodeId) {
      setState(() {
        _pendingFromNodeId = null;
        _pendingFromPort = null;
      });
      return;
    }

    final exists = _edges.any((e) =>
        e.fromNodeId == _pendingFromNodeId &&
        e.fromPort == _pendingFromPort &&
        e.toNodeId == toNodeId);
    if (exists) {
      setState(() {
        _pendingFromNodeId = null;
        _pendingFromPort = null;
      });
      return;
    }

    setState(() {
      _edges.add(LinkEdge(
          fromNodeId: _pendingFromNodeId!,
          fromPort: _pendingFromPort!,
          toNodeId: toNodeId));
      _pendingFromNodeId = null;
      _pendingFromPort = null;
    });
  }

  void _deleteEdge(LinkEdge e) {
    setState(() => _edges.remove(e));
  }

  Offset _canvasToWorld(Offset canvasOffset) {
    final m = _canvasController.value.clone()..invert();
    final v = vm.Vector3(canvasOffset.dx, canvasOffset.dy, 0);
    final r = m.transform3(v);
    return Offset(r.x, r.y);
  }

  /// Tenta localizar em qual phone e qual doc de whatsappChats está este contato.
  Future<({String phoneId, String chatId})?> _findPhoneAndChatForContact(
    String empresaId,
    String contactJid, {
    String? preferPhoneId,
    String? preferChatId,
  }) async {
    final phonesCol = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones');

    final numberOnly = contactJid.split('@').first;

    // Função utilitária para tentar em um phone específico
    Future<({String phoneId, String chatId})?> _tryInPhone(
        String phoneId) async {
      final chats = phonesCol.doc(phoneId).collection('whatsappChats');

      // 1) se veio um chatId preferido, confira
      if (preferChatId != null && preferChatId.isNotEmpty) {
        final snap = await chats.doc(preferChatId).get();
        if (snap.exists) return (phoneId: phoneId, chatId: preferChatId);
      }

      // 2) tente por IDs candidatos (JID e número puro)
      for (final cand in <String>[contactJid, numberOnly]) {
        final s = await chats.doc(cand).get();
        if (s.exists) return (phoneId: phoneId, chatId: s.id);
      }

      // 3) tente por campos comuns
      Future<({String phoneId, String chatId})?> _q(
          String field, String val) async {
        final qs = await chats.where(field, isEqualTo: val).limit(1).get();
        if (qs.docs.isNotEmpty) {
          return (phoneId: phoneId, chatId: qs.docs.first.id);
        }
        return null;
      }

      return await (_q('jid', contactJid) ??
          _q('contactId', contactJid) ??
          _q('waId', numberOnly) ??
          _q('phone', numberOnly));
    }

    // Priorize o phone explícito (se souber)
    if (preferPhoneId != null && preferPhoneId.isNotEmpty) {
      final hit = await _tryInPhone(preferPhoneId);
      if (hit != null) return hit;
    }

    // Senão, procure em todos os phones da empresa
    final phones = await phonesCol.get();
    for (final ph in phones.docs) {
      final hit = await _tryInPhone(ph.id);
      if (hit != null) return hit;
    }

    return null;
  }

  /* -----------------------------------------------------------
   *                        SALVAR
   * ----------------------------------------------------------- */

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _empresaId == null) return;
    setState(() => _saving = true);

    // 👇 estamos criando se ainda não estamos editando
    final bool isCreate = !_isEditing;

    try {
      final compiled = _compileToStepsLite();
      if (compiled.steps.isEmpty) {
        throw Exception('Fluxo vazio: crie pelo menos um bloco.');
      }

      final base = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'defaultSpacingMs': 1200,
        'startStepId': compiled.startStepId,
        'steps': compiled.steps,
        'greeting': '',
        'fallback': {
          'message': _fallbackCtrl.text.trim().isEmpty
              ? 'Não entendi. Responda com um número.'
              : _fallbackCtrl.text.trim(),
          'maxRetries': 2,
          'onFail': 'handoff'
        },
        'officeHours': {'enabled': false},
        'flow': {
          'nodes': _nodes.values.map((n) => {
            'id': n.id,
            'type': n.type.name,
            'title': n.title,
            'pos': {'x': n.pos.dx, 'y': n.pos.dy},
            'data': n.data,
          }).toList(),
          'edges': _edges.map((e) => e.toJson()).toList(),
        },
      };

      final col = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_empresaId)
          .collection('chatbots');

      if (_isEditing) {
        await col.doc(_chatbotId).set(
          {...base, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      } else {
        final doc = await col.add(
          {...base, 'createdAt': FieldValue.serverTimestamp()},
        );
        setState(() => _chatbotId = doc.id);
      }

      if (!mounted) return;

      await _showNotice(
        title: isCreate ? 'Chatbot criado com sucesso' : 'Alterações salvas',
        message: isCreate
            ? 'Seu chatbot foi criado com sucesso.'
            : 'As alterações do chatbot foram salvas.',
        buttonText: 'Ok',
      );
    } catch (e) {
      if (!mounted) return;
      await _showNotice(
        title: 'Erro ao salvar',
        message: 'Falha ao salvar: $e',
        buttonText: 'Fechar',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateEdgeHoverAtWorld(Offset worldPt) {
    if (_pendingFromNodeId != null) {
      if (_hoverEdge != null) {
        setState(() {
          _hoverEdge = null;
          _hoverEdgeWorld = null;
        });
      }
      return;
    }

    if (_hitAnyNode(worldPt)) {
      if (_hoverEdge != null) {
        setState(() {
          _hoverEdge = null;
          _hoverEdgeWorld = null;
        });
      }
      return;
    }

    final double thresholdWorld =
        ((_hoverEdge == null) ? _edgeHitEnterPx : _edgeHitExitPx) /
            (_currentScale == 0 ? 1.0 : _currentScale);

    LinkEdge? best;
    Offset? bestWorld;
    double bestDist = double.infinity;

    for (final e in _edges) {
      final from = _nodes[e.fromNodeId];
      final to = _nodes[e.toNodeId];
      if (from == null || to == null) continue;

      final sW = _portCenterWorld(from, e.fromPort, isOut: true);
      final tW = _portCenterWorld(to, 'in', isOut: false);

      final dx = (tW.dx - sW.dx).abs();
      final c1W = Offset(sW.dx + dx * .5, sW.dy);
      final c2W = Offset(tW.dx - dx * .5, tW.dy);

      final minX = math.min(math.min(sW.dx, tW.dx), math.min(c1W.dx, c2W.dx));
      final maxX = math.max(math.max(sW.dx, tW.dx), math.max(c1W.dx, c2W.dx));
      final minY = math.min(math.min(sW.dy, tW.dy), math.min(c1W.dy, c2W.dy));
      final maxY = math.max(math.max(sW.dy, tW.dy), math.max(c1W.dy, c2W.dy));
      if (worldPt.dx < minX - thresholdWorld ||
          worldPt.dx > maxX + thresholdWorld ||
          worldPt.dy < minY - thresholdWorld ||
          worldPt.dy > maxY + thresholdWorld) {
        continue;
      }

      final res = _nearestOnCubic(
          p: worldPt, p0: sW, c1: c1W, c2: c2W, p1: tW, samples: 96);
      if (res.dist < bestDist) {
        bestDist = res.dist;
        bestWorld = res.point;
        best = e;
      }
    }

    final nextEdge = (best != null && bestDist <= thresholdWorld) ? best : null;
    final nextWorld = bestWorld;

    if (!identical(nextEdge, _hoverEdge) ||
        (nextWorld != null &&
            (_hoverEdgeWorld == null ||
                (_hoverEdgeWorld! - nextWorld).distanceSquared > 1))) {
      setState(() {
        _hoverEdge = nextEdge;
        _hoverEdgeWorld = nextWorld;
      });
    }
  }

  Future<void> applyStepActions({
    required String contactId, // ex.: "554691073494@s.whatsapp.net"
    required Map<String, dynamic> step,
    String? phoneId, // opcional: se já souber o phone
    String? whatsappChatsId, // opcional: se já souber o chatId
  }) async {
    final actions = (step['actions'] as Map?)?.cast<String, dynamic>();
    if (actions == null) return;

    final String tagId = (actions['addTagId'] ?? '').toString().trim();
    if (tagId.isEmpty) return;

    final empresaId = _empresaId;
    if (empresaId == null || empresaId.isEmpty) {
      debugPrint('[applyStepActions] empresaId ausente.');
      return;
    }

    // Descobrir phoneId + chatId
    final hit = await _findPhoneAndChatForContact(
      empresaId,
      contactId,
      preferPhoneId: phoneId,
      preferChatId: whatsappChatsId,
    );

    if (hit == null) {
      debugPrint(
          '[applyStepActions] Chat não encontrado para $contactId em $empresaId.');
      return;
    }

    final chatRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(hit.phoneId)
        .collection('whatsappChats')
        .doc(hit.chatId);

    // Grava a etiqueta no array "tags" do chat
    await chatRef.set({
      'tags': FieldValue.arrayUnion([tagId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // (Opcional) espelhar em subcoleção "tags" para histórico/queries
    // await chatRef.collection('tags').doc(tagId).set({
    //   'createdAt': FieldValue.serverTimestamp(),
    // }, SetOptions(merge: true));

    debugPrint('[applyStepActions] Tag "$tagId" aplicada em '
        'empresas/$empresaId/phones/${hit.phoneId}/whatsappChats/${hit.chatId}');
  }

  // ---------- Compilador de grafo → steps ----------
  _CompiledSteps _compileToStepsLite() {
    // ---- helpers locais
    final used = <String>{};
    String _makeStepId(String nodeId) {
      final safe = nodeId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      var base = 's_$safe';
      if (base.length > 28) base = base.substring(0, 28);
      var id = base;
      var i = 2;
      while (used.contains(id) || id == 'end') {
        id = '${base}_$i';
        i++;
      }
      used.add(id);
      return id;
    }

    final Map<String, String> sid = <String, String>{
      for (final n in _nodes.values) n.id: _makeStepId(n.id),
    };

    // nó de entrada (sem arestas que chegam) com fallback para o primeiro
    final Set<String> inputSet = _edges.map((e) => e.toNodeId).toSet();
    final FunnelNode? entry = _nodes.values
        .where((n) => !inputSet.contains(n.id))
        .cast<FunnelNode?>()
        .followedBy(<FunnelNode?>[
      _nodes.values.isNotEmpty ? _nodes.values.first : null
    ]).first;

    String? _to(String nodeId, String port) {
      final e = _edges.firstWhere(
        (x) => x.fromNodeId == nodeId && x.fromPort == port,
        orElse: () => LinkEdge(fromNodeId: '', fromPort: '', toNodeId: ''),
      );
      if (e.fromNodeId.isEmpty) return null;

      final target = _nodes[e.toNodeId];
      if (target == null) return null;

      final targetSid = sid[target.id]!;
      switch (target.type) {
        case NodeType.end:
          {
            final txt = (target.data['text'] ?? '').toString().trim();
            final tagId = (target.data['tagId'] ?? '').toString().trim();
            if (txt.isNotEmpty) return '${targetSid}_msg';
            if (tagId.isNotEmpty)
              return '${targetSid}_tag'; // ⭐ entra no step com actions
            return 'end';
          }
        case NodeType.handoff:
          return '${targetSid}_msg';
        case NodeType.message:
        case NodeType.menu:
        case NodeType.start:
          return targetSid;
      }
    }

    int _toMinutes(dynamic v, dynamic u) {
      final int val = int.tryParse('${v ?? ''}') ?? 10;
      final String unit = (u ?? 'minutes').toString().toLowerCase();
      if (val <= 0) return 0;
      if (unit.startsWith('hour')) return val * 60;
      if (unit.startsWith('day')) return val * 24 * 60;
      return val;
    }

    // ---- construção dos steps
    final List<Map<String, dynamic>> steps = <Map<String, dynamic>>[];

    for (final n in _nodes.values) {
      final String id = sid[n.id]!;
      switch (n.type) {
        case NodeType.message:
          {
            final String tagId = (n.data['tagId'] ?? '').toString().trim();
            final String text = (n.data['text'] ?? '').toString();
            final String onReply =
                _to(n.id, 'onReply') ?? _to(n.id, 'out') ?? 'end';
            final String? onTimeout = _to(n.id, 'onTimeout');
            final int waitMin =
                _toMinutes(n.data['waitValue'], n.data['waitUnit']);
            final String varName = (n.data['var'] ?? '').toString().trim();

            final Map<String, dynamic> m = <String, dynamic>{
              'id': id,
              'type': 'message',
              'text': text,
              'next': onReply,
              if (varName.isNotEmpty) 'var': varName,
            };

            if (waitMin > 0) {
              final Map<String, dynamic> meta = <String, dynamic>{
                'timeoutMinutes': waitMin,
                if (onTimeout != null) 'timeoutNext': onTimeout,
              };
              m['meta'] = meta;
            }
            if (tagId.isNotEmpty) {
              final Map<String, String> actions = <String, String>{
                'addTagId': tagId
              };
              m['actions'] = actions; // tipo explícito evita inferência errada
            }
            steps.add(m);
            break;
          }

        case NodeType.menu:
          {
            final String tagId = (n.data['tagId'] ?? '').toString().trim();
            final String prompt =
                (n.data['prompt'] ?? 'Escolha uma opção:').toString();
            final List opts = (n.data['options'] as List?) ?? <dynamic>[];
            final int waitMin =
                _toMinutes(n.data['waitValue'], n.data['waitUnit']);
            final String toTimeout = _to(n.id, 'onTimeout') ?? 'end';
            final String varName = (n.data['var'] ?? '').toString().trim();

            // force o tipo da lista de opções
            final List<Map<String, String>> options =
                opts.map<Map<String, String>>((o) {
              final String k = (o['key'] ?? '1').toString();
              final String lb = (o['label'] ?? 'Opção $k').toString();
              final String nx = _to(n.id, 'opt:$k') ?? 'end';
              return <String, String>{'key': k, 'label': lb, 'next': nx};
            }).toList();

            final Map<String, dynamic> step = <String, dynamic>{
              'id': id,
              'type': 'menu',
              'text': prompt,
              'options': options,
              if (varName.isNotEmpty) 'var': varName,
            };

            if (tagId.isNotEmpty) {
              step['actions'] = <String, String>{'addTagId': tagId};
            }
            if (waitMin > 0) {
              step['meta'] = <String, dynamic>{
                'timeoutMinutes': waitMin,
                'timeoutNext': toTimeout,
              };
            }
            steps.add(step);
            break;
          }

        case NodeType.handoff:
          {
            final String tagId = (n.data['tagId'] ?? '').toString().trim();
            final String txt = (n.data['text'] ?? '').toString().trim();
            final String msgId = '${id}_msg';
            final String hdId = '${id}_handoff';

            final Map<String, dynamic> first = <String, dynamic>{
              'id': msgId,
              'type': 'message',
              'text': txt,
              'next': hdId,
            };
            if (tagId.isNotEmpty) {
              first['actions'] = <String, String>{'addTagId': tagId};
            }
            steps
              ..add(first)
              ..add(<String, dynamic>{
                'id': hdId,
                'type': 'handoff',
                'next': 'end'
              });
            break;
          }

        case NodeType.end:
          {
            final String tagId = (n.data['tagId'] ?? '').toString().trim();
            final String txt = (n.data['text'] ?? '').toString().trim();
            if (txt.isNotEmpty) {
              final String msgId = '${id}_msg';
              final Map<String, dynamic> m = <String, dynamic>{
                'id': msgId,
                'type': 'message',
                'text': txt,
                'next': 'end',
              };
              if (tagId.isNotEmpty) {
                m['actions'] = <String, String>{'addTagId': tagId};
              }
              steps.add(m);
            } else if (tagId.isNotEmpty) {
              steps.add(<String, dynamic>{
                'id': '${id}_tag',
                'type': 'message', // ou 'action'
                'text': '',
                'next': 'end',
                'actions': <String, String>{'addTagId': tagId},
              });
            }
            break;
          }

        case NodeType.start:
          // nó técnico — não gera step
          break;
      }
    }

    if (!steps.any((s) => s['id'] == 'end')) {
      steps.add(<String, dynamic>{'id': 'end', 'type': 'end'});
    }

    String _computeStart(FunnelNode? entryNode) {
      if (entryNode == null) {
        return steps.isNotEmpty ? (steps.first['id'] as String) : 'end';
      }
      final entrySid = sid[entryNode.id]!;
      switch (entryNode.type) {
        case NodeType.end:
          {
            final txt = (entryNode.data['text'] ?? '').toString().trim();
            final tagId = (entryNode.data['tagId'] ?? '').toString().trim();
            if (txt.isNotEmpty) return '${entrySid}_msg';
            if (tagId.isNotEmpty) return '${entrySid}_tag'; // ⭐
            return 'end';
          }
        case NodeType.handoff:
          return '${entrySid}_msg';
        case NodeType.start:
          return _to(entryNode.id, 'out') ?? 'end';
        case NodeType.message:
        case NodeType.menu:
          return entrySid;
      }
    }

    final String startStepId = _computeStart(entry);
    return _CompiledSteps(startStepId: startStepId, steps: steps);
  }

  // --------- drag de ligação (bolinha) ----------
  void _beginLinkDrag(String nodeId, String fromPort, Offset globalPos) {
    final w = _globalToWorld(globalPos);
    setState(() {
      _pendingFromNodeId = nodeId;
      _pendingFromPort = fromPort;
      _dragWorld = w;
    });
  }

  void _updateLinkDrag(Offset globalPos) {
    final w = _globalToWorld(globalPos);
    setState(() => _dragWorld = w);
  }

  void _endLinkDrag([Offset? globalPos]) {
    if (globalPos != null) {
      _dragWorld = _globalToWorld(globalPos);
    }
    final w = _dragWorld;
    if (w != null) {
      final targetId = _nodeIdAtWorld(w);
      if (targetId != null && _pendingFromNodeId != null) {
        _finishLink(targetId);
      } else {
        setState(() {
          _pendingFromNodeId = null;
          _pendingFromPort = null;
        });
      }
    }
    setState(() => _dragWorld = null);
  }

  /* -----------------------------------------------------------
   *                           UI
   * ----------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!kIsWeb) {
      return Scaffold(
        appBar: _appBar(cs),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
                'A criação de chatbots (fúnil) está disponível apenas na versão Web.'),
          ),
        ),
      );
    }

    if (_resolving) {
      return Scaffold(
          appBar: _appBar(cs),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_resolveError != null) {
      return Scaffold(
        appBar: _appBar(cs),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_resolveError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
    }

    if (_isEditing && _loadingChatbot) {
      return Scaffold(
        appBar: _appBar(cs),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: _appBar(cs),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final selected = _selectedNodeId != null ? _nodes[_selectedNodeId!] : null;

    final scale = _currentScale;

    return Scaffold(
      appBar: _appBar(cs),
      body: Listener(
        behavior: HitTestBehavior.translucent, // não bloqueia os gestos filhos
        onPointerDown: _handleGlobalPointerDown,
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: _leftPanel(cs),
            ),
            // Canvas
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      constrained: false,
                      transformationController: _canvasController,
                      maxScale: 2.5,
                      minScale: 0.5,
                      boundaryMargin: const EdgeInsets.all(800),
                      child: SizedBox(
                        key: _canvasKey,
                        width: _worldSize.width,
                        height: _worldSize.height,
                        child: GestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          onTapDown: (details) {
                            final world = _globalToWorld(details.globalPosition);
                            if (!_hitAnyNode(world)) {
                              setState(() {
                                _selectedNodeId = null;
                                _pendingFromNodeId = null;
                                _pendingFromPort = null;
                                _dragWorld = null;
                              });
                            }
                          },
                          child: MouseRegion(
                            opaque: false,
                            onHover: (e) => _updateEdgeHoverAtWorld(
                                _globalToWorld(e.position)),
                            child: CustomPaint(
                              foregroundPainter: _EdgesPainter(
                                nodes: _nodes,
                                edges: _edges,
                                selectedEdge: _hoverEdge,
                                tempFromNodeId: _pendingFromNodeId,
                                tempFromPort: _pendingFromPort,
                                tempCursorWorld: _dragWorld,
                                outAnchors: _outAnchors,
                                anchorsVersion: _anchorsVersion,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Nós
                                  ..._nodes.values.map((n) => Positioned(
                                        left: n.pos.dx,
                                        top: n.pos.dy,
                                        child: _NodeWidget(
                                          node: n,
                                          selected: n.id == _selectedNodeId,
                                          canvasScale: _currentScale,
                                          onTap: () => setState(
                                              () => _selectedNodeId = n.id),
                                          onDrag: (deltaWorld) {
                                            setState(() {
                                              final next = _clampToWorld(
                                                  n.pos + deltaWorld);
                                              _nodes[n.id] =
                                                  n.copyWith(pos: next);
                                            });
                                          },
                                          onRemove: () => _removeNode(n.id),
                                          onStartLink: _startLink,
                                          onFinishLink: _finishLink,
                                          onDuplicate: () => _duplicateNode(n.id),
                                          onBeginLinkDrag: _beginLinkDrag,
                                          onUpdateLinkDrag: _updateLinkDrag,
                                          onEndLinkDrag: _endLinkDrag,
                                          onReportPortGlobal: _recordOutAnchor,
                                        ),
                                      )),

                                  // 🔴 Botão de romper vínculo — agora no PAI, em coordenadas de MUNDO
                                  if (_hoverEdge != null &&
                                      _hoverEdgeWorld != null)
                                    Positioned(
                                      left: _hoverEdgeWorld!.dx - 16,
                                      top: _hoverEdgeWorld!.dy - 16,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () {
                                            final e = _hoverEdge!;
                                            _deleteEdge(e);
                                            setState(() {
                                              _hoverEdge = null;
                                              _hoverEdgeWorld = null;
                                            });
                                          },
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.black.withOpacity(.80),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                    blurRadius: 8,
                                                    color: Colors.black
                                                        .withOpacity(.25))
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: const Tooltip(
                                              message: 'Romper vínculo',
                                              child: Icon(Icons.link_off_rounded,
                                                  color: Colors.white, size: 18),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Botão flutuante acima da curva
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _floatingToolbox(cs),
                  ),
                ],
              ),
            ),
            // Painel direito – propriedades do nó selecionado
            if (selected != null)
              SizedBox(
                key: _rightPanelKey,
                width: 590,
                child: _rightPanelForNode(cs, selected),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(ColorScheme cs) {
    return AppBar(
      toolbarHeight: 72,
      automaticallyImplyLeading: false,
      backgroundColor: cs.secondary,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new,
                    color: cs.onBackground, size: 18),
                const SizedBox(width: 6),
                Text('Voltar', style: TextStyle(color: cs.onSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(_isEditing ? 'Editar Chatbot (Fúnil)' : 'Novo Chatbot (Fúnil)',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondary)),
          const Spacer(),
          IconButton(
            tooltip: _isEditing ? 'Salvar alterações' : 'Salvar',
            icon: Icon(Icons.save, color: cs.onBackground, size: 28),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _leftPanel(ColorScheme cs) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: cs.surface,
      child: Form(
        key: _formKey,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Informações básicas', style: t.titleMedium),
            const SizedBox(height: 15),
            _Labeled(
              'Nome do chatbot',
              TextFormField(
                controller: _nameCtrl,
                decoration: _dec(context, 'Nome do chatbot'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
            ),
            const SizedBox(height: 20),
            _Labeled(
              'Descrição',
              TextFormField(
                controller: _descCtrl,
                decoration: _dec(context, 'Descrição'),
                minLines: 1,
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
            _Labeled(
              'Mensagem de fallback',
              TextFormField(
                controller: _fallbackCtrl,
                decoration: _dec(context, 'Mensagem de fallback'),
                minLines: 1,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 12),
            Text('Adicionar bloco', style: t.titleMedium),
            const SizedBox(height: 15),
            Column(
              children: [
                _blockChoice(context, 'Mensagem', Icons.sms_outlined,
                    () => _addNode(NodeType.message)),
                const SizedBox(height: 8),
                _blockChoice(context, 'Menu', Icons.segment_outlined,
                    () => _addNode(NodeType.menu)),
                const SizedBox(height: 8),
                _blockChoice(context, 'Handoff', Icons.support_agent_outlined,
                    () => _addNode(NodeType.handoff)),
                const SizedBox(height: 8),
                _blockChoice(context, 'Fim', Icons.stop_circle_outlined,
                    () => _addNode(NodeType.end)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingToolbox(ColorScheme cs) {
    return Card(
      color: cs.secondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom +',
            onPressed: () {
              final m = _canvasController.value.clone()..scale(1.15);
              _canvasController.value = m;
            },
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: 'Zoom −',
            onPressed: () {
              final m = _canvasController.value.clone()..scale(0.87);
              _canvasController.value = m;
            },
            icon: const Icon(Icons.zoom_out),
          ),
          const Divider(height: 0),
          IconButton(
            tooltip: 'Centralizar',
            onPressed: () => _canvasController.value = Matrix4.identity(),
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }

  Widget _rightPanelForNode(ColorScheme cs, FunnelNode? node) {
    if (node == null) return const SizedBox.shrink();

    switch (node.type) {
      case NodeType.message:
        return _messageEditor(cs, node);
      case NodeType.menu:
        return _menuEditor(cs, node);
      case NodeType.handoff:
        return _handoffEditor(cs, node);
      case NodeType.end:
        return _endEditor(cs, node);
      case NodeType.start:
        return _messageEditor(cs, node);
    }
  }

  // ---------- Painel “Mensagem” ----------
  Widget _messageEditor(ColorScheme cs, FunnelNode n) {
    final waitValue = (n.data['waitValue'] ?? 10) as int;
    final waitUnit =
        _unitFromName((n.data['waitUnit'] ?? WaitUnit.minutes.name).toString());

    return Container(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho com Voltar/Fechar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: () => setState(() => _selectedNodeId = null),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Text('Editar mensagem',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Icon(Icons.help_outline, size: 18, color: cs.onSecondary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Dados salvos automaticamente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: cs.onSecondary),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedNodeId = null),
                ),
              ],
            ),
          ),
          // Métricas
          const SizedBox(height: 8),

          // Conteúdo rolável
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const SizedBox(height: 16),
                Text('Nome de Referência',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: n.title,
                  onChanged: (v) =>
                      setState(() => _nodes[n.id] = n.copyWith(title: v)),
                  decoration: _dec(
                    context,
                    '[MSG 1 - Saudação — Texto]',
                  ),
                ),
                const SizedBox(height: 12),
                _Labeled(
                  'Salvar resposta em (variável) — opcional',
                  TextFormField(
                    initialValue: (n.data['var'] ?? '').toString(),
                    decoration: _dec(context, 'ex.: nome, email, cidade'),
                    onChanged: (v) => setState(() => n.data['var'] = v.trim()),
                  ),
                ),
                const SizedBox(height: 12),
                _tagPickerField(n),
                const SizedBox(height: 18),
                Text('Digite sua mensagem aqui',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: (n.data['text'] ?? '').toString(),
                  onChanged: (v) => setState(() => n.data['text'] = v),
                  minLines: 5,
                  maxLines: 12,
                  decoration: _dec(
                    context,
                    '{Saudação} {PrimeiroNome}, blz?',
                  ),
                ),
                const SizedBox(height: 18),
                Text('Resposta',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                _DashedPanel(
                  radius: 8,
                  color: cs.outlineVariant,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Text(
                            'Tempo de espera para o contato responder',
                            style: TextStyle(color: cs.onSecondary),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: _Labeled(
                          'Valor',
                          TextFormField(
                            initialValue: '$waitValue',
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() =>
                                n.data['waitValue'] =
                                    int.tryParse(v) ?? waitValue),
                            decoration: _dec(context, '', dense: true),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: _Labeled(
                          'Unidade',
                          DropdownButtonFormField<WaitUnit>(
                            value: waitUnit,
                            decoration: _dec(context, '', dense: true),
                            onChanged: (val) => setState(() =>
                                n.data['waitUnit'] = (val ?? waitUnit).name),
                            items: const [
                              DropdownMenuItem(
                                  value: WaitUnit.minutes,
                                  child: Text('Minutos')),
                              DropdownMenuItem(
                                  value: WaitUnit.hours, child: Text('Horas')),
                              DropdownMenuItem(
                                  value: WaitUnit.days, child: Text('Dias')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: () {
                          setState(() {
                            n.data['waitValue'] = 0;
                            n.data['waitUnit'] = WaitUnit.minutes.name;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  WaitUnit _unitFromName(String name) {
    switch (name) {
      case 'hours':
        return WaitUnit.hours;
      case 'days':
        return WaitUnit.days;
      default:
        return WaitUnit.minutes;
    }
  }

  Widget _menuEditor(ColorScheme cs, FunnelNode n) {
    final List opts = (n.data['options'] as List?) ?? [];
    final waitValue = (n.data['waitValue'] ?? 10) as int;
    final waitUnit =
        _unitFromName((n.data['waitUnit'] ?? WaitUnit.minutes.name).toString());

    return _propPanel(
      cs,
      title: 'Menu — propriedades',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Labeled(
            'Título do bloco',
            TextFormField(
              initialValue: n.title,
              decoration: _dec(context, 'Título do bloco'),
              onChanged: (v) =>
                  setState(() => _nodes[n.id] = n.copyWith(title: v)),
            ),
          ),
          const SizedBox(height: 8),
          _Labeled(
            'Pergunta do menu',
            TextFormField(
              initialValue:
                  (n.data['prompt'] ?? 'Escolha uma opção:').toString(),
              decoration: _dec(context, 'Pergunta do menu'),
              minLines: 2,
              maxLines: 5,
              onChanged: (v) => setState(() => n.data['prompt'] = v),
            ),
          ),
          const SizedBox(height: 8),
          _Labeled(
            'Salvar opção escolhida em (variável) — opcional',
            TextFormField(
              initialValue: (n.data['var'] ?? '').toString(),
              decoration: _dec(context, 'ex.: plano, categoria'),
              onChanged: (v) => setState(() => n.data['var'] = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          _tagPickerField(n),
          const SizedBox(height: 12),
          Text('Opções:', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          ...opts.asMap().entries.map((e) {
            final i = e.key;
            final m = Map<String, dynamic>.from(e.value as Map);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                // << alinha na linha dos campos
                children: [
                  SizedBox(
                    width: 80,
                    child: _Labeled(
                      'Tecla',
                      TextFormField(
                        initialValue: (m['key'] ?? '').toString(),
                        decoration: _dec(context, 'Tecla', dense: true),
                        onChanged: (v) {
                          setState(() {
                            m['key'] = v;
                            opts[i] = m;
                            n.data['options'] = opts;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Labeled(
                      'Rótulo',
                      TextFormField(
                        initialValue: (m['label'] ?? '').toString(),
                        decoration: _dec(context, 'Rótulo', dense: true),
                        onChanged: (v) {
                          setState(() {
                            m['label'] = v;
                            opts[i] = m;
                            n.data['options'] = opts;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Align(
                    // << gruda o botão no fundo (mesma linha dos campos)
                    alignment: Alignment.bottomCenter,
                    child: IconButton(
                      tooltip: 'Remover',
                      onPressed: () {
                        setState(() {
                          opts.removeAt(i);
                          n.data['options'] = opts;
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 36, height: 36),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onPressed: () {
              setState(() {
                final List o = (n.data['options'] as List?) ?? [];
                o.add({
                  'key': '${o.length + 1}',
                  'label': 'Opção ${o.length + 1}'
                });
                n.data['options'] = o;
              });
            },
            icon: const Icon(Icons.add),
            label:
                Text('Adicionar opção', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 16),
          Text('Tempo para o cliente responder (timeout):',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: _Labeled(
                  'Valor',
                  TextFormField(
                    initialValue: '$waitValue',
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() =>
                        n.data['waitValue'] = int.tryParse(v) ?? waitValue),
                    decoration: _dec(context, '', dense: true),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: _Labeled(
                  'Unidade',
                  DropdownButtonFormField<WaitUnit>(
                    value: waitUnit,
                    decoration: _dec(context, '', dense: true),
                    onChanged: (val) => setState(
                        () => n.data['waitUnit'] = (val ?? waitUnit).name),
                    items: const [
                      DropdownMenuItem(
                          value: WaitUnit.minutes, child: Text('Minutos')),
                      DropdownMenuItem(
                          value: WaitUnit.hours, child: Text('Horas')),
                      DropdownMenuItem(
                          value: WaitUnit.days, child: Text('Dias')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _handoffEditor(ColorScheme cs, FunnelNode n) {
    return _propPanel(
      cs,
      title: 'Encerrar/Handoff — propriedades',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Labeled(
            'Título do bloco',
            TextFormField(
              initialValue: n.title,
              decoration: _dec(context, 'Título do bloco'),
              onChanged: (v) =>
                  setState(() => _nodes[n.id] = n.copyWith(title: v)),
            ),
          ),
          const SizedBox(height: 8),
          _Labeled(
            'Mensagem antes de transferir',
            TextFormField(
              initialValue: (n.data['text'] ?? '').toString(),
              minLines: 2,
              maxLines: 6,
              decoration: _dec(context, 'Iremos transferir seu atendimento...'),
              onChanged: (v) => setState(() => n.data['text'] = v),
            ),
          ),
          const SizedBox(height: 8),
          _tagPickerField(n),
          const SizedBox(height: 8),
          Text(
              'Este bloco envia a mensagem e em seguida transfere para um atendente.',
              style: TextStyle(color: cs.onSecondary)),
        ],
      ),
    );
  }

  Widget _endEditor(ColorScheme cs, FunnelNode n) {
    return _propPanel(
      cs,
      title: 'Fim — propriedades',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Labeled(
            'Título do bloco',
            TextFormField(
              initialValue: n.title,
              decoration: _dec(context, 'Título do bloco'),
              onChanged: (v) =>
                  setState(() => _nodes[n.id] = n.copyWith(title: v)),
            ),
          ),
          const SizedBox(height: 8),
          _Labeled(
            'Mensagem final',
            TextFormField(
              initialValue: (n.data['text'] ?? '').toString(),
              minLines: 2,
              maxLines: 6,
              decoration: _dec(context, 'Encerrando seu atendimento...'),
              onChanged: (v) => setState(() => n.data['text'] = v),
            ),
          ),
          const SizedBox(height: 8),
          _tagPickerField(n),
          const SizedBox(height: 8),
          Text('Este bloco envia a mensagem e finaliza o fluxo.',
              style: TextStyle(color: cs.onSecondary)),
        ],
      ),
    );
  }

  // Helpers UI
  InputDecoration _dec(
    BuildContext context,
    String hint, {
    Widget? suffixIcon,
    bool dense = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    // mesma cor SEMPRE (inclusive hover/focus)
    final MaterialStateColor constantFill =
        MaterialStateColor.resolveWith((_) => cs.background);

    OutlineInputBorder _none() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        );

    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: constantFill,
      // mantém a cor fixa
      hoverColor: cs.background,
      // <- mata o "acende no hover"
      focusColor: cs.background,
      // <- idem pra foco
      isDense: dense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: dense ? 10 : 12,
      ),

      // garante que NENHUMA borda apareça/alterne em estados diferentes
      border: _none(),
      enabledBorder: _none(),
      focusedBorder: _none(),
      disabledBorder: _none(),
      errorBorder: _none(),
      focusedErrorBorder: _none(),

      floatingLabelBehavior: FloatingLabelBehavior.never,
      suffixIcon: suffixIcon,
    );
  }

  Widget _blockChoice(
    BuildContext context,
    String label,
    IconData ic,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(ic, color: cs.onSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: cs.onSecondary),
                ),
              ),
              Icon(Icons.add, color: cs.onSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _propPanel(ColorScheme cs,
      {required String title, required Widget child}) {
    return Container(
      color: cs.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: () => setState(() => _selectedNodeId = null),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => setState(() => _selectedNodeId = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/* ===========================================================
 *                     WIDGET DE NÓ + EDGES
 * =========================================================== */

class _NodeWidget extends StatefulWidget {
  const _NodeWidget({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onDrag,
    required this.onRemove,
    required this.onDuplicate,
    required this.onStartLink,
    required this.onFinishLink,
    required this.canvasScale,
    required this.onBeginLinkDrag,
    required this.onUpdateLinkDrag,
    required this.onEndLinkDrag,
    required this.onReportPortGlobal,
  });

  final FunnelNode node;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset delta) onDrag;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;
  final void Function(String nodeId, String fromPort) onStartLink;
  final void Function(String toNodeId) onFinishLink;
  final double canvasScale;
  final void Function(String nodeId, String port, Offset globalCenter)
      onReportPortGlobal;

  // drag de ligação
  final void Function(String nodeId, String fromPort, Offset globalPos)
      onBeginLinkDrag;
  final void Function(Offset globalPos) onUpdateLinkDrag;
  final void Function([Offset? globalPos]) onEndLinkDrag;
  static const double _hoverPillHeight = 40; // altura total do overlay
  static const double _hoverPillGap = 8; // distância do topo do nó

  @override
  State<_NodeWidget> createState() => _NodeWidgetState();
}

class _NodeWidgetState extends State<_NodeWidget> {
  Offset? _dragStart;
  bool _hover = false;

  final GlobalKey _replyKey = GlobalKey();
  final GlobalKey _timeoutKey = GlobalKey();
  final Map<String, GlobalKey> _menuOptKeys = {};
  final GlobalKey _menuTimeoutKey = GlobalKey();

  void _reportAnchorsPostFrame() {
    final nodeBox = context.findRenderObject() as RenderBox?;
    if (nodeBox == null || !nodeBox.attached) return;

    Offset localOf(GlobalKey k) {
      final ctx = k.currentContext;
      if (ctx == null) return Offset.zero;
      final portBox = ctx.findRenderObject() as RenderBox?;
      if (portBox == null || !portBox.attached) return Offset.zero;
      final sz = portBox.size;
      final centerGlobal =
          portBox.localToGlobal(Offset(sz.width / 2, sz.height / 2));
      return nodeBox.globalToLocal(centerGlobal);
    }

    if (widget.node.type == NodeType.message) {
      widget.onReportPortGlobal(widget.node.id, 'onReply', localOf(_replyKey));
      widget.onReportPortGlobal(
          widget.node.id, 'onTimeout', localOf(_timeoutKey));
    } else if (widget.node.type == NodeType.menu) {
      final List opts = (widget.node.data['options'] as List?) ?? [];
      for (final o in opts) {
        final keyStr = (o['key'] ?? '1').toString();
        final port = 'opt:$keyStr';
        final gk = _menuOptKeys[port];
        if (gk != null) {
          widget.onReportPortGlobal(widget.node.id, port, localOf(gk));
        }
      }
      widget.onReportPortGlobal(
          widget.node.id, 'onTimeout', localOf(_menuTimeoutKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = widget.node;
    // mede as bolinhas depois que o widget renderiza
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportAnchorsPostFrame());

    final headerColor = () {
      switch (n.type) {
        case NodeType.message:
          return Colors.indigo;
        case NodeType.menu:
          return Colors.blue;
        case NodeType.handoff:
          return Colors.purple;
        case NodeType.end:
          return Colors.teal;
        case NodeType.start:
          return Colors.indigo;
      }
    }();

    final mainCard = GestureDetector(
      onTap: widget.onTap,
      onPanStart: (d) => _dragStart = d.localPosition,
      onPanUpdate: (d) {
        if (_dragStart == null) return;
        final worldDelta = d.delta;
        widget.onDrag(worldDelta);
      },
      onPanEnd: (_) => _dragStart = null,
      child: Container(
        width: _CreateChatbotPageState.nodeWidth,
        constraints: const BoxConstraints(
            minHeight: _CreateChatbotPageState.baseNodeHeight),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                blurRadius: 12,
                offset: const Offset(0, 6),
                color: cs.shadow.withOpacity(.08))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- header só para tipos != message
            if (n.type != NodeType.message)
              Container(
                decoration: BoxDecoration(
                  color: headerColor.withOpacity(.9),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(_iconFor(n.type), color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n.title.isEmpty ? _fallbackTitle(n.type) : n.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // --- corpo (novo visual)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: _nodeBody(n, context),
            ),

            if (n.type != NodeType.message)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: _portsRow(n, cs),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // 1) Empurra apenas o CARD para baixo
          Padding(
            padding: EdgeInsets.only(
              top: _NodeWidget._hoverPillHeight + _NodeWidget._hoverPillGap,
            ),
            child: mainCard,
          ),

          // 2) A pílula fica no topo do Stack (dentro da área, logo clicável)
          if (_hover)
            Positioned(
              top: 0,
              child: SizedBox(
                height: _NodeWidget._hoverPillHeight,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    height: _NodeWidget._hoverPillHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.78),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Duplicar',
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white),
                          onPressed: widget.onDuplicate,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 32),
                          splashRadius: 18,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Excluir',
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white),
                          onPressed: widget.onRemove,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 32),
                          splashRadius: 18,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hoverBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _portsRow(FunnelNode n, ColorScheme cs) {
    List<Widget> outs;
    switch (n.type) {
      case NodeType.message:
        outs = []; // portas ficam no corpo
        break;
      case NodeType.handoff:
      case NodeType.start:
        outs = [
          _portButton(
            cs,
            onStart: (d) =>
                widget.onBeginLinkDrag(n.id, 'out', d.globalPosition),
            onUpdate: (d) => widget.onUpdateLinkDrag(d.globalPosition),
            onEnd: (_) => widget.onEndLinkDrag(),
          )
        ];
        break;
      case NodeType.end:
        outs = [];
        break;
      case NodeType.menu:
        outs = []; // agora todos os conectores (opt:k e timeout) estão no corpo
        break;
    }

    return Row(children: [const Spacer(), ...outs]);
  }

  Widget _nodeBody(FunnelNode n, BuildContext context) {
    switch (n.type) {
      case NodeType.message:
        {
          final cs = Theme.of(context).colorScheme;
          final waitValue = (n.data['waitValue'] ?? 10) as int;
          final waitUnit =
              (n.data['waitUnit'] ?? WaitUnit.minutes.name).toString();
          String unitLabel() {
            switch (waitUnit) {
              case 'hours':
                return waitValue == 1 ? 'hora' : 'horas';
              case 'days':
                return waitValue == 1 ? 'dia' : 'dias';
              default:
                return waitValue == 1 ? 'minuto' : 'minutos';
            }
          }

          Widget stat(String label) => Expanded(
                child: Column(
                  children: [
                    Text('0',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 25)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white, fontSize: 10)),
                  ],
                ),
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(children: [
                  stat('Agendadas'),
                  stat('Enviadas'),
                  stat('Canceladas'),
                  stat('Aguardando')
                ]),
              ),
              const SizedBox(height: 10),
              Text(
                '[${n.title.isEmpty ? _fallbackTitle(n.type) : n.title}]',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              _fieldBox(context, (n.data['text'] ?? '').toString()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: Text('Se o contato responder',
                          style: Theme.of(context).textTheme.bodySmall)),
                  _portButton(
                    cs,
                    key: _replyKey,
                    fill: Colors.green,
                    size: 11,
                    onStart: (d) => widget.onBeginLinkDrag(
                        n.id, 'onReply', d.globalPosition),
                    onUpdate: (d) => widget.onUpdateLinkDrag(d.globalPosition),
                    onEnd: (_) => widget.onEndLinkDrag(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Se o contato não responder (máximo $waitValue ${unitLabel()})',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  _portButton(
                    cs,
                    key: _timeoutKey,
                    fill: Colors.red,
                    size: 11,
                    onStart: (d) => widget.onBeginLinkDrag(
                        n.id, 'onTimeout', d.globalPosition),
                    onUpdate: (d) => widget.onUpdateLinkDrag(d.globalPosition),
                    onEnd: (_) => widget.onEndLinkDrag(),
                  ),
                ],
              ),
            ],
          );
        }

      case NodeType.menu:
        {
          final cs = Theme.of(context).colorScheme;
          final prompt = (n.data['prompt'] ?? '').toString();
          final List opts = (n.data['options'] as List?) ?? [];
          final waitValue = (n.data['waitValue'] ?? 10) as int;
          final waitUnit =
              (n.data['waitUnit'] ?? WaitUnit.minutes.name).toString();
          String unitLabel() {
            switch (waitUnit) {
              case 'hours':
                return waitValue == 1 ? 'hora' : 'horas';
              case 'days':
                return waitValue == 1 ? 'dia' : 'dias';
              default:
                return waitValue == 1 ? 'minuto' : 'minutos';
            }
          }

          // garantir chaves para cada opção existente
          final wanted = <String>{
            for (final o in opts) 'opt:${(o['key'] ?? '1')}'
          };
          for (final p in wanted) {
            _menuOptKeys.putIfAbsent(p, () => GlobalKey());
          }
          _menuOptKeys.removeWhere((p, _) => !wanted.contains(p));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldBox(context, prompt),
              const SizedBox(height: 8),
              ...opts.map((o) {
                final k = (o['key'] ?? '1').toString();
                final lb = (o['label'] ?? 'Opção $k').toString();
                final port = 'opt:$k';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 🟦 mesma “caixa de campo” usada nos outros nós
                      Expanded(
                        child: _fieldBox(
                          context,
                          '• $k: $lb',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _portButton(
                        cs,
                        key: _menuOptKeys[port],
                        fill: Colors.green,
                        size: 11,
                        onStart: (d) => widget.onBeginLinkDrag(
                            n.id, port, d.globalPosition),
                        onUpdate: (d) =>
                            widget.onUpdateLinkDrag(d.globalPosition),
                        onEnd: (_) => widget.onEndLinkDrag(),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Se não responder (máximo $waitValue ${unitLabel()})',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  _portButton(
                    cs,
                    key: _menuTimeoutKey,
                    fill: Colors.redAccent,
                    size: 11,
                    onStart: (d) => widget.onBeginLinkDrag(
                        n.id, 'onTimeout', d.globalPosition),
                    onUpdate: (d) => widget.onUpdateLinkDrag(d.globalPosition),
                    onEnd: (_) => widget.onEndLinkDrag(),
                  ),
                ],
              ),
            ],
          );
        }

      case NodeType.handoff:
        return _fieldBox(
          context,
          (n.data['text'] ?? 'Transferindo para atendente...').toString(),
        );
      case NodeType.end:
        return _fieldBox(
          context,
          (n.data['text'] ?? 'Encerrando atendimento...').toString(),
        );
      case NodeType.start:
        return const SizedBox.shrink();
    }
  }

  IconData _iconFor(NodeType t) {
    switch (t) {
      case NodeType.message:
        return Icons.sms_outlined;
      case NodeType.menu:
        return Icons.segment_outlined;
      case NodeType.handoff:
        return Icons.support_agent_outlined;
      case NodeType.end:
        return Icons.stop_circle_outlined;
      case NodeType.start:
        return Icons.play_circle_outline;
    }
  }

  String _fallbackTitle(NodeType t) {
    switch (t) {
      case NodeType.message:
        return 'Mensagem — Texto';
      case NodeType.menu:
        return 'Menu';
      case NodeType.handoff:
        return 'Encerrar/Handoff';
      case NodeType.end:
        return 'Fim';
      case NodeType.start:
        return 'Início';
    }
  }

  // --- helper visual: caixa com "cara de campo" ---
  Widget _fieldBox(
    BuildContext context,
    String text, {
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    double radius = 10,
    Color? bg,
    TextStyle? style,
  }) {
    final cs = Theme.of(context).colorScheme;
    final value = text;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg ?? cs.onSurface.withOpacity(.12),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        value,
        style: style ??
            Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface),
      ),
    );
  }

  Widget _portButton(
    ColorScheme cs, {
    required void Function(DragStartDetails) onStart,
    required void Function(DragUpdateDetails) onUpdate,
    required void Function(DragEndDetails) onEnd,
    Color? fill,
    double size = 10,
    Key? key, // <<< novo
  }) {
    return GestureDetector(
      onPanStart: onStart,
      onPanUpdate: onUpdate,
      onPanEnd: onEnd,
      child: Container(
        key: key, // <<< novo
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill ?? cs.secondary,
          border: Border.all(color: cs.outlineVariant, width: 1),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.nodes,
    required this.edges,
    this.selectedEdge,
    this.tempFromNodeId,
    this.tempFromPort,
    this.tempCursorWorld,
    required this.outAnchors,
    required this.anchorsVersion,
  });

  final Map<String, FunnelNode> nodes;
  final List<LinkEdge> edges;
  final LinkEdge? selectedEdge;

  // preview do drag
  final String? tempFromNodeId;
  final String? tempFromPort;
  final Offset? tempCursorWorld;
  final Map<String, Map<String, Offset>> outAnchors;
  final int anchorsVersion;

  static const double w = _CreateChatbotPageState.nodeWidth;
  static const double h = _CreateChatbotPageState.baseNodeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Arestas oficiais
    for (final e in edges) {
      final from = nodes[e.fromNodeId];
      final to = nodes[e.toNodeId];
      if (from == null || to == null) continue;

      final start = _portCenter(from, e.fromPort, isOut: true);
      final end = _portCenter(to, 'in', isOut: false);

      final p = Path();
      final dx = (end.dx - start.dx).abs();
      final c1 = Offset(start.dx + dx * .5, start.dy);
      final c2 = Offset(end.dx - dx * .5, end.dy);
      p.moveTo(start.dx, start.dy);
      p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      final isHovered = identical(selectedEdge, e);
      final Color edgeColor =
          isHovered ? const Color(0xFF933FFC) : const Color(0xFFB7B3C6);
      final double edgeWidth = isHovered ? 2.5 : 2.0;

      final paint = Paint()
        ..color = edgeColor.withOpacity(.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth;

      canvas.drawPath(p, paint);

// seta com cor/espessura em sincronia com o hover
      _drawArrow(
        canvas,
        c2,
        end,
        color: edgeColor,
        strokeWidth: edgeWidth,
        opacity: isHovered ? 1.0 : .9,
      );
    }

    // preview enquanto arrasta
    if (tempFromNodeId != null &&
        tempFromPort != null &&
        tempCursorWorld != null) {
      final from = nodes[tempFromNodeId];
      if (from != null) {
        final start = _portCenter(from, tempFromPort!, isOut: true);
        final end = tempCursorWorld!;
        final p = Path();
        final dx = (end.dx - start.dx).abs();
        final c1 = Offset(start.dx + dx * .5, start.dy);
        final c2 = Offset(end.dx - dx * .5, end.dy);
        p.moveTo(start.dx, start.dy);
        p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        final previewColor = const Color(0xFFB7B3C6);
        final previewWidth = 2.0;

        final paint = Paint()
          ..color = previewColor.withOpacity(.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = previewWidth;

        canvas.drawPath(p, paint);

        _drawArrow(
          canvas,
          c2,
          end,
          color: previewColor,
          strokeWidth: previewWidth,
          opacity: .9,
        );
      }
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset c2,
    Offset end, {
    required Color color,
    double strokeWidth = 2.0,
    double opacity = .95,
  }) {
    final dir = end - c2;
    final len = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
    if (len > 0.0001) {
      final ux = dir.dx / len, uy = dir.dy / len;
      const double arrowLen = 12;
      const double angle = 25 * math.pi / 180;

      final arrowP1 = Offset(
        end.dx - arrowLen * (ux * math.cos(angle) - uy * math.sin(angle)),
        end.dy - arrowLen * (uy * math.cos(angle) + ux * math.sin(angle)),
      );
      final arrowP2 = Offset(
        end.dx - arrowLen * (ux * math.cos(-angle) - uy * math.sin(-angle)),
        end.dy - arrowLen * (uy * math.cos(-angle) + ux * math.sin(-angle)),
      );

      final arrowPaint = Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      canvas.drawLine(end, arrowP1, arrowPaint);
      canvas.drawLine(end, arrowP2, arrowPaint);
    }
  }

  Offset _portCenter(FunnelNode n, String port, {required bool isOut}) {
    // 1) Usa anchor reportado (preciso)
    if (isOut) {
      final local = outAnchors[n.id]?[port];
      if (local != null) return n.pos + local;
    }

    // 2) Fallback geométrico simples
    final x = n.pos.dx + (isOut ? w : 0);
    double y = n.pos.dy + 60;

    if (n.type == NodeType.message && isOut) {
      y = port == 'onTimeout' ? (n.pos.dy + 100) : (n.pos.dy + 60);
    } else if (n.type == NodeType.menu && isOut) {
      final List opts = (n.data['options'] as List?) ?? [];
      if (opts.isNotEmpty) {
        final idx = opts.indexWhere((o) => 'opt:${o['key']}' == port);
        if (idx >= 0) y = n.pos.dy + 56 + 18.0 * (idx.clamp(0, 4));
      }
      if (port == 'onTimeout') y = n.pos.dy + 100;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter old) {
    return old.nodes != nodes ||
        old.edges != edges ||
        old.selectedEdge != selectedEdge ||
        old.tempFromNodeId != tempFromNodeId ||
        old.tempFromPort != tempFromPort ||
        old.tempCursorWorld != tempCursorWorld ||
        old.anchorsVersion != anchorsVersion;
  }
}

/* ===========================================================
 *                        WIDGETS AUXILIARES
 * =========================================================== */

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon,
        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant);
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child, {super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelMedium),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/* ===========================================================
 *                     TIPOS AUXILIARES
 * =========================================================== */

class _CompiledSteps {
  _CompiledSteps({required this.startStepId, required this.steps});

  final String startStepId;
  final List<Map<String, dynamic>> steps;
}

class _DashedPanel extends StatelessWidget {
  const _DashedPanel({
    required this.child,
    this.radius = 8,
    this.color,
  });

  final Widget child;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outlineVariant;
    return CustomPaint(
      foregroundPainter: _DashedRectPainter(color: c, radius: radius),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter(
      {required this.color, this.strokeWidth = 1.2, this.radius = 8});

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final metric in path.computeMetrics()) {
      double dist = 0;
      const double dash = 8;
      const double gap = 6;
      while (dist < metric.length) {
        final next = dist + dash;
        final seg = metric.extractPath(dist, next.clamp(0, metric.length));
        canvas.drawPath(seg, paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
