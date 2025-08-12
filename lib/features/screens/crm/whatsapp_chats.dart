import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_io/features/screens/crm/chat_detail.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:app_io/features/screens/crm/welcome_connect_phone.dart';


class WhatsAppChats extends StatefulWidget {
  const WhatsAppChats({Key? key}) : super(key: key);

  @override
  State<WhatsAppChats> createState() => _WhatsAppChatsState();
}

enum SortOption { oldestFirst, newestFirst }
SortOption _sort = SortOption.newestFirst;
enum ChatTab { novos, atendendo }

class TagItem {
  final String name;
  final Color color;
  TagItem(this.name, this.color);
}

// fora da classe (ou como método estático dentro dela)
String _initials(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));        // remove espaços repetidos
  final letters = parts.where((p) => p.isNotEmpty)       // descarta vazios
      .map((p) => p[0])                 // primeira letra
      .take(2)
      .join()
      .toUpperCase();
  return letters.isEmpty ? '•' : letters;                // fallback se ainda estiver vazio
}

class _WhatsAppChatsState extends State<WhatsAppChats> {
  String? _companyId;
  String? _phoneId;
  ChatTab _currentTab = ChatTab.novos;
  String _searchTerm = '';
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+55';
  StreamSubscription? _tagSub;
  final Map<String, TagItem> _tagMap = {};
  Set<String> _filterTags = {};
  bool _showUnreadOnly = false;
  bool _noPhone = false;

  CollectionReference<Map<String,dynamic>> chatsCol() =>
      FirebaseFirestore.instance
          .collection('empresas').doc(_companyId)
          .collection('phones').doc(_phoneId)
          .collection('whatsappChats');

