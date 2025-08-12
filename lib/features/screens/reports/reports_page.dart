import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as prt;

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class ActiveFilter {
  final String type;
  final String field;
  final dynamic value;
  final String label;
  final Color? color;

  ActiveFilter(this.type, this.field, this.value, this.label, [this.color]);
}

// lista de filtros em uso
final List<ActiveFilter> _activeFilters = [];

class _ReportsPageState extends State<ReportsPage> {
/*────────────────────────  filtros / estado  ───────────────────────*/

  String _search = '';
  String? _mainFilter;
  String? _statusFilter;
  List<Map<String, String>> _attendants = [];
  String? _attendantFilter;
  ActiveFilter? _editingFilter;

  final _statusOpts = [
    'novo',
    'atendendo',
    'concluido_com_venda',
    'recusado',
  ];

  final _fmt = DateFormat('dd/MM/yy ‑ HH:mm');
  final _urlRx = RegExp(r'https://[^\s]+');
  final GlobalKey _chipKey = GlobalKey();

  late String _companyId;
  late String _phoneId;
  bool _ready = false;

/*────────────────────────  init  ───────────────────────────────────*/
  @override
  void initState() {
    super.initState();
    _initIds();
  }

  /*────────────────────  EXPORTAR EM PDF  ────────────────────*/
  Future<void> _exportLeadsPdf() async {
    /* ── 0. Nome da empresa ─────────────────────────────────────────── */
    final companySnap = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .get();
    final companyName =
        (companySnap.data()?['NomeEmpresa'] as String?) ?? 'Empresa sem nome';

    /* ── 1. Mesma query da tela (off‑line) ──────────────────────────── */
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats');

    if (_search.isNotEmpty) {
      q = q.where('keywords', arrayContains: _search.toLowerCase());
    }
    for (final f in _activeFilters) {
      if (f.field == 'tags') {
        q = q.where('tags', arrayContains: f.value);
      } else if (f.field == 'arrivalAt') {
        final r = f.value as DateTimeRange;
        q = q
            .where('arrivalAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(r.start))
            .where('arrivalAt',
                isLessThan:
                    Timestamp.fromDate(r.end.add(const Duration(days: 1))));
      } else {
        q = q.where(f.field, isEqualTo: f.value);
      }
    }

    final snap = await q.get();
    if (snap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum lead para exportar.')),
        );
      }
      return;
    }

    /* ── 2. Timbrado (opcional) ─────────────────────────────────────── */
    pw.MemoryImage? letterhead;
    try {
      final bytes = await rootBundle.load('assets/images/reports/timbrado.png');
      letterhead = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      letterhead = null;
    }

    /* ── 3. Helpers gerais ──────────────────────────────────────────── */
    final tagName = {for (final t in _tags) t['id']!: t['name']!};
    final attendantName = {for (final a in _attendants) a['id']!: a['name']!};

    String formatPhone(String raw) {
      final d = raw.replaceAll(RegExp(r'\D'), '');
      if (d.startsWith('55') && d.length >= 10) {
        final ddd = d.substring(2, 4);
        final local = d.substring(4);
        return '+55 $ddd ${local.substring(0, local.length - 4)}-${local.substring(local.length - 4)}';
      } else if (d.length > 10) {
        final cc = d.substring(0, d.length - 10);
        final ddd = d.substring(d.length - 10, d.length - 8);
        final local = d.substring(d.length - 8);
        return '+$cc $ddd ${local.substring(0, local.length - 4)}-${local.substring(local.length - 4)}';
      }
      return raw;
    }

    String formatWait(int sec) {
      if (sec >= 3600) {
        final h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
        return m > 0 ? '${h}h ${m}m' : '${h}h';
      } else if (sec >= 60) {
        final m = sec ~/ 60, s = sec % 60;
        return s > 0 ? '${m}m ${s}s' : '${m}m';
      }
      return '${sec}s';
    }

