import 'package:app_io/features/screens/crm/tag_manager_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';


class ContactProfilePage extends StatefulWidget {
  final String chatId;     // 55119888…
  final String name;       // nome salvo no chat
  final String photoUrl;   // URL (pode ser vazio)

  const ContactProfilePage({
    Key? key,
    required this.chatId,
    required this.name,
    required this.photoUrl,
  }) : super(key: key);

  @override
  State<ContactProfilePage> createState() => _ContactProfilePageState();
}

class _ContactProfilePageState extends State<ContactProfilePage> {
  /* mapeia id-da-tag  → (nome, cor)  */
  final Map<String, TagItem> _tagMap = {};
  late DocumentReference<Map<String, dynamic>> _chatDoc;
  late CollectionReference<Map<String, dynamic>> _tagCol;
  bool _refsReady = false;   // só construímos a UI depois que tudo está pronto

  @override
  void initState() {
    super.initState();
    _initRefsAndListeners();
  }

  String formatBrazilPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');

    // só tratamos Brasil (+55); fora disso devolvemos cru
    if (!digits.startsWith('55')) return raw;

    final ddd   = digits.substring(2, 4);      // código de área
    final local = digits.substring(4);         // resto

    if (local.length == 9) {                   // celular 9-dígitos: 9 XXXX XXXX
      return '+55 $ddd ${local.substring(0,5)}-${local.substring(5)}';
    } else if (local.length == 8) {            // fixo 8-dígitos: XXXX XXXX
      return '+55 $ddd ${local.substring(0,4)}-${local.substring(4)}';
    } else {
      // qualquer outro formato – devolve cru p/ você revisar depois
      return '+55 $ddd $local';
    }
  }

  Future<(String companyId, String? phoneId)> _resolvePhoneCtx() async {
    final fs  = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

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

    // 3) se ainda null, pega o 1º phones/ e persiste como default
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

  Future<void> _initRefsAndListeners() async {
    try {
      final (companyId, phoneId) = await _resolvePhoneCtx();

      if (phoneId == null) {
        if (!mounted) return;
        setState(() => _refsReady = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum número configurado para esta empresa.')),
        );
        return;
      }

      _chatDoc = FirebaseFirestore.instance
          .collection('empresas').doc(companyId)
          .collection('phones').doc(phoneId)
          .collection('whatsappChats').doc(widget.chatId);

      _tagCol  = FirebaseFirestore.instance
          .collection('empresas').doc(companyId)
          .collection('tags');

      // listener das tags
      _tagCol.orderBy('name').snapshots().listen((qs) {
        if (!mounted) return;
        setState(() {
          _tagMap
            ..clear()
            ..addEntries(qs.docs.map((d) => MapEntry(d.id, TagItem.fromDoc(d))));
        });
      });

      if (mounted) setState(() => _refsReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _refsReady = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar dados do contato: $e')),
      );
    }
  }

  void _openTagManager() {
    if (!_refsReady) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TagManagerSheet(chatId: widget.chatId),
    );
  }

  /*──────────────── helper para cada “bloco” ───────────────*/
  Widget _section({
    required String title,
    required Widget child,
    bool showEdit = false,
    VoidCallback? onEdit,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /* ─── título (fora do input) ─── */
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: theme.colorScheme.onBackground,
            ),
          ),
          const SizedBox(height: 6),

          /* ─── “input” propriamente dito ─── */
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,       // fundo do input
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: child),
                if (showEdit)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    splashRadius: 20,
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rawDigits   = widget.chatId.split('@').first;   // 55… sem domínio
    final phonePretty = formatBrazilPhone(rawDigits);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.colorScheme.background,
        foregroundColor: theme.colorScheme.onBackground,
        automaticallyImplyLeading: false,
        title: const Text('Dados do contato'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      /*────────────────── corpo ──────────────────*/
      body: !_refsReady
          ? const Center(child: CircularProgressIndicator())   // ainda montando refs
          : StreamBuilder<DocumentSnapshot>(
        stream: _chatDoc.snapshots(),                    // caminho CORRETO
        builder: (ctx, snap) {
          /* ---------- tags ligadas ao chat ---------- */
          final data    = (snap.data?.data() as Map<String,dynamic>?) ?? {};
          final tagIds  = List<String>.from(data['tags'] ?? const []);
          final tagItems= tagIds
              .where(_tagMap.containsKey)
              .map((id) => _tagMap[id]!)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Column(
              children: [
                /* -------- avatar + nome -------- */
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: theme.colorScheme.inverseSurface,
                        backgroundImage: widget.photoUrl.isNotEmpty
                            ? NetworkImage(widget.photoUrl)
                            : null,
                        child: widget.photoUrl.isEmpty
                            ? const Text('-',
                            style:
                            TextStyle(fontSize: 32, color: Colors.white))
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onBackground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),

                /* -------- telefone -------- */
                _section(
                  title: 'Telefone',
                  child: Row(
                    children: [
                      Text(
                        phonePretty,
                        style: TextStyle(
                          fontSize: 15,
                          color: theme.colorScheme.onSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.background,
                          borderRadius: BorderRadius.circular(10)
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          FontAwesomeIcons.whatsapp,
                          size: 16,
                          color: theme.colorScheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                /* -------- etiquetas -------- */
                _section(
                  title: 'Etiquetas',
                  // showEdit = false → ícone ficará dentro do próprio child
                  showEdit: false,
                  child: tagItems.isEmpty
                      ? Text(
                    'Nenhuma etiqueta cadastrada',
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSecondary),
                  )

                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      /* ---------- chips (crescem em altura) ---------- */
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 12,
                          runSpacing: 10,
                          children: tagItems.map((t) {
                            final onDark = ThemeData.estimateBrightnessForColor(t.color)
                                == Brightness.dark;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: t.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 14,               // um pouco maior
                                  fontWeight: FontWeight.w600,
                                  color: onDark ? Colors.white : Colors.black,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      /* ---------- botão editar ---------- */
                      IconButton(
                        icon: Icon(Icons.mode_edit_outlined,
                            size: 22, color: theme.colorScheme.onSecondary),
                        splashRadius: 22,
                        onPressed: _openTagManager,          // ← abre o mesmo modal
                      ),
                    ],
                  ),
                ),

                /* -------- CPF (exemplo) -------- */
                // _section(
                //   title: 'CPF',
                //   showEdit: true,
                //   onEdit: () {},
                //   child: Text('-',
                //       style: TextStyle(
                //         fontSize: 15,
                //         color: theme.colorScheme.onSecondary,
                //       )),
                // ),
              ],
            ),
          );
        },
      ),
    );
  }
}