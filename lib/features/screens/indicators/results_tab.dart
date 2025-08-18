import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AtendimentosTab extends StatefulWidget {
  const AtendimentosTab({
    super.key,
    required this.from,
    required this.to,
  });

  final DateTime from;
  final DateTime to;

  @override
  State<AtendimentosTab> createState() => _AtendimentosTabState();
}

class _AtendimentosTabState extends State<AtendimentosTab> {
  /* ───────────────────────── estado local ─────────────────────────── */
  late DateTime _from, _to;                       // período exibido
  final _fmt = DateFormat('d/M');                 // p/ cabeçalho do filtro
  final _currency = NumberFormat.currency(symbol: 'R\$'); // total vendas

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to   = widget.to;
  }

  /* ───────────────────────── utilidades ───────────────────────────── */
  /// Resolve companyId/phoneId para user OU empresa.
  /// Retorna (companyId, phoneId) onde phoneId pode ser null.
  Future<(String companyId, String? phoneId)> _resolvePhoneCtx() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final fs  = FirebaseFirestore.instance;

    String companyId = uid;
    String? phoneId;

    // 1) tenta users/{uid}
    final uSnap = await fs.collection('users').doc(uid).get();
    if (uSnap.exists) {
      final u = uSnap.data() ?? {};
      companyId =
      (u['createdBy'] as String?)?.isNotEmpty == true ? u['createdBy'] as String : uid;
      phoneId = u['defaultPhoneId'] as String?;
    }

    // 2) tenta empresas/{companyId}.defaultPhoneId
    if (phoneId == null) {
      final eSnap = await fs.collection('empresas').doc(companyId).get();
      if (eSnap.exists) {
        phoneId = eSnap.data()?['defaultPhoneId'] as String?;
      }
    }

    // 3) pega o primeiro doc em empresas/{companyId}/phones e persiste como default
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

  /* ─────────────────── date-range picker ──────────────────────────── */
  Future<void> _pickRange() async {
    final cs = Theme.of(context).colorScheme;

    final range = await showDateRangePicker(
      context        : context,
      firstDate      : DateTime(2020),
      lastDate       : DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale         : const Locale('pt', 'BR'),
      builder        : (_, child) => Theme(
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
      ),
    );

    if (range != null) {
      setState(() {
        _from = range.start;
        _to   = range.end;
      });
    }
  }

  /* ───────────── stream de estatísticas (tempo real) ─────────────── */
  /* ───────── mesma lógica do QualityCard, mas lendo `history` ───────── */
  Stream<_RankStats> _statsStream(String companyId, String phoneId) async* {
    final endExclusive = DateTime(_to.year, _to.month, _to.day + 1);

    // ATENÇÃO: esta query só funciona se cada doc em `history`
    // tiver os campos `empresaId` e `phoneId`.
    final history$ = FirebaseFirestore.instance
        .collectionGroup('history')
        .where('empresaId', isEqualTo: companyId)
        .where('phoneId',   isEqualTo: phoneId)
        .where('changedAt', isGreaterThanOrEqualTo: _from)
        .where('changedAt', isLessThan: endExclusive)
        .where('status', whereIn: ['concluido_com_venda', 'recusado'])
        .snapshots();

    await for (final qs in history$) {
      final Map<String, int> productCount = {};
      final Map<String, int> reasonCount  = {};
      var totalWon  = 0;
      var totalLost = 0;
      var sumSale   = 0.0;

      for (final d in qs.docs) {
        final data   = d.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';

        if (status == 'concluido_com_venda') {
          totalWon++;
          final prod = (data['productName'] ?? '—') as String;
          productCount.update(prod, (v) => v + 1, ifAbsent: () => 1);
          final dynamic v = data['saleValue'];
          sumSale += (v is num) ? v.toDouble() : 0.0;
        } else if (status == 'recusado') {
          totalLost++;
          final reason = (data['noSaleReason'] ?? '—') as String;
          reasonCount.update(reason, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      yield _RankStats(
        productCount : productCount,
        reasonCount  : reasonCount,
        wonTotal     : totalWon,
        lostTotal    : totalLost,
        sumSale      : sumSale,
      );
    }
  }

  /* ──────────────────── construção de um ranking ─────────────────── */
  Widget _rankingCard({
    required String titleText,
    required int    total,
    required Map<String, int> items,
    double? somatorio,
    Color? barColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bool isWonCard = titleText.toLowerCase().contains('atingid');
    final Color totalColor = isWonCard ? Colors.green.shade700 : Colors.red.shade700;
    final Color itemColor = barColor ?? (isWonCard ? Colors.green.shade700 : Colors.red.shade700);

    // ➊ decide a mensagem padrão com base no título
    String _emptyMsg() {
      if (titleText.toLowerCase().contains('atingido')) {
        return 'Você não possui objetivos atingidos no período selecionado';
      }
      return 'Você não possui objetivos perdidos no período selecionado';
    }

    final entries = items.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: Container(
        decoration: BoxDecoration(
          color: cs.secondary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 4),
              color: cs.shadow.withOpacity(.05),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,   // ← garante centralização
          children: [
            /* cabeçalho */
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 6),
                Text(titleText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onBackground.withOpacity(.9),
                    )),
              ],
            ),
            const SizedBox(height: 10),

            /* ---------- se não há dados, mostra texto central ---------- */
            if (total == 0) ...[
              Text(
                _emptyMsg(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onBackground.withOpacity(.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else ...[
              Text(
                total.toString(),
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: totalColor,
                ),
              ),
              if (somatorio != null) ...[
                const SizedBox(height: 4),
                Text(
                  _currency.format(somatorio),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onBackground.withOpacity(.75),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              /* lista de barras */
              for (int i = 0; i < entries.length; i++) ...[
                _progressRow(
                  label: entries[i].key,
                  count: entries[i].value,
                  total: total,
                  color: itemColor,
                ),
                if (i != entries.length - 1) const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /* linha - barra de progresso + legenda + quantidade */
  Widget _progressRow({
    required String label,
    required int    count,
    required int    total,
    required Color  color,
  }) {
    final pct = count / total;
    final cs  = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /* 1) barra + % + quantidade */
        Row(
          children: [
            /* bolacha com % */
            Container(
              width: 38,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),

            /* barra */
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: cs.onSecondary.withOpacity(.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: pct,                  // 0–1
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            /* quantidade absoluta */
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onBackground.withOpacity(.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        /* 2) legenda (nome do produto ou motivo) */
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: cs.onBackground.withOpacity(.8),
          ),
        ),
      ],
    );
  }

  /* ────────────────────────── build ──────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          /* seletor de período ------------------------------------------------ */
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

          const SizedBox(height: 20),

          /* stream de dados --------------------------------------------------- */
          Expanded(
            child: FutureBuilder<(String, String?)>(
              future: _resolvePhoneCtx(),
              builder: (_, idSnap) {
                if (!idSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (companyId, phoneId) = idSnap.data!;
                if (phoneId == null) {
                  return Center(
                    child: Text('Nenhum número configurado.', style: TextStyle(color: cs.onBackground)),
                  );
                }

                return StreamBuilder<_RankStats>(
                  stream: _statsStream(companyId, phoneId),
                  builder: (_, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Erro Firestore:\n${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final stats = snap.data!;
                    // ... mantém o restante da UI exatamente como está ...
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _rankingCard(
                            titleText : 'Objetivos atingidos',
                            total     : stats.wonTotal,
                            items     : stats.productCount,
                            somatorio : stats.sumSale,
                          ),
                          const SizedBox(height: 20),
                          _rankingCard(
                            titleText : 'Objetivos perdidos',
                            total     : stats.lostTotal,
                            items     : stats.reasonCount,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ────────────────────────── modelo de dados ─────────────────────── */
class _RankStats {
  _RankStats({
    required this.productCount,
    required this.reasonCount,
    required this.wonTotal,
    required this.lostTotal,
    required this.sumSale,
  });

  final Map<String, int> productCount;
  final Map<String, int> reasonCount;
  final int    wonTotal;
  final int    lostTotal;
  final double sumSale;
}