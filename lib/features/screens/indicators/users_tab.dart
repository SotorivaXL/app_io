import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({
    super.key,
    required this.from,
    required this.to,
  });

  final DateTime from;
  final DateTime to;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  /* ─────────── status local ────────────────── */
  late DateTime _from, _to;
  String? _selectedUid;                      // vendedor escolhido
  List<(String uid, String name)> _users = []; // lista p/ o select

  /* ─────────── utilidades ──────────────────── */
  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _dayAfter(DateTime d) => _day(d).add(const Duration(days: 1));
  final _fmt = DateFormat('d/M');
  final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to   = widget.to;
    _loadUsers();           // preenche o select
  }

  /// Converte segundos em s, min, h ou "X dias e Y h"
  String _prettyDuration(num secN) {
    final sec = secN.floor();

    if (sec < 60)    return '$sec s';
    if (sec < 3600)  return '${(sec / 60).round()} min';
    if (sec < 86400) return '${(sec / 3600).toStringAsFixed(1)} h';

    final days  = sec ~/ 86400;
    final rem   = sec % 86400;
    final hours = rem ~/ 3600;

    // Dias SEM decimal:
    return hours == 0 ? '$days dias' : '$days dias e $hours h';
  }

  (Color, double) _percentStyle(double pct) {
    if (pct < 50)   return (Colors.red.shade600   , pct/100);
    if (pct < 75)   return (Colors.orange.shade700, pct/100);
    /* 75 – 100 */  return (Colors.green.shade600 , pct/100);
  }

  Future<void> _loadUsers() async {
    final fs  = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // 1) companyId do usuário logado
    final uSnap = await fs.collection('users').doc(uid).get();
    final udata = uSnap.data() as Map<String, dynamic>? ?? {};
    final String companyId = (udata['createdBy'] as String?)?.isNotEmpty == true
        ? udata['createdBy'] as String
        : uid;

    // 2) colaboradores da empresa
    final qs = await fs
        .collection('users')
        .where('createdBy', isEqualTo: companyId)
        .get();

    final List<(String uid, String name)> list = qs.docs.map((d) {
      final m = d.data() as Map<String, dynamic>;
      final name = (m['displayName'] ?? m['name'] ?? m['email'] ?? 'Sem nome') as String;
      return (d.id, name);
    }).toList();

    // 3) nome da EMPRESA — prioriza "NomeEmpresa"
    String companyLabel = 'Empresa';
    final eSnap = await fs.collection('empresas').doc(companyId).get();
    if (eSnap.exists) {
      final e = eSnap.data() as Map<String, dynamic>? ?? {};
      companyLabel = (e['NomeEmpresa'] ??
          e['nomeFantasia'] ??
          e['razaoSocial'] ??
          e['name'] ??
          e['displayName'] ??
          'Empresa') as String;
    } else {
      // fallback: tenta users/{companyId}
      final ownerSnap = await fs.collection('users').doc(companyId).get();
      if (ownerSnap.exists) {
        final o = ownerSnap.data() as Map<String, dynamic>? ?? {};
        companyLabel = (o['NomeEmpresa'] ??
            o['displayName'] ??
            o['name'] ??
            o['email'] ??
            'Empresa') as String;
      }
    }

    // 4) garante a empresa no topo (sem duplicar)
    final idx = list.indexWhere((u) => u.$1 == companyId);
    if (idx >= 0) {
      list[idx] = (companyId, companyLabel); // substitui o label pelo NomeEmpresa
    } else {
      list.insert(0, (companyId, companyLabel));
    }

    // ordena os demais por nome, mantendo empresa no topo
    final rest = list.where((e) => e.$1 != companyId).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final finalList = <(String, String)>[(companyId, companyLabel), ...rest];

    setState(() {
      _users = finalList;
      _selectedUid ??= companyId; // seleciona empresa por padrão
    });
  }

  /* helper de formato para o rodapé */
  String _period() => '${_fmt.format(_from)} — ${_fmt.format(_to)}';

