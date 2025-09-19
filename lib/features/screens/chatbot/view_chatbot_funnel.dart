import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// ====== modelos mínimos p/ visualizar ======
enum NodeType { start, message, menu, handoff, end }

class FunnelNode {
  FunnelNode({
    required this.id,
    required this.type,
    required this.pos,
    this.title = '',
    Map<String, dynamic>? data,
  }) : data = data ?? {};
  final String id;
  final NodeType type;
  final Offset pos;
  final String title;
  final Map<String, dynamic> data;
}

class LinkEdge {
  LinkEdge({
    required this.fromNodeId,
    required this.fromPort,
    required this.toNodeId,
  });
  final String fromNodeId;
  final String fromPort;
  final String toNodeId;

  static LinkEdge fromJson(Map<String, dynamic> j) => LinkEdge(
    fromNodeId: (j['fromNodeId'] ?? '').toString(),
    fromPort: (j['fromPort'] ?? '').toString(),
    toNodeId: (j['toNodeId'] ?? '').toString(),
  );
}

/// ====== página de visualização ======
class ViewChatbotFunnelPage extends StatefulWidget {
  const ViewChatbotFunnelPage({
    super.key,
    required this.empresaId,
    required this.botId,
  });

  final String empresaId;
  final String botId;

  @override
  State<ViewChatbotFunnelPage> createState() => _ViewChatbotFunnelPageState();
}

class _ViewChatbotFunnelPageState extends State<ViewChatbotFunnelPage> {
  static const Size _worldSize = Size(8000, 6000);
  static const double nodeWidth = 300.0;
  static const double baseNodeHeight = 120.0;

  final _canvasController = TransformationController();