    /* ── 4. Texto de filtros para cabeçalho ─────────────────────────── */
    String filtersText() {
      if (_activeFilters.isEmpty && _search.isEmpty) {
        return 'Sem filtros selecionados';
      }

      final parts = <String>[];
      for (final f in _activeFilters) {
        switch (f.field) {
          case 'arrivalAt':
            final r = f.value as DateTimeRange;
            parts.add(
                'Período: ${DateFormat('dd/MM/yyyy').format(r.start)} à ${DateFormat('dd/MM/yyyy').format(r.end)}');
            break;
          case 'status':
            parts.add('Status: ${f.value}');
            break;
          case 'updatedBy':
            parts.add('Atendente: ${f.label}');
            break;
          case 'tags':
            parts.add('Etiqueta: ${f.label}');
            break;
        }
      }
      if (_search.isNotEmpty) parts.add('Busca: "$_search"');
      return parts.join(' • ');
    }

    /* ── 5. Cálculos para os 4 cards resumidos ──────────────────────── */
    int fila = 0;
    int atendendo = 0;
    int concluidos = 0;
    DateTime? minArrive;

    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString();
      final arrivalTs = data['arrivalAt'] as Timestamp?;
      final arrive = arrivalTs?.toDate();
      if (arrive != null && (minArrive == null || arrive.isBefore(minArrive))) {
        minArrive = arrive;
      }