/* ---------- NOVO CARD ---------- */
  Widget _niceCard({
    required String title,
    required String value,
    required Color  accent,
    String? footer,
    bool    showUnit = true,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.secondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(blurRadius: 10, offset: const Offset(0,4), color: cs.shadow.withOpacity(.05)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // ↓ um pouco menos
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onBackground.withOpacity(.85)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown, // ↓ encolhe o número se faltar altura
            child: Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: accent)),
          ),
          if (showUnit) ...[
            const SizedBox(height: 2),
            Text('Atendimentos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
          ],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onBackground.withOpacity(.55)),
            ),
          ],
        ],
      ),
    );
  }

  /// Card “% do total”  ─ barra + texto lado-a-lado
  /// Card “% do total” – barra e número alinhados
  Widget _percentCard(double pct, {String title = 'Taxa de conversão'}) {
    final cs = Theme.of(context).colorScheme;

    Color barColor;
    if (pct < 50) {
      barColor = Colors.red.shade600;
    } else if (pct < 75) {
      barColor = Colors.orange.shade700;
    } else {
      barColor = Colors.green.shade600;
    }

    const double _fontSz = 30;
    final txtStyle = TextStyle(
      fontSize: _fontSz,
      fontWeight: FontWeight.w800,
      color: barColor,
    );

    return Container(
      decoration: BoxDecoration(
        color: cs.secondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(blurRadius: 10, offset: Offset(0,4), color: cs.shadow.withOpacity(.05))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 10,
                height: _fontSz,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: cs.onSecondary.withOpacity(.20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      heightFactor: (pct.clamp(0, 100)) / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${pct.toStringAsFixed(1)} %', style: txtStyle), // 1 casa fica mais “pro”
            ],
          ),
        ],
      ),
    );
  }

  /* ─────────── seletor de período ──────────── */
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

  Stream<Map<String, dynamic>> _statsStream(String companyId, String phoneId) async* {
    if (_selectedUid == null) {
      // evita spinner infinito; emite zeros enquanto nada selecionado
      yield {
        'atend': 0, 'won': 0, 'lost': 0,
        'avgWaitSec': 0, 'avgAttendSec': 0, 'avgTotalSec': 0,
        'sumSale': 0.0,
      };
      return;
    }

    final endExclusive = _dayAfter(_to);

    // CHATS do telefone selecionado para o vendedor escolhido
    final chats$ = FirebaseFirestore.instance
        .collection('empresas').doc(companyId)
        .collection('phones').doc(phoneId)
        .collection('whatsappChats')
        .where('updatedBy', isEqualTo: _selectedUid)
        .where('updatedAt', isGreaterThanOrEqualTo: _day(_from))
        .where('updatedAt', isLessThan: endExclusive)
        .snapshots();

    // HISTORY (global) do vendedor no período — se puder, também filtre por empresaId/phoneId
    final hist$ = FirebaseFirestore.instance
        .collectionGroup('history')
        .where('updatedBy', isEqualTo: _selectedUid)
        .where('changedAt', isGreaterThanOrEqualTo: _day(_from))
        .where('changedAt', isLessThan: endExclusive)
        .snapshots();

    await for (final pair in StreamZip([chats$, hist$])) {
      final QuerySnapshot chats = pair[0] as QuerySnapshot;
      final QuerySnapshot hist  = pair[1] as QuerySnapshot;

      final Set<String> wonIds  = {};
      final Set<String> lostIds = {};
      final Set<String> allIds  = {};
      double sumSale = 0.0;

      // 1) chats
      for (final d in chats.docs) {
        final m   = d.data() as Map<String, dynamic>;
        final cid = d.id;
        final st  = m['status'] as String? ?? '';
        allIds.add(cid);
        if (st == 'concluido_com_venda') {
          if (wonIds.add(cid)) {
            final v = m['saleValue'];
            sumSale += (v is num) ? v.toDouble() : 0.0;
          }
        } else if (st == 'recusado') {
          lostIds.add(cid);
        }
      }

      // 2) history (evita duplicar chats)
      for (final h in hist.docs) {
        final m  = h.data() as Map<String, dynamic>;
        final st = m['status'] as String? ?? '';
        if (st != 'concluido_com_venda' && st != 'recusado') continue;

        final cid = h.reference.parent.parent!.id;
        allIds.add(cid);

        if (st == 'concluido_com_venda') {
          if (wonIds.add(cid)) {
            final v = m['saleValue'];
            sumSale += (v is num) ? v.toDouble() : 0.0;
          }
        } else {
          lostIds.add(cid);
        }
      }

      // 3) tempos médios (campos podem não existir)
      int sumWait   = 0;
      int sumAttend = 0;
      for (final d in chats.docs) {
        final m = d.data() as Map<String, dynamic>;
        sumWait   += (m['waitTimeSec']      ?? 0) as int;
        sumAttend += (m['attendingTimeSec'] ?? 0) as int;
      }
      final n = chats.docs.isEmpty ? 1 : chats.docs.length;
      final avgWait   = sumWait ~/ n;
      final avgAttend = sumAttend ~/ n;

      yield {
        'atend'       : allIds.length,
        'won'         : wonIds.length,
        'lost'        : lostIds.length,
        'avgWaitSec'  : avgWait,
        'avgAttendSec': avgAttend,
        'avgTotalSec' : avgWait + avgAttend,
        'sumSale'     : sumSale,
      };
    }
  }

  /// Resolve companyId/phoneId tanto para user quanto para empresa.
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
      companyId = (u['createdBy'] as String?)?.isNotEmpty == true
          ? u['createdBy'] as String
          : uid;
      phoneId = u['defaultPhoneId'] as String?;
    }

    // 2) tenta empresas/{companyId}.defaultPhoneId
    if (phoneId == null) {
      final eSnap = await fs.collection('empresas').doc(companyId).get();
      if (eSnap.exists) {
        phoneId = eSnap.data()?['defaultPhoneId'] as String?;
      }
    }

    // 3) se ainda null, pega o primeiro doc de phones/ e persiste como default
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

  /* ─────────── build ───────────────────────── */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left:16, right: 16),
      child: Column(
        children: [
          // ----- SELECT de usuários -----------------------------------
          DropdownButton2<String>(
            // ↓↓↓  MESMAS PROPS QUE VOCÊ JÁ TINHA  ↓↓↓
            isExpanded: true,
            value     : _selectedUid,
            items     : _users
                .map((u) => DropdownMenuItem(value: u.$1, child: Text(u.$2)))
                .toList(),
            onChanged : (v) => setState(() => _selectedUid = v),

            /// ---------------- estilo do BOTÃO ----------------
            buttonStyleData: ButtonStyleData(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            /// ---------------- estilo do MENU ----------------
            dropdownStyleData: DropdownStyleData(
              offset    : const Offset(0, 4),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    color: cs.shadow.withOpacity(.05),
                  )
                ],
              ),
            ),

            /// (facultativo) remover sublinhado e splash roxos
            underline: const SizedBox.shrink(),
            iconStyleData: const IconStyleData(
              iconEnabledColor: Colors.grey,                 // cor do caret
            ),
          ),

          const SizedBox(height: 16),

          // ----- seletor de data --------------------------------------
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
                  Text('${_fmt.format(_from)}  –  ${_fmt.format(_to)}',
                      style: TextStyle(
                        color: cs.onBackground.withOpacity(.8),
                        fontWeight: FontWeight.w500,
                      )),
                  Icon(Icons.calendar_month, color: cs.primary),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ----- métricas em tempo-real --------------------------------
          Expanded(
            child: FutureBuilder<(String, String?)>(
              future: _resolvePhoneCtx(),
              builder: (_, idSnap) {
                if (idSnap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao resolver contexto do telefone:\n${idSnap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!idSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final (companyId, phoneId) = idSnap.data!;
                if (phoneId == null) {
                  return Center(
                    child: Text(
                      'Nenhum número configurado.',
                      style: TextStyle(color: cs.onBackground),
                    ),
                  );
                }

                if (_users.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum usuário encontrado para esta empresa.',
                      style: TextStyle(color: cs.onBackground.withOpacity(.75)),
                    ),
                  );
                }

                if (_selectedUid == null) {
                  return Center(
                    child: Text(
                      'Selecione um usuário para ver os indicadores.',
                      style: TextStyle(color: cs.onBackground.withOpacity(.75)),
                    ),
                  );
                }

                return StreamBuilder<Map<String, dynamic>>(
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

                    final m = snap.data!;
                    final int atend = (m['atend'] as int?) ?? 0;
                    final int won   = (m['won'] as int?) ?? 0;
                    final int lost  = (m['lost'] as int?) ?? 0;
                    final decided   = won + lost;
                    final double pct = decided == 0 ? 0.0 : (won / decided) * 100.0;

                    Widget _card(String title, String value, Color color) => Container(
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
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cs.onBackground.withOpacity(.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );

                    return LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final cols = w >= 700 ? 3 : 2;
                        const spacing = 12.0;

                        // largura efetiva do tile considerando os espaçamentos
                        final tileWidth = (w - (cols - 1) * spacing) / cols;

                        // altura alvo (um pouco maior no mobile)
                        final tileHeight = w >= 700 ? 160.0 : 150.0;

                        final ratio = tileWidth / tileHeight;

                        final grid = GridView.count(
                          crossAxisCount: cols,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: ratio,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _niceCard(
                              title: 'Atendimentos',
                              value: atend.toString(),
                              accent: Colors.blue.shade700,
                            ),
                            _niceCard(
                              title: 'Objetivos atingidos',
                              value: won.toString(),
                              accent: Colors.green,
                              footer: _brl.format((m['sumSale'] ?? 0) as num),
                            ),
                            _niceCard(
                              title: 'Objetivos perdidos',
                              value: lost.toString(),
                              accent: Colors.red,
                            ),
                            _niceCard(
                              title: 'Primeira resposta',
                              value: _prettyDuration(((m['avgWaitSec'] ?? 0) as num).toInt()),
                              accent: Colors.amber.shade800,
                              showUnit: false,
                            ),
                            _niceCard(
                              title: 'Tempo atendimento',
                              value: _prettyDuration(((m['avgAttendSec'] ?? 0) as num).toInt()),
                              accent: cs.tertiary,
                              showUnit: false,
                            ),
                            _percentCard(pct),
                          ],
                        );

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: grid,
                        );
                      },
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}