  Future<String> getCompanyId() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    return (userSnap.exists && (userSnap['createdBy'] ?? '').toString().isNotEmpty)
        ? userSnap['createdBy'] as String
        : uid;
  }

  @override
  void initState() {
    super.initState();

    // 1. carrega dados
    _loadIds().then((_) {
      // 2. só aqui companyId/phoneId estão definidos
      if (_companyId != null && _phoneId != null) {
        _refreshPhotosSilently();
      }
    });
  }

  @override
  void dispose() {
    _tagSub?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  static const _mediaMatchers = {
    // extensão        → (rótulo,   ícone)
    'jpg'  : ('Imagem',  Icons.photo),
    'jpeg' : ('Imagem',  Icons.photo),
    'png'  : ('Imagem',  Icons.photo),
    'gif'  : ('Imagem',  Icons.photo),
    'webp' : ('Figurinha', Icons.emoji_emotions),
    'mp4'  : ('Vídeo',   Icons.videocam),
    'mov'  : ('Vídeo',   Icons.videocam),
    'mkv'  : ('Vídeo',   Icons.videocam),
    'mp3'  : ('Áudio',   Icons.audiotrack),
    'aac'  : ('Áudio',   Icons.audiotrack),
    'm4a'  : ('Áudio',   Icons.audiotrack),
    'ogg'  : ('Áudio',   Icons.audiotrack),
    'opus' : ('Áudio',   Icons.audiotrack),
  };

  ( String, IconData )? _classifyMediaMessage(String msg) {
    if (!msg.startsWith('http')) return null;          // não é URL
    final uri = Uri.tryParse(msg);
    if (uri == null) return null;

    final path = uri.path.toLowerCase();
    final ext  = path.split('.').last;                 // pega extensão

    return _mediaMatchers[ext];
  }

  Future<void> _refreshPhotosSilently() async {
    final url = Uri.parse(
      'https://updatecontactphotos-5a3yl3wsma-uc.a.run.app',
    );

    try {
      final r = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'empresaId': _companyId, 'phoneId': _phoneId}));

      if (r.statusCode != 200) {
        debugPrint('updateContactPhotos ERRO ${r.statusCode}: ${r.body}');
      }
    } catch (e, s) {
      debugPrint('updateContactPhotos exception: $e\n$s');
    }
  }

  Future<void> _loadIds() async {
    /* ----------------------------------------------------------------- */
    /* 1. Lê o doc do usuário em segurança                                */
    /* ----------------------------------------------------------------- */
    final uid  = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = snap.data() as Map<String, dynamic>? ?? {};

    _companyId = (data['createdBy'] as String?)?.isNotEmpty == true
        ? data['createdBy'] as String          // colaborador ⇒ herda empresa
        : uid;                                 // owner ⇒ sua própria empresa

    _phoneId   = data['defaultPhoneId'] as String?;

    /* ----------------------------------------------------------------- */
    /* 2. Se o usuário ainda não definiu um número, pegar o 1º da empresa */
    /* ----------------------------------------------------------------- */
    if (_phoneId == null) {
      final phonesCol = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('phones');

      final q = await phonesCol.limit(1).get();
      if (q.docs.isNotEmpty) {
        _phoneId = q.docs.first.id;

        // 🚩 opcional – grave o phoneId no usuário para não repetir a busca
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'defaultPhoneId': _phoneId}, SetOptions(merge: true));
      }
    }

    if (_phoneId == null) {
      if (mounted) setState(() => _noPhone = true);
      return;
    }

    if (_companyId != null && _phoneId != null) {
      _refreshPhotosSilently();     // ← dispara já na 1ª abertura
    }

    _tagSub?.cancel();
    _tagSub = FirebaseFirestore.instance
        .collection('empresas').doc(_companyId)
        .collection('tags')
        .orderBy('name')
        .snapshots()
        .listen((qs) {
      if (!mounted) return;

      // 1º: atualiza o mapa (isso sim dentro do setState)
      setState(() {
        _tagMap
          ..clear()
          ..addEntries(qs.docs.map((d) => MapEntry(
            d.id,
            TagItem(d['name'] ?? '', Color(d['color'] ?? 0xFF9E9E9E)),
          )));
      });

      // 2º: dispara refresh fora do setState
      _refreshPhotosSilently();
    });

    if (mounted) setState(() {});     // força rebuild inicial
  }

  // 3) construir o número limpo
  Future<void> _startConversation() async {
    // ── 1. Sanitiza o número ─────────────────────────────────────────────
    final raw = _phoneMask.getUnmaskedText();          // 11999998888
    if (raw.length < 10) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Número inválido')));
      return;
    }

    final chatId = '${_countryCode.replaceAll(RegExp(r'\D'), '')}$raw'; // 5511…

    // ── 2. Referência ao doc do chat ─────────────────────────────────────
    final chatRef  = FirebaseFirestore.instance
        .collection('empresas').doc(_companyId).collection('phones').doc(_phoneId).collection('whatsappChats')
        .doc(chatId);

    final snap = await chatRef.get();

    // Variáveis que serão passadas ao ChatDetail
    String chatName      = chatId;
    String contactPhoto  = '';

    // ── 3. Se já existe, usa name/foto do Firestore ──────────────────────
    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>;
      chatName     = data['name']          ?? chatName;
      contactPhoto = data['contactPhoto']  ?? '';
    } else {
      // Cria stub para novo chat
      await chatRef.set({
        'chatId'          : chatId,
        'name'            : chatName,
        'lastMessage'     : '',
        'lastMessageTime' : '',
        'timestamp'       : FieldValue.serverTimestamp(),
        'opened'          : false,
        'unreadCount'     : 0,
        'contactPhoto'    : contactPhoto,
        'status'         : 'novo',
        'saleValue'      : null,
      });
    }

    // ── 4. Abre a tela de detalhes ───────────────────────────────────────
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetail(
          chatId: chatId,
          chatName: chatName,
          contactPhoto: contactPhoto,
        ),
      ),
    );
  }

  Widget _avatar(String contactPhoto, String name, ColorScheme cs) {
    final avatarKey = ValueKey(contactPhoto);

    if (contactPhoto.isNotEmpty) {
      // ───── com foto ─────
      return CircleAvatar(
        key: avatarKey,
        radius: 22,
        backgroundColor: cs.inverseSurface,
        foregroundImage: NetworkImage(contactPhoto),
        onForegroundImageError: (_, __) {
          // volta para as iniciais se o link 403 / expirar
          if (mounted) setState(() {});
        },
        child: null,                           // sem fallback aqui
      );
    }

    // ───── sem foto ─────
    return CircleAvatar(
      key: avatarKey,
      radius: 22,
      backgroundColor: cs.inverseSurface,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: cs.outline,
          fontSize: 14,
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // ITEM DE LISTA
  // ---------------------------------------------------------------------------
  // ===================== ITEM DA LISTA DE CHATS =====================
  Widget _buildChatItem(
      BuildContext context, {
        required String chatId,
        required String name,
        required String lastMessage,
        required String lastMessageTime,
        required int unreadCount,
        required String contactPhoto,
        required List<TagItem> tags,
      }) {
    final theme = Theme.of(context);
    final mediaInfo = _classifyMediaMessage(lastMessage);   // (label, icon)? ou null

    // ---------- linha que mostra a última mensagem ----------
    late final Widget lastLine;
    if (mediaInfo != null) {
      final (label, icon) = mediaInfo;
      lastLine = Row(
        children: [
          Icon(icon,
              size: 14,
              color: theme.colorScheme.onSecondary.withOpacity(.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSecondary.withOpacity(.7),
            ),
          ),
        ],
      );
    } else {
      lastLine = Text(
        lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSecondary.withOpacity(.7),
        ),
      );
    }

    // ---------- widget completo ----------
    return InkWell(
      onTap: () async {
        await FirebaseFirestore.instance
            .collection('empresas').doc(_companyId).collection('phones').doc(_phoneId).collection('whatsappChats')
            .doc(chatId)
            .set(
          {'unreadCount': 0},
          SetOptions(merge: true),
        );

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetail(
              chatId: chatId,
              chatName: name,
              contactPhoto: contactPhoto,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- avatar ----------
            Stack(
              clipBehavior: Clip.none,
              children: [
                _avatar(contactPhoto, name, theme.colorScheme),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Center(
                      child: FaIcon(FontAwesomeIcons.whatsapp,
                          size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 12),

            // ---------- nome + tags + última mensagem ----------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tags.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondary,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((tag) {
                        final onDark =
                            ThemeData.estimateBrightnessForColor(tag.color) ==
                                Brightness.dark;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: tag.color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            tag.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              color: onDark ? Colors.white : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 3),
                  lastLine,
                ],
              ),
            ),

            // ---------- hora + badge ----------
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastMessageTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSecondary.withOpacity(.7),
                  ),
                ),
                const SizedBox(height: 6),
                if (unreadCount > 0)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _currentTab == ChatTab.novos
                          ? theme.colorScheme.error        // bolinha vermelha nos “Novos”
                          : theme.colorScheme.tertiary,    // badge comum em “Atendendo”
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFilterSheet() {
    if (_tagMap.isEmpty) return;

    final tmp = _filterTags.toSet();      // cópia mutável

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── cabeçalho ───
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
                  const Text(
                    'Filtrar por etiquetas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  // ─── lista de tags ───
                  ..._tagMap.entries.map((e) {
                    final tag = e.value;
                    final sel = tmp.contains(e.key);
                    final onDark =
                        ThemeData.estimateBrightnessForColor(tag.color) ==
                            Brightness.dark;

                    void toggle() => setModalState(() {
                      sel ? tmp.remove(e.key) : tmp.add(e.key);
                    });

                    return InkWell(
                      onTap: toggle,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: tag.color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tag.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: onDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            Checkbox(
                              value: sel,
                              activeColor: cs.primary,
                              onChanged: (_) => toggle(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 18),

                  // ─── botões ───
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: cs.onSecondary,        // cor do texto
                        ),
                        onPressed: () =>
                            setModalState(() => tmp.clear()),     // desmarca visualmente
                        child: const Text('Limpar'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onSurface,
                        ),
                        onPressed: () {
                          // grava seleção no estado principal e fecha o modal
                          setState(() => _filterTags = tmp);
                          Navigator.pop(context);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget _item({
              required SortOption option,
              required String label,
              required IconData icon,
            }) {
              final selected = _sort == option;

              return InkWell(
                onTap: () => setModalState(() => _sort = option),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(icon,
                          color: cs.onSecondary,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onBackground,
                            )),
                      ),
                      // radio “fake”
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.onSecondary, width: 2),
                          color: selected ? cs.onSecondary : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding:
              EdgeInsets.only(top: 18, bottom: 24, left: 4, right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _item(
                    option: SortOption.oldestFirst,
                    label: 'Mais antigos primeiro',
                    icon: Icons.arrow_downward, // 🔻
                  ),
                  _item(
                    option: SortOption.newestFirst,
                    label: 'Últimas interações primeiro',
                    icon: Icons.arrow_upward,   // 🔺
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onSurface,
                      minimumSize: const Size(160, 46),
                    ),
                    onPressed: () {
                      // grava escolha e fecha
                      setState(() {});   // força rebuild da lista
                      Navigator.pop(ctx);
                    },
                    child: const Text('Aplicar'),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_companyId == null || _phoneId == null) {
      if (_noPhone) return const WelcomeConnectPhone();
    }
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ------------ LINHA DE ABAS ------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: StreamBuilder<QuerySnapshot>(
                // agora sem filtro – recebemos todos
                stream: FirebaseFirestore.instance
                    .collection('empresas').doc(_companyId).collection('phones').doc(_phoneId).collection('whatsappChats')
                    .snapshots(),
                builder: (context, snap) {
                  int novosCount = 0;

                  if (snap.hasData) {
                    // conta chats cujo 'opened' NÃO é true (false ou inexistente)
                    novosCount = snap.data!.docs.where((d) {
                      final map = d.data() as Map<String, dynamic>;
                      return (map['opened'] as bool?) != true;
                    }).length;
                  }

                  return Row(
                    children: [
                      _buildTab('Novos', ChatTab.novos, badge: novosCount),
                      const SizedBox(width: 8),
                      _buildTab('Atendendo', ChatTab.atendendo),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        color: Theme.of(context).colorScheme.onSecondary,
                        onPressed: () {},
                      ),
                    ],
                  );
                },
              ),
            ),

            // ------------ CAMPO DE BUSCA ------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search,
                              color:
                              theme.colorScheme.onBackground.withOpacity(0.5)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (v) =>
                                  setState(() => _searchTerm = v.trim().toLowerCase()),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: 'Buscar atendimento',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onBackground
                                      .withOpacity(0.5),
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _filterTags.isEmpty
                          ? Icons.filter_alt_outlined
                          : Icons.filter_alt,          // ícone cheio se houver filtro
                    ),
                    color: theme.colorScheme.onSecondary,  // destaque
                    splashRadius: 22,
                    onPressed: _openFilterSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    color: theme.colorScheme.onSecondary,
                    splashRadius: 22,
                    onPressed: _openSortSheet,   // ← troque para chamar o novo método
                  ),
                  IconButton(
                    icon: Icon(
                      _showUnreadOnly ? Icons.filter_list : Icons.filter_list_outlined,
                    ),
                    color: _showUnreadOnly
                        ? theme.colorScheme.primary     // destaque quando ON
                        : theme.colorScheme.onSecondary,
                    splashRadius: 22,
                    tooltip: 'Somente não lidas',
                    onPressed: () => setState(() => _showUnreadOnly = !_showUnreadOnly),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ------------ LISTA ------------
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('empresas').doc(_companyId).collection('phones').doc(_phoneId).collection('whatsappChats')
                    .orderBy('timestamp', descending: _sort == SortOption.newestFirst)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  List<QueryDocumentSnapshot> docs = snap.data!.docs;

                  bool _isOpened(QueryDocumentSnapshot d) {
                    final map = d.data() as Map<String, dynamic>;
                    return (map['opened'] as bool?) ?? false;   // se não existir ⇒ false
                  }

                  // filtragem por aba
                  if (_currentTab == ChatTab.novos) {
                    docs = docs.where((d) => !_isOpened(d)).toList();
                  } else {
                    docs = docs.where(_isOpened).toList(); // Atendendo
                  }

                  // filtro por texto
                  docs = docs.where((d) {
                    final name =
                    (d['name'] as String? ?? '').toLowerCase();
                    return name.contains(_searchTerm);
                  }).toList();

                  if (_filterTags.isNotEmpty) {
                    docs = docs.where((d) {
                      final map      = d.data() as Map<String, dynamic>;
                      final tagList  = (map['tags'] as List?)?.cast<String>() ?? const [];
                      return tagList.any(_filterTags.contains);     // pelo menos 1 tag bate
                    }).toList();
                  }

                  // — filtro “somente não-lidas” —
                  if (_showUnreadOnly) {
                    docs = docs.where((d) {
                      final unread = (d['unreadCount'] as int?) ?? 0;
                      return unread > 0;
                    }).toList();
                  }

                  docs = docs.where((d) {
                    final status = d['status'] as String? ?? 'novo';
                    return status != 'concluido' &&
                        status != 'concluido_com_venda' &&
                        status != 'recusado';
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Não há novos atendimentos',
                        style: TextStyle(
                            color: theme.colorScheme.onSecondary, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final ids = List<String>.from(data['tags'] ?? const []);
                      final tags = ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();

                      final chatId = data['chatId'] as String? ?? '';
                      final name = data['name'] as String? ?? chatId;
                      final lastMessage = data['lastMessage'] as String? ?? '';
                      final unread = data['unreadCount'] as int? ?? 0;
                      final contactPhoto = data['contactPhoto'] as String? ?? '';

                      // formata horário
                      String lastMsgTime = '';
                      final ts = data['timestamp'];
                      if (ts is Timestamp) {
                        final date = ts.toDate();
                        final now  = DateTime.now();

                        final bool sameDay =
                            date.year == now.year && date.month == now.month && date.day == now.day;

                        if (sameDay) {
                          // Ex.: 14:05
                          lastMsgTime = '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else {
                          // Ex.: 09/06
                          lastMsgTime = '${date.day.toString().padLeft(2, '0')}/'
                              '${date.month.toString().padLeft(2, '0')}';
                        }
                      }

                      return _buildChatItem(
                        context,
                        chatId: chatId,
                        name: name,
                        lastMessage: lastMessage,
                        lastMessageTime: lastMsgTime,
                        unreadCount: unread,
                        contactPhoto: contactPhoto,
                        tags: tags,
                      );
                    },
                  );
                },
              ),
            ),

            // ==================== RODAPÉ – TELEFONE + BOTÃO CONVERSAR ====================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // ---------- Dropdown do país ----------
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,                      // fundo próprio
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _countryCode,
                        alignment: Alignment.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondary,
                        ),
                        icon: Icon(Icons.arrow_drop_down,
                            color: theme.colorScheme.onBackground.withOpacity(0.5)),
                        items: const [
                          DropdownMenuItem(
                            value: '+55',
                            child: Text('+55'),
                          ),
                          DropdownMenuItem(
                            value: '+1',
                            child: Text('+1'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _countryCode = v ?? '+55'),
                      )
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ---------- Campo de telefone ----------
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _phoneController,
                        inputFormatters: [_phoneMask],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: theme.colorScheme.onSecondary),
                        decoration: InputDecoration(
                          hintText: '(00) 0000-0000',
                          hintStyle: TextStyle(
                              color: theme.colorScheme.onBackground.withOpacity(0.5)),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ---------- Botão "Conversar" ----------
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,                         // texto branco
                      padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _startConversation,
                    child: const Text(
                      'Conversar',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // ========================= TAB WIDGET =========================
  Widget _buildTab(String label, ChatTab tab, {int badge = 0}) {
    final theme    = Theme.of(context);
    final selected = _currentTab == tab;

    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,           // <= não ocupar espaço extra
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSecondary,
              ),
            ),

            // ───── badge ─────
            if (badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}