      switch (status) {
        case 'novo':
          fila++;
          break;
        case 'atendendo':
          atendendo++;
          break;
        case 'concluido_com_venda':
        case 'concluido':
        case 'recusado':
          concluidos++;
          break;
      }
    }
    final total = snap.docs.length;

    /* Período para cards (filtro arrivalAt ou data do mais antigo → hoje) */
    String rangeLabel;
    final arrivalFilter = _activeFilters.firstWhere(
        (f) => f.field == 'arrivalAt',
        orElse: () => ActiveFilter('', '', null, ''));
    if (arrivalFilter.field == 'arrivalAt') {
      final r = arrivalFilter.value as DateTimeRange;
      rangeLabel =
          '${DateFormat('dd/MM').format(r.start)} à ${DateFormat('dd/MM').format(r.end)}';
    } else {
      final start = (minArrive ?? DateTime.now()).toLocal(); // se nulo usa hoje
      final end = DateTime.now();
      rangeLabel =
          '${DateFormat('dd/MM').format(start)} à ${DateFormat('dd/MM').format(end)}';
    }

    /* ── 6. Gera o PDF ──────────────────────────────────────────────── */
    final pdfDoc = pw.Document();

    /*  ──  cores & estilos  ── */
    const _purple = pdf.PdfColor.fromInt(0xFF6B00E3);
    const _headerText = pdf.PdfColor.fromInt(0xFFFFFFFF);
    const _cellBorder = pdf.PdfColor.fromInt(0xFFCCCCCC);
    const _bodyText = pdf.PdfColor.fromInt(0xFF000000);
    const _red = pdf.PdfColor.fromInt(0xFFE53935);
    const _orange = pdf.PdfColor.fromInt(0xFFFFA726);
    const _green = pdf.PdfColor.fromInt(0xFF43A047);
    const _blue = pdf.PdfColor.fromInt(0xFF1E88E5);

    const headers = [
      'Nome',
      'Telefone',
      'Status',
      'Etiquetas',
      'Atendente',
      'Tempo p/ 1º resposta'
    ];

    /*  ---- monta as páginas (queimando até 20 linhas por página) ---- */
    const rowsPerPage = 20;
    for (var i = 0; i < snap.docs.length; i += rowsPerPage) {
      final chunk = snap.docs.skip(i).take(rowsPerPage);

      /* ---- converte docs em linhas da tabela ---- */
      final rows = chunk.map((d) {
        final m = d.data();
        var phone = (m['chatId'] as String?) ?? '';
        if (phone.contains('@')) phone = phone.split('@')[0];

        final tagIds =
            (m['tags'] as List<dynamic>? ?? []).map((e) => e.toString());
        final tags = tagIds.isEmpty
            ? 'Sem etiquetas'
            : tagIds.map((id) => tagName[id] ?? id).join(', ');

        final updId = m['updatedBy'] as String?;
        final attendant = attendantName[updId] ?? (m['updatedByName'] ?? '');

        return <String>[
          (m['name'] ?? m['contactName'] ?? '').toString(),
          formatPhone(phone),
          (m['status'] ?? '').toString(),
          tags,
          attendant.toString(),
          formatWait(m['waitTimeSec'] as int? ?? 0),
        ];
      }).toList();

      pdfDoc.addPage(
        pw.Page(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              if (letterhead != null)
                pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(letterhead!, fit: pw.BoxFit.cover),
                ),

              /* ── Cabeçalho (título + filtros) ── */
              pw.Positioned(
                left: 40,
                right: 40,
                top: 120,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Relatório de Atendimentos - $companyName',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Flexible(
                      child: pw.Text(
                        filtersText(),
                        textAlign: pw.TextAlign.right,
                        maxLines: 2,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),

              /* ── Linha de 4 cards resumo ── */
              pw.Positioned(
                left: 40,
                right: 40,
                top: 150,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryCard('Fila', fila, _red, rangeLabel),
                    _summaryCard(
                        'Em atendimento', atendendo, _orange, rangeLabel),
                    _summaryCard('Concluídos', concluidos, _green, rangeLabel),
                    _summaryCard('Total', total, _blue, rangeLabel),
                  ],
                ),
              ),

              /* ── Tabela ── */
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(40, 260, 40, 40),
                child: pw.Table(
                  defaultVerticalAlignment:
                      pw.TableCellVerticalAlignment.middle,
                  border: pw.TableBorder.all(color: _cellBorder, width: .5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3),
                    1: pw.FlexColumnWidth(2),
                    2: pw.FlexColumnWidth(1.5),
                    3: pw.FlexColumnWidth(2),
                    4: pw.FlexColumnWidth(2),
                    5: pw.FlexColumnWidth(2),
                  },
                  children: [
                    /* cabeçalho */
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: _purple),
                      children: [
                        for (final h in headers)
                          pw.Container(
                            alignment: pw.Alignment.center,
                            padding: const pw.EdgeInsets.symmetric(vertical: 6),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                color: _headerText,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                    /* dados */
                    for (final row in rows)
                      pw.TableRow(
                        children: [
                          for (final cell in row)
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 5, horizontal: 2),
                              child: pw.Text(
                                cell,
                                style: const pw.TextStyle(
                                    fontSize: 9, color: _bodyText),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    /* ── 7. Exibe diálogo de impressão / compartilhamento ───────────── */
    await prt.Printing.layoutPdf(
      name: 'relatorio_leads.pdf',
      onLayout: (_) => pdfDoc.save(),
    );
  }

/*───────────────── widget auxiliar: card resumo ─────────────────*/
  pw.Widget _summaryCard(
    String title,
    int value,
    pdf.PdfColor color,
    String period, {
    String? subtitle,
  }) {
    return pw.Expanded(
      child: pw.Container(
        height: 80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(8),
          color: const pdf.PdfColor.fromInt(0xf6f6f6),
          boxShadow: [
            pw.BoxShadow(
              blurRadius: 2,
              color: const pdf.PdfColor.fromInt(0x22000000),
            ),
          ],
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: const pdf.PdfColor.fromInt(0xFF444444))),
            pw.SizedBox(height: 2),
            pw.Text(value.toString(),
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: color)),
            pw.SizedBox(height: 2),
            pw.Text('Atendimentos',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: color)),
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle ?? period,
              style: const pw.TextStyle(
                fontSize: 8,
                color: pdf.PdfColor.fromInt(0xFF000000), // ← preto direto
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initIds() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final usnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    final data = usnap.data() as Map<String, dynamic>? ?? {};

    _companyId = (data['createdBy'] as String?)?.isNotEmpty == true
        ? data['createdBy'] as String
        : uid;

    _phoneId = data['defaultPhoneId'] as String? ?? '';

    setState(() => _ready = _phoneId.isNotEmpty);

    if (_ready) {
      await _loadAttendants();
      await _loadTags();
    }
  }

  Future<void> _pickDateRange({
    ActiveFilter? filter,
    required BuildContext filterContext,
  }) async {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: filter?.value as DateTimeRange?,
      locale: const Locale('pt', 'BR'),
      builder: (_, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: cs.primary,
            onPrimary: Colors.white,
            surface: cs.secondary,
            onSurface: cs.onBackground,
          ),
          datePickerTheme: const DatePickerThemeData(
            rangeSelectionBackgroundColor: Color(0x220090EE),
          ),
        ),
        child: child!,
      ),
    );
    if (range == null) return;

    final label = '${DateFormat('dd/MM').format(range.start)} – '
        '${DateFormat('dd/MM').format(range.end)}';
    final newFilter = ActiveFilter(
      'Data de criação',
      'arrivalAt',
      range,
      label,
    );

    setState(() {
      if (filter != null) {
        final idx = _activeFilters.indexOf(filter);
        _activeFilters[idx] = newFilter;
      } else {
        _activeFilters.add(newFilter);
      }
      _mainFilter = null;
    });
  }

  Future<void> _loadAttendants() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('createdBy', isEqualTo: _companyId)
        .get();

    setState(() {
      _attendants = snap.docs
          .map((d) =>
              {'id': d.id, 'name': (d.data()['name'] as String?) ?? 'Sem nome'})
          .toList();
    });
  }

  List<Map<String, String>> _tags = [];

  Future<void> _loadTags() async {
    final snap = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('tags')
        .get();

    setState(() {
      _tags = snap.docs
          .map((d) =>
              {'id': d.id, 'name': (d.data()['name'] as String?) ?? 'Sem nome'})
          .toList();
    });
  }

