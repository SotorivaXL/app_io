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
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // 1) pega o companyId do usuário logado
    final usnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final udata = usnap.data() as Map<String,dynamic>? ?? {};
    final String companyId = (udata['createdBy'] as String?)?.isNotEmpty == true
        ? udata['createdBy']
        : uid;

// ───────── 2) TODOS os usuários da empresa ─────────────────────────
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .where('createdBy', isEqualTo: companyId)   // ← campo certo!
        .get();

    setState(() {
      _users = qs.docs.map((d) => (
      d.id,
      (d.data()['displayName'] ?? d.data()['name'] ?? 'Sem nome') as String
      )).toList()
        ..sort((a,b) => a.$2.compareTo(b.$2));

      // Seleciona o primeiro por padrão
      _selectedUid ??= _users.isNotEmpty ? _users.first.$1 : null;
    });
  }

  /* helper de formato para o rodapé */
  String _period() => '${_fmt.format(_from)} — ${_fmt.format(_to)}';

/* ---------- NOVO CARD ---------- */
  Widget _niceCard({
    required String title,
    required String value,
    required Color  accent,
    String? footer,        // continua opcional
    bool    showUnit = true,  // <<< NOVO — mostra “Atendimentos” por padrão
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.secondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0,4),
            color: cs.shadow.withOpacity(.05),
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(fontSize: 15,fontWeight: FontWeight.w700,
                  color: cs.onBackground.withOpacity(.85))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(fontSize: 28,fontWeight: FontWeight.w800,color: accent)),

          // ---------- subtítulo opcional ----------
          if (showUnit) ...[
            const SizedBox(height: 2),
            Text('Atendimentos',
                style: TextStyle(fontSize: 13,fontWeight: FontWeight.w700,color: accent)),
          ],

          if (footer != null) ...[
            const SizedBox(height: 10),
            Text(footer,
                style: TextStyle(fontSize: 11,color: cs.onBackground.withOpacity(.55))),
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

  /* ─────────── consulta de métricas ────────── */
  /* ─────────── consulta de métricas ────────── */
  Stream<Map<String, dynamic>> _statsStream() async* {
    if (_selectedUid == null) return;

    /* ids fixos do usuário logado */
    final (companyId, phoneId) = await _getIds();

    /* ---------- stream dos CHATS ----------- */
    final chats$ = FirebaseFirestore.instance
        .collection('empresas').doc(companyId)
        .collection('phones').doc(phoneId)
        .collection('whatsappChats')
        .where('updatedBy', isEqualTo: _selectedUid)
        .where('updatedAt', isGreaterThanOrEqualTo: _day(_from))
        .where('updatedAt', isLessThan: _dayAfter(_to))
        .snapshots();

    /* ---------- stream da HISTORY ----------- */
    final hist$ = FirebaseFirestore.instance
        .collectionGroup('history')
        .where('updatedBy', isEqualTo: _selectedUid)
        .where('changedAt', isGreaterThanOrEqualTo: _day(_from))
        .where('changedAt', isLessThan: _dayAfter(_to))
        .snapshots();

    /* ---------- junta as duas ---------- */
    await for (final pair in StreamZip([chats$, hist$])) {
      final QuerySnapshot chats = pair[0] as QuerySnapshot;
      final QuerySnapshot hist  = pair[1] as QuerySnapshot;

      // ----------------- HISTÓRICO filtrado -----------------
      final wantedStatuses = {'concluido_com_venda', 'recusado'};
      final Set<String> histChatsWon  = {};
      final Set<String> histChatsLost = {};

      for (final doc in hist.docs) {
        final data   = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (!wantedStatuses.contains(status)) continue;

        final parentChatId = doc.reference.parent.parent!.id;

        if (status == 'concluido_com_venda') {
          histChatsWon.add(parentChatId);
        } else {
          histChatsLost.add(parentChatId);
        }
      }

      /* ---------- contagens & métricas ---------- */
      final Set<String> wonIds  = {};
      final Set<String> lostIds = {};
      final Set<String> allIds  = {};
      double sumSale = 0.0;

      /* 1) chats vivos --------------------------------------------------*/
      for (final d in chats.docs) {
        final data   = d.data() as Map<String, dynamic>;
        final cid    = d.id;
        final status = data['status'] as String? ?? '';

        allIds.add(cid);

        if (status == 'concluido_com_venda') {
          if (wonIds.add(cid)) sumSale += (data['saleValue'] ?? 0).toDouble();
        } else if (status == 'recusado') {
          lostIds.add(cid);
        }
      }

      /* 2) histórico (para evitar duplicação) ---------------------------*/
      for (final doc in hist.docs) {
        final data   = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status != 'concluido_com_venda' && status != 'recusado') continue;

        final cid = doc.reference.parent.parent!.id;
        allIds.add(cid);

        if (status == 'concluido_com_venda') {
          if (wonIds.add(cid)) sumSale += (data['saleValue'] ?? 0).toDouble();
        } else {
          lostIds.add(cid);
        }
      }

      /* 3) tempos médios (campos podem não existir) -------------------- */
      int sumWaitSec   = 0;
      int sumAttendSec = 0;

      for (final d in chats.docs) {
        final data = d.data() as Map<String, dynamic>;
        sumWaitSec   += (data['waitTimeSec']      ?? 0) as int;
        sumAttendSec += (data['attendingTimeSec'] ?? 0) as int; // ← seguro
      }

      final qtyChats     = chats.docs.isEmpty ? 1 : chats.docs.length;
      final avgWaitSec   = sumWaitSec   ~/ qtyChats;
      final avgAttendSec = sumAttendSec ~/ qtyChats;
      final avgTotalSec  = avgWaitSec + avgAttendSec;

      /* 4) emite resultado ---------------------------------------------*/
      yield {
        'atend'       : allIds.length,
        'won'         : wonIds.length,
        'lost'        : lostIds.length,
        'avgWaitSec'  : avgWaitSec,
        'avgAttendSec': avgAttendSec,
        'avgTotalSec' : avgTotalSec,
        'sumSale'     : sumSale,
      };
    }
  }

  Future<(String companyId, String phoneId)> _getIds() async {
    final uid   = FirebaseAuth.instance.currentUser!.uid;
    final usnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data  = usnap.data() as Map<String,dynamic>? ?? {};

    final companyId = (data['createdBy'] as String?)?.isNotEmpty == true
        ? data['createdBy'] as String
        : uid;

    final phoneId   = data['defaultPhoneId'] as String;
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
            child:
            StreamBuilder<Map<String, dynamic>>(
              stream: _statsStream(),
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
                final tot = m['atend'] == 0 ? 1 : m['atend'];
                final int decided = (m['won'] as int) + (m['lost'] as int);
                final double pct = decided == 0 ? 0 : (m['won'] / decided) * 100;

                Widget _card(String title,String value,Color color)=>Container(
                  decoration: BoxDecoration(
                    color: cs.secondary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      blurRadius: 10,
                      offset: const Offset(0,4),
                      color: cs.shadow.withOpacity(.05),
                    )],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children:[
                      Text(title,style: TextStyle(
                        fontSize: 15,fontWeight: FontWeight.w700,
                        color: cs.onBackground.withOpacity(.8),
                      )),
                      const SizedBox(height: 8),
                      Text(value,style: TextStyle(
                        fontSize: 28,fontWeight: FontWeight.w800,color: color,
                      )),
                    ],
                  ),
                );

                final grid = GridView.count(
                  crossAxisCount  : MediaQuery.of(context).size.width > 700 ? 3 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing : 12,
                  childAspectRatio: 1.3,
                  children: [
                    _niceCard(                                    // mantém “Atendimentos”
                      title : 'Atendimentos',
                      value : m['atend'].toString(),
                      accent: Colors.blue.shade700,
                    ),
                    _niceCard(                                    // mantém
                      title  : 'Objetivos atingidos',
                      value  : m['won'].toString(),
                      accent : Colors.green,
                      footer: _brl.format((m['sumSale'] ?? 0) as num),
                    ),
                    _niceCard(                                    // mantém
                      title : 'Objetivos perdidos',
                      value : m['lost'].toString(),
                      accent: Colors.red,
                    ),

                    _niceCard(
                      title     : 'Primeira resposta',
                      value    : _prettyDuration(m['avgWaitSec'] as int),
                      accent    : Colors.amber.shade800,
                      showUnit  : false,
                    ),
                    _niceCard(
                      title    : 'Tempo atendimento',
                      value    : _prettyDuration(((m['avgAttendSec'] ?? 0) as num).toInt()),
                      accent   : cs.tertiary,
                      showUnit : false,
                    ),
                    _percentCard(pct),
                  ],
                );

                return Padding(
                  padding: const EdgeInsets.only(top:8),
                  child: grid,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}