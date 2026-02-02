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
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

// thin rail (menu)
bool _sideExpanded = false;

// conversa selecionada no desktop
class _SelectedChat {
  final String id, name, photo;

  _SelectedChat(this.id, this.name, this.photo);
}

_SelectedChat? _selected;

// fora da classe (ou como método estático dentro dela)
String _initials(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+')); // remove espaços repetidos
  final letters = parts
      .where((p) => p.isNotEmpty) // descarta vazios
      .map((p) => p[0]) // primeira letra
      .take(2)
      .join()
      .toUpperCase();
  return letters.isEmpty ? '•' : letters; // fallback se ainda estiver vazio
}

class _WhatsAppChatsState extends State<WhatsAppChats> {
  String? _companyId;
  String? _phoneId;
  ChatTab _currentTab = ChatTab.novos;
  String _searchTerm = '';
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  String _countryCode = '+55';
  StreamSubscription? _tagSub;
  final Map<String, TagItem> _tagMap = {};
  Set<String> _filterTags = {};
  bool _showUnreadOnly = false;
  bool _noPhone = false;
  bool _showArchived = false;

  // ✅ lock anti-duplo clique / double-tap (evita duplicar log)
  final Set<String> _openingLocks = <String>{};

  // helper (dentro da _WhatsAppChatsState)
  Color get _paneBg => Theme.of(context).colorScheme.background;

  // --- Desktop responsiveness ---
  bool get _isDesktop {
    final w = MediaQuery.maybeOf(context)?.size.width ?? 0;
    return w >= 1100; // limiar de “modo desktop”
  }

  CollectionReference<Map<String, dynamic>> chatsCol() =>
      FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('phones')
          .doc(_phoneId)
          .collection('whatsappChats');

