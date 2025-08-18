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
    companyId = (u['createdBy'] as String?)?.isNotEmpty == true ? u['createdBy'] as String : uid;
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
        .collection('empresas').doc(companyId)
        .collection('phones')
        .limit(1)
        .get();

    if (phonesSnap.docs.isNotEmpty) {
      phoneId = phonesSnap.docs.first.id;

      // (opcional) Persistir como default para não precisar resolver toda vez.
      // Se existir users/{uid}, grava lá; senão grava em empresas/{companyId}.
      if (userSnap.exists) {
        await fs.collection('users').doc(uid).set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
      } else {
        await fs.collection('empresas').doc(companyId).set({'defaultPhoneId': phoneId}, SetOptions(merge: true));
      }
    }
  }

  return _PhoneCtx(companyId: companyId, phoneId: phoneId);
}

class _ReportsPageState extends State<IndicatorsPage> {
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
    final cs = Theme.of(context).colorScheme;       // esquema atual do app

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate : DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('pt', 'BR'),

      /// builder permite injetar um Theme apenas no DatePicker
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            /* ---------------- CORES BÁSICAS ---------------- */
            colorScheme: ColorScheme.light(             // << sempre legível
              primary   : cs.primary,                   // fundo das datas
              onPrimary : Colors.white,                 // nº da data selecionada
              surface   : cs.secondary,                // cards, cabeçalhos
              onSurface : cs.onBackground,              // texto padrão (números,
            ),                                          //  mês, dias da semana)

            /* -------- (opcional) faixas do intervalo ------- */
            datePickerTheme: const DatePickerThemeData(
              rangeSelectionBackgroundColor: Color(0x220090EE), // cor pálida
            ),

            /* -- (opcional) tipografia/cor dos cabeçalhos -- */
            textTheme: Theme.of(context).textTheme.copyWith(
              titleMedium: TextStyle(                  // “julho 2025”
                fontWeight: FontWeight.w600,
                color: cs.onBackground,
              ),
              bodyMedium : TextStyle(color: cs.onBackground),
              bodySmall  : TextStyle(color: cs.onBackground),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
  // dentro de _ReportsPageState
  Widget _dashboard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (_, constraints) {
        const spacing = 16.0;
        final bool wide   = constraints.maxWidth > 600;
        final int columns = wide ? 4 : 2;

        return FutureBuilder<_PhoneCtx>(
          future: _resolvePhoneCtx(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final ctxv = snap.data!;
            if (ctxv.phoneId == null) {
              // Aqui realmente não há nenhum telefone cadastrado para essa empresa
              return Center(
                child: Text(
                  'Nenhum número configurado.',
                  style: TextStyle(color: cs.onBackground),
                ),
              );
            }

            // 2) Escuta os chats do telefone resolvido
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('empresas').doc(ctxv.companyId)
                  .collection('phones').doc(ctxv.phoneId)
                  .collection('whatsappChats')
                  .snapshots(),
              builder: (ctx, snap2) {
                if (!snap2.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap2.data!.docs;

                final fila      = docs.where((d) => d['status'] == 'novo').length;
                final atendendo = docs.where((d) => d['status'] == 'atendendo').length;
                final conclu30  = docs.where((d) {
                  final st = d['status'];
                  if (st != 'concluido_com_venda' && st != 'recusado') return false;
                  final ts = (d['timestamp'] as Timestamp?)?.toDate();
                  if (ts == null) return false;
                  return ts.isAfter(DateTime.now().subtract(const Duration(days: 30)));
                }).length;
                final total = docs.length;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: wide ? 1.25 : 1.15,
                        children: [
                          _metricCard(
                            title1    : 'Fila',
                            title     : 'Atendimentos',
                            value     : fila.toString(),
                            subtitle  : 'agora',
                            valueColor: Colors.red.shade600,
                            cs        : cs,
                          ),
                          _metricCard(
                            title1    : 'Em atendimento',
                            title     : 'Atendimentos',
                            value     : atendendo.toString(),
                            subtitle  : 'agora',
                            valueColor: Colors.amber.shade800,
                            cs        : cs,
                          ),
                          _metricCard(
                            title1    : 'Concluídos',
                            title     : 'Atendimentos',
                            value     : conclu30.toString(),
                            subtitle  : 'Últimos 30 dias',
                            valueColor: Colors.green.shade700,
                            cs        : cs,
                          ),
                          _metricCard(
                            title1    : 'Total',
                            title     : 'Atendimentos',
                            value     : total.toString(),
                            subtitle  : 'Pendentes + concluídos',
                            valueColor: Colors.blue.shade700,
                            cs        : cs,
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

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

                      const SizedBox(height: 10),
                      CapacityCard(
                        key : ValueKey('${_from.toIso8601String()}_${_to.toIso8601String()}'),
                        from: _from,
                        to  : _to,
                      ),
                      const SizedBox(height: 20),
                      QualityCard(
                        key : ValueKey('q_${_from.toIso8601String()}_${_to.toIso8601String()}'),
                        from: _from,
                        to  : _to,
                      ),
                    ],
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
                  _styledTab('Resultados', 1, cs),
                  _styledTab('Usuários', 2, cs),
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
                  AtendimentosTab(
                    key : ValueKey('at_${_from.toIso8601String()}_${_to.toIso8601String()}'),
                    from: _from,
                    to  : _to,
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