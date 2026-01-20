import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_io/features/screens/indicators/quality_card.dart';
import 'package:app_io/features/screens/indicators/capacity_card.dart';
import 'package:app_io/features/screens/indicators/users_tab.dart';
import 'package:app_io/features/screens/indicators/results_tab.dart';

class IndicatorsPage extends StatefulWidget {
  const IndicatorsPage({Key? key}) : super(key: key);

  @override
  State<IndicatorsPage> createState() => _ReportsPageState();
}

/// Contexto resolvido para a tela: companyId + phoneId
class _PhoneCtx {
  final String companyId;
  final String? phoneId; // pode ser null se não houver nenhum telefone
  _PhoneCtx({required this.companyId, required this.phoneId});
}

/// Resolve companyId/phoneId para user **ou** empresa
Future<_PhoneCtx> _resolvePhoneCtx() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final fs = FirebaseFirestore.instance;

  String companyId = uid;
  String? phoneId;

  // 1) Tenta users/{uid}
  final userSnap = await fs.collection('users').doc(uid).get();
  if (userSnap.exists) {
    final u = userSnap.data() ?? {};
    companyId = (u['createdBy'] as String?)?.isNotEmpty == true
        ? u['createdBy'] as String
        : uid;
    phoneId = u['defaultPhoneId'] as String?;
  } else {
    // conta empresa: users/{uid} normalmente não existe
    companyId = uid;
  }

  // 2) Se ainda não há phoneId, tenta empresas/{companyId}.defaultPhoneId
  if (phoneId == null) {
    final empSnap = await fs.collection('empresas').doc(companyId).get();
    if (empSnap.exists) {
      final e = empSnap.data() ?? {};
      phoneId = e['defaultPhoneId'] as String?;
    }
  }

  // 3) Se ainda não há phoneId, pega o primeiro de empresas/{companyId}/phones
  if (phoneId == null) {
    final phonesSnap = await fs
        .collection('empresas')
        .doc(companyId)
        .collection('phones')
        .limit(1)
        .get();

    if (phonesSnap.docs.isNotEmpty) {
      phoneId = phonesSnap.docs.first.id;

      // (opcional) Persistir como default
      if (userSnap.exists) {
        await fs
            .collection('users')
            .doc(uid)
            .set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
      } else {
        await fs
            .collection('empresas')
            .doc(companyId)
            .set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
      }
    }
  }

  return _PhoneCtx(companyId: companyId, phoneId: phoneId);
}

class _ReportsPageState extends State<IndicatorsPage> {
  /// período exibido no seletor
  late DateTime _from;
  late DateTime _to;
  final GlobalKey _rangePillKey = GlobalKey();

  /// aba atualmente selecionada (0, 1 ou 2)
  int _currentTab = 0;

  /// formatação dd/MM/yyyy
  final _fmt = DateFormat('dd/MM/yyyy');

  bool get _isDesktop {
    final w = MediaQuery.of(context).size.width;
    return w >= 1024;
  }

  EdgeInsets _sideGutters() {
    // mesmos gutters para toda a página (desktop e mobile variam levemente)
    final w = MediaQuery.of(context).size.width;
    if (w >= 1440)
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    if (w >= 1024)
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  }

  @override
  void initState() {
    super.initState();
    _to = DateTime.now();
    _from = _to.subtract(const Duration(days: 7));
  }

