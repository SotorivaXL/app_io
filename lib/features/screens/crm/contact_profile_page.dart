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

  @override
  void initState() {
    super.initState();
    _loadCompanyTags();          // carrega todas as tags da empresa
  }


  Future<void> _loadCompanyTags() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    final companyId = (userSnap.exists && (userSnap['createdBy'] ?? '').toString().isNotEmpty)
        ? userSnap['createdBy'] as String
        : uid;

    FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .collection('tags')
        .snapshots()
        .listen((qs) {
      setState(() {
        _tagMap
          ..clear()
          ..addEntries(qs.docs.map((d) => MapEntry(d.id, TagItem.fromDoc(d))));
      });
    });
  }

  void _openTagManager() {
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

    /* formata o telefone (ex.: (46) 98827-2844) */
    final phoneMask = widget.chatId.replaceFirstMapped(
      RegExp(r'^(\d{2})(\d{2})(\d{5})(\d{4})$'),
          (m) => '(${m[2]}) ${m[3]}-${m[4]}',
    );

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
        actions: const [
          Icon(Icons.block, size: 22),
          SizedBox(width: 16),
          Icon(Icons.delete_outline, size: 22),
          SizedBox(width: 16),
          Icon(Icons.mode_edit_outlined, size: 22),
          SizedBox(width: 8),
        ],
      ),

      /*────────────────── corpo ──────────────────*/
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('whatsappChats')
            .doc(widget.chatId)
            .snapshots(),
        builder: (ctx, snap) {
          /* ids das tags ligadas a este chat */
          final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
          final tagIds = (data['tags'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
              [];

          final tagItems = tagIds
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
                        phoneMask,
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