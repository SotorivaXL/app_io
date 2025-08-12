import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import 'package:string_similarity/string_similarity.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/* ─────────────────────────── model ─────────────────────────── */
class TagItem {
  final String id;
  final String name;
  final Color color;

  TagItem(this.id, this.name, this.color);

  factory TagItem.fromDoc(DocumentSnapshot d) =>
      TagItem(d.id, d['name'] ?? '', Color(d['color'] ?? 0xFF9E9E9E));
}

/* ─────────────────────── LISTA / SELEÇÃO ─────────────────────── */
class TagManagerSheet extends StatefulWidget {
  final String chatId;

  const TagManagerSheet({super.key, required this.chatId});

  @override
  State<TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<TagManagerSheet> {
  /* refs --------- */
  late DocumentReference<Map<String, dynamic>> _chatDoc;
  late CollectionReference<Map<String, dynamic>> _tagCol;
  bool _refsReady = false; // para sabermos se já podemos usar

  /* estado -------- */
  List<TagItem> _allTags = [];
  Set<String> _selected = {};
  final _searchCtrl = TextEditingController();
  String _query = '';

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _chatDoc = FirebaseFirestore.instance
        .collection('whatsappChats')
        .doc(widget.chatId);

    _discoverCompanyAndListen();
  }

  /* ── quem é a empresa? ───────────────────────────────────────── */
  Future<void> _discoverCompanyAndListen() async {
    // 1) usuário logado
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userSnap.data() ?? {};

    // 2) quem é a empresa dona deste operador?
    final companyId = (userData['createdBy'] as String?)?.isNotEmpty == true
        ? userData['createdBy'] as String // colaborador
        : uid; // conta-empresa

    // 3) telefone padrão que o operador escolheu
    final phoneId = userData['defaultPhoneId'] as String?;
    if (phoneId == null) return; // não há telefone cadastrado → aborta

    _chatDoc = FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .collection('phones')
        .doc(phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId);

    _tagCol = FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .collection('tags');

    // 5) listeners
    _subs.add(_tagCol.orderBy('name').snapshots().listen((qs) =>
        setState(() => _allTags = qs.docs.map(TagItem.fromDoc).toList())));

    _subs.add(_chatDoc.snapshots().listen((snap) {
      if (!snap.exists) return;
      final ids = List<String>.from(snap['tags'] ?? const []);
      setState(() => _selected = ids.toSet());
    }));

    // 6) avisa que já podemos usar as refs
    if (mounted) setState(() => _refsReady = true);
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /* add / remove ------------------------------------------------- */
  Future<void> _toggleTag(String id, bool add) async {
    if (!_refsReady) return; // ainda não carregou
    await _chatDoc.update({
      'tags': add ? FieldValue.arrayUnion([id]) : FieldValue.arrayRemove([id]),
    });
  }

  /* abre 2º bottom-sheet para criar tag -------------------------- */
// dentro de _TagManagerSheetState:
  void _openNewTagSheet([TagItem? tag]) {
    if (!_refsReady) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => NewTagSheet(
        chatDoc: _chatDoc,
        tagCol: _tagCol,
        tagToEdit: tag,
        existingTags: _allTags,
      ),
    );
  }

  /* ───────────────────────── UI ───────────────────────── */
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (!_refsReady) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final chatDoc = _chatDoc; // já foram inicializados
    final tagCol = _tagCol;