  Future<String> getCompanyId() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    return (userSnap.exists &&
            (userSnap['createdBy'] ?? '').toString().isNotEmpty)
        ? userSnap['createdBy'] as String
        : uid;
  }

  Future<Map<String, dynamic>> _callCreateChatV2({
    required String empresaId,
    required String phoneId,
    required String phoneDigits, // ex: 5546991073494 (com DDI)
  }) async {
    final url =
        Uri.parse('https://createchat-v2-5a3yl3wsma-uc.a.run.app'); // <- ajuste

    final r = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'empresaId': empresaId,
        'phoneId': phoneId,
        'phone': phoneDigits,
      }),
    );

    final body = (r.body.isNotEmpty) ? jsonDecode(r.body) : {};
    if (r.statusCode != 200) {
      throw Exception('createChat_v2 ${r.statusCode}: $body');
    }
    return (body as Map).cast<String, dynamic>();
  }

  String _ensureJid(String chatIdOrDigits) {
    final s = chatIdOrDigits.trim();
    return s.contains('@') ? s : '$s@s.whatsapp.net';
  }

  String _digitsFromJid(String jid) =>
      jid.replaceAll('@s.whatsapp.net', '').replaceAll(RegExp(r'\D'), '');

  // ✅ CORRIGIDO: NÃO DUPLICA MAIS
  Future<void> _openChat({
    required String chatId,
    required String name,
    required String contactPhoto,
  }) async {
    // ✅ lock anti-duplo clique
    if (_openingLocks.contains(chatId)) return;
    _openingLocks.add(chatId);

    final ref = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(chatId);

    bool shouldLogHumanStart = false;
    Map<String, dynamic> previous = {};

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = (snap.data() as Map<String, dynamic>?) ?? {};

        // (opcional) se você quiser guardar pra debug:
        // final curOpened = (data['opened'] as bool?) ?? false;

        final updates = <String, dynamic>{
          'unreadCount': 0,
          'opened': true,
          'chatId': chatId,
          'lastSeenAt': FieldValue.serverTimestamp(),
        };

        tx.set(ref, updates, SetOptions(merge: true));
      });

      if (_isDesktop) {
        if (!mounted) return;
        setState(() => _selected = _SelectedChat(chatId, name, contactPhoto));
      } else {
        if (!mounted) return;
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
      }
    } finally {
      _openingLocks.remove(chatId);
    }

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
    _phoneFocus.dispose();
    super.dispose();
  }

  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  static const Map<String, (String, IconData)> _extMatchers = {
    // extensão        → (rótulo,     ícone)
    'jpg': ('Imagem', Icons.photo),
    'jpeg': ('Imagem', Icons.photo),
    'png': ('Imagem', Icons.photo),
    'gif': ('Imagem', Icons.photo),
    'webp': ('Figurinha', Icons.emoji_emotions),
    'mp4': ('Vídeo', Icons.videocam),
    'mov': ('Vídeo', Icons.videocam),
    'mkv': ('Vídeo', Icons.videocam),
    'mp3': ('Áudio', Icons.audiotrack),
    'aac': ('Áudio', Icons.audiotrack),
    'm4a': ('Áudio', Icons.audiotrack),
    'ogg': ('Áudio', Icons.audiotrack),
    'opus': ('Áudio', Icons.audiotrack),
  };

  // substitua o método inteiro por este:
  (String, IconData)? _classifyMediaMessage(String raw) {
    if (raw.isEmpty) return null;
    final msg = raw.trim();

    // 1) data URI
    if (msg.startsWith('data:')) {
      final semi = msg.indexOf(';');
      if (semi > 5) {
        final mime = msg.substring(5, semi).toLowerCase();
        if (mime.startsWith('image/webp')) return ('Figurinha', Icons.emoji_emotions);
        if (mime.startsWith('image/')) return ('Imagem', Icons.photo);
        if (mime.startsWith('video/')) return ('Vídeo', Icons.videocam);
        if (mime.startsWith('audio/')) return ('Áudio', Icons.audiotrack);
      }
    }

    // 2) URL (extensão ou contentType/mimeType na query)
    if (msg.startsWith('http')) {
      final uri = Uri.tryParse(msg);
      if (uri != null) {
        final path = uri.path.toLowerCase();
        final parts = path.split('.');
        final String? ext = parts.length > 1 ? parts.last : null;
        if (ext != null && _extMatchers.containsKey(ext)) {
          return _extMatchers[ext];
        }
        final qp = uri.queryParametersAll.map(
          (k, v) => MapEntry(
            k.toLowerCase(),
            v.map((x) => Uri.decodeComponent(x).toLowerCase()).toList(),
          ),
        );
        final mimeParam =
            (qp['contenttype'] ?? qp['mimetype'] ?? qp['mime'] ?? const [])
                .cast<String?>()
                .firstWhere((e) => e != null && e!.contains('/'),
                    orElse: () => null);
        if (mimeParam != null) {
          final mime = mimeParam;
          if (mime.startsWith('image/webp')) return ('Figurinha', Icons.emoji_emotions);
          if (mime.startsWith('image/')) return ('Imagem', Icons.photo);
          if (mime.startsWith('video/')) return ('Vídeo', Icons.videocam);
          if (mime.startsWith('audio/')) return ('Áudio', Icons.audiotrack);
        }
      }
    }

    // 3) Base64 “cru”
    bool _looksLikeBase64(String s) {
      final cleaned = s.replaceAll(RegExp(r'\s'), '');
      if (cleaned.length < 32) return false;
      return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(cleaned);
    }

    List<int>? _decodeHead(String s, {int take = 512}) {
      try {
        var cleaned = s.replaceAll(RegExp(r'\s'), '');
        cleaned = cleaned.substring(0, cleaned.length.clamp(0, take * 2));
        final mod = cleaned.length % 4;
        if (mod != 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
        return base64Decode(cleaned);
      } catch (_) {
        return null;
      }
    }

    if (_looksLikeBase64(msg)) {
      final head = _decodeHead(msg);
      if (head != null && head.isNotEmpty) {
        bool startsWithSig(List<int> sig) {
          if (head.length < sig.length) return false;
          for (var i = 0; i < sig.length; i++) {
            if (head[i] != sig[i]) return false;
          }
          return true;
        }

        // Imagens
        if (startsWithSig([0x89, 0x50, 0x4E, 0x47])) return ('Imagem', Icons.photo);
        if (startsWithSig([0xFF, 0xD8, 0xFF])) return ('Imagem', Icons.photo);
        if (String.fromCharCodes(head).startsWith('GIF8')) return ('Imagem', Icons.photo);
        final ascii = String.fromCharCodes(head);
        if (ascii.startsWith('RIFF') && ascii.contains('WEBP')) {
          return ('Figurinha', Icons.emoji_emotions);
        }

        // Áudio: OGG/OPUS, MP3
        if (ascii.startsWith('OggS')) return ('Áudio', Icons.audiotrack);
        if (ascii.startsWith('ID3')) return ('Áudio', Icons.audiotrack);

        // Contêiner ISO-BMFF (mp4/mov/m4a) – tem 'ftyp'
        final ftypAt = ascii.indexOf('ftyp');
        if (ftypAt >= 0 && head.length >= ftypAt + 8) {
          final mbStart = ftypAt + 4;
          final mbEnd = mbStart + 4;
          final majorBrand = String.fromCharCodes(head.sublist(mbStart, mbEnd));

          if (majorBrand.startsWith('M4A') || majorBrand.startsWith('M4B')) {
            return ('Áudio', Icons.audiotrack);
          }

          final lower = ascii.toLowerCase();
          const audioHints = ['mp4a', 'alac', 'ac-3', 'ec-3'];
          const videoHints = ['avc1', 'hvc1', 'hev1', 'vp09', 'av01', 'mp4v', 'encv'];

          final hasAudioHint = audioHints.any(lower.contains);
          final hasVideoHint = videoHints.any(lower.contains);

          if (hasAudioHint && !hasVideoHint) return ('Áudio', Icons.audiotrack);
          if (hasVideoHint && !hasAudioHint) return ('Vídeo', Icons.videocam);

          return ('Áudio', Icons.audiotrack);
        }
      }
    }

    return null;
  }

  Future<void> _refreshPhotosSilently() async {
    final url = Uri.parse(
      'https://updatecontactphotos-5a3yl3wsma-uc.a.run.app',
    );

    try {
      final r = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'empresaId': _companyId, 'phoneId': _phoneId}),
      );

      if (r.statusCode != 200) {
        debugPrint('updateContactPhotos ERRO ${r.statusCode}: ${r.body}');
      }
    } catch (e, s) {
      debugPrint('updateContactPhotos exception: $e\n$s');
    }
  }

  void _clearPhoneInput() {
    _phoneController.clear();
    _phoneMask.clear();

    // fecha teclado e remove foco de vez
    _phoneFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    // opcional (bem efetivo em alguns Android/Windows):
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _loadIds() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final empresasRef = FirebaseFirestore.instance.collection('empresas').doc(uid);

    // Lê doc de users/{uid} apenas para saber se É colaborador (createdBy)
    final userSnap = await usersRef.get();
    final Map<String, dynamic> userData = (userSnap.data() as Map<String, dynamic>?) ?? {};
    final String? createdBy = (userData['createdBy'] as String?)?.trim();

    // ✔️ Colaborador SÓ se tem createdBy não-vazio
    final bool isCollaborator = createdBy != null && createdBy.isNotEmpty;

    // companyId: colaborador herda createdBy; dono usa o próprio uid
    _companyId = isCollaborator ? createdBy : uid;

    // Tenta carregar o defaultPhoneId do lugar correto (sem escrever nada)
    if (isCollaborator) {
      _phoneId = userData['defaultPhoneId'] as String?;
    } else {
      final empSnap = await empresasRef.get();
      _phoneId = (empSnap.data()?['defaultPhoneId'] as String?);
    }

    // Se não tiver defaultPhoneId, pega o primeiro phone da empresa (APENAS EM MEMÓRIA)
    if (_phoneId == null) {
      final phonesCol = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('phones');

      final q = await phonesCol.limit(1).get();
      if (q.docs.isNotEmpty) {
        _phoneId = q.docs.first.id;
      }
    }

    if (_phoneId == null) {
      if (mounted) setState(() => _noPhone = true);
      return;
    }

    // Dispara refresh e listeners (também não escrevem em users/)
    if (_companyId != null && _phoneId != null) {
      _refreshPhotosSilently();
    }

    _tagSub?.cancel();
    _tagSub = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('tags')
        .orderBy('name')
        .snapshots()
        .listen((qs) {
      if (!mounted) return;
      setState(() {
        _tagMap
          ..clear()
          ..addEntries(qs.docs.map((d) => MapEntry(
                d.id,
                TagItem(d['name'] ?? '', Color(d['color'] ?? 0xFF9E9E9E)),
              )));
      });
      _refreshPhotosSilently();
    });

    if (mounted) setState(() {});
  }

  // 3) construir o número limpo
  Future<void> _startConversation() async {
    if (_companyId == null || _phoneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carregando telefone da empresa...')),
      );
      return;
    }

    final raw = _phoneMask.getUnmaskedText();
    if (raw.length < 10) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Número inválido')));
      return;
    }

    final ddi = _countryCode.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = '$ddi$raw'; // ex: 5546991073494

    try {
      // 1) Backend resolve (com/sem 9) e tenta buscar nome/foto
      final resp = await _callCreateChatV2(
        empresaId: _companyId!,
        phoneId: _phoneId!,
        phoneDigits: phoneDigits,
      );

      final resolvedChatId = _ensureJid((resp['chatId'] ?? '').toString());
      final resolvedDigits = _digitsFromJid(resolvedChatId);

      final contactName = (resp['contactName'] ?? resolvedChatId).toString();
      final contactPhoto = (resp['contactPhoto'] ?? '').toString();

      final chatsBase = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('phones')
          .doc(_phoneId)
          .collection('whatsappChats');

      final jidRef = chatsBase.doc(resolvedChatId); // padrão correto
      final bareRef = chatsBase.doc(resolvedDigits); // legado sem "@"

      // 2) Migra legado (sem @) -> JID, se necessário
      final jidSnap = await jidRef.get();
      if (!jidSnap.exists) {
        final bareSnap = await bareRef.get();
        if (bareSnap.exists) {
          final data = bareSnap.data() ?? {};
          await jidRef.set({
            ...data,
            'chatId': resolvedChatId,
            'waId': resolvedDigits,
          }, SetOptions(merge: true));
          await bareRef.delete();
        } else {
          // 3) Não existe nada -> cria stub (usando o ID resolvido)
          await jidRef.set({
            'chatId': resolvedChatId,
            'waId': resolvedDigits,
            'name': contactName,
            'lastMessage': '',
            'lastMessageTime': '',
            'timestamp': FieldValue.serverTimestamp(),
            'opened': false,
            'unreadCount': 0,
            'contactPhoto': contactPhoto,

            // ✅ defaults corretos
            'status': 'novo',
            'aiMode': 'ai',

            'saleValue': null,
          });
        }
      }
      _clearPhoneInput();

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetail(
            chatId: resolvedChatId,
            chatName: contactName,
            contactPhoto: contactPhoto,
          ),
        ),
      );

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _phoneFocus.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    } catch (e, s) {
      debugPrint('Conversar: erro createChat_v2: $e\n$s');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao iniciar conversa: $e')),
      );
    }
  }

  Widget _actionIcon({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    String? tooltip,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, color: color ?? cs.onSecondary),
      tooltip: tooltip,
      splashRadius: 22,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 40,
      ),
      onPressed: onPressed,
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
        child: null, // sem fallback aqui
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
    final mediaInfo = _classifyMediaMessage(lastMessage);

    late final Widget lastLine;
    if (mediaInfo != null) {
      final (label, icon) = mediaInfo;
      lastLine = Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondary.withOpacity(.7)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSecondary.withOpacity(.7),
              ),
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

    return InkWell(
      onTap: () => _openChat(
        chatId: chatId,
        name: name,
        contactPhoto: contactPhoto,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      child: FaIcon(FontAwesomeIcons.whatsapp, size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
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
                            ThemeData.estimateBrightnessForColor(tag.color) == Brightness.dark;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _currentTab == ChatTab.novos
                          ? theme.colorScheme.error
                          : theme.colorScheme.tertiary,
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

    final tmp = _filterTags.toSet();

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
                  ..._tagMap.entries.map((e) {
                    final tag = e.value;
                    final sel = tmp.contains(e.key);
                    final onDark = ThemeData.estimateBrightnessForColor(tag.color) == Brightness.dark;

                    void toggle() => setModalState(() {
                          sel ? tmp.remove(e.key) : tmp.add(e.key);
                        });

                    return InkWell(
                      onTap: toggle,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: cs.onSecondary,
                        ),
                        onPressed: () => setModalState(() => tmp.clear()),
                        child: const Text('Limpar'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onSurface,
                        ),
                        onPressed: () {
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
                      Icon(icon, color: cs.onSecondary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onBackground,
                          ),
                        ),
                      ),
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
              padding: EdgeInsets.only(top: 18, bottom: 24, left: 4, right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _item(
                    option: SortOption.oldestFirst,
                    label: 'Mais antigos primeiro',
                    icon: Icons.arrow_downward,
                  ),
                  _item(
                    option: SortOption.newestFirst,
                    label: 'Últimas interações primeiro',
                    icon: Icons.arrow_upward,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onSurface,
                      minimumSize: const Size(160, 46),
                    ),
                    onPressed: () {
                      setState(() {});
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

    return Scaffold(
      backgroundColor: _paneBg,
      body: _isDesktop ? _buildDesktop(context) : SafeArea(child: _buildMobile(context)),
    );
  }

  // ========================= MOBILE =========================
  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('empresas')
                .doc(_companyId)
                .collection('phones')
                .doc(_phoneId)
                .collection('whatsappChats')
                .snapshots(),
            builder: (context, snap) {
              int novosCount = 0;
              int atendendoUnread = 0;

              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final map = d.data() as Map<String, dynamic>;
                  final opened = (map['opened'] as bool?) == true;
                  final unread = (map['unreadCount'] as int?) ?? 0;

                  if (!opened) {
                    novosCount += 1;
                  } else if (unread > 0) {
                    atendendoUnread += unread;
                  }
                }
              }

              return Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildTab('Novos', ChatTab.novos, badge: novosCount),
                          const SizedBox(width: 8),
                          _buildTab('Atendendo', ChatTab.atendendo, badge: atendendoUnread),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _actionIcon(
                        icon: _showArchived ? Icons.archive : Icons.archive_outlined,
                        color: _showArchived
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSecondary,
                        tooltip: _showArchived ? 'Mostrar em andamento' : 'Mostrar concluídos',
                        onPressed: () => setState(() => _showArchived = !_showArchived),
                      ),
                      _actionIcon(
                        icon: _filterTags.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
                        onPressed: _openFilterSheet,
                      ),
                      _actionIcon(
                        icon: Icons.swap_vert,
                        onPressed: _openSortSheet,
                      ),
                      _actionIcon(
                        icon: _showUnreadOnly ? Icons.filter_list : Icons.filter_list_outlined,
                        color: _showUnreadOnly
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSecondary,
                        tooltip: 'Somente não lidas',
                        onPressed: () => setState(() => _showUnreadOnly = !_showUnreadOnly),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        // ------------ BUSCA ------------
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
                      Icon(Icons.search, color: theme.colorScheme.onBackground.withOpacity(0.5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _searchTerm = v.trim().toLowerCase()),
                          textAlign: TextAlign.start,
                          decoration: InputDecoration(
                            hintText: 'Buscar atendimento',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onBackground.withOpacity(0.5),
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
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ------------ LISTA ------------
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('empresas')
                .doc(_companyId)
                .collection('phones')
                .doc(_phoneId)
                .collection('whatsappChats')
                .orderBy('timestamp', descending: _sort == SortOption.newestFirst)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              List<QueryDocumentSnapshot> docs = snap.data!.docs;

              bool _isOpened(QueryDocumentSnapshot d) {
                final map = d.data() as Map<String, dynamic>;
                return (map['opened'] as bool?) ?? false;
              }

              if (!_showArchived) {
                if (_currentTab == ChatTab.novos) {
                  docs = docs.where((d) => !_isOpened(d)).toList();
                } else {
                  docs = docs.where(_isOpened).toList();
                }
              }

              docs = docs.where((d) {
                final name = (d['name'] as String? ?? '').toLowerCase();
                return name.contains(_searchTerm);
              }).toList();

              if (_filterTags.isNotEmpty) {
                docs = docs.where((d) {
                  final map = d.data() as Map<String, dynamic>;
                  final tagList = (map['tags'] as List?)?.cast<String>() ?? const [];
                  return tagList.any(_filterTags.contains);
                }).toList();
              }

              if (_showUnreadOnly) {
                docs = docs.where((d) => ((d['unreadCount'] as int?) ?? 0) > 0).toList();
              }

              if (_showArchived) {
                docs = docs.where((d) {
                  final st = d['status'] as String? ?? '';
                  return st == 'concluido_com_venda' || st == 'recusado';
                }).toList();
              } else {
                docs = docs.where((d) {
                  final st = d['status'] as String? ?? 'novo';
                  return st != 'concluido' && st != 'concluido_com_venda' && st != 'recusado';
                }).toList();
              }

              if (docs.isEmpty) {
                final msg = _showArchived
                    ? 'Não há conversas concluídas'
                    : (_currentTab == ChatTab.novos
                        ? 'Não há novos atendimentos'
                        : 'Nenhum atendimento em andamento');

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 56, color: theme.colorScheme.onSecondary),
                      const SizedBox(height: 12),
                      Text(
                        msg,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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

                  final doc = docs[i];
                  final chatId = doc.id;
                  final name = data['name'] as String? ?? chatId;
                  final lastMessage = data['lastMessage'] as String? ?? '';
                  final unread = data['unreadCount'] as int? ?? 0;
                  final contactPhoto = data['contactPhoto'] as String? ?? '';

                  String lastMsgTime = '';
                  final ts = data['timestamp'];
                  if (ts is Timestamp) {
                    final date = ts.toDate();
                    final now = DateTime.now();

                    final bool sameDay =
                        date.year == now.year && date.month == now.month && date.day == now.day;

                    if (sameDay) {
                      lastMsgTime =
                          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                    } else {
                      lastMsgTime =
                          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
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

        // ------------ RODAPÉ ------------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _countryCode,
                    alignment: Alignment.center,
                    style: TextStyle(color: theme.colorScheme.onSecondary),
                    icon: Icon(Icons.arrow_drop_down,
                        color: theme.colorScheme.onBackground.withOpacity(0.5)),
                    items: const [
                      DropdownMenuItem(value: '+55', child: Text('+55')),
                      DropdownMenuItem(value: '+1', child: Text('+1')),
                    ],
                    onChanged: (v) => setState(() => _countryCode = v ?? '+55'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                    focusNode: _phoneFocus,
                    inputFormatters: [_phoneMask],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: theme.colorScheme.onSecondary),
                    decoration: InputDecoration(
                      hintText: '(00) 0000-0000',
                      hintStyle: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.5)),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _startConversation,
                  child: const Text(
                    'Conversar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========================= DESKTOP =========================
  Widget _buildLeftPaneDesktop(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 420,
      color: _paneBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('empresas')
                  .doc(_companyId)
                  .collection('phones')
                  .doc(_phoneId)
                  .collection('whatsappChats')
                  .snapshots(),
              builder: (context, snap) {
                int novosCount = 0;
                int atendendoUnread = 0;

                if (snap.hasData) {
                  for (final d in snap.data!.docs) {
                    final map = d.data() as Map<String, dynamic>;
                    final opened = (map['opened'] as bool?) == true;
                    final unread = (map['unreadCount'] as int?) ?? 0;

                    if (!opened) {
                      novosCount += 1;
                    } else if (unread > 0) {
                      atendendoUnread += unread;
                    }
                  }
                }

                return Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildTab('Novos', ChatTab.novos, badge: novosCount),
                            const SizedBox(width: 8),
                            _buildTab('Atendendo', ChatTab.atendendo, badge: atendendoUnread),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionIcon(
                          icon: _showArchived ? Icons.archive : Icons.archive_outlined,
                          color: _showArchived
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSecondary,
                          tooltip: _showArchived ? 'Mostrar em andamento' : 'Mostrar concluídos',
                          onPressed: () => setState(() => _showArchived = !_showArchived),
                        ),
                        _actionIcon(
                          icon: _filterTags.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
                          onPressed: _openFilterSheet,
                        ),
                        _actionIcon(
                          icon: Icons.swap_vert,
                          onPressed: _openSortSheet,
                        ),
                        _actionIcon(
                          icon: _showUnreadOnly ? Icons.filter_list : Icons.filter_list_outlined,
                          color: _showUnreadOnly
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSecondary,
                          tooltip: 'Somente não lidas',
                          onPressed: () => setState(() => _showUnreadOnly = !_showUnreadOnly),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          // busca
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
                            color: theme.colorScheme.onBackground.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _searchTerm = v.trim().toLowerCase()),
                            textAlign: TextAlign.start,
                            decoration: InputDecoration(
                              hintText: 'Buscar atendimento',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onBackground.withOpacity(0.5),
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
              ],
            ),
          ),
          const SizedBox(height: 8),

          // lista
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('empresas')
                  .doc(_companyId)
                  .collection('phones')
                  .doc(_phoneId)
                  .collection('whatsappChats')
                  .orderBy('timestamp', descending: _sort == SortOption.newestFirst)
                  .snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                List<QueryDocumentSnapshot> docs = snap.data!.docs;

                bool _isOpened(QueryDocumentSnapshot d) {
                  final map = d.data() as Map<String, dynamic>;
                  return (map['opened'] as bool?) ?? false;
                }

                if (!_showArchived) {
                  if (_currentTab == ChatTab.novos) {
                    docs = docs.where((d) => !_isOpened(d)).toList();
                  } else {
                    docs = docs.where(_isOpened).toList();
                  }
                }

                docs = docs.where((d) {
                  final name = (d['name'] as String? ?? '').toLowerCase();
                  return name.contains(_searchTerm);
                }).toList();

                if (_filterTags.isNotEmpty) {
                  docs = docs.where((d) {
                    final map = d.data() as Map<String, dynamic>;
                    final tagList = (map['tags'] as List?)?.cast<String>() ?? const [];
                    return tagList.any(_filterTags.contains);
                  }).toList();
                }

                if (_showUnreadOnly) {
                  docs = docs.where((d) => ((d['unreadCount'] as int?) ?? 0) > 0).toList();
                }

                if (_showArchived) {
                  docs = docs.where((d) {
                    final st = d['status'] as String? ?? '';
                    return st == 'concluido_com_venda' || st == 'recusado';
                  }).toList();
                } else {
                  docs = docs.where((d) {
                    final st = d['status'] as String? ?? 'novo';
                    return st != 'concluido' && st != 'concluido_com_venda' && st != 'recusado';
                  }).toList();
                }

                if (docs.isEmpty) {
                  final msg = _showArchived
                      ? 'Não há conversas concluídas'
                      : (_currentTab == ChatTab.novos
                          ? 'Não há novos atendimentos'
                          : 'Nenhum atendimento em andamento');

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 56, color: theme.colorScheme.onSecondary),
                        const SizedBox(height: 12),
                        Text(
                          msg,
                          style: TextStyle(
                            color: theme.colorScheme.onSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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

                    final doc = docs[i];
                    final chatId = doc.id;
                    final name = data['name'] as String? ?? chatId;
                    final lastMessage = data['lastMessage'] as String? ?? '';
                    final unread = data['unreadCount'] as int? ?? 0;
                    final contactPhoto = data['contactPhoto'] as String? ?? '';

                    String lastMsgTime = '';
                    final ts = data['timestamp'];
                    if (ts is Timestamp) {
                      final date = ts.toDate();
                      final now = DateTime.now();

                      final bool sameDay =
                          date.year == now.year && date.month == now.month && date.day == now.day;

                      if (sameDay) {
                        lastMsgTime =
                            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      } else {
                        lastMsgTime =
                            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
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

          // rodapé desktop
          Container(
            decoration: BoxDecoration(
              border: BoxBorder.fromSTEB(
                top: BorderSide(
                  color: theme.colorScheme.onSecondary.withOpacity(.08),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _countryCode,
                      alignment: Alignment.center,
                      style: TextStyle(color: theme.colorScheme.onSecondary),
                      icon: Icon(Icons.arrow_drop_down,
                          color: theme.colorScheme.onBackground.withOpacity(0.5)),
                      items: const [
                        DropdownMenuItem(value: '+55', child: Text('+55')),
                        DropdownMenuItem(value: '+1', child: Text('+1')),
                      ],
                      onChanged: (v) => setState(() => _countryCode = v ?? '+55'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
                        hintStyle:
                            TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.5)),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _startConversation,
                    child: const Text(
                      'Conversar',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPaneDesktop(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_selected == null) {
      return Container(
        color: _paneBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 100, color: cs.onSecondary),
              const SizedBox(height: 16),
              Text(
                'Selecione uma conversa',
                style: TextStyle(fontSize: 22, color: cs.onSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return ChatDetail(
      chatId: _selected!.id,
      chatName: _selected!.name,
      contactPhoto: _selected!.photo,
    );
  }

  Widget _softSeparator(BuildContext ctx) => Container(
        width: 1,
        color: Theme.of(ctx).colorScheme.onSecondary.withOpacity(0.08),
      );

  Widget _buildOverlayMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 56,
      top: 0,
      bottom: 0,
      width: _sideExpanded ? 280 : 0,
      child: IgnorePointer(
        ignoring: !_sideExpanded,
        child: Material(
          color: cs.surface,
          elevation: 12,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Fechar'),
                  onTap: () => setState(() => _sideExpanded = false),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _showArchived,
                  onChanged: (v) => setState(() => _showArchived = v),
                  secondary: const Icon(Icons.archive_outlined),
                  title: const Text('Mostrar concluídos'),
                ),
                SwitchListTile(
                  value: _showUnreadOnly,
                  onChanged: (v) => setState(() => _showUnreadOnly = v),
                  secondary: const Icon(Icons.mark_chat_unread_outlined),
                  title: const Text('Somente não lidas'),
                ),
                ListTile(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: const Text('Filtrar por etiquetas'),
                  onTap: () {
                    _openFilterSheet();
                    setState(() => _sideExpanded = false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_vert),
                  title: const Text('Ordenar'),
                  onTap: () {
                    _openSortSheet();
                    setState(() => _sideExpanded = false);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            _buildLeftPaneDesktop(context),
            _softSeparator(context),
            Expanded(child: _buildRightPaneDesktop(context)),
          ],
        ),
        _buildOverlayMenu(context),
      ],
    );
  }

  // ========================= TAB WIDGET =========================
  Widget _buildTab(String label, ChatTab tab, {int badge = 0}) {
    final theme = Theme.of(context);
    final selected = _currentTab == tab;

    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? theme.colorScheme.onSurface : theme.colorScheme.onSecondary,
              ),
            ),
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
