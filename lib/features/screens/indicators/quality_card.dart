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

  // --------------------- helpers de Firestore ------------------------------
  Future<(String, String)> _getIds() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final snap =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final data = snap.data() as Map<String, dynamic>? ?? {};

    final String companyId = (data['createdBy'] as String?)?.isNotEmpty == true
        ? data['createdBy'] as String
        : uid;

    final String phoneId = data['defaultPhoneId'] as String;

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

    return FutureBuilder(
      future: _getIds(),
      builder: (_, idsSnap) {
        if (!idsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (companyId, phoneId) = idsSnap.data!;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('empresas')
              .doc(companyId)
              .collection('phones')
              .doc(phoneId)
              .collection('whatsappChats')
              .where('arrivalAt', isGreaterThanOrEqualTo: widget.from)
              .where('arrivalAt',
              isLessThanOrEqualTo: widget.to.add(const Duration(days: 1)))
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

            // máximos
            final maxWaitSec = _days
                .map((d) => _avg(_wait[d]!))
                .fold<double>(0, math.max);
            final maxTotalSec = _days
                .map((d) => _avg(_total[d]!))
                .fold<double>(0, math.max);

            final unitWait = _pickUnit(maxWaitSec);
            final unitTotal = _pickUnit(maxTotalSec);

            // valores já convertidos para a unidade escolhida
            final waitVals = _days
                .map((d) => _avg(_wait[d]!) / unitWait.factor)
                .toList();
            final totalVals = _days
                .map((d) => _avg(_total[d]!) / unitTotal.factor)
                .toList();

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
                  _quickMetrics(cs, periodWaitSec, periodTotalSec),
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
                              'Tempo médio de espera (${unitWait.labelShort})',
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
                              minY: 0,
                              maxY: [...waitVals, ...totalVals]
                                  .fold<double>(0, math.max) +
                                  2,
                              lineBarsData: [
                                _line(waitVals, Colors.purple),
                                _line(totalVals, Colors.amber),
                              ],
                              gridData: FlGridData(
                                show: true,
                                horizontalInterval: unitWait == _Unit.sec
                                    ? 30
                                    : unitWait == _Unit.min
                                    ? 1
                                    : 2,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (v) => FlLine(
                                    color: Colors.grey.withOpacity(.2),
                                    strokeWidth: 1),
                              ),
                              titlesData:
                              _buildTitles(cs, unitWait, unitTotal),
                              borderData: FlBorderData(show: false),
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
                              'Tempo médio de atendimento (${unitTotal.labelShort})',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legend(cs, Colors.purple, 'Tempo médio de espera'),
                      const SizedBox(width: 12),
                      _legend(cs, Colors.amber, 'Tempo médio de atendimento'),
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
    children: [
      Container(
          width: 12,
          height: 12,
          decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(txt, style: const TextStyle(fontSize: 12)),
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
  FlTitlesData _buildTitles(
      ColorScheme cs,
      _Unit unitWait,
      _Unit unitTotal,
      ) {
    // intervalo em SEGUNDOS que queremos marcar no gráfico
    double _secPerTick(_Unit u) {
      switch (u) {
        case _Unit.sec:  return 15;          // 0, 15, 30, 45…
        case _Unit.min:  return 60;          // 0, 1, 2, 3 min…
        case _Unit.hour: return 3600;        // 0, 1, 2, 3 h…
        case _Unit.day:  return 86400;       // 0, 1, 2, 3 dias…
      }
    }

    /// Converte `v` (que chega em segundos) para a unidade escolhida,
    /// arredonda e devolve como string sem casas decimais.
    String _fmt(double v, _Unit u) => (v / u.factor).round().toString();

    return FlTitlesData(
      /* ---------- EIXO ESQUERDO ---------- */
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: _secPerTick(unitWait),
          getTitlesWidget: (v, _) {
            if (v < 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _fmt(v, unitWait),            // ← sempre inteiro
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onBackground.withOpacity(.7),
                ),
              ),
            );
          },
        ),
      ),

      /* ---------- EIXO DIREITO ---------- */
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          interval: _secPerTick(unitTotal),
          getTitlesWidget: (v, _) {
            if (v < 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _fmt(v, unitTotal),           // ← sempre inteiro
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onBackground.withOpacity(.7),
                ),
              ),
            );
          },
        ),
      ),

      /* ---------- EIXO INFERIOR ---------- */
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
              style: TextStyle(
                fontSize: 11,
                color: cs.onBackground.withOpacity(.7),
              ),
            );
          },
        ),
      ),

      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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