// quality_card.dart
import 'dart:math';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// ----------- WIDGET --------------------------------------------------------
class QualityCard extends StatefulWidget {
  const QualityCard({
    super.key,
    required this.from,
    required this.to,
  });

  final DateTime from;
  final DateTime to;

  @override
  State<QualityCard> createState() => _QualityCardState();
}

enum _Unit { sec, min, hour, day }

extension on _Unit {
  double get factor {
    switch (this) {
      case _Unit.sec:
        return 1;
      case _Unit.min:
        return 60;
      case _Unit.hour:
        return 3600;
      case _Unit.day:
        return 86400;
    }
  }

  String get labelShort {
    switch (this) {
      case _Unit.sec:
        return 's';
      case _Unit.min:
        return 'min';
      case _Unit.hour:
        return 'h';
      case _Unit.day:
        return 'dias';
    }
  }
}

/// ----------- ESTADO --------------------------------------------------------
class _QualityCardState extends State<QualityCard> {
  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  double _tickInterval(_Unit u) => u == _Unit.sec ? 15 : 1; // 15s ou 1 unidade

  // arredonda X para o múltiplo de M imediatamente acima (ex.: 23 → 25)
  double _ceilToMultiple(double x, double m) =>
      (x <= 0) ? m : (x / m).ceil() * m;

// escolhe um passo "bonito" (1, 2, 5, 10, 20, 50, 100...)
// mirando ~5 divisões no eixo
  double _niceInterval(double maxY) {
    if (maxY <= 0) return 1;
    double raw = maxY / 5;     // alvo ≈ 5 linhas
    double step = 1;
    while (raw > step) {
      if (raw <= step * 2) return step * 2;
      if (raw <= step * 5) return step * 5;
      step *= 10;
    }
    return step;
  }

  late List<DateTime> _days;
  late Map<DateTime, List<double>> _wait, _total;

  @override
  void initState() {
    super.initState();
    _rebuildRanges();
  }

  @override
  void didUpdateWidget(covariant QualityCard old) {
    super.didUpdateWidget(old);
    if (_day(old.from) != _day(widget.from) ||
        _day(old.to) != _day(widget.to)) {
      _rebuildRanges();
    }
  }

  void _rebuildRanges() {
    _days = [];
    _wait = {};
    _total = {};
    for (var d = _day(widget.from);
    !d.isAfter(_day(widget.to));
    d = d.add(const Duration(days: 1))) {
      _days.add(d);
      _wait[d] = [];
      _total[d] = [];
    }
    setState(() {});
  }

  Future<(String companyId, String? phoneId)> _resolvePhoneCtx() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final fs = FirebaseFirestore.instance;

    String companyId = uid;
    String? phoneId;

