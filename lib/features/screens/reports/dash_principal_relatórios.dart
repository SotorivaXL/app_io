import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_io/features/screens/reports/cards_grafico.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({Key? key}) : super(key: key);

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  /// período exibido no seletor
  late DateTime _from;
  late DateTime _to;

  /// aba atualmente selecionada (0, 1 ou 2)
  int _currentTab = 0;

  /// formatação dd/MM/yyyy
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _to   = DateTime.now();
    _from = _to.subtract(const Duration(days: 7));
  }

  // ─────────────────────────  seletor de datas  ─────────────────────────
  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Selecionar período',
      locale: const Locale('pt', 'BR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme,
        ),
        child: child!,
      ),
    );

    if (range != null) {
      setState(() {
        _from = range.start;
        _to   = range.end;
      });
    }
  }

  // ───────────────────────── card de métricas ─────────────────────────
  Widget _metricCard({
    required String title1,
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
    required ColorScheme cs,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.secondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0, 4),
            color: cs.shadow.withOpacity(0.05),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),               // ↓ padding menor
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,   // centraliza vertical
        crossAxisAlignment: CrossAxisAlignment.center, // centraliza horizontal
        children: [
          Text(title1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onBackground.withOpacity(.8),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              )),
          const SizedBox(height: 8),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w800,
                fontSize: 32,
              )),
          const SizedBox(height: 2),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: valueColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onBackground.withOpacity(.6),
                fontSize: 12,
              )),
        ],
      ),
    );
  }

  // ─────────────────────────  dashboard  ─────────────────────────
  Widget _dashboard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (_, constraints) {
        const spacing = 16.0;
        final bool wide = constraints.maxWidth > 600;
        final columns   = wide ? 4 : 2;

        return SingleChildScrollView(          // permite rolar se faltar espaço
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              /// GRID DE MÉTRICAS (sem Expanded)
              GridView.count(
                shrinkWrap: true,                         // altura exata
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: wide ? 1.25 : 1.15,
                children: [
                  _metricCard(
                    title1: 'Fila',
                    title:  'Atendimentos',
                    value:  '1',
                    subtitle: 'agora',
                    valueColor: Colors.red.shade600,
                    cs: cs,
                  ),
                  _metricCard(
                    title1: 'Em atendimento',
                    title:  'Atendimentos',
                    value:  '87',
                    subtitle: 'agora',
                    valueColor: Colors.amber.shade800,
                    cs: cs,
                  ),
                  _metricCard(
                    title1: 'Concluídos',
                    title:  'Atendimentos',
                    value:  '658',
                    subtitle: 'Últimos 30 dias',
                    valueColor: Colors.green.shade700,
                    cs: cs,
                  ),
                  _metricCard(
                    title1: 'Total',
                    title:  'Atendimentos',
                    value:  '746',
                    subtitle: 'Pendentes + concluídos',
                    valueColor: Colors.blue.shade700,
                    cs: cs,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              /// SELETOR DE PERÍODO – agora imediatamente após os cards
              GestureDetector(
                onTap: _pickRange,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: cs.secondary,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_fmt.format(_from)}  –  ${_fmt.format(_to)}',
                        style: TextStyle(
                          color: cs.onBackground.withOpacity(.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(Icons.calendar_month, color: cs.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),   // mesmo espaçamento dos cards
              const CapacityCard(),         // card com linha + barras
              const SizedBox(height: 20),
              const QualityCard(),    // ⇦ NOVO card adicionado
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────  TAB estilizada  ─────────────────────────
  Tab _styledTab(String label, int idx, ColorScheme cs) {
    final bool selected = _currentTab == idx;

    return Tab(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        decoration: selected
            ? BoxDecoration(
          color: cs.primary,                // fundo roxo SÓ se ativa
          borderRadius: BorderRadius.circular(18),
        )
            : const BoxDecoration(),             // abas inativas sem fundo
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : cs.onBackground.withOpacity(.9), // só texto na aba inativa
          ),
        ),
      ),
    );
  }

  // ─────────────────────────  build  ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: cs.background,
        body: Column(
          children: [
            const SizedBox(height: 12),

            /// TABBAR
            Center(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,

                // 100 % sem borda
                dividerColor: Colors.transparent,
                dividerHeight: 0,

                // indicador invisível (continua satisfazendo o assert)
                indicator: const BoxDecoration(),

                overlayColor: MaterialStateProperty.all(Colors.transparent),
                onTap: (i) => setState(() => _currentTab = i),
                tabs: [
                  _styledTab('Geral', 0, cs),
                  _styledTab('Usuário', 1, cs),
                  _styledTab('Resultados', 2, cs),
                ],
              ),
            ),
            const SizedBox(height: 12),

            /// CONTEÚDO
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _dashboard(context),               // Aba “Geral”
                  Center(child: Text('Usuário')),    // placeholder
                  Center(child: Text('Resultados')), // placeholder
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}