  final Map<String, Map<String, Offset>> _outAnchors = {};
  int _anchorsVersion = 0;
  void _recordOutAnchor(String nodeId, String port, Offset localInNode) {
    final prev = _outAnchors[nodeId]?[port];
    if (prev == null || (prev - localInNode).distanceSquared > 0.25) {
      setState(() {
        (_outAnchors[nodeId] ??= {})[port] = localInNode;
        _anchorsVersion++;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
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
                  Icon(Icons.arrow_back_ios_new, color: cs.onBackground, size: 18),
                  const SizedBox(width: 6),
                  Text('Voltar', style: TextStyle(color: cs.onSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text('Visualizar Chatbot',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondary,
                )),
          ],
        ),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('empresas')
            .doc(widget.empresaId)
            .collection('chatbots')
            .doc(widget.botId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !(snap.data?.exists ?? false)) {
            return const Center(child: Text('Chatbot não encontrado.'));
          }

          final data = (snap.data!.data() ?? <String, dynamic>{});
          final flow = (data['flow'] ?? {}) as Map<String, dynamic>;
          final List rawNodes = (flow['nodes'] ?? []) as List;
          final List rawEdges = (flow['edges'] ?? []) as List;

          final nodes = <String, FunnelNode>{};
          for (final raw in rawNodes) {
            final m = (raw as Map).cast<String, dynamic>();
            final node = FunnelNode(
              id: (m['id'] ?? '').toString(),
              type: _nodeTypeFromName((m['type'] ?? 'message').toString()),
              pos: _toOffset(m['pos']),
              title: (m['title'] ?? '').toString(),
              data: Map<String, dynamic>.from((m['data'] ?? {}) as Map),
            );
            nodes[node.id] = node;
          }
          final edges = rawEdges
              .map((e) => LinkEdge.fromJson((e as Map).cast<String, dynamic>()))
              .toList();

          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  constrained: false,
                  transformationController: _canvasController,
                  maxScale: 2.5,
                  minScale: 0.5,
                  boundaryMargin: const EdgeInsets.all(800),
                  child: SizedBox(
                    width: _worldSize.width,
                    height: _worldSize.height,
                    child: CustomPaint(
                      foregroundPainter: _EdgesPainterView(
                        nodes: nodes,
                        edges: edges,
                        outAnchors: _outAnchors,
                        anchorsVersion: _anchorsVersion,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final n in nodes.values)
                            Positioned(
                              left: n.pos.dx,
                              top: n.pos.dy,
                              child: _NodeCardView(
                                node: n,
                                width: nodeWidth,
                                minHeight: baseNodeHeight,
                                onReportPortLocal: _recordOutAnchor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 16,
                child: _FloatingToolbox(
                  onZoomIn: () {
                    final m = _canvasController.value.clone()..scale(1.15);
                    _canvasController.value = m;
                  },
                  onZoomOut: () {
                    final m = _canvasController.value.clone()..scale(0.87);
                    _canvasController.value = m;
                  },
                  onCenter: () => _canvasController.value = Matrix4.identity(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EdgesPainterView extends CustomPainter {
  _EdgesPainterView({
    required this.nodes,
    required this.edges,
    required this.outAnchors,      // ⬅️ NOVO
    required this.anchorsVersion,  // ⬅️ NOVO
  });

  final Map<String, FunnelNode> nodes;
  final List<LinkEdge> edges;
  final Map<String, Map<String, Offset>> outAnchors; // ⬅️ NOVO
  final int anchorsVersion;                           // ⬅️ NOVO

  static const double nodeWidth = _ViewChatbotFunnelPageState.nodeWidth;
  static const double nodeHeight = _ViewChatbotFunnelPageState.baseNodeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final from = nodes[e.fromNodeId];
      final to   = nodes[e.toNodeId];
      if (from == null || to == null) continue;

      final start = _portCenter(from, e.fromPort, isOut: true);
      final end   = _portCenter(to, 'in', isOut: false);

      final dx = (end.dx - start.dx).abs();
      final c1 = Offset(start.dx + dx * .5, start.dy);
      final c2 = Offset(end.dx - dx * .5, end.dy);

      final p = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      final paint = Paint()
        ..color = const Color(0xFFB7B3C6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawPath(p, paint);
      _drawArrow(canvas, c2, end, color: const Color(0xFFB7B3C6));
    }
  }

  void _drawArrow(Canvas canvas, Offset c2, Offset end,
      {required Color color, double strokeWidth = 2.0}) {
    final dir = end - c2;
    final len = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
    if (len <= 0.0001) return;
    final ux = dir.dx / len, uy = dir.dy / len;
    const double arrowLen = 12;
    const double angle = 25 * math.pi / 180;

    final p1 = Offset(
      end.dx - arrowLen * (ux * math.cos(angle) - uy * math.sin(angle)),
      end.dy - arrowLen * (uy * math.cos(angle) + ux * math.sin(angle)),
    );
    final p2 = Offset(
      end.dx - arrowLen * (ux * math.cos(-angle) - uy * math.sin(-angle)),
      end.dy - arrowLen * (uy * math.cos(-angle) + ux * math.sin(-angle)),
    );

    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawLine(end, p1, arrowPaint);
    canvas.drawLine(end, p2, arrowPaint);
  }

  Offset _portCenter(FunnelNode n, String port, {required bool isOut}) {
    // 1) usa âncora LOCAL medida pela UI (precisa)
    if (isOut) {
      final local = outAnchors[n.id]?[port];
      if (local != null) return n.pos + local;
    }

    // 2) fallback geométrico (igual ao viewer anterior)
    final x = n.pos.dx + (isOut ? nodeWidth : 0);
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
    } else if (!isOut) {
      y = n.pos.dy + (nodeHeight * .5);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainterView old) =>
      old.nodes != nodes ||
          old.edges != edges ||
          old.anchorsVersion != anchorsVersion || // ⬅️ repintar quando âncoras mudarem
          old.outAnchors != outAnchors;
}

class _NodeCardView extends StatefulWidget {
  const _NodeCardView({
    required this.node,
    required this.width,
    required this.minHeight,
    required this.onReportPortLocal, // ⬅️ NOVO
  });

  final FunnelNode node;
  final double width;
  final double minHeight;
  final void Function(String nodeId, String port, Offset localInNode)
  onReportPortLocal; // ⬅️ NOVO

  @override
  State<_NodeCardView> createState() => _NodeCardViewState();
}

class _NodeCardViewState extends State<_NodeCardView> {
  final GlobalKey _replyKey = GlobalKey();
  final GlobalKey _timeoutKey = GlobalKey();
  final GlobalKey _menuTimeoutKey = GlobalKey();
  final Map<String, GlobalKey> _menuOptKeys = {}; // port -> key

  @override
  void didUpdateWidget(covariant _NodeCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // atualiza mapa de keys quando opções mudam
    if (widget.node.type == NodeType.menu) {
      final List opts = (widget.node.data['options'] as List?) ?? [];
      final wanted = <String>{for (final o in opts) 'opt:${(o['key'] ?? '1')}'};
      for (final p in wanted) {
        _menuOptKeys.putIfAbsent(p, () => GlobalKey());
      }
      _menuOptKeys.removeWhere((p, _) => !wanted.contains(p));
    }
  }

  @override
  Widget build(BuildContext context) {
    // mede após renderizar e reporta âncoras locais
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportAnchors());

    final cs = Theme.of(context).colorScheme;

    return IgnorePointer(
      ignoring: true, // visualização apenas
      child: Container(
        width: widget.width,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset: const Offset(0, 6),
              color: cs.shadow.withOpacity(.08),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.node.type != NodeType.message)
              Container(
                decoration: BoxDecoration(
                  color: _headerColor().withOpacity(.9),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(_iconFor(widget.node.type), color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.node.title.isEmpty ? _fallbackTitle() : widget.node.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: _body(context, widget.node),
            ),
          ],
        ),
      ),
    );
  }

  void _reportAnchors() {
    final nodeBox = context.findRenderObject() as RenderBox?;
    if (nodeBox == null || !nodeBox.attached) return;

    Offset localOf(GlobalKey k) {
      final ctx = k.currentContext;
      if (ctx == null) return Offset.zero;
      final portBox = ctx.findRenderObject() as RenderBox?;
      if (portBox == null || !portBox.attached) return Offset.zero;
      final sz = portBox.size;
      final centerGlobal = portBox.localToGlobal(Offset(sz.width / 2, sz.height / 2));
      return nodeBox.globalToLocal(centerGlobal); // LOCAL dentro do nó
    }

    final n = widget.node;
    if (n.type == NodeType.message) {
      widget.onReportPortLocal(n.id, 'onReply',  localOf(_replyKey));
      widget.onReportPortLocal(n.id, 'onTimeout', localOf(_timeoutKey));
    } else if (n.type == NodeType.menu) {
      final List opts = (n.data['options'] as List?) ?? [];
      for (final o in opts) {
        final k   = (o['key'] ?? '1').toString();
        final p   = 'opt:$k';
        final gk  = _menuOptKeys[p];
        if (gk != null) {
          widget.onReportPortLocal(n.id, p, localOf(gk));
        }
      }
      widget.onReportPortLocal(n.id, 'onTimeout', localOf(_menuTimeoutKey));
    }
  }

  Color _headerColor() {
    switch (widget.node.type) {
      case NodeType.message: return Colors.indigo;
      case NodeType.menu:    return Colors.blue;
      case NodeType.handoff: return Colors.purple;
      case NodeType.end:     return Colors.teal;
      case NodeType.start:   return Colors.indigo;
    }
  }

  String _fallbackTitle() {
    switch (widget.node.type) {
      case NodeType.message: return 'Mensagem — Texto';
      case NodeType.menu:    return 'Menu';
      case NodeType.handoff: return 'Encerrar/Handoff';
      case NodeType.end:     return 'Fim';
      case NodeType.start:   return 'Início';
    }
  }

  IconData _iconFor(NodeType t) {
    switch (t) {
      case NodeType.message: return Icons.sms_outlined;
      case NodeType.menu:    return Icons.segment_outlined;
      case NodeType.handoff: return Icons.support_agent_outlined;
      case NodeType.end:     return Icons.stop_circle_outlined;
      case NodeType.start:   return Icons.play_circle_outline;
    }
  }

  Widget _fieldBox(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      ),
    );
  }

  Widget _portDot(
      BuildContext context, {
        required Color fill,
        double size = 11,
        Key? key, // ⬅️ NOVO: para medir
      }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
    );
  }

  Widget _body(BuildContext context, FunnelNode n) {
    switch (n.type) {
      case NodeType.message: {
        final cs = Theme.of(context).colorScheme;
        final int waitValue = (n.data['waitValue'] ?? 10) as int;
        final String waitUnit = (n.data['waitUnit'] ?? 'minutes').toString().toLowerCase();

        String unitLabel() {
          switch (waitUnit) {
            case 'hours': return waitValue == 1 ? 'hora' : 'horas';
            case 'days':  return waitValue == 1 ? 'dia'  : 'dias';
            default:      return waitValue == 1 ? 'minuto' : 'minutos';
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '[${n.title.isEmpty ? _fallbackTitle() : n.title}]',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _fieldBox(context, (n.data['text'] ?? '').toString()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Se o contato responder',
                    style: Theme.of(context).textTheme.bodySmall)),
                _portDot(context, fill: Colors.green, size: 11, key: _replyKey), // ⬅️ mede
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(
                  'Se o contato não responder (máximo $waitValue ${unitLabel()})',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
                _portDot(context, fill: Colors.red, size: 11, key: _timeoutKey), // ⬅️ mede
              ],
            ),
          ],
        );
      }

      case NodeType.menu: {
        final cs = Theme.of(context).colorScheme;
        final String prompt = (n.data['prompt'] ?? '').toString();
        final List opts = (n.data['options'] as List?) ?? [];
        final int waitValue = (n.data['waitValue'] ?? 10) as int;
        final String waitUnit = (n.data['waitUnit'] ?? 'minutes').toString().toLowerCase();

        // garantir que temos keys para cada opção
        final wanted = <String>{for (final o in opts) 'opt:${(o['key'] ?? '1')}'};
        for (final p in wanted) { _menuOptKeys.putIfAbsent(p, () => GlobalKey()); }
        _menuOptKeys.removeWhere((p, _) => !wanted.contains(p));

        String unitLabel() {
          switch (waitUnit) {
            case 'hours': return waitValue == 1 ? 'hora' : 'horas';
            case 'days':  return waitValue == 1 ? 'dia'  : 'dias';
            default:      return waitValue == 1 ? 'minuto' : 'minutos';
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldBox(context, prompt),
            const SizedBox(height: 8),
            ...opts.map((o) {
              final k  = (o['key'] ?? '1').toString();
              final lb = (o['label'] ?? 'Opção $k').toString();
              final port = 'opt:$k';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _fieldBox(context, '• $k: $lb')),
                    const SizedBox(width: 8),
                    _portDot(context, fill: Colors.green, size: 11, key: _menuOptKeys[port]), // ⬅️ mede
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text(
                  'Se não responder (máximo $waitValue ${unitLabel()})',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
                _portDot(context, fill: Colors.redAccent, size: 11, key: _menuTimeoutKey), // ⬅️ mede
              ],
            ),
          ],
        );
      }

      case NodeType.handoff:
        return _fieldBox(context, (n.data['text'] ?? 'Transferindo para atendente...').toString());
      case NodeType.end:
        return _fieldBox(context, (n.data['text'] ?? 'Encerrando atendimento...').toString());
      case NodeType.start:
        return const SizedBox.shrink();
    }
  }
}

/// ====== toolbox flutuante ======
class _FloatingToolbox extends StatelessWidget {
  const _FloatingToolbox({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Zoom +', onPressed: onZoomIn, icon: const Icon(Icons.zoom_in)),
          IconButton(tooltip: 'Zoom −', onPressed: onZoomOut, icon: const Icon(Icons.zoom_out)),
          const Divider(height: 0),
          IconButton(tooltip: 'Centralizar', onPressed: onCenter, icon: const Icon(Icons.center_focus_strong)),
        ],
      ),
    );
  }
}