/*────────────────────────  Stream de chats  ────────────────────────*/
  Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream() {
    if (!_ready) return const Stream.empty();

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats');

    // filtro de texto
    if (_search.isNotEmpty) {
      q = q.where('keywords', arrayContains: _search.toLowerCase());
    }

    for (var f in _activeFilters) {
      if (f.field == 'tags') {
        q = q.where(f.field, arrayContains: f.value);
      } else if (f.field == 'arrivalAt') {
        final range = f.value as DateTimeRange;
        final startTs = Timestamp.fromDate(range.start);
        final endTs =
            Timestamp.fromDate(range.end.add(const Duration(days: 1)));
        q = q
            .where('arrivalAt', isGreaterThanOrEqualTo: startTs)
            .where('arrivalAt', isLessThan: endTs);
      } else {
        q = q.where(f.field, isEqualTo: f.value);
      }
    }

    return q.snapshots().handleError((e, _) {
      if (e is FirebaseException &&
          e.code == 'failed-precondition' &&
          e.message != null) {
        final link = _urlRx.firstMatch(e.message!)?.group(0);
        debugPrint('⚠️  Precisa criar índice: $link');
      }
    });
  }

  // dentro de _ReportsPageState:
  Future<void> _showFilterMenu({
    ActiveFilter? filter,
    required BuildContext filterContext,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final renderBox = filterContext.findRenderObject() as RenderBox;
    final topLeft = renderBox.localToGlobal(Offset.zero);

    /* ---------- itens já usados neste mesmo tipo de chip ---------- */
    final type = filter?.type ?? _mainFilter!;
    final usedValues = _activeFilters
        .where((f) => f.type == type && f != filter)
        .map((f) => f.value.toString())
        .toSet();

    /* ---------- lista de itens com estilo unificado ---------- */
    TextStyle itemStyle = TextStyle(
      color: cs.onBackground.withOpacity(.85),
      fontWeight: FontWeight.w500,
    );

    List<PopupMenuEntry<String>> items;
    if (type == 'Status') {
      items = _statusOpts.map((s) {
        final disabled = usedValues.contains(s);
        return PopupMenuItem<String>(
          value: disabled ? null : s,
          enabled: !disabled,
          child: Text(s,
              style: itemStyle.copyWith(
                color: disabled
                    ? cs.onBackground.withOpacity(.25)
                    : cs.onBackground.withOpacity(.85),
              )),
        );
      }).toList();
    } else if (type == 'Atendente') {
      items = _attendants.map((u) {
        final id = u['id']!;
        final name = u['name']!;
        final disabled = usedValues.contains(id);
        return PopupMenuItem<String>(
          value: disabled ? null : id,
          enabled: !disabled,
          child: Text(name,
              style: itemStyle.copyWith(
                color: disabled
                    ? cs.onBackground.withOpacity(.25)
                    : cs.onBackground.withOpacity(.85),
              )),
        );
      }).toList();
    } else {
      items = _tags.map((t) {
        final id = t['id']!;
        final name = t['name']!;
        final disabled = usedValues.contains(id);
        return PopupMenuItem<String>(
          value: disabled ? null : id,
          enabled: !disabled,
          child: Text(name,
              style: itemStyle.copyWith(
                color: disabled
                    ? cs.onBackground.withOpacity(.25)
                    : cs.onBackground.withOpacity(.85),
              )),
        );
      }).toList();
    }

    /* ---------- exibe o menu – cores/raio/sombra alinhados ---------- */
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + renderBox.size.height, // 4 px abaixo do chip
        topLeft.dx + renderBox.size.width,
        topLeft.dy,
      ),
      items: items,
      color: cs.secondary,
      // fundo igual ao outro
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      elevation: 4, // mesma sombra leve
    );

    if (selected == null) return;

    /* ---------- cria/atualiza o filtro escolhido ---------- */
    ActiveFilter newFilter;
    if (type == 'Status') {
      newFilter = ActiveFilter(type, 'status', selected, selected);
    } else if (type == 'Atendente') {
      final name = _attendants.firstWhere((u) => u['id'] == selected)['name']!;
      newFilter = ActiveFilter(type, 'updatedBy', selected, name);
    } else {
      final name = _tags.firstWhere((t) => t['id'] == selected)['name']!;
      newFilter = ActiveFilter(type, 'tags', selected, name);
    }

    setState(() {
      if (filter != null) {
        final idx = _activeFilters.indexOf(filter);
        _activeFilters[idx] = newFilter;
      } else {
        _activeFilters.add(newFilter);
      }
      _mainFilter = null;
    });
  }

  String _fieldFor(String type) {
    switch (type) {
      case 'Status':
        return 'status';
      case 'Atendente':
        return 'updatedBy';
      case 'Etiqueta':
        return 'tags';
      default:
        return '';
    }
  }

