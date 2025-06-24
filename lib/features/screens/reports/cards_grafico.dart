import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// ────────────────── CARD “Capacidade de atendimento” ──────────────────
class CapacityCard extends StatelessWidget {
  const CapacityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // --- dados fictícios para o gráfico (substitua pelos seus) ------------
    final days   = ['4/6','5/6','6/6','7/6','8/6','9/6','10/6','11/6'];
    final novos  = [20,13,27,10,  5, 50,25,  5];
    final fins   = [10,30,25, 8,  2, 15,30,  3];
    final pend   = [70,65,60,58,80,95,90,88];

    LineChartBarData _linePendentes() => LineChartBarData(
      spots: List.generate(pend.length, (i) => FlSpot(i.toDouble(), pend[i].toDouble())),
      isCurved: true,
      dotData: FlDotData(show: false),
      barWidth: 3,
      color: Colors.blue.shade200,
    );

    BarChartGroupData _barGroup(int i) => BarChartGroupData(
      x: i,
      barRods: [
        BarChartRodData(
          toY: novos[i].toDouble(),
          color: Colors.purple,
          width: 6,
          borderRadius: BorderRadius.zero,
        ),
        BarChartRodData(
          toY: fins[i].toDouble(),
          color: Colors.orange.shade400,
          width: 6,
          borderRadius: BorderRadius.zero,
        ),
      ],
      barsSpace: 2,
    );

    return Container(
      margin: const EdgeInsets.only(top: 20), // espaço pós seletor de datas
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
          /// títulos
          Text('Capacidade de atendimento',
              style: TextStyle(
                  color: cs.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text('Número de atendimentos novos x concluídos',
              style: TextStyle(
                  color: cs.onBackground.withOpacity(.6), fontSize: 13)),

          const SizedBox(height: 16),

          /// bloco de métricas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric('Atendimentos', '196', '0%', cs),
              _metric('Novos',        '24,5', '0%', cs),
              _metric('Concluídos',   '21,38','-25%', cs),
            ],
          ),

          const SizedBox(height: 20),

          /// CHART ----------------------------------------------------------
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                /// linha de pendentes
                LineChart(
                  LineChartData(
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    minY: 0,
                    maxY: 100,
                    lineBarsData: [_linePendentes()],
                  ),
                ),
                /// barras de novos e finalizados
                BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 20,                         // 0-20-40-60-80-100
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: Colors.grey.withOpacity(.3),           // cor das linhas
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            return idx < days.length
                                ? Text(
                              days[idx],
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            )
                                : const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(days.length, (i) => _barGroup(i)),
                    maxY: 100,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          /// legenda
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(color: Colors.purple, label: 'Novos'),
              const SizedBox(width: 12),
              _legendDot(color: Colors.orange.shade400, label: 'Finalizados'),
              const SizedBox(width: 12),
              _legendDot(color: Colors.blue.shade200, label: 'Pendentes'),
            ],
          ),
        ],
      ),
    );
  }

  /// pequeno texto + seta/percentual (placeholder simplificado)
  Widget _metric(String label, String valor, String delta, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: cs.onBackground.withOpacity(.6), fontSize: 13)),
        const SizedBox(height: 2),
        Text(valor,
            style: TextStyle(
                color: cs.onBackground,
                fontWeight: FontWeight.w800,
                fontSize: 22)),
        const SizedBox(height: 2),
        Text('▼ $delta por dia',
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
    );
  }

  Widget _legendDot({required Color color, required String label}) => Row(
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

/// ────────────────── CARD “Qualidade do atendimento” ──────────────────
class QualityCard extends StatelessWidget {
  const QualityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ---------- dados fictícios (substitua pelos seus) -----------------
    final days = ['4/6','5/6','6/6','7/6','8/6','9/6','10/6','11/6'];

    // tempo médio de espera (horas)
    final esperaH = [0.1,0.2,0.3,0.5,0.7,1.5,3.1,3.2];

    // tempo médio de atendimento (dias) convertido em “escala horas*2”
    // – usamos esse truque p/ ter duas unidades em um único eixo Y
    final atendeD = [1.0,3.8,3.9,3.8,3.7,3.5,3.2,3.0]; // dias
    final atendeEsc = atendeD.map((d) => d*2).toList(); // escala 0–8

    // linha roxa (espera)
    LineChartBarData _linhaEspera() => LineChartBarData(
      spots: List.generate(esperaH.length,
              (i) => FlSpot(i.toDouble(), esperaH[i])),
      isCurved: true,
      color: Colors.purple,
      barWidth: 3,
      dotData: FlDotData(show: false),
    );

    // linha amarela (atendimento em escala)
    LineChartBarData _linhaAtende() => LineChartBarData(
      spots: List.generate(atendeEsc.length,
              (i) => FlSpot(i.toDouble(), atendeEsc[i])),
      isCurved: true,
      color: Colors.orange.shade400,
      barWidth: 3,
      dotData: FlDotData(show: false),
    );

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
          /// títulos
          Text('Qualidade do atendimento',
              style: TextStyle(
                  color: cs.onBackground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 2),
          Text('Evolução da qualidade do atendimento',
              style: TextStyle(
                  color: cs.onBackground.withOpacity(.6), fontSize: 13)),

          const SizedBox(height: 16),

          /// métricas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric('Tempo de espera', '89 min', '-72%', cs),
              _metric('Tempo de atendimento', '30 hrs', '-74%', cs),
            ],
          ),

          const SizedBox(height: 20),

          /// GRÁFICO --------------------------------------------------------
          SizedBox(
            height: 230,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 8,                // escala comum (horas*2)
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.withOpacity(.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 2,
                      // converte “escala horas*2” → dias
                      getTitlesWidget: (v, _) => Text(
                        (v/2).toStringAsFixed(0),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  topTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        return idx < days.length
                            ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(days[idx],
                              style: const TextStyle(fontSize: 11)),
                        )
                            : const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [_linhaEspera(), _linhaAtende()],
              ),
            ),
          ),

          const SizedBox(height: 12),

          /// legenda
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(color: Colors.purple, label: 'Tempo médio de espera'),
              const SizedBox(width: 12),
              _legendDot(
                  color: Colors.orange.shade400,
                  label: 'Tempo médio de atendimento'),
            ],
          ),
        ],
      ),
    );
  }

  /// componente de métrica
  Widget _metric(String label, String valor, String delta, ColorScheme cs) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: cs.onBackground.withOpacity(.6), fontSize: 13)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(
                  color: cs.onBackground,
                  fontWeight: FontWeight.w800,
                  fontSize: 22)),
          const SizedBox(height: 2),
          Text('▼ $delta',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      );

  Widget _legendDot({required Color color, required String label}) => Row(
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