  Future<void> _pickRangeAnchored() async {
    final cs = Theme.of(context).colorScheme;
    final box = _rangePillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final screen = MediaQuery.of(context).size;
    final offset = box.localToGlobal(Offset.zero);
    final size   = box.size;

    // popover quadrado e compacto
    const double popupW = 360;
    const double popupH = 360;
    const double margin = 12;

    double left = offset.dx;
    double top  = offset.dy + size.height + 8;

    if (left + popupW > screen.width - margin) {
      left = screen.width - margin - popupW;
    }
    if (top + popupH > screen.height - margin) {
      top = (offset.dy - popupH - 8).clamp(margin, screen.height - popupH - margin);
    }

    final picked = await showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(.2),
      builder: (ctx) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top : top,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: popupW,
                  height: popupH,
                  child: Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: ColorScheme.light(
                        primary   : cs.primary,
                        onPrimary : Colors.white,
                        surface   : cs.secondary,
                        onSurface : cs.onBackground,
                      ),
                      datePickerTheme: const DatePickerThemeData(
                        rangeSelectionBackgroundColor: Color(0x220090EE),
                        // opcional: deixa os cantos do calendário retos
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                    ),
                    child: DateRangePickerDialog(
                      firstDate: DateTime(2020),
                      lastDate : DateTime.now(),
                      initialDateRange: DateTimeRange(start: _from, end: _to),

                      // ↓ deixa compacto e “moderno”
                      initialEntryMode: DatePickerEntryMode.calendarOnly,
                      helpText: '',                // remove título grande
                      cancelText: 'Cancelar',
                      confirmText: 'Aplicar',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to   = picked.end;
      });
    }
  }

  // ─────────────────────────  seletor de datas  ─────────────────────────
  Future<void> _pickRange() async {
    // no desktop -> popover ancorado
    if (_isDesktop) {
      await _pickRangeAnchored();
      return;
    }

    // no mobile -> mantém o full-screen padrão
    final cs = Theme.of(context).colorScheme;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate : DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary   : cs.primary,
              onPrimary : Colors.white,
              surface   : cs.secondary,
              onSurface : cs.onBackground,
            ),
            datePickerTheme: const DatePickerThemeData(
              rangeSelectionBackgroundColor: Color(0x220090EE),
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null) {
      setState(() {
        _from = range.start;
        _to   = range.end;
      });
    }
  }

  /// mesmo seletor de período, extraído para reuso
  Widget _dateRangePill() {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _pickRange,
      child: Container(
        key: _rangePillKey, // <<< AQUI!
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: cs.secondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_fmt.format(_from)}  –  ${_fmt.format(_to)}',
              style: TextStyle(
                color: cs.onBackground.withOpacity(.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.calendar_month, color: cs.primary),
          ],
        ),
      ),
    );
  }

  // helper simples (evita importar outras libs)
  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  // ───────────────────────── card de métricas ─────────────────────────
  Widget _metricCard({
    required String title1,
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
    required ColorScheme cs,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        // baseia os tamanhos no menor lado do card (funciona pra 2 ou 4 colunas)
        final base = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight);

        // tamanhos responsivos com limites (não exagera no mobile nem no desktop)
        final pad       = _clamp(base * 0.10, 14, 24);
        final gapSm     = _clamp(base * 0.02,  4, 10);
        final gapMd     = _clamp(base * 0.04,  6, 14);

        final valueSize = _clamp(base * 0.28, 30, 56); // número grande
        final title1Sz  = _clamp(base * 0.12, 14, 22); // "Fila", "Em atendimento"
        final titleSz   = _clamp(base * 0.12, 14, 22); // "Atendimentos"
        final subSz     = _clamp(base * 0.09, 11, 16); // "agora", "Últimos 30 dias"

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
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onBackground.withOpacity(.8),
                  fontWeight: FontWeight.w700,
                  fontSize: title1Sz,
                  height: 1.05,
                ),
              ),
              SizedBox(height: gapMd),

              // valor em destaque
              Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontSize: valueSize,
                  height: 1.0,
                ),
              ),
              SizedBox(height: gapSm),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: valueColor,
                  fontSize: titleSz,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              SizedBox(height: gapMd),

              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onBackground.withOpacity(.6),
                  fontSize: subSz,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────  dashboard  ─────────────────────────
  Widget _dashboard(BuildContext context, {required bool inlineFilter}) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (_, constraints) {
        const spacing = 16.0;
        final bool wide = constraints.maxWidth > 600;
        final int columns = wide ? 4 : 2;

        return FutureBuilder<_PhoneCtx>(
          future: _resolvePhoneCtx(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final ctxv = snap.data!;
            if (ctxv.phoneId == null) {
              return Center(
                child: Text('Nenhum número configurado.',
                    style: TextStyle(color: cs.onBackground)),
              );
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('empresas')
                  .doc(ctxv.companyId)
                  .collection('phones')
                  .doc(ctxv.phoneId)
                  .collection('whatsappChats')
                  .snapshots(),
              builder: (ctx, snap2) {
                if (!snap2.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap2.data!.docs;

                final fila       = docs.where((d){ final m=(d.data() as Map<String,dynamic>? ?? {}); return (m['status'] as String?)=='novo'; }).length;
                final atendendo  = docs.where((d){ final m=(d.data() as Map<String,dynamic>? ?? {}); return (m['status'] as String?)=='atendendo'; }).length;
                final conclu30   = docs.where((d){
                  final m = (d.data() as Map<String,dynamic>? ?? {});
                  final st = (m['status'] as String?) ?? '';
                  if (st!='concluido_com_venda' && st!='recusado') return false;
                  final ts = (m['timestamp'] as Timestamp?)?.toDate();
                  return ts!=null && ts.isAfter(DateTime.now().subtract(const Duration(days:30)));
                }).length;
                final total = docs.length;

                return SingleChildScrollView(
                  padding: _sideGutters(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // no mobile, o filtro fica aqui mesmo (inline)
                          if (inlineFilter) ...[
                            _dateRangePill(),
                            const SizedBox(height: 12),
                          ],

                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: columns,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: wide ? 1.25 : 1.15,
                            padding: EdgeInsets.zero,
                            children: [
                              _metricCard(
                                title1: 'Fila',
                                title: 'Atendimentos',
                                value: fila.toString(),
                                subtitle: 'agora',
                                valueColor: Colors.red.shade600,
                                cs: cs,
                              ),
                              _metricCard(
                                title1: 'Em atendimento',
                                title: 'Atendimentos',
                                value: atendendo.toString(),
                                subtitle: 'agora',
                                valueColor: Colors.amber.shade800,
                                cs: cs,
                              ),
                              _metricCard(
                                title1: 'Concluídos',
                                title: 'Atendimentos',
                                value: conclu30.toString(),
                                subtitle: 'Últimos 30 dias',
                                valueColor: Colors.green.shade700,
                                cs: cs,
                              ),
                              _metricCard(
                                title1: 'Total',
                                title: 'Atendimentos',
                                value: total.toString(),
                                subtitle: 'Pendentes + concluídos',
                                valueColor: Colors.blue.shade700,
                                cs: cs,
                              ),
                            ],
                          ),

                          SizedBox(height: _isDesktop ? 24 : 6),
                          CapacityCard(
                            key: ValueKey(
                                '${_from.toIso8601String()}_${_to.toIso8601String()}'),
                            from: _from,
                            to: _to,
                          ),
                          const SizedBox(height: 20),
                          QualityCard(
                            key: ValueKey(
                                'q_${_from.toIso8601String()}_${_to.toIso8601String()}'),
                            from: _from,
                            to: _to,
                          ),
                          const SizedBox(height: 130),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: selected
            ? BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(18),
              )
            : const BoxDecoration(),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : cs.onBackground.withOpacity(.9),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────  build  ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // barra superior (tabs à esquerda, filtro à direita) — só no desktop
    Widget _desktopTopRow() {
      return Padding(
        padding: _sideGutters(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        // ← no seu SDK é TabBarThemeData
                        tabBarTheme: const TabBarThemeData(
                          labelPadding: EdgeInsets.zero, // zera padding de cada aba
                          // se sua versão tiver esse campo, pode ativar também:
                          // padding: EdgeInsets.zero,
                        ),
                      ),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start, // garante início absoluto
                        labelPadding: EdgeInsets.zero,    // redundante, mas reforça
                        indicatorPadding: EdgeInsets.zero,

                        dividerColor: Colors.transparent,
                        dividerHeight: 0,
                        indicator: const BoxDecoration(),
                        overlayColor: const MaterialStatePropertyAll(Colors.transparent),
                        onTap: (i) => setState(() => _currentTab = i),
                        tabs: [
                          _styledTab('Geral', 0, cs),
                          _styledTab('Resultados', 1, cs),
                          _styledTab('Usuários', 2, cs),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),
                // Filtro (pílula) à direita
                _dateRangePill(),
              ],
            ),
          ),
        ),
      );
    }

    // topo no mobile (abas centralizadas; sem filtro aqui)
    Widget _mobileTopTabs() {
      return Padding(
        padding: _sideGutters(),
        child: Center(
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            indicator: const BoxDecoration(),
            overlayColor: MaterialStateProperty.all(Colors.transparent),
            onTap: (i) => setState(() => _currentTab = i),
            tabs: [
              _styledTab('Geral', 0, cs),
              _styledTab('Resultados', 1, cs),
              _styledTab('Usuários', 2, cs),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: cs.background,
        body: Column(
          children: [
            const SizedBox(height: 12),
            if (_isDesktop) _desktopTopRow() else _mobileTopTabs(),
            const SizedBox(height: 12),

            /// CONTEÚDO
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Aba “Geral”
                  _dashboard(context, inlineFilter: !_isDesktop),
                  AtendimentosTab(
                    key: ValueKey(
                        'at_${_from.toIso8601String()}_${_to.toIso8601String()}'),
                    from: _from,
                    to: _to,
                  ),
                  UsersTab(from: _from, to: _to),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