    final uSnap = await fs.collection('users').doc(uid).get();
    if (uSnap.exists) {
      final u = uSnap.data() ?? {};
      companyId =
      (u['createdBy'] as String?)?.isNotEmpty == true ? u['createdBy'] as String : uid;
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

  void _accum(DateTime day, double wait, double tot) {
    if (!_wait.containsKey(day)) return;
    if (wait > 0) _wait[day]!.add(wait);
    if (tot > 0) _total[day]!.add(tot);
  }

  String _fmtDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()} s';
    if (seconds < 3600) return '${(seconds / 60).round()} min';
    if (seconds < 86400) return '${(seconds / 3600).round()} h';
    return '${(seconds / 86400).round()} dias';
  }

  double _avg(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  _Unit _pickUnit(double maxSeconds) {
    if (maxSeconds < 120) return _Unit.sec;
    if (maxSeconds < 7200) return _Unit.min;
    if (maxSeconds < 172800) return _Unit.hour;
    return _Unit.day;
  }

  // --------------------- BUILD ---------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<(String, String?)>(
      future: _resolvePhoneCtx(),
      builder: (_, idsSnap) {
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
              .where('arrivalAt', isGreaterThanOrEqualTo: widget.from)
              .where('arrivalAt', isLessThanOrEqualTo: widget.to.add(const Duration(days: 1)))
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // limpa buffers
            for (final d in _days) {
              _wait[d]!.clear();
              _total[d]!.clear();
            }

            // popula buffers
            for (final doc in snap.data!.docs) {
              final data = doc.data()! as Map<String, dynamic>;
              final day = _day((data['arrivalAt'] as Timestamp).toDate());

              final waitSec = (data['waitTimeSec'] ?? 0).toDouble();
              final totalSec = (data['totalTimeSec'] ?? 0).toDouble();

              _accum(day, waitSec, totalSec);
            }

            final maxWaitSec  = _days.map((d) => _avg(_wait[d]!)).fold<double>(0, math.max);
            final maxTotalSec = _days.map((d) => _avg(_total[d]!)).fold<double>(0, math.max);

            final unit = _pickUnit(math.max(maxWaitSec, maxTotalSec));

            final waitVals  = _days.map((d) => (_avg(_wait[d]!)  / unit.factor).roundToDouble()).toList();
            final totalVals = _days.map((d) => (_avg(_total[d]!) / unit.factor).roundToDouble()).toList();
            final maxSerie = [...waitVals, ...totalVals].fold<double>(0, math.max);
            final interval = _niceInterval(maxSerie);
            final maxY = _ceilToMultiple(maxSerie, interval); // dá um respiro no topo

            // métricas rápidas
            final periodWaitSec = _avg(_days
                .map((d) => _avg(_wait[d]!))
                .where((v) => v > 0)
                .toList());
            final periodTotalSec = _avg(_days
                .map((d) => _avg(_total[d]!))
                .where((v) => v > 0)
                .toList());

            // ----- UI card --------------------------------------------------
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
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Qualidade do atendimento',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onBackground)),
                  const SizedBox(height: 2),
                  Text('Evolução da qualidade do atendimento',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onBackground.withOpacity(.6))),
                  const SizedBox(height: 20),

// Desktop/Web: alinhado à esquerda; Mobile: mantém spaceBetween
                  Builder(builder: (context) {
                    final bool isDesktop = MediaQuery.of(context).size.width >= 1024;

                    final items = <Widget>[
                      _metric('Tempo de espera', _fmtDuration(periodWaitSec), cs),
                      _metric('Tempo de atendimento', _fmtDuration(periodTotalSec), cs),
                    ];

                    return isDesktop
                        ? Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 28,   // espaço horizontal entre as métricas
                      runSpacing: 8, // quebra bonita se faltar largura
                      children: items,
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: items,
                    );
                  }),

                  const SizedBox(height: 20),

                  // -------- gráfico + legendas --------------------------------
                  SizedBox(
                    height: 240,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // eixo esquerdo (legenda)
                        Padding(
                          padding:
                          const EdgeInsets.only(left: 4, right: 6, top: 12),
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'Tempo médio de espera (${unit.labelShort})',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onBackground.withOpacity(.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),

                        // gráfico
                        Expanded(
                          child: LineChart(
                            LineChartData(
                              clipData: FlClipData.all(),
                              minX: 0,
                              maxX: (_days.length - 1).toDouble(),
                              minY: 0,
                              maxY: maxY,

                              lineBarsData: [
                                _line(waitVals, Colors.purple),
                                _line(totalVals, Colors.amber),
                              ],

                              // grade horizontal com o MESMO intervalo do eixo (fica limpo)
                              gridData: FlGridData(
                                show: true,
                                horizontalInterval: interval,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (v) =>
                                    FlLine(color: Colors.grey.withOpacity(.18), strokeWidth: 1),
                              ),

                              titlesData: _buildTitles(cs, unit, interval), // ← nova assinatura
                              borderData: FlBorderData(show: false),

                              // ===== Tooltip bonito e claro =====
                              lineTouchData: LineTouchData(
                                handleBuiltInTouches: true,
                                touchTooltipData: LineTouchTooltipData(
                                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  fitInsideHorizontally: true,
                                  fitInsideVertically: true,
                                  getTooltipItems: (spots) => spots.map((s) {
                                    final label = s.barIndex == 0 ? 'Espera' : 'Atend.';
                                    final val   = s.y.toInt(); // sem casas decimais
                                    return LineTooltipItem(
                                      '$label: $val ${unit.labelShort}',
                                      TextStyle(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  }).toList(),
                                ),
                                getTouchedSpotIndicator: (barData, indexes) => indexes.map((i) {
                                  final c = barData.color ?? Colors.black;
                                  return TouchedSpotIndicatorData(
                                    FlLine(color: c.withOpacity(.30), strokeWidth: 1.5),
                                    FlDotData(
                                      show: true,
                                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                                        radius: 4,
                                        color: Colors.white,
                                        strokeWidth: 3,
                                        strokeColor: c,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),

                        // eixo direito (legenda)
                        Padding(
                          padding:
                          const EdgeInsets.only(left: 6, right: 4, top: 12),
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              'Tempo médio de atendimento (${unit.labelShort})',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onBackground.withOpacity(.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // legenda
                  // ⬇️ Substitua a seção da legenda
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,          // encolhe se faltar espaço
                          child: _legend(cs, Colors.purple, 'Tempo médio de espera'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _legend(cs, Colors.amber, 'Tempo médio de atendimento'),
                        ),
                      ),
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

  /// ----------- helpers visuais -------------------------------------------
  Widget _legend(ColorScheme cs, Color c, String txt) => Row(
    mainAxisSize: MainAxisSize.min,       // não ocupa mais do que precisa
    children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 4),
      Text(txt, style: const TextStyle(fontSize: 12), softWrap: false),
    ],
  );

  LineChartBarData _line(List<double> vals, Color color) {
    final spots = <FlSpot>[];
    for (var i = 0; i < vals.length; i++) {
      spots.add(FlSpot(i.toDouble(), vals[i]));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(show: false),
    );
  }

  /// --- títulos de eixos / rótulos ---------------------------------
  FlTitlesData _buildTitles(ColorScheme cs, _Unit unit, double interval) {
    String _fmt(double v) => v.round().toString(); // sempre inteiro

    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,                 // mais espaço
          interval: interval,               // menos rótulos
          getTitlesWidget: (v, _) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              _fmt(v),
              style: TextStyle(fontSize: 11, color: cs.onBackground.withOpacity(.7)),
            ),
          ),
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,                 // mais espaço
          interval: interval,
          getTitlesWidget: (v, _) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              _fmt(v),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: cs.onBackground.withOpacity(.7)),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= _days.length) return const SizedBox.shrink();
            if (_days.length > 14 && i.isOdd) return const SizedBox.shrink();
            return Text(
              DateFormat('d/M').format(_days[i]),
              style: TextStyle(fontSize: 11, color: cs.onBackground.withOpacity(.7)),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  Widget _quickMetrics(ColorScheme cs, double waitSec, double totalSec) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _metric('Tempo de espera', _fmtDuration(waitSec), cs),
        _metric('Tempo de atendimento', _fmtDuration(totalSec), cs),
      ],
    );
  }

  Widget _metric(String title, String value, ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title,
          style: TextStyle(
              color: cs.onBackground.withOpacity(.6), fontSize: 13)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              color: cs.onBackground,
              fontWeight: FontWeight.w800,
              fontSize: 22)),
    ],
  );
}