    /* aplica filtro de pesquisa */
    final visibleTags = _query.isEmpty
        ? _allTags
        : _allTags
            .where((t) => t.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    /* --------------------------- UI --------------------------- */
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          top: 16,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /* puxador */
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            /* título + barra de busca */
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('Etiquetas',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: theme.colorScheme.onBackground),
              decoration: InputDecoration(
                hintText: 'Buscar etiquetas…',
                hintStyle: TextStyle(
                    color: theme.colorScheme.onSecondary,
                    fontWeight: FontWeight.w500),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.background,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                // arredonda todo o background
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            /* lista */
            _allTags.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Nenhuma etiqueta cadastrada',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                  )
                : Flexible(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: visibleTags.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final tag = visibleTags[i];
                        final sel = _selected.contains(tag.id);
                        final onDark =
                            ThemeData.estimateBrightnessForColor(tag.color) ==
                                Brightness.dark;

                        return Row(
                          children: [
                            Checkbox(
                              value: sel,
                              activeColor: theme.primaryColor,
                              checkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),

                              side: MaterialStateBorderSide.resolveWith(
                                    (states) {
                                  // Marcar ➜ deixa como está (borda some sob o fill)
                                  if (states.contains(MaterialState.selected)) {
                                    return const BorderSide(color: Colors.transparent);
                                  }
                                  // Desmarcado ➜ contorno na cor desejada
                                  return BorderSide(color: cs.onSecondary, width: 2);
                                },
                              ),
                              onChanged: (_) => _toggleTag(tag.id, !sel),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _toggleTag(tag.id, !sel),
                                child: Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: tag.color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    tag.name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          onDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                              splashRadius: 20,
                              onPressed: () => _openNewTagSheet(tag),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
            const SizedBox(height: 20),

            /* botão “Criar uma nova etiqueta” ocupando 100 % da largura */
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: cs.background,
                  foregroundColor: cs.onSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide.none,
                ),
                onPressed: _openNewTagSheet,
                child: const Text(
                  'Criar uma nova etiqueta',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/* ───────────────────── CRIAR NOVA TAG ───────────────────── */
class NewTagSheet extends StatefulWidget {
  final DocumentReference chatDoc;
  final CollectionReference tagCol;
  final TagItem? tagToEdit;
  final List<TagItem> existingTags;

  const NewTagSheet({
    super.key,
    required this.chatDoc,
    required this.tagCol,
    this.tagToEdit,
    required this.existingTags,
  });

  @override
  State<NewTagSheet> createState() => _NewTagSheetState();
}

class _NewTagSheetState extends State<NewTagSheet> {
  late final TextEditingController _nameCtrl;
  late Color _picked;

  @override
  void initState() {
    super.initState();
    // pré-popula se for edição
    _nameCtrl = TextEditingController(
      text: widget.tagToEdit?.name.toUpperCase() ?? '',
    );
    _picked = widget.tagToEdit?.color ?? Colors.deepPurple;
  }

  String normalize(String txt) =>
      txt.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  double similarityHybrid(String a, String b) {
    final lev = StringSimilarity.compareTwoStrings(normalize(a), normalize(b));

    List<String> tok(String s) =>
        normalize(s).split(' ').where((w) => w.isNotEmpty).toList();

    final wa = tok(a);
    final wb = tok(b);
    final common = wa.where((w) => wb.contains(w)).length;
    final wordOverlap = wa.isEmpty ? 0 : common / wa.length; // 0‒1

    // média simples das duas métricas
    return (lev + wordOverlap) / 2;
  }

  Future<void> _save() async {
    final raw = _nameCtrl.text.trim();
    if (raw.isEmpty) return;

    // ── verificação de possíveis duplicatas ─────────────────────
    const threshold = 0.8;
    final normNew = normalize(raw);

    final possibles = widget.existingTags.where((t) {
      final sim = similarityHybrid(normNew, t.name);
      return sim >= threshold || normNew.startsWith(normalize(t.name));
    }).toList();

    if (possibles.isNotEmpty && widget.tagToEdit == null) {
      final exists = possibles.first.name;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Etiqueta parecida encontrada'),
          content: Text(
              'Já existe a etiqueta “$exists”.\nDeseja criar mesmo assim?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text('Criar assim mesmo'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // ── criação / edição efetiva ────────────────────────────────
    final rawUp = raw.toUpperCase();
    String id;

    if (widget.tagToEdit != null) {
      id = widget.tagToEdit!.id;
      await widget.tagCol
          .doc(id)
          .update({'name': rawUp, 'color': _picked.value});
    } else {
      final dup =
          await widget.tagCol.where('name', isEqualTo: rawUp).limit(1).get();
      if (dup.docs.isNotEmpty) {
        id = dup.docs.first.id;
      } else {
        final doc =
            await widget.tagCol.add({'name': rawUp, 'color': _picked.value});
        id = doc.id;
      }
      await widget.chatDoc.update({
        'tags': FieldValue.arrayUnion([id])
      });
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.tagToEdit == null) return;

    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir etiqueta?'),
        content: Text('Esta ação removerá “${widget.tagToEdit!.name}”. '
            'Você tem certeza?'),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white, // ← texto branco
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final id = widget.tagToEdit!.id;

    await widget.tagCol.doc(id).delete();
    await widget.chatDoc.update({
      'tags': FieldValue.arrayRemove([id]),
    });

    if (mounted) Navigator.pop(context); // fecha o sheet
  }

  /* picker de cor */
  void _pickColor() {
    final old = _picked;
    showDialog(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          // centraliza o título
          title: Center(
            child: Text('Cor da etiqueta'),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: StatefulBuilder(
            builder: (_, setDlg) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // pré-visualização full-width
                Container(
                  width: double.infinity,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _picked,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    (_nameCtrl.text.isEmpty ? 'Etiqueta' : _nameCtrl.text)
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ThemeData.estimateBrightnessForColor(_picked) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ColorPicker(
                  pickerColor: _picked,
                  enableAlpha: false,
                  labelTypes: const [],
                  pickerAreaHeightPercent: .65,
                  onColorChanged: (c) {
                    setDlg(() => _picked = c);
                    setState(() => _picked = c);
                  },
                ),
              ],
            ),
          ),
          // centraliza os botões
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                setState(() => _picked = old);
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /* ── UI ── */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final display = _nameCtrl.text.isEmpty ? 'Etiqueta' : _nameCtrl.text;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          top: 16,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // puxador
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // título
            Text(
              widget.tagToEdit == null ? 'Nova etiqueta' : 'Editar etiqueta',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),

            // pré-visualização full-width
            Container(
              width: double.infinity,
              height: 38,
              decoration: BoxDecoration(
                color: _picked,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                display.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ThemeData.estimateBrightnessForColor(_picked) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // campo de texto + paleta (linha)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Nome da etiqueta',
                      isDense: true,
                      filled: true,
                      fillColor: cs.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _pickColor,
                  borderRadius: BorderRadius.circular(22),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: _picked,
                    child: const Icon(Icons.palette,
                        size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // salvar / cancelar
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.tagToEdit != null)
              SizedBox(
                width: 200,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _delete,
                  child: const Text('Excluir etiqueta'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
