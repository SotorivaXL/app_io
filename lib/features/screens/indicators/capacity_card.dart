// capacity_card.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CapacityCard extends StatefulWidget {
  const CapacityCard({
    super.key,
    required this.from,
    required this.to,
  });

  final DateTime from;
  final DateTime to;

  @override
  State<CapacityCard> createState() => _CapacityCardState();
}

class _CapacityCardState extends State<CapacityCard> {
  /* ------------------------- dados -------------------------------- */
  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  late List<DateTime> _days;
  late Map<DateTime, int> _novos, _pend, _fins;

  /* ------------------------- zoom / pan --------------------------- */
  late final TransformationController _tc;
  bool _panEnabled = true;
  bool _zoomEnabled = true;

  /* ------------------------- tooltip ------------------------------ */
  int? _fixedGroup;       // índice do grupo fixado
  Offset? _tooltipPos;    // coordenada local dentro do gráfico

  /* ---------------------------------------------------------------- */
  @override
  void initState() {
    super.initState();
    _tc = TransformationController();
    _rebuildRanges();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CapacityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_day(oldWidget.from) != _day(widget.from) ||
        _day(oldWidget.to) != _day(widget.to)) {
      _rebuildRanges();
    }
  }

  void _rebuildRanges() {
    _days = [];
    _novos = {};
    _pend = {};
    _fins = {};

    for (DateTime d = _day(widget.from);
    !d.isAfter(_day(widget.to));
    d = d.add(const Duration(days: 1))) {
      _days.add(d);
      _novos[d] = _pend[d] = _fins[d] = 0;
    }
    setState(() {});
  }

  /// Resolve companyId/phoneId para user OU empresa
  Future<(String companyId, String? phoneId)> _resolvePhoneCtx() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final fs = FirebaseFirestore.instance;

    String companyId = uid;
    String? phoneId;

    // tenta users/{uid}
    final uSnap = await fs.collection('users').doc(uid).get();
    if (uSnap.exists) {
      final u = uSnap.data() ?? {};
      companyId =
      (u['createdBy'] as String?)?.isNotEmpty == true ? u['createdBy'] as String : uid;
      phoneId = u['defaultPhoneId'] as String?;
    }

    // tenta empresas/{companyId}.defaultPhoneId
    if (phoneId == null) {
      final eSnap = await fs.collection('empresas').doc(companyId).get();
      if (eSnap.exists) {
        phoneId = eSnap.data()?['defaultPhoneId'] as String?;
      }
    }

    // pega o primeiro de empresas/{companyId}/phones e persiste como default
    if (phoneId == null) {
      final ph = await fs
          .collection('empresas').doc(companyId)
          .collection('phones')
          .limit(1)
          .get();

      if (ph.docs.isNotEmpty) {
        phoneId = ph.docs.first.id;

        if (uSnap.exists) {
          await fs.collection('users').doc(uid)
              .set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
        } else {
          await fs.collection('empresas').doc(companyId)
              .set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
        }
      }
    }

    return (companyId, phoneId);
  }

  void _inc(Map<DateTime, int> map, Timestamp? ts) {
    if (ts == null) return;
    final day = _day(ts.toDate());
    if (day.isBefore(_day(widget.from)) || day.isAfter(_day(widget.to))) return;
    map[day] = (map[day] ?? 0) + 1;
  }

  Color _axisColor(BuildContext context, {double opacity = .7}) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface
        : cs.onBackground;
    return base.withOpacity(opacity);
  }

  /* ---------------------------------------------------------------- */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<(String, String?)>(
      future: _resolvePhoneCtx(),
      builder: (context, idsSnap) {
        if (!idsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (companyId, phoneId) = idsSnap.data!;
        if (phoneId == null) {
          return Center(
            child: Text('Nenhum número configurado.', style: TextStyle(color: cs.onBackground)),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('empresas').doc(companyId)
              .collection('phones').doc(phoneId)
              .collection('whatsappChats')
              .snapshots(),
          builder: (context, chatSnap) {
            if (!chatSnap.hasData) return const Center(child: CircularProgressIndicator());

            /* ---- zera contadores ---- */
            for (final d in _days) _novos[d] = _pend[d] = _fins[d] = 0;

            /* ---- status atual ---- */
            for (final c in chatSnap.data!.docs) {
              final st = c['status'];
              _inc(st == 'novo' ? _novos : st == 'atendendo' ? _pend : _fins,
                  c['timestamp'] as Timestamp?);
            }

            /* ---- histórico ---- */
            for (final c in chatSnap.data!.docs) {
              FirebaseFirestore.instance
                  .collection('empresas')
                  .doc(companyId)
                  .collection('phones')
                  .doc(phoneId)
                  .collection('whatsappChats')
                  .doc(c.id)
                  .collection('history')
                  .where('changedAt',
                  isGreaterThanOrEqualTo: widget.from,
                  isLessThanOrEqualTo: widget.to.add(const Duration(days: 1)))
                  .get()
                  .then((hSnap) {
                for (final h in hSnap.docs) {
                  final st = h['status'];
                  _inc(st == 'novo' ? _novos : st == 'atendendo' ? _pend : _fins,
                      h['changedAt'] as Timestamp?);
                }
                if (mounted) setState(() {});
              });
            }

            /* ---- listas alinhadas ---- */
            final novos = _days.map((d) => _novos[d]!).toList();
            final fins = _days.map((d) => _fins[d]!).toList();
            final pend = _days.map((d) => _pend[d]!).toList();

            final totalNovos = novos.reduce((a, b) => a + b);
            final totalFins = fins.reduce((a, b) => a + b);
            final totalPend = pend.reduce((a, b) => a + b);
            final totalAtend = totalNovos + totalFins + totalPend;

            /* ---- eixo Y ---- */
            double maxY =
            [novos, fins, pend].expand((l) => l).fold<double>(0, (m, v) => v > m ? v.toDouble() : m);
            double _calcStep(double v) {
              if (v <= 10) return 1;
              if (v <= 20) return 2;
              if (v <= 40) return 4;
              if (v <= 60) return 10;
              if (v <= 120) return 20;
              if (v <= 300) return 50;
              return 100;
            }

            if (maxY < 10) maxY = 10;
            final step = _calcStep(maxY);
            maxY = ((maxY / step).ceil()) * step;
            final smallRange = maxY <= 10;
            final labelInterval = smallRange ? 1.0 : step;
            final gridInterval = smallRange ? 1.0 : step;

            /* ---- grupo de barras ---- */
            BarChartGroupData _barGroup(int i) {
              final rods = <BarChartRodData>[
                if (novos[i] > 0) BarChartRodData(toY: novos[i].toDouble(), color: Colors.purple, width: 8),
                if (fins[i] > 0)  BarChartRodData(toY: fins [i].toDouble(), color: Colors.orange.shade400, width: 8),
                if (pend[i] > 0)  BarChartRodData(toY: pend [i].toDouble(), color: Colors.blue.shade200, width: 8),
              ];
              return BarChartGroupData(x: i, barsSpace: 4, barRods: rods);
            }

            /* ---- widget principal ---- */
            return Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    color: cs.shadow.withOpacity(.05),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Capacidade de atendimento', style: TextStyle(color: cs.onBackground, fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 2),
                  Text('Número de atendimentos novos x concluídos', style: TextStyle(color: cs.onBackground.withOpacity(.6), fontSize: 13)),
                  const SizedBox(height: 16),

                  /* métricas */
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _metric('Total de Atendimentos', totalAtend.toString(), cs),
                      _metric('Novos', totalNovos.toString(), cs),
                      _metric('Concluídos', totalFins.toString(), cs),
                    ],
                  ),
                  const SizedBox(height: 20),

                  /* gráfico + tooltip */
                  SizedBox(
                    height: 220,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double tooltipWidth = 120;
                        const double tooltipHeight = 70;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            /* gráfico */
                            BarChart(
                              transformationConfig: FlTransformationConfig(
                                scaleAxis: FlScaleAxis.horizontal,
                                minScale: 1,
                                maxScale: 25,
                                panEnabled: _panEnabled,
                                scaleEnabled: _zoomEnabled,
                                transformationController: _tc,
                              ),
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                groupsSpace: 12,
                                barGroups: List.generate(_days.length, _barGroup),
                                maxY: maxY,
                                borderData: FlBorderData(show: false),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: gridInterval,
                                  checkToShowHorizontalLine: (_) => true,
                                  getDrawingHorizontalLine: (_) => FlLine(color: _axisColor(context, opacity: .2), strokeWidth: 1),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 32,
                                      interval: labelInterval,
                                      getTitlesWidget: (value, _) => Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Text(value.toInt().toString(), style: TextStyle(fontSize: 11, color: _axisColor(context))),
                                      ),
                                    ),
                                  ),
                                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      getTitlesWidget: (value, meta) {
                                        final idx = value.toInt();
                                        if (idx >= _days.length) return const SizedBox.shrink();

                                        final bool hasBars = (_novos[_days[idx]]! + _fins[_days[idx]]! + _pend[_days[idx]]!) > 0;
                                        final stepX = (_days.length / 10).ceil();
                                        if (!hasBars && idx % stepX != 0) return const SizedBox.shrink();

                                        return Transform.rotate(
                                          angle: -45 * 3.1416 / 180,
                                          child: Text(DateFormat('d/M').format(_days[idx]), style: const TextStyle(fontSize: 11)),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                /* touch */
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  handleBuiltInTouches: true,
                                  touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 15),
                                  touchTooltipData: BarTouchTooltipData(
                                    tooltipPadding: EdgeInsets.zero,
                                    tooltipMargin: 0,
                                    getTooltipItem: (a, b, c, d) => null,
                                  ),
                                  touchCallback: (event, resp) {
                                    if (resp == null || resp.spot == null) {
                                      if (_fixedGroup != null) {
                                        setState(() {
                                          _fixedGroup = null;
                                          _tooltipPos = null;
                                        });
                                      }
                                      return;
                                    }

                                    final index = resp.spot!.touchedBarGroupIndex;
                                    final offset = resp.spot!.offset; // dentro do gráfico

                                    if (event is FlTapUpEvent) {
                                      setState(() {
                                        if (_fixedGroup == index) {
                                          _fixedGroup = null;
                                          _tooltipPos = null;
                                        } else {
                                          _fixedGroup = index;
                                          _tooltipPos = offset;
                                        }
                                      });
                                    } else if (event is FlPanUpdateEvent) {
                                      setState(() {
                                        _fixedGroup = index;
                                        _tooltipPos = offset;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),

                            /* tooltip */
                            if (_fixedGroup != null && _tooltipPos != null)
                              Positioned(
                                left: (_tooltipPos!.dx - tooltipWidth / 2).clamp(0.0, constraints.maxWidth - tooltipWidth),
                                top: (_tooltipPos!.dy - tooltipHeight - 8).clamp(0.0, constraints.maxHeight - tooltipHeight),
                                child: _TooltipCard(
                                  scheme: cs,
                                  date: _days[_fixedGroup!],
                                  novos: _novos[_days[_fixedGroup!]]!,
                                  concl: _fins[_days[_fixedGroup!]]!,
                                  pend: _pend[_days[_fixedGroup!]]!,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendDot(color: Colors.purple, label: 'Novos'),
                      const SizedBox(width: 12),
                      _legendDot(color: Colors.orange.shade400, label: 'Concluídos'),
                      const SizedBox(width: 12),
                      _legendDot(color: Colors.blue.shade200, label: 'Pendentes'),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /* ------------------- pequenos helpers -------------------- */
  Widget _metric(String label, String valor, ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: cs.onBackground.withOpacity(.6), fontSize: 13)),
      const SizedBox(height: 2),
      Text(valor, style: TextStyle(color: cs.onBackground, fontWeight: FontWeight.w800, fontSize: 22)),
    ],
  );

  Widget _legendDot({required Color color, required String label}) => Row(
    children: [
      Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

/* ---------------------- tooltip card ----------------------- */
class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.scheme,
    required this.date,
    required this.novos,
    required this.concl,
    required this.pend,
  });

  final ColorScheme scheme;
  final DateTime date;
  final int novos, concl, pend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.onTertiaryContainer,
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('d/M').format(date), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Novos: $novos', style: const TextStyle(color: Colors.purple, fontSize: 11)),
            Text('Concluídos: $concl', style: const TextStyle(color: Colors.orange, fontSize: 11)),
            Text('Pendentes: $pend', style: const TextStyle(color: Colors.blue, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}