/*────────────────────────  UI  ─────────────────────────────────────*/
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDateChip = _activeFilters.any((f) => f.field == 'arrivalAt');
    final filterOpts = ['Atendente', 'Etiquetas', 'Status', 'Data de criação'];
    if (hasDateChip) filterOpts.remove('Data de criação');

    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Pesquisar',
                hintStyle: TextStyle(color: cs.onSecondary),
                prefixIcon: Icon(Icons.search, color: cs.onSecondary),
                filled: true,
                fillColor: cs.secondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),

            const SizedBox(height: 15),

            // ── 2. LINHA COM DROPDOWN + BOTÃO (ambos 50 %) ─────────────────────
            Row(
              children: [
                /* ─── DROPDOWN “Mais filtros” ─── */
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: DropdownButton2<String>(
                      // usamos customButton para injetar o ícone de filtro
                      customButton: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.secondary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.filter_alt_outlined,
                                    color: cs.onSecondary, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  _mainFilter ?? 'Mais filtros',
                                  style: TextStyle(
                                    color: cs.onSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),

                      value: _mainFilter,
                      items: filterOpts
                          .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: TextStyle(
                                color: cs.onBackground.withOpacity(.85))),
                      ))
                          .toList(),
                      underline: const SizedBox.shrink(),
                      onChanged: (v) => setState(() {
                        _mainFilter      = v;
                        _statusFilter    = null;
                        _attendantFilter = null;
                      }),

                      // ↓↓↓ mantém o mesmo estilo dos itens/caixa do menu
                      dropdownStyleData: DropdownStyleData(
                        offset: const Offset(0, 4),
                        padding: EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: cs.secondary,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                              color: cs.shadow.withOpacity(.05),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                /* ─── BOTÃO “Exportar relatório” ─── */
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: cs.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _exportLeadsPdf,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sim_card_download_outlined,
                              color: cs.onSecondary, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'Exportar relatório',
                            style: TextStyle(
                              color: cs.onSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (_activeFilters.isNotEmpty) ...[
              const SizedBox(height: 8),
              /* chips já selecionados */
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _activeFilters.map((f) {
                  return Builder(builder: (chipCtx) {
                    return InputChip(
                      backgroundColor: cs.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(
                            color: Colors.transparent, width: 0),
                      ),
                      label: Text(f.label),
                      // ↓↓↓ ajuste AQUI
                      labelStyle: TextStyle(
                        color: cs.onSurface, // era cs.onSecondary
                        fontWeight: FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      onPressed: () {
                        if (f.type == 'Data de criação') {
                          _pickDateRange(filter: f, filterContext: chipCtx);
                        } else {
                          _showFilterMenu(filter: f, filterContext: chipCtx);
                        }
                      },
                      onDeleted: () => setState(() => _activeFilters.remove(f)),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteIconColor: cs.onSurface,
                      // para combinar com o texto
                      pressElevation: 0,
                    );
                  });
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_mainFilter == 'Status' ||
                _mainFilter == 'Atendente' ||
                _mainFilter == 'Etiquetas')
              Builder(builder: (chipCtx) {
                return InputChip(
                  backgroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.transparent, width: 0),
                  ),
                  label: Text('$_mainFilter: Selecione'),
                  // ↓↓↓ texto agora usa onPrimary
                  labelStyle: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  onPressed: () =>
                      _showFilterMenu(filter: null, filterContext: chipCtx),
                  onDeleted: () => setState(() => _mainFilter = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  deleteIconColor: cs.onSurface,
                  // opcional, combina com o texto
                  pressElevation: 0,
                );
              }),
            if (_mainFilter == 'Data de criação')
              Builder(builder: (chipCtx) {
                return InputChip(
                  backgroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.transparent),
                  ),
                  label: const Text('Data de criação: Selecione'),
                  labelStyle: TextStyle(color: cs.onSurface),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  onPressed: () =>
                      _pickDateRange(filter: null, filterContext: chipCtx),
                  onDeleted: () => setState(() => _mainFilter = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  deleteIconColor: cs.onSurface,
                  pressElevation: 0,
                );
              }),
            const SizedBox(height: 20),

            /*─────────────  LISTA  ─────────────*/
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _tagsStream(),
                builder: (_, tagSnap) {
                  if (tagSnap.hasError) {
                    return Center(
                      child: Text(
                        'Erro ao carregar etiquetas: ${tagSnap.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (!tagSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final tagsMap = {
                    for (var doc in tagSnap.data!.docs) doc.id: doc.data()
                  };

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chatsStream(),
                    builder: (_, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Erro: ${snap.error}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data!.docs.toList()
                        ..sort((a, b) {
                          final mapA = a.data();
                          final mapB = b.data();
                          final aa = (mapA['updatedAt'] as Timestamp?) ??
                              (mapA['createdAt'] as Timestamp?) ??
                              Timestamp(0, 0);
                          final bb = (mapB['updatedAt'] as Timestamp?) ??
                              (mapB['createdAt'] as Timestamp?) ??
                              Timestamp(0, 0);
                          return bb.compareTo(aa);
                        });

                      if (docs.isEmpty) {
                        return const Center(
                            child: Text('Nenhum atendimento encontrado'));
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final rawChatId = d['chatId'] as String? ?? '';
                          final phoneNumber = rawChatId.contains('@')
                              ? rawChatId.split('@')[0]
                              : rawChatId;
// extrai só dígitos
                          final digits =
                              phoneNumber.replaceAll(RegExp(r'\D'), '');
                          String formattedPhone = phoneNumber;

// se for Brasil (+55)
                          if (digits.startsWith('55') && digits.length > 4) {
                            final country = '55';
                            final rest = digits.substring(2);
                            final ddd = rest.substring(0, 2);
                            final local = rest.substring(2);
                            if (local.length <= 4) {
                              // muito curto, sem hífen
                              formattedPhone = '+$country $ddd $local';
                            } else {
                              final p1 = local.substring(0, local.length - 4);
                              final p2 = local.substring(local.length - 4);
                              formattedPhone = '+$country $ddd $p1-$p2';
                            }
                          } else if (digits.length > 10) {
                            final country =
                                digits.substring(0, digits.length - 10);
                            final ddd = digits.substring(
                                digits.length - 10, digits.length - 8);
                            final rest = digits.substring(digits.length - 8);
                            final p1 = rest.substring(0, rest.length - 4);
                            final p2 = rest.substring(rest.length - 4);
                            formattedPhone = '+$country $ddd $p1-$p2';
                          }

                          final contact =
                              d['name'] ?? d['contactName'] ?? 'Contato';
                          final lastMsg = d['lastMsg'] ?? '';

                          final status = d['status'] ?? '';
                          final userName = d['updatedByName'] ?? '';
                          final startedAt =
                              (d['createdAt'] as Timestamp?)?.toDate();
                          final finishedAt =
                              (d['finishedAt'] as Timestamp?)?.toDate();
                          final updatedAt = d['updatedAt'] as Timestamp?;
                          final waitSec = d['waitTimeSec'] as int? ?? 0;

                          String firstReplyText;
                          if (updatedAt == null) {
                            firstReplyText = 'Ainda não respondido';
                          } else if (waitSec >= 3600) {
                            final h = waitSec ~/ 3600;
                            final m = (waitSec % 3600) ~/ 60;
                            firstReplyText = m > 0 ? '${h}h ${m}m' : '${h}h';
                          } else if (waitSec >= 60) {
                            final m = waitSec ~/ 60;
                            final s = waitSec % 60;
                            firstReplyText = s > 0 ? '${m}m ${s}s' : '${m}m';
                          } else {
                            firstReplyText = '${waitSec}s';
                          }
                          final updatedById = d['updatedBy'] as String?;

                          // pega tags (List<dynamic>) e converte pra List<String>
                          final rawTags = d['tags'] as List<dynamic>? ?? [];
                          final tagIds =
                              rawTags.map((e) => e.toString()).toList();

                          // gera widgets de tag com tratamento de color String ou int
                          final tagWidgets = tagIds.map((tagId) {
                            final tag = tagsMap[tagId];
                            if (tag == null) return const SizedBox.shrink();

                            final rawColor = tag['color'];
                            Color color;
                            if (rawColor is String) {
                              // "#RRGGBB" ou "RRGGBB"
                              var hex = rawColor.startsWith('#')
                                  ? rawColor.substring(1)
                                  : rawColor;
                              color = Color(int.parse('0xFF$hex'));
                            } else if (rawColor is int) {
                              color = Color(rawColor);
                            } else {
                              color = cs.primary; // fallback
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 1),
                              margin:
                                  const EdgeInsets.only(right: 4, bottom: 4),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag['name'] as String,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                            );
                          }).toList();

                          return Material(
                            color: cs.secondary,
                            borderRadius: BorderRadius.circular(12),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                // remove splash, highlight e hover do ExpansionTile
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                splashFactory: NoSplash.splashFactory,
                                listTileTheme: const ListTileThemeData(
                                  dense: true,
                                  visualDensity: VisualDensity(vertical: -1),
                                ),
                              ),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 15, vertical: 0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                // título e subtítulo na mesma linha (opção 1)
                                title: Text(
                                  contact,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onBackground.withOpacity(
                                        0.9), // <— aqui você define a cor do título
                                  ),
                                ),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                children: [
                                  _kv(
                                      'Telefone',
                                      formattedPhone.isNotEmpty
                                          ? formattedPhone
                                          : 'Não informado'),
                                  _kv('Status', status),
                                  if (tagWidgets.isEmpty)
                                    _kv('Etiquetas', 'Sem etiquetas')
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Etiquetas: ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          Expanded(
                                              child:
                                                  Wrap(children: tagWidgets)),
                                        ],
                                      ),
                                    ),
                                  if (updatedById == null)
                                    _kv('Atendente', 'Atendimento não iniciado')
                                  else
                                    FutureBuilder<
                                        DocumentSnapshot<Map<String, dynamic>>>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(updatedById)
                                          .get(),
                                      builder: (context, userSnap) {
                                        if (userSnap.connectionState !=
                                            ConnectionState.done) {
                                          return _kv(
                                              'Atendente', 'Carregando...');
                                        }
                                        if (userSnap.hasError ||
                                            !userSnap.data!.exists) {
                                          return _kv(
                                              'Atendente', 'Desconhecido');
                                        }
                                        final data = userSnap.data!.data();
                                        final nome = data?['name'] as String? ??
                                            'Desconhecido';
                                        return _kv('Atendente', nome);
                                      },
                                    ),
                                  if (startedAt != null)
                                    _kv('Início', _fmt.format(startedAt)),
                                  if (finishedAt != null)
                                    _kv('Conclusão', _fmt.format(finishedAt)),
                                  _kv('Primeira resposta', firstReplyText),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _tagsStream() {
    if (!_ready) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('tags')
        .snapshots();
  }

/*────────────────────────  helper  label : value  ──────────────────*/
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text('$k: ',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}
