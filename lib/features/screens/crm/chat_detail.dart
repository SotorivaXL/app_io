import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as CrossAxisSize show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' as rec;
import 'package:app_io/features/screens/crm/video.dart';
import 'package:app_io/features/screens/crm/tag_manager_sheet.dart';
import 'package:app_io/features/screens/crm/contact_profile_page.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import 'package:logger/logger.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:app_io/features/screens/crm/media_composer_page.dart';
import '../../../util/video_thumb/video_thumb.dart';
import '../../../util/record_bytes/record_bytes.dart';
import 'package:collection/collection.dart';
import '../../../util/web_waveform/web_waveform.dart';
import '../../../util/web_waveform/web_waveform_widget.dart';

const String kProxyMediaEndpoint =
    'https://us-central1-app-io-1c16f.cloudfunctions.net/proxyMedia';

String proxifyMediaUrl(String url) {
  final u = url.trim();
  if (!kIsWeb) return u;
  if (kProxyMediaEndpoint.isEmpty || kProxyMediaEndpoint.startsWith('COLE_'))
    return u;
  if (!u.startsWith('http')) return u;

  final host = Uri.tryParse(u)?.host ?? '';
  final isStorage = host.contains('firebasestorage.googleapis.com') ||
      host.contains('storage.googleapis.com') ||
      host.contains('googleusercontent.com');

  // Só proxy quando for Storage/Google (onde dá CORS no Web)
  if (!isStorage) return u;

  return '$kProxyMediaEndpoint?url=${Uri.encodeComponent(u)}';
}

class AudioWaveCache {
  AudioWaveCache._(); // private ctor
  static final AudioWaveCache instance = AudioWaveCache._();

  // msgId  →  CachedAudio
  final Map<String, CachedAudio> map = {};
}

final log = Logger(printer: PrettyPrinter());

final Map<int, List<double>> _webPeaksCache = {};

class ZoomPageRoute extends PageRouteBuilder {
  final Widget page;

  ZoomPageRoute({required this.page})
      : super(
          opaque: false,
          barrierColor: Colors.black,
          // fundo já escurece
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutQuad,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.70, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

class TagItem {
  final String id;
  final String name;
  final Color color;

  const TagItem(this.id, this.name, this.color);

  factory TagItem.fromDoc(DocumentSnapshot d) =>
      TagItem(d.id, d['name'] ?? '', Color(d['color'] ?? 0xFF9E9E9E));
}

/// Tela de detalhe do chat com seleção e exclusão de mensagens.
class ChatDetail extends StatefulWidget {
  final String chatId;
  final String chatName;
  final String contactPhoto;

  const ChatDetail({
    Key? key,
    required this.chatId,
    required this.chatName,
    required this.contactPhoto,
  }) : super(key: key);

  @override
  State<ChatDetail> createState() => _ChatDetailState();
}

class _ImagePreviewPage extends StatelessWidget {
  final String content; // base64 ou URL
  final String heroTag;
  final String sender; // ex.: “Você” ou “Maria”
  final String sentAt; // ex.: “18 de julho 15:03”

  const _ImagePreviewPage({
    Key? key,
    required this.content,
    required this.heroTag,
    required this.sender,
    required this.sentAt,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = content.startsWith('http')
        ? NetworkImage(proxifyMediaUrl(content))
        : MemoryImage(base64Decode(content));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /* imagem com zoom */
          Center(
            child: InteractiveViewer(
              minScale: .8,
              maxScale: 4,
              child: Image(image: provider),
            ),
          ),

          /* barra superior (voltar + remetente + hora) */
          SafeArea(
            child: Container(
              height: kToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.black.withOpacity(.40), // leve transparência
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sender,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      Text(sentAt,
                          style: TextStyle(
                              color: Colors.white.withOpacity(.85),
                              fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatDetailState extends State<ChatDetail> {
  final Map<String, Uint8List> _videoThumbMem = {};
  final Map<String, Future<Uint8List?>> _videoThumbFuture = {};

  final Map<String, double> _videoDlProgress = {}; // 0..1
  final Set<String> _videoDownloading = {}; // msgId em download
  final Map<String, String> _videoLocalCachePath = {}; // msgId -> path local

  Future<String?> _ensureVideoCached(String msgId, String videoUrl) async {
    // Web: não fazemos download completo aqui (streaming), só retorna URL original
    if (kIsWeb) return videoUrl;

    // se não for URL http, já é caminho local / base64 etc
    if (!videoUrl.startsWith('http')) return videoUrl;

    // se já cacheamos esse msgId
    final cached = _videoLocalCachePath[msgId];
    if (cached != null && cached.isNotEmpty && await File(cached).exists()) {
      return cached;
    }

    // marca “baixando”
    if (mounted) {
      setState(() {
        _videoDownloading.add(msgId);
        _videoDlProgress[msgId] = 0.0;
      });
    }

    try {
      // usa cache manager (salva em disco e reaproveita)
      final stream = cache.DefaultCacheManager()
          .getFileStream(videoUrl, withProgress: true);

      String? localPath;

      await for (final event in stream) {
        if (event is cache.DownloadProgress) {
          final total = event.totalSize ?? 0;
          final downloaded = event.downloaded;
          final p = (total > 0) ? (downloaded / total) : 0.0;

          if (mounted) {
            setState(() {
              _videoDlProgress[msgId] = p.clamp(0.0, 1.0).toDouble();
            });
          }
        } else if (event is cache.FileInfo) {
          localPath = event.file.path;
          break;
        }
      }

      if (localPath != null) {
        _videoLocalCachePath[msgId] = localPath;
      }

      return localPath ?? videoUrl;
    } catch (_) {
      // falhou baixar -> tenta tocar via URL mesmo
      return videoUrl;
    } finally {
      if (mounted) {
        setState(() {
          _videoDownloading.remove(msgId);
          _videoDlProgress.remove(msgId);
        });
      }
    }
  }

  Future<Uint8List?> _getOrCreateVideoThumb(String msgId, String videoUrl) {
    // já tem em memória
    if (_videoThumbMem.containsKey(msgId)) {
      return Future.value(_videoThumbMem[msgId]);
    }

    // evita disparar várias vezes
    if (_videoThumbFuture.containsKey(msgId)) {
      return _videoThumbFuture[msgId]!;
    }

    final fut = () async {
      try {
        // para gerar thumb no Web via bytes, precisamos baixar o vídeo
        // use proxy APENAS para download (CORS), não para playback
        final fetchUrl = proxifyMediaUrl(videoUrl);

        // ⚠️ se o vídeo for grande, isso pode ser pesado.
        // mas é o “mínimo” sem mexer no backend.
        final resp = await http.get(Uri.parse(fetchUrl));
        if (resp.statusCode != 200) return null;

        final bytes = resp.bodyBytes;

        // limite de segurança (ajuste se quiser)
        const maxThumbSource = 25 * 1024 * 1024; // 25MB
        if (bytes.length > maxThumbSource) return null;

        Uint8List? thumb;
        if (kIsWeb) {
          thumb = await generateVideoThumbWeb(bytes);
        } else {
          // mobile/desktop: salva temp e gera thumb
          final dir = await getTemporaryDirectory();
          final tmp = p.join(dir.path, 'vid_$msgId.mp4');
          await File(tmp).writeAsBytes(bytes, flush: true);

          thumb = await VideoThumbnail.thumbnailData(
            video: tmp,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 480,
            quality: 75,
          );

          try {
            await File(tmp).delete();
          } catch (_) {}
        }

        if (thumb != null) {
          _videoThumbMem[msgId] = thumb;
        }
        return thumb;
      } catch (_) {
        return null;
      }
    }();

    _videoThumbFuture[msgId] = fut;
    return fut;
  }

  bool get _isDesktop {
    final w = MediaQuery.maybeOf(context)?.size.width ?? 0;
    return w >= 1200;
  }

  double _bubbleMaxWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;

    // WhatsApp-like: bolhas mais estreitas
    final frac = _isDesktop ? .46 : .76;
    final cap = _isDesktop ? 520.0 : 460.0;

    return CrossAxisSize.min(w * frac, cap);
  }

  final Map<String, bool> _expandedText = {};

  double get _sideGutter => _isDesktop ? 72.0 : 12.0;
  String? _companyId;
  String? _phoneId;
  String _myAvatarUrl = '';
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _recordCanceled = false;
  bool _recPaused = false; // NOVO

  /* ------------- controle de mensagens ------------- */
  final _messageController = TextEditingController();
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  bool _showEmojiPicker = false;
  bool _isRecording = false;
  late String _recordPath;
  final _audioCache = AudioWaveCache.instance.map;
  StreamSubscription? _preloadSub;
  bool _preloaded = false;

  /* ------------- seleção de mensagens ------------- */
  bool selectionMode = false;
  final Set<String> selectedMessageIds = {};
  final Map<String, bool> _messageFromMeMap = {};

  /* ------------- TAGS ------------- */
  final Map<String, TagItem> _tagMap = {}; // id → TagItem (todas da empresa)
  List<TagItem> _chatTags = []; // tags atribuídas a ESTE chat
  StreamSubscription? _tagSub;
  StreamSubscription? _chatSub;

  /* ------------- STREAM de mensagens ------------- */
  Stream<QuerySnapshot> get _messagesStream => FirebaseFirestore.instance
      .collection('empresas')
      .doc(_companyId)
      .collection('phones')
      .doc(_phoneId)
      .collection('whatsappChats')
      .doc(widget.chatId)
      .collection('messages')
      .orderBy('timestamp', descending: true)
      .snapshots();

  Future<Uint8List?> _makeVideoThumb(XFile picked, Uint8List videoBytes) async {
    if (kIsWeb) {
      // Web: gera via <video> + canvas
      return await generateVideoThumbWeb(videoBytes);
    } else {
      // Mobile/Desktop: gera via plugin
      return await VideoThumbnail.thumbnailData(
        video: picked.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480, // bom p/ preview
        quality: 75,
      );
    }
  }

  /* ------------- INIT ------------- */
  @override
  void initState() {
    super.initState();
    _loadIds();
    _preloadSub = _messagesStream.listen((qs) {
      _precacheAudios(qs);
      if (_preloaded) _preloadSub?.cancel(); // 🔌
    });
  }

  Widget _collapsibleText(String msgId, String text) {
    // heurística simples: mostra botão se for grandinho
    final needsMore = text.trim().length > 240 || text.split('\n').length > 8;
    final expanded = _expandedText[msgId] ?? false;

    final body = Text(
      text,
      style: const TextStyle(fontSize: 15),
      maxLines: expanded ? null : 10, // limite de linhas
      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
    );

    if (!needsMore) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _expandedText[msgId] = !expanded),
          child: Text(
            expanded ? 'Ver menos' : 'Ler mais',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
          ),
        ),
      ],
    );
  }

  void _precacheAudios(QuerySnapshot qs) async {
    if (kIsWeb) return;

    for (final doc in qs.docs) {
      if (doc['type'] != 'audio') continue;

      final id = doc.id;
      final cont = doc['content'] as String;

      if (_audioCache.containsKey(id)) continue;

      final path = await _obterArquivoLocal(cont);

      final pc = aw.PlayerController();

      // ✅ extrai waveform e já prepara o player
      await pc.preparePlayer(
        path: path,
        shouldExtractWaveform: true,
        noOfSamples: 90, // ajuda performance e evita “travado”
      );

      // ✅ pega duração pelo próprio PlayerController (sem ExoPlayer)
      final maxMs = await pc.getDuration(aw.DurationType.max);
      final dur = Duration(milliseconds: maxMs > 0 ? maxMs : pc.maxDuration);

      _audioCache[id] = CachedAudio(path, dur, pc);
    }

    _preloaded = true;
    if (mounted) setState(() {});
  }

  Future<String> _obterArquivoLocal(String content) async {
    if (content.startsWith('http')) {
      final file = await cache.DefaultCacheManager().getSingleFile(content);
      return file.path;
    } else {
      final raw = _clean(content);
      final bytes = base64Decode(raw);

      final ext = _audioExtFromBytes(bytes);

      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'snd_${DateTime.now().microsecondsSinceEpoch}_${content.hashCode}$ext',
      );

      await File(path).writeAsBytes(bytes);
      return path;
    }
  }

  Future<void> _loadIds() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final empRef = FirebaseFirestore.instance.collection('empresas').doc(uid);

    // Lê users/{uid} só para saber se É colaborador
    final userSnap = await usersRef.get();
    final Map<String, dynamic> userData =
        (userSnap.data() as Map<String, dynamic>?) ?? {};
    final String? createdBy = (userData['createdBy'] as String?)?.trim();

    // ✔️ colaborador somente se tem createdBy não-vazio
    final bool isCollaborator = createdBy != null && createdBy.isNotEmpty;

    // companyId: colaborador herda createdBy; dono usa o próprio uid
    _companyId = isCollaborator ? createdBy : uid;

    // tenta ler defaultPhoneId do local certo (sem criar nada)
    if (isCollaborator) {
      _phoneId = userData['defaultPhoneId'] as String?;
    } else {
      final empSnap = await empRef.get();
      _phoneId = (empSnap.data()?['defaultPhoneId'] as String?);
    }

    // se não houver phoneId, pega o 1º da empresa (e persiste com update seguro)
    if (_phoneId == null) {
      final phonesCol = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('phones');

      final q = await phonesCol.limit(1).get();
      if (q.docs.isNotEmpty) {
        _phoneId = q.docs.first.id;

        try {
          if (isCollaborator) {
            // só atualiza se o doc de users já existir – não cria!
            if (userSnap.exists) {
              await usersRef.update({'defaultPhoneId': _phoneId});
            }
          } else {
            // dono: persiste em empresas/{uid} (update não cria)
            await empRef.update({'defaultPhoneId': _phoneId});
          }
        } catch (_) {
          // ignora not-found/permission – não criar nada aqui
        }
      }
    }

    if (_phoneId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Nenhum número encontrado.\nCadastre um telefone em Configurações.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {}); // libera UI

    _initTags(); // usa _companyId
    _markIncomingAsRead(); // usa _companyId/_phoneId
    _fetchMyAvatar();
  }

  Future<void> _fetchMyAvatar() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // 1. tenta na coleção de usuários
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    String url = userSnap.data()?['photoUrl'] ?? '';

    // 2. se vazio, tenta na coleção de empresas
    if (url.isEmpty && _companyId != null) {
      final compSnap = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .get();
      url = compSnap.data()?['photoUrl'] ?? '';
    }

    if (mounted) setState(() => _myAvatarUrl = url);
  }

  Future<void> _markIncomingAsRead() async {
    final batch = FirebaseFirestore.instance.batch();
    final q = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId)
        .collection('messages')
        .where('fromMe', isEqualTo: false)
        .where('read', isEqualTo: false)
        .get();

    for (final d in q.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();

    // dispara para Z-API (caso deseje baixar os 2 ✓ no telefone do lead)
    _sendMarkReadToZapi();
  }

  Future<void> _sendMarkReadToZapi() async {
    // dispara a própria Cloud Function sendMessage
    final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');

    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'empresaId': _companyId,
          'phoneId': _phoneId,
          'chatId': widget.chatId, // o mesmo ID que já usa no app
          'fileType': 'read' // sinaliza que é apenas “marcar como lido”
        }),
      );
    } catch (e) {
      debugPrint('Erro ao marcar como lido: $e');
    }
  }

  /// Depois que o operador responde, move o chat para "Atendendo"
  Future<void> _markChatAsAttended() async {
    final uid = FirebaseAuth.instance.currentUser!.uid; //  <<< adição

    final chatRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId);

    await chatRef.set({
      'opened': true,
      // 'status': 'atendendo',
      'updatedBy': uid, //  <<< adição
      'updatedAt': FieldValue.serverTimestamp(), //  <<< adição
    }, SetOptions(merge: true));

    // (opcional) salva no histórico ─ só se você quiser
    await chatRef.collection('history').add({
      // 'status': 'atendendo',
      'saleValue': null,
      'changedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid, //  <<< adição
    });
  }

  Future<void> _initTags() async {
    // 1) ouvir TODAS as tags da empresa
    final tagCol = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('tags');

    void _refreshChatTags() {
      final ids = _chatTags.map((t) => t.id);
      _chatTags =
          ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();
    }

    _tagSub = tagCol.orderBy('name').snapshots().listen((qs) {
      if (!mounted) return;
      setState(() {
        _tagMap
          ..clear()
          ..addEntries(qs.docs.map((d) => MapEntry(d.id, TagItem.fromDoc(d))));
        _refreshChatTags();
      });
    });

    // 2) ouvir o próprio chat para saber ids atribuídos
    _chatSub = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final ids = List<String>.from(data['tags'] ?? const []);
      setState(() {
        _chatTags =
            ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();
      });
    });
  }

  @override
  void dispose() {
    _preloadSub?.cancel();
    _tagSub?.cancel();
    _chatSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    if (kIsWeb) {
      // No Web, a permissão vem do próprio plugin (getUserMedia)
      return await _recorder.hasPermission();
    }

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  // INÍCIO DE GRAVAÇÃO DE ÁUDIO
  Future<void> _startRecording() async {
    if (!await _ensureMicPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de microfone negada')),
        );
      }
      return;
    }

    final cfg = rec.RecordConfig(
      encoder: kIsWeb ? rec.AudioEncoder.opus : rec.AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );

    if (kIsWeb) {
      // ✅ no Web o plugin ainda exige um "path" (use um nome virtual)
      _recordPath = 'rec_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _recorder.start(cfg, path: _recordPath);
    } else {
      final dir = await getTemporaryDirectory();
      _recordPath =
          p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

      await _recorder.start(cfg, path: _recordPath);
    }

    _recordCanceled = false;
    _recElapsed = Duration.zero;

    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recElapsed += const Duration(seconds: 1));
    });

    _recPaused = false;
    setState(() => _isRecording = true);
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    _recordCanceled = true;
    final pathOrUrl = await _recorder.stop();

    _recTimer?.cancel();
    _recPaused = false;
    setState(() => _isRecording = false);

    if (pathOrUrl == null) return;

    if (!kIsWeb) {
      await deleteLocalIfExists(pathOrUrl);
    } else {
      await revokeIfBlobUrl(pathOrUrl);
    }
  }

  // TÉRMINO DE GRAVAÇÃO E ENVIO
  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    final pathOrUrl = await _recorder.stop();

    _recTimer?.cancel();
    _recPaused = false;
    setState(() => _isRecording = false);

    if (_recordCanceled || pathOrUrl == null) {
      if (pathOrUrl != null && kIsWeb) await revokeIfBlobUrl(pathOrUrl);
      return;
    }

    try {
      final bytes = await readRecordedBytes(pathOrUrl);
      final base64Audio = base64Encode(bytes);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final r = await http.post(
        Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'empresaId': _companyId,
          'phoneId': _phoneId,
          'chatId': widget.chatId,
          'message': '',
          'fileType': 'audio',
          'fileData': base64Audio,
          'senderType': 'human',
          'senderUid': uid,
        }),
      );

      if (kIsWeb) {
        await revokeIfBlobUrl(pathOrUrl);
      } else {
        // opcional: se você quiser deletar o arquivo local após enviar
        // await deleteLocalIfExists(pathOrUrl);
      }

      if (r.statusCode == 200) {
        await _markChatAsAttended();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falha ao enviar áudio')),
          );
        }
      }
    } catch (e) {
      if (kIsWeb) await revokeIfBlobUrl(pathOrUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar áudio: $e')),
        );
      }
    }
  }

  Future<void> _togglePauseResume() async {
    // NOVO
    if (!_isRecording) return;
    if (!_recPaused) {
      await _recorder.pause();
      _recPaused = true;
      _recTimer?.cancel();
    } else {
      await _recorder.resume();
      _recPaused = false;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recElapsed += const Duration(seconds: 1));
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickVideo({required bool fromCamera}) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    const maxBytes = 15 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vídeo muito grande. Envie até 15MB.')),
        );
      }
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaComposerPage(
          empresaId: _companyId!,
          phoneId: _phoneId!,
          chatId: widget.chatId,
          initial: [
            PendingMedia(
              fileName: picked.name,
              type: PendingMediaType.video,
              bytes: bytes,
            ),
          ],
          onSentOk: _markChatAsAttended,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true, // importante no Web
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;

    final base64File = base64Encode(bytes);
    final fileName = file.name;

    try {
      final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'empresaId': _companyId,
          'phoneId': _phoneId,
          'chatId': widget.chatId,
          'message': '',
          'fileType': 'file',
          'fileName': fileName,
          'fileData': base64File,
        }),
      );

      if (response.statusCode == 200) {
        await _markChatAsAttended();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao enviar arquivo')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  // Escolhe imagem (da galeria ou câmera)
  Future<void> _pickImage({required bool fromCamera}) async {
    final picker = ImagePicker();

    final XFile? pickedFile = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem muito grande. Envie até 8MB.')),
        );
      }
      return;
    }

    // ✅ abre a tela de pré-visualização
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaComposerPage(
          empresaId: _companyId!,
          phoneId: _phoneId!,
          chatId: widget.chatId,
          initial: [
            PendingMedia(
              fileName: pickedFile.name,
              type: PendingMediaType.image,
              bytes: bytes,
            ),
          ],
          onSentOk: _markChatAsAttended, // mantém seu fluxo
        ),
      ),
    );
  }

  void _showDeleteOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            "Excluir Mensagens",
          ),
          content: Text("Deseja realmente excluir as mensagens?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteSelectedMessagesForMe(); // Chamando local ou via function
              },
              child: const Text("Excluir"),
            ),
          ],
        );
      },
    );
  }

  void _openAttachOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.image),
                iconColor: Theme.of(context).colorScheme.onSecondary,
                title: Text("Galeria",
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(fromCamera: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                iconColor: Theme.of(context).colorScheme.onSecondary,
                title: Text("Câmera",
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(fromCamera: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    try {
      final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
        'empresaId': _companyId,
        'phoneId': _phoneId,
        'chatId': widget.chatId,
        'message': text,
        'fileType': 'text',

        // ✅ NOVO
        'senderType': 'human',
        'senderUid': uid,
      }),
      );
      if (response.statusCode == 200) {
        await _markChatAsAttended(); // move para “Atendendo”
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar mensagem')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  // Função para deletar mensagens para "mim" (exclusão local)
  Future<void> _deleteSelectedMessagesForMe() async {
    final chatDocRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId);

    // 1) Exclui as mensagens selecionadas do sub-collection
    for (final msgId in selectedMessageIds) {
      await chatDocRef.collection('messages').doc(msgId).delete();
    }

    setState(() {
      selectedMessageIds.clear();
      selectionMode = false;
    });

    // 2) Busca a nova última mensagem no chat
    final query = await chatDocRef
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      // Se houver mensagens restantes, usamos a última mensagem como referência
      final lastDoc = query.docs.first;
      final lastData = lastDoc.data();

      final newLastMessage = lastData['content'] ?? '';
      final lastTimestamp = lastData['timestamp'];
      String newLastTime = '';

      if (lastTimestamp is Timestamp) {
        final date = lastTimestamp.toDate();
        newLastTime =
            "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
      }

      // Atualiza o documento do chat com a última mensagem, horário e também atualiza o 'timestamp' para o timestamp da última mensagem
      await chatDocRef.set({
        'lastMessage': newLastMessage,
        'lastMessageTime': newLastTime,
        'timestamp': lastTimestamp,
      }, SetOptions(merge: true));
    } else {
      // Se não houver mais mensagens, limpa os campos e atualiza o 'timestamp' com o horário atual
      await chatDocRef.set({
        'lastMessage': '',
        'lastMessageTime': '',
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // Função para deletar mensagens para "todos" (via API + exclusão no Firestore)
  Future<void> _deleteSelectedMessagesForEveryone() async {
    for (final msgId in selectedMessageIds) {
      try {
        final url = Uri.parse(
          'https://us-central1-app-io-1c16f.cloudfunctions.net/deleteMessage',
        );
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'empresaId': _companyId,
            'phoneId': _phoneId,
            'chatId': widget.chatId,
            'docId': msgId, // <-- aqui troquei para 'docId': ...
            'owner': true, // se você quer sempre apagar 'para todos'
          }),
        );

        if (response.statusCode == 200) {
          await FirebaseFirestore.instance
              .collection('empresas')
              .doc(_companyId)
              .collection('phones')
              .doc(_phoneId)
              .collection('whatsappChats')
              .doc(widget.chatId)
              .collection('messages')
              .doc(msgId)
              .delete();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao deletar para todos: $e')),
        );
      }
    }

    setState(() {
      selectedMessageIds.clear();
      selectionMode = false;
    });
  }

  // AppBar customizada: modo seleção ou padrão
  PreferredSizeWidget _buildAppBar() {
    /* --- abre o perfil do contato --- */
    void _openProfile() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContactProfilePage(
            chatId: widget.chatId,
            name: widget.chatName,
            photoUrl: widget.contactPhoto,
          ),
        ),
      );
    }

    /* ────────────────────────────
   * 1) MODO SELEÇÃO
   * ──────────────────────────── */
    if (selectionMode) {
      return AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
                  selectionMode = false;
                  selectedMessageIds.clear();
                }),
            color: Theme.of(context).colorScheme.onSecondary),
        title: Text('${selectedMessageIds.length} selecionado(s)',
            style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Excluir',
            onPressed: _showDeleteOptions,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
          IconButton(
            icon: const Icon(Icons.sell_outlined),
            tooltip: 'Etiquetas',
            onPressed: _openTagManager,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.secondary,
        surfaceTintColor: Colors.transparent,
      );
    }

    /* ────────────────────────────
   * 2) MODO NORMAL
   * ──────────────────────────── */
    return AppBar(
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.secondary,
      foregroundColor: Theme.of(context).colorScheme.onSecondary,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leadingWidth: 40,

      /* ← seta voltar */
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new),
        onPressed: () => Navigator.pop(context),
      ),

      /* -------- título (tap → perfil) -------- */
      title: InkWell(
        onTap: _openProfile,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            /* foto / avatar */
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.inverseSurface,
              backgroundImage: widget.contactPhoto.isNotEmpty
                  ? NetworkImage(widget.contactPhoto)
                  : null,
              child: widget.contactPhoto.isEmpty
                  ? Icon(Icons.person,
                      size: 20, color: Theme.of(context).colorScheme.outline)
                  : null,
            ),
            const SizedBox(width: 12),

            /* nome + chips de tags */
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /* nome */
                  Text(
                    widget.chatName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),

                  /* tags: mostra 2 + "+N" */
                  if (_chatTags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Builder(
                      builder: (_) {
                        final displayTags = _chatTags.take(1).toList();
                        final extra = _chatTags.length - displayTags.length;

                        return Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            ...displayTags.map((tag) {
                              final onDark =
                                  ThemeData.estimateBrightnessForColor(
                                          tag.color) ==
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
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    color: onDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              );
                            }),
                            if (extra > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                child: Text(
                                  '+$extra',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onBackground,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      /* -------- ações -------- */
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.sell_outlined),
                tooltip: 'Etiquetas',
                onPressed: _openTagManager,
              ),
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Concluir',
                onPressed:
                    _confirmFinishFlow, // ← chama só o fluxo de conclusão
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, String>>> _fetchProducts() async {
    final qs = await FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId) // já preenchido na tela
        .collection('produtos')
        .orderBy('nome') // ou outro campo
        .get();

    return qs.docs
        .map((d) => {
              'id': d.id,
              'nome': (d['nome'] ?? '—') as String,
            })
        .toList();
  }

  /*───────────────────────────────────────────────────────────────*/
/* 2. Fluxo de conclusão – versão definitiva                     */
/*───────────────────────────────────────────────────────────────*/
  Future<void> _confirmFinishFlow() async {
    bool? sale; // <-- agora é visível depois do diálogo
    String? produtoId, produtoNome;
    final valorCtrl = MoneyMaskedTextController(
      leftSymbol: 'R\$ ',
      decimalSeparator: ',',
      thousandSeparator: '.',
    );
    String? motivoNv;
    /* — 1. Confirmação simples — */
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            'Concluir atendimento',
            style: TextStyle(color: cs.onSecondary),
          ),
          content: Text(
            'Deseja realmente concluir este atendimento?',
            style: TextStyle(color: cs.onSecondary),
          ),
          actions: [
            // botão “Cancelar”
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),

            // botão “Concluir”
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0, // sem sombra (opcional)
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Concluir'),
            ),
          ],
        );
      },
    );
    if (sure != true) return; // usuário desistiu

    const motivosNv = [
      'Não interagiu',
      'Pesquisando valores',
      'Clicou no anúncio sem querer',
      'Parou de responder',
      'Valor muito alto',
    ];

    // carrega produtos REAIS da empresa
    final produtos = await _fetchProducts(); // id / nome

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final formKey = GlobalKey<FormState>();

        return StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            title: const Text('Houve venda neste atendimento?'),
            content: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─────────── radios ───────────
                  RadioListTile<bool>(
                    value: true,
                    groupValue: sale,
                    onChanged: (v) => setModal(() => sale = v),
                    title: Text('Sim, houve venda',
                        style: TextStyle(color: cs.onSecondary)),

                    // ======= ESTILO ORIGINAL =======
                    activeColor: cs.primary,
                    // pontinho cheio
                    fillColor: MaterialStateProperty.resolveWith<Color>(
                      (states) {
                        // quando NÃO selecionado
                        if (!states.contains(MaterialState.selected)) {
                          return cs.onSecondary
                              .withOpacity(0.54); // argola vazia
                        }
                        // quando selecionado
                        return cs.primary;
                      },
                    ),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: sale,
                    onChanged: (v) => setModal(() => sale = v),
                    title: Text('Não, sem venda',
                        style: TextStyle(color: cs.onSecondary)),
                    activeColor: cs.primary,
                    fillColor: MaterialStateProperty.resolveWith<Color>(
                      (states) {
                        // quando NÃO selecionado
                        if (!states.contains(MaterialState.selected)) {
                          return cs.onSecondary
                              .withOpacity(0.54); // argola vazia
                        }
                        // quando selecionado
                        return cs.primary;
                      },
                    ),
                  ),

                  // ─────────── campos dependentes ───────────
                  if (sale == true) ...[
                    const SizedBox(height: 12),
                    // VALOR
                    TextFormField(
                      controller: valorCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Valor da venda',
                        filled: true,
                        fillColor: cs.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (_) =>
                          valorCtrl.numberValue == 0 ? 'Informe o valor' : null,
                    ),
                    const SizedBox(height: 12),
                    // PRODUTO
                    DropdownButtonFormField2<String>(
                      value: produtoId,
                      isExpanded: true,

                      // ========= ESTILO ORIGINAL =========
                      hint: Text(
                        'Produto vendido',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSecondary.withOpacity(0.54),
                          height: 1,
                        ),
                      ),
                      buttonStyleData: ButtonStyleData(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      dropdownStyleData: DropdownStyleData(
                        decoration: BoxDecoration(
                          color: cs.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // ===================================

                      items: produtos
                          .map((p) => DropdownMenuItem<String>(
                                value: p['id'],
                                child: Text(p['nome']!,
                                    style: TextStyle(color: cs.onSecondary)),
                              ))
                          .toList(),
                      onChanged: (v) => setModal(() {
                        produtoId = v;
                        produtoNome =
                            produtos.firstWhere((e) => e['id'] == v)['nome'];
                      }),
                      validator: (v) => sale == true && v == null
                          ? 'Selecione o produto'
                          : null,

                      decoration: const InputDecoration(
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ] else if (sale == false) ...[
                    const SizedBox(height: 12),
                    // MOTIVO NÃO-VENDA
                    DropdownButtonFormField2<String>(
                      value: motivoNv,
                      isExpanded: true,
                      hint: Text(
                        'Qual o motivo de não ter venda?',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSecondary.withOpacity(0.54),
                          height: 1,
                        ),
                      ),
                      buttonStyleData: ButtonStyleData(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      dropdownStyleData: DropdownStyleData(
                        decoration: BoxDecoration(
                          color: cs.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: motivosNv
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m,
                                    style: TextStyle(color: cs.onSecondary)),
                              ))
                          .toList(),
                      onChanged: (v) => setModal(() => motivoNv = v),
                      validator: (v) => v == null ? 'Selecione o motivo' : null,
                      decoration: const InputDecoration(
                        filled: true,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ─────────── botões ───────────
            actions: [
              // ───────────── BOTÃO VOLTAR ─────────────
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(110, 42), // altura + largura mín.
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Voltar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

              // ───────────── BOTÃO SALVAR ─────────────
              ElevatedButton(
                onPressed: () {
                  // mesma lógica de antes
                  if (sale == false) {
                    Navigator.pop(
                        ctx, true); // usuário marcou “não houve venda”
                  } else if (sale == true && formKey.currentState!.validate()) {
                    Navigator.pop(
                        ctx, true); // marcou “venda” e o form é válido
                  }
                },
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  // sem sombra
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(110, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Salvar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return; // usuário cancelou

    /* — 3. Persiste no Firestore — */
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final chatRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(_companyId)
        .collection('phones')
        .doc(_phoneId)
        .collection('whatsappChats')
        .doc(widget.chatId);

    final double? valor = (sale == true) ? valorCtrl.numberValue : null;

    await chatRef.set({
      'status': (sale == true) ? 'concluido_com_venda' : 'recusado',
      'saleValue': valor,
      'productId': produtoId,
      'productName': produtoNome,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'noSaleReason': (sale == true) ? null : motivoNv,
    }, SetOptions(merge: true));

    await chatRef.collection('history').add({
      'status': (sale == true) ? 'concluido_com_venda' : 'recusado',
      'saleValue': valor,
      'productId': produtoId,
      'productName': produtoNome,
      'changedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'empresaId': _companyId, // ← novo
      'phoneId': _phoneId, // ← novo
      'noSaleReason': (sale == true) ? null : motivoNv,
    });

    /* — 4. Volta para a lista de chats — */
    if (mounted) Navigator.pop(context);
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

  Widget _readIcon(Map<String, dynamic> msg, BuildContext ctx) {
    if (!(msg['fromMe'] as bool? ?? false)) return const SizedBox();
    final bool isRead = msg['read'] == true;

    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Icon(
        Icons.done_all,
        size: 16,
        color: isRead
            ? Theme.of(ctx).colorScheme.onError // roxo
            : Theme.of(ctx).colorScheme.tertiaryContainer, // cinza
      ),
    );
  }

    // ✅ Badge minimalista: mostra se foi BOT ou HUMANO (quando existir senderType/senderName)
  Widget _senderBadge(Map<String, dynamic> data) {
    final cs = Theme.of(context).colorScheme;

    final senderType = (data['senderType'] as String? ?? '').trim();
    final senderName = (data['senderName'] as String? ?? '').trim();

    if (senderType.isEmpty) return const SizedBox.shrink();
    if (senderType == 'lead') return const SizedBox.shrink(); // não poluir msg do cliente
    if (senderType == 'system') return const SizedBox.shrink();

    String label;
    if (senderType == 'ai') {
      label = '🤖 ${senderName.isNotEmpty ? senderName : 'Bot'}';
    } else if (senderType == 'human') {
      label = senderName.isNotEmpty ? '👤 $senderName' : '👤 Atendente';
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.0,
          color: cs.onSecondary.withOpacity(.55),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }


  // Constrói a bolha de mensagem com suporte à seleção
  Widget _buildMessageBubble(String msgId, Map<String, dynamic> data) {
    final caption = (data['caption'] as String? ?? '').trim();
    final content = data['content'] as String? ?? '';
    final type = data['type'] as String? ?? 'text';
    final fromMe = data['fromMe'] as bool? ?? false;
    final timestamp = data['timestamp'];
    String timeString = '';

    _messageFromMeMap[msgId] = fromMe;

    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      timeString =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final isSelected = selectedMessageIds.contains(msgId);

    /*═════════════════════════════════════════════════════════════════════
   * 2. Monta o widget da mensagem (texto / imagem / áudio …)
   *════════════════════════════════════════════════════════════════════*/

    // -----SYSTEM -------------------------------------------------------  ✅
    if (type == 'system') {
      final label = data['content'] as String? ?? '';
      return _buildSystemMarker(label, timestamp);
    }

    // ----- TEXTO -------------------------------------------------------  ✅
    if (type == 'text') {
      return _buildRegularBubble(
        msgId: msgId,
        data: data, // ✅ novo
        inner: _collapsibleText(msgId, content),
        fromMe: fromMe,
        timeString: timeString,
        isSelected: isSelected,
        read: data['read'] == true,
      );
    }


    // ----- IMAGEM / FIGURINHA -----------------------------------------  ✅
    if (type == 'image' || type == 'sticker') {
      final heroTag = '$msgId-$type';

      // provider + aspect cache
      final ImageProvider provider = content.startsWith('http')
          ? NetworkImage(proxifyMediaUrl(content))
          : MemoryImage(base64Decode(content));

      // aquece o aspect ratio (w/h)
      _warmAspect(msgId, provider);

      final maxW = _isDesktop ? 360.0 : 280.0;
      final maxH = _isDesktop ? 420.0 : 360.0;

      final aspect = _mediaAspect[msgId];
      final box =
          _fitMediaBox(maxW: maxW, maxH: maxH, aspect: aspect, minW: 170.0);

      Widget img = SizedBox(
        width: box.width,
        height: box.height,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: 34),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      );

      // sticker: mantém “ícone”
      if (type == 'sticker') {
        img = Stack(
          children: [
            img,
            Positioned(
              bottom: 8,
              left: 8,
              child: Icon(Icons.emoji_emotions,
                  size: 18, color: Colors.white.withOpacity(.85)),
            ),
          ],
        );
      }

      return _buildMediaBubble(
      msgId: msgId,
      data: data, // ✅ novo
      fromMe: fromMe,
      read: data['read'] == true,
      isSelected: isSelected,
      timeString: timeString,
      caption: caption,
      mediaWidth: box.width,
      mediaHeight: box.height,
      mediaChild: Hero(tag: heroTag, child: img),
      onOpen: () {
        Navigator.of(context).push(
          ZoomPageRoute(
            page: _ImagePreviewPage(
              content: content,
              heroTag: heroTag,
              sender: fromMe ? 'Você' : widget.chatName,
              sentAt: (timestamp is Timestamp)
                  ? DateFormat("d 'de' MMMM HH:mm", 'pt_BR')
                      .format(timestamp.toDate())
                  : '',
            ),
          ),
        );
      },
    );
    }

    if (type == 'audio') {
      final cached = _audioCache[msgId];
      final audioWidget = AudioMessageBubble(
        key: ValueKey(content),
        base64Audio: content,
        isFromMe: fromMe,
        sentTime: timeString,
        avatarUrl: fromMe ? _myAvatarUrl : widget.contactPhoto,
        senderType: data['senderType'] as String?,
        senderName: data['senderName'] as String?,
        preloadedPath: cached?.localPath,
        preloadedWave: cached?.wave,
        preloadedDur: cached?.total,
      );

      return GestureDetector(
        onLongPress: () {
          setState(() {
            selectionMode = true;
            selectedMessageIds.add(msgId);
          });
        },
        onTap: () {
          if (selectionMode) {
            setState(() {
              if (isSelected) {
                selectedMessageIds.remove(msgId);
                if (selectedMessageIds.isEmpty) selectionMode = false;
              } else {
                selectedMessageIds.add(msgId);
              }
            });
          }
        },

        // highlight azul
        child: Container(
          color: (selectionMode && isSelected)
              ? Colors.blue.withOpacity(.30)
              : Colors.transparent,
          padding: const EdgeInsets.all(5),

          // só alinhamento + largura máx.
          child: Align(
            alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _bubbleMaxWidth(context), // antes: width * .60
              ),
              child: audioWidget,
            ),
          ),
        ),
      );
    }

    // ----- VÍDEO ou outros -------------------------------------------- ✅
    if (type == 'video') {
      final media = (data['media'] is Map)
          ? Map<String, dynamic>.from(data['media'])
          : null;

      final thumb = (media?['thumbUrl'] ??
          media?['thumbnailUrl'] ??
          media?['previewUrl']) as String?;

      final thumbUrl = (thumb != null && thumb.trim().isNotEmpty)
          ? proxifyMediaUrl(thumb)
          : null;

      final videoUrl = content; // não proxifica playback

      final maxW = _isDesktop ? 360.0 : 280.0;
      final maxH = _isDesktop ? 420.0 : 360.0;

// ✅ largura/altura que vamos usar na bolha
      double mediaWidth = 260.0;
      double mediaHeight = 160.0;

      Widget thumbChild;

      if (thumbUrl != null) {
        final provider = NetworkImage(thumbUrl);
        _warmAspect('thumb_$msgId', provider);

        final aspect = _mediaAspect['thumb_$msgId'];
        final box =
            _fitMediaBox(maxW: maxW, maxH: maxH, aspect: aspect, minW: 190.0);

        mediaWidth = box.width;
        mediaHeight = box.height;

        // ✅ NÃO prende size aqui, deixa o SizedBox externo mandar
        thumbChild = Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.black45),
        );
      } else {
        thumbChild = FutureBuilder<Uint8List?>(
          future: _getOrCreateVideoThumb(msgId, videoUrl),
          builder: (_, snap) {
            final b = snap.data;
            if (b == null) {
              return const ColoredBox(color: Colors.black45);
            }
            return Image.memory(b, fit: BoxFit.cover);
          },
        );
      }

// ✅ Stack expandindo 100% na área do preview
      final videoThumbStack = SizedBox(
        width: mediaWidth,
        height: mediaHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbChild,
            Center(
              child: Icon(Icons.play_circle_fill,
                  size: 56, color: Colors.white.withOpacity(.92)),
            ),
            if (_videoDownloading.contains(msgId))
              Container(
                color: Colors.black.withOpacity(.45),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        value: (_videoDlProgress[msgId] ?? 0.0) > 0
                            ? (_videoDlProgress[msgId] ?? 0.0)
                            : null,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(.95),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (_videoDlProgress[msgId] != null &&
                              (_videoDlProgress[msgId] ?? 0) > 0)
                          ? 'Baixando ${(100 * (_videoDlProgress[msgId] ?? 0)).round()}%'
                          : 'Baixando…',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

      return _buildMediaBubble(
        msgId: msgId,
        data: data, // ✅ novo
        fromMe: fromMe,
        read: data['read'] == true,
        isSelected: isSelected,
        timeString: timeString,
        caption: caption,
        mediaWidth: mediaWidth,
        mediaHeight: mediaHeight,
        mediaChild: videoThumbStack,
        onOpen: () async {
          final playable = await _ensureVideoCached(msgId, videoUrl);
          if (!mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                videoUrl: playable ?? videoUrl,
                sender: fromMe ? 'Você' : widget.chatName,
                sentAt: (timestamp is Timestamp) ? timestamp.toDate() : null,
              ),
            ),
          );
        },
      );

    }

    /* default: texto genérico caso algum tipo novo apareça ------------- */
    return _buildRegularBubble(
      msgId: msgId,
      data: data, // ✅ novo
      inner: Text(content, style: const TextStyle(fontSize: 15)),
      fromMe: fromMe,
      timeString: timeString,
      isSelected: isSelected,
      read: data['read'] == true,
    );

  }

  // cache de aspect ratio (w/h) para imagens/thumbs
  final Map<String, double> _mediaAspect = {};

  Future<void> _warmAspect(String key, ImageProvider provider) async {
    if (_mediaAspect.containsKey(key)) return;

    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) {
        _mediaAspect[key] = w / h;
        if (mounted) setState(() {});
      }
      stream.removeListener(listener);
    }, onError: (_, __) {
      stream.removeListener(listener);
    });

    stream.addListener(listener);
  }

  Size _fitMediaBox({
    required double maxW,
    required double maxH,
    required double? aspect, // w/h
    double minW = 160,
  }) {
    // fallback quadrado
    if (aspect == null || aspect <= 0) {
      final s = maxW.clamp(minW, maxW).toDouble();
      final h = s.clamp(120.0, maxH).toDouble();
      return Size(s, h);
    }

    // começa usando largura máxima
    double w = maxW;
    double h = w / aspect;

    // se estourar altura, ajusta pela altura
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }

    // garante um mínimo de largura (pra não ficar “micro”)
    if (w < minW) {
      w = minW;
      h = w / aspect;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
    }

    return Size(w, h);
  }

  Widget _mediaMetaOverlay({
    required bool fromMe,
    required bool read,
    required String timeString,
  }) {
    final cs = Theme.of(context).colorScheme;

    final tickColor = read
        ? cs.onError // seu “roxo” de lido (igual já usa)
        : cs.surfaceBright; // cinza

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeString,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (fromMe) ...[
            const SizedBox(width: 4),
            Icon(Icons.done_all, size: 16, color: tickColor),
          ],
        ],
      ),
    );
  }

  BorderRadius _mediaRadius(bool fromMe) {
    // bem próximo do WhatsApp (mídia “encosta” mais nas bordas)
    return fromMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(14),
          );
  }

  Widget _mediaMetaInline({
    required bool fromMe,
    required bool read,
    required String timeString,
  }) {
    final cs = Theme.of(context).colorScheme;

    final tickColor = read ? cs.onError : cs.surfaceBright;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeString,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSecondary.withOpacity(.70),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (fromMe) ...[
          const SizedBox(width: 4),
          Icon(Icons.done_all, size: 16, color: tickColor),
        ],
      ],
    );
  }

  Widget _buildMediaBubble({
  required String msgId,
  required Map<String, dynamic> data, // ✅ novo
  required bool fromMe,
  required bool read,
  required bool isSelected,
  required String timeString,
  required Widget mediaChild,
  required String caption,
  required double mediaWidth,
  required double mediaHeight,
  VoidCallback? onOpen,
}) {
  final cs = Theme.of(context).colorScheme;

  final borderColor = fromMe ? cs.tertiary.withOpacity(.50) : cs.secondary;
  const borderPad = 3.0;

  final outerR = _mediaRadius(fromMe);
  final innerR = BorderRadius.only(
    topLeft: Radius.circular((outerR.topLeft.x - borderPad).clamp(0.0, 999.0)),
    topRight:
        Radius.circular((outerR.topRight.x - borderPad).clamp(0.0, 999.0)),
    bottomLeft:
        Radius.circular((outerR.bottomLeft.x - borderPad).clamp(0.0, 999.0)),
    bottomRight: Radius.circular(
        (outerR.bottomRight.x - borderPad).clamp(0.0, 999.0)),
  );

  final hasCaption = caption.trim().isNotEmpty;
  final double innerW = mediaWidth;

  // ✅ Badge só pra outgoing
  final senderBadge = fromMe ? _senderBadge(data) : const SizedBox.shrink();

  final innerContent = hasCaption
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ badge acima da mídia quando tem caption
            if (fromMe)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: senderBadge,
              ),

            SizedBox(width: innerW, height: mediaHeight, child: mediaChild),

            SizedBox(
              width: innerW,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        caption,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSecondary,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _mediaMetaInline(
                      fromMe: fromMe,
                      read: read,
                      timeString: timeString,
                    ),
                  ],
                ),
              ),
            ),
          ],
        )
      : SizedBox(
          width: innerW,
          height: mediaHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              mediaChild,

              // ✅ badge “WhatsApp-like” sobre a mídia (sem caption)
              if (fromMe)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                      child: senderBadge,
                    ),
                  ),
                ),

              Positioned(
                right: 6,
                bottom: 6,
                child: _mediaMetaOverlay(
                  fromMe: fromMe,
                  read: read,
                  timeString: timeString,
                ),
              ),
            ],
          ),
        );

  final bubble = ClipRRect(
    borderRadius: outerR,
    child: Container(
      color: borderColor,
      padding: const EdgeInsets.all(borderPad),
      child: ClipRRect(
        borderRadius: innerR,
        child: innerContent,
      ),
    ),
  );

  final tappableBubble = GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: () {
      setState(() {
        selectionMode = true;
        selectedMessageIds.add(msgId);
      });
    },
    onTap: () {
      if (selectionMode) {
        setState(() {
          if (isSelected) {
            selectedMessageIds.remove(msgId);
            if (selectedMessageIds.isEmpty) selectionMode = false;
          } else {
            selectedMessageIds.add(msgId);
          }
        });
      } else {
        onOpen?.call();
      }
    },
    child: bubble,
  );

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: (selectionMode && isSelected)
              ? Colors.blue.withOpacity(.30)
              : Colors.transparent,
          borderRadius: outerR,
        ),
        child: tappableBubble,
      ),
    ),
  );
}


    Widget _buildRegularBubble({
    required String msgId,
    required Map<String, dynamic> data,
    required Widget inner,
    required bool fromMe,
    required String timeString,
    required bool isSelected,
    required bool read,
  }) {
    return GestureDetector(
      onLongPress: () {
        setState(() {
          selectionMode = true;
          selectedMessageIds.add(msgId);
        });
      },
      onTap: () {
        if (selectionMode) {
          setState(() {
            if (isSelected) {
              selectedMessageIds.remove(msgId);
              if (selectedMessageIds.isEmpty) selectionMode = false;
            } else {
              selectedMessageIds.add(msgId);
            }
          });
        }
      },
      child: Container(
        color: (selectionMode && isSelected)
            ? Colors.blue.withOpacity(.30)
            : Colors.transparent,
        padding: const EdgeInsets.all(5),
        child: Align(
          alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _bubbleMaxWidth(context),
            ),
            child: IntrinsicWidth(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: fromMe
                      ? Theme.of(context).colorScheme.tertiary.withOpacity(.50)
                      : Theme.of(context).colorScheme.secondary,
                  borderRadius: fromMe
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        )
                      : const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fromMe) _senderBadge(data),
                    inner,
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeString,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary
                                  .withOpacity(.60),
                            ),
                          ),
                          if (fromMe)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.done_all,
                                size: 16,
                                color: read
                                    ? Theme.of(context).colorScheme.onError
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceBright,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemMarker(String text, dynamic ts) {
    final cs = Theme.of(context).colorScheme;

    String when = '';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      when =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.inverseSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    when,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withOpacity(.7),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_companyId == null || _phoneId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      // 1) deixe o Scaffold sem cor de fundo
      backgroundColor: Colors.transparent,

      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(),

      // 2) aplique o papel de parede aqui ─ ele “forra” toda a tela
      body: Container(
        decoration: BoxDecoration(
          // ❶ NÃO use const aqui
          image: DecorationImage(
            image: AssetImage(
              isDark
                  ? 'assets/images/chats/mobile-escuro.webp'
                  : 'assets/images/chats/mobile-claro.webp',
            ),
            fit: BoxFit.cover,
          ),
        ),

        // 3) conteúdo original permanece igual
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      // pode mostrar um placeholder ou simplesmente um Container vazio
                      return const SizedBox.expand(); // << evita o crash
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: _sideGutter),
                      // só aplica no desktop
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        reverse: true,
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final msgId = docs[index].id;
                          final data =
                              docs[index].data()! as Map<String, dynamic>;
                          return Builder(
                            builder: (context) {
                              try {
                                return _buildMessageBubble(msgId, data);
                              } catch (e, st) {
                                debugPrint('ERRO na mensagem $msgId – $e\n$st');
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Erro ao exibir mensagem',
                                      style: TextStyle(color: Colors.red)),
                                );
                              }
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MessageInputBar(
                      messageController: _messageController,
                      showEmojiPicker: _showEmojiPicker,
                      onToggleEmoji: () =>
                          setState(() => _showEmojiPicker = !_showEmojiPicker),
                      onPickImage: _pickImage,
                      onPickVideo: _pickVideo,
                      onPickFile: _pickFile,
                      onSendText: _sendTextMessage,
                      onStartRecording: _startRecording,
                      onStopRecording: _stopRecordingAndSend,
                      isRecording: _isRecording,
                      recElapsed: _recElapsed,
                      onCancelRecording: _cancelRecording,
                      recPaused: _recPaused,
                      onTogglePause: _togglePauseResume,
                    ),
                    if (_showEmojiPicker)
                      SizedBox(
                        height: 250,
                        child: emoji.EmojiPicker(
                          onEmojiSelected: (c, e) =>
                              _messageController.text += e.emoji,
                          config: const emoji.Config(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PlusAction { image, video, file, camera }

class MessageInputBar extends StatefulWidget {
  final bool recPaused;
  final VoidCallback onTogglePause;
  final Duration recElapsed;
  final VoidCallback onCancelRecording;

  final TextEditingController messageController;
  final bool showEmojiPicker;
  final VoidCallback onToggleEmoji;
  final Future<void> Function({required bool fromCamera}) onPickImage;
  final Future<void> Function({required bool fromCamera}) onPickVideo;
  final Future<void> Function() onPickFile;
  final VoidCallback onSendText;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final bool isRecording;

  const MessageInputBar({
    Key? key,
    required this.recElapsed,
    required this.onCancelRecording,
    required this.messageController,
    required this.showEmojiPicker,
    required this.onToggleEmoji,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickFile,
    required this.onSendText,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.isRecording,
    required this.recPaused,
    required this.onTogglePause,
  }) : super(key: key);

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  late final FocusNode _inputFocusNode;

  bool _autoCapLock = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode();

    // 1ª letra maiúscula (primeira letra "de verdade", ignorando espaços)
    widget.messageController.addListener(_autoCapitalizeFirstLetter);
  }

  @override
  void dispose() {
    widget.messageController.removeListener(_autoCapitalizeFirstLetter);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _autoCapitalizeFirstLetter() {
    if (_autoCapLock) return;

    final t = widget.messageController.text;
    if (t.isEmpty) return;

    // acha a primeira letra (unicode)
    final re = RegExp(r'\p{L}', unicode: true);
    final m = re.firstMatch(t);
    if (m == null) return;

    final i = m.start;
    final ch = t[i];

    // se já estiver maiúsculo, não mexe
    final up = ch.toUpperCase();
    if (ch == up) return;

    final newText = t.substring(0, i) + up + t.substring(i + 1);

    _autoCapLock = true;
    final sel = widget.messageController.selection;

    // mantém cursor/seleção igual (tamanho não muda)
    widget.messageController.value = widget.messageController.value.copyWith(
      text: newText,
      selection: sel,
      composing: TextRange.empty,
    );
    _autoCapLock = false;
  }

  void _insertNewlineAtCursor() {
    final controller = widget.messageController;
    final text = controller.text;
    final sel = controller.selection;

    final start = (sel.start >= 0) ? sel.start : text.length;
    final end = (sel.end >= 0) ? sel.end : text.length;

    final newText = text.replaceRange(start, end, '\n');
    final newOffset = start + 1;

    controller.value = controller.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Só no KeyDown pra não disparar 2x
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;

    if (!isEnter) return KeyEventResult.ignored;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isShift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);

    if (isShift) {
      // Shift + Enter => quebra linha
      _insertNewlineAtCursor();
    } else {
      // Enter => envia
      if (widget.messageController.text.trim().isNotEmpty) {
        widget.onSendText();
      }
    }

    return KeyEventResult.handled; // impede o TextField de adicionar \n sozinho
  }

  final GlobalKey _plusKey = GlobalKey();

  Future<void> _openPlusMenu() async {
    final cs = Theme.of(context).colorScheme;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = _plusKey.currentContext!.findRenderObject() as RenderBox;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    const double menuLift = 180; // ajuste fino (120~200 costuma ficar ótimo)

    final rect = Rect.fromLTWH(
      topLeft.dx,
      (topLeft.dy - menuLift).clamp(0.0, double.infinity),
      box.size.width,
      box.size.height,
    );

    final selected = await showMenu<_PlusAction>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: const [
        PopupMenuItem<_PlusAction>(
          value: _PlusAction.image,
          child: Row(
            children: [
              Icon(Icons.image_outlined),
              SizedBox(width: 10),
              Text('Imagem'),
            ],
          ),
        ),
        PopupMenuItem<_PlusAction>(
          value: _PlusAction.video,
          child: Row(
            children: [
              Icon(Icons.video_library_outlined),
              SizedBox(width: 10),
              Text('Vídeo'),
            ],
          ),
        ),
        PopupMenuItem<_PlusAction>(
          value: _PlusAction.camera,
          child: Row(
            children: [
              Icon(Icons.camera_alt_outlined),
              SizedBox(width: 10),
              Text('Câmera'),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case _PlusAction.image:
        await widget.onPickImage(fromCamera: false);
        break;
      case _PlusAction.video:
        await widget.onPickVideo(fromCamera: false);
        break;
      case _PlusAction.file:
        await widget.onPickFile();
        break;
      case _PlusAction.camera:
        await widget.onPickImage(fromCamera: true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.messageController,
      builder: (context, value, child) {
        if (widget.isRecording) {
          return _RecordingBar(
            elapsed: widget.recElapsed,
            paused: widget.recPaused,
            onTogglePause: widget.onTogglePause,
            onCancel: widget.onCancelRecording,
            onSend: widget.onStopRecording,
          );
        }

        final hasText = value.text.trim().isNotEmpty;
        final bool isWeb = kIsWeb;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              // deixa “larga” no web/desktop, mas ainda segura absurdos se quiser
              constraints: const BoxConstraints(maxWidth: 1920),
              child: Material(
                color: isDark ? cs.secondary : cs.secondary.withOpacity(.95),
                elevation: 2,
                shadowColor: Colors.black.withOpacity(.25),
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 58, // um pouco mais alto, estilo WhatsApp
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        IconButton(
                          key: _plusKey,
                          icon: const Icon(Icons.add),
                          onPressed: _openPlusMenu,
                          color: cs.onSecondary,
                          splashRadius: 22,
                        ),

                        IconButton(
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          onPressed: widget.onToggleEmoji,
                          color: cs.onSecondary,
                          splashRadius: 22,
                        ),

                        // Campo de texto ocupa o “miolo”
                        Expanded(
                          child: Focus(
                            focusNode: _inputFocusNode,
                            onKeyEvent: _handleKeyEvent,
                            child: TextField(
                              controller: widget.messageController,
                              onTap: () {
                                if (widget.showEmojiPicker)
                                  widget.onToggleEmoji();
                              },
                              keyboardType: TextInputType.multiline,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Mensagem',
                                hintStyle: TextStyle(
                                  color: cs.onSecondary.withOpacity(.6),
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                        ),

                        // ✅ Botão mic/send DENTRO da barra
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _InsideActionButton(
                            icon: hasText ? Icons.send_rounded : Icons.mic_rounded,
                            onTap: hasText
                                ? widget.onSendText
                                : () {
                              // ✅ WEB: clique inicia gravação (permite pedir permissão)
                              if (isWeb) widget.onStartRecording();
                            },

                            // ✅ MOBILE: mantém "pressionar e segurar"
                            onLongPressStart: (hasText || isWeb) ? null : (_) => widget.onStartRecording(),
                            onLongPressEnd: (hasText || isWeb) ? null : (_) => widget.onStopRecording(),
                            onLongPressMoveUpdate: (hasText || isWeb)
                                ? null
                                : (d) {
                              if (d.offsetFromOrigin.dx < -120) {
                                widget.onCancelRecording();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AudioMessageBubble extends StatefulWidget {
  final String base64Audio; // base64 OU http/https
  final bool isFromMe;
  final String sentTime;
  final String avatarUrl;

  // ✅ novos
  final String? senderType; // 'ai' | 'human' | 'lead' | 'system'
  final String? senderName;

  final String? preloadedPath;
  final aw.PlayerController? preloadedWave;
  final Duration? preloadedDur;

  const AudioMessageBubble({
    super.key,
    required this.base64Audio,
    required this.isFromMe,
    required this.sentTime,
    required this.avatarUrl,
    this.senderType,
    this.senderName,
    this.preloadedPath,
    this.preloadedWave,
    this.preloadedDur,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  List<double>? _webPeaks;
  bool _loadingPeaks = false;
  late final aw.PlayerController _wave;
  late final bool _ownsWave;
  final ja.AudioPlayer _player = ja.AudioPlayer();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<ja.ProcessingState>? _procSub;

  Duration _pos = Duration.zero;
  Duration _total = Duration.zero;
  bool _playing = false;

  String? _tempPath;
  bool _waveOk = true;

  @override
  void initState() {
    super.initState();
    _ownsWave = !kIsWeb && widget.preloadedWave == null;
    _wave = widget.preloadedWave ?? aw.PlayerController();

    _bindPlayerStreams();
    _prepare();
  }

  void _bindPlayerStreams() {
    if (kIsWeb) {
      _posSub = _player.positionStream.listen((d) {
        if (!mounted) return;
        setState(() => _pos = d);
      });

      _durSub = _player.durationStream.listen((d) {
        if (!mounted) return;
        if (d != null) setState(() => _total = d);
      });

      _stateSub = _player.playerStateStream.listen((st) {
        if (!mounted) return;
        setState(() => _playing = st.playing);
      });

      _procSub = _player.processingStateStream.listen((st) async {
        if (st == ja.ProcessingState.completed) {
          await _player.pause();
          await _player.seek(Duration.zero);
          if (!mounted) return;
          setState(() {
            _playing = false;
            _pos = Duration.zero;
          });
        }
      });

      return;
    }

    _wave.onCurrentDurationChanged.listen((ms) {
      if (!mounted) return;
      setState(() => _pos = Duration(milliseconds: ms));
    });

    _wave.onPlayerStateChanged.listen((st) {
      if (!mounted) return;
      setState(() => _playing = st == aw.PlayerState.playing);
    });

    _wave.onCompletion.listen((_) async {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _pos = Duration.zero;
      });
      try {
        await _wave.seekTo(0);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _procSub?.cancel();

    _player.dispose();

// ✅ Web: NÃO existe implementação do plugin, então não pode dispose/release
    if (!kIsWeb && _ownsWave) {
      try {
        _wave.dispose();
      } catch (_) {}
    }

    if (!kIsWeb && _tempPath != null) {
      try {
        File(_tempPath!).delete();
      } catch (_) {}
    }

    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      // 1) Cache pronto (mobile/desktop)
      if (!kIsWeb && widget.preloadedPath != null) {
        final pth = widget.preloadedPath!;
        try {
          await _wave.preparePlayer(
            path: pth,
            shouldExtractWaveform: true,
            noOfSamples: 90,
          );

          final maxMs = await _wave.getDuration(aw.DurationType.max);

          if (mounted) {
            setState(() {
              _total = Duration(
                milliseconds: maxMs > 0 ? maxMs : _wave.maxDuration,
              );
              _waveOk = true;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _waveOk = false);
        }
        return;
      }

      // 2) URL
      if (widget.base64Audio.startsWith('http')) {
        final url = proxifyMediaUrl(widget.base64Audio);

        if (kIsWeb) {
          final resp = await http.get(Uri.parse(url));
          final bytes = resp.bodyBytes;

          await _player.setUrl(url);
          await _player.load();
          if (mounted) setState(() => _total = _player.duration ?? Duration.zero);

          await _ensureWebPeaks(bytes);
          _waveOk = false;
          return;
        }

        final bytes = (await http.get(Uri.parse(url))).bodyBytes;
        final ext = _audioExtFromBytes(bytes);

        final dir = await getTemporaryDirectory();
        _tempPath = p.join(
          dir.path,
          'snd_${DateTime.now().microsecondsSinceEpoch}_${widget.hashCode}$ext',
        );

        await File(_tempPath!).writeAsBytes(bytes, flush: true);

        await _player.setFilePath(_tempPath!);

        try {
          await _wave.preparePlayer(
            path: _tempPath!,
            shouldExtractWaveform: true,
            noOfSamples: 90,
          );
          final maxMs = await _wave.getDuration(aw.DurationType.max);
          if (mounted) {
            setState(() {
              _total = Duration(milliseconds: maxMs > 0 ? maxMs : _wave.maxDuration);
              _waveOk = true;
            });
          }
        } catch (_) {
          _waveOk = false;
        }

        return;
      }

      // 3) base64
      final raw = _clean(widget.base64Audio);
      final bytes = base64Decode(raw);
      final ext = _audioExtFromBytes(bytes);

      if (kIsWeb) {
        final mime = _mimeFromExt(ext);
        final dataUrl = 'data:$mime;base64,$raw';
        await _player.setUrl(dataUrl);
        await _player.load();
        if (mounted) {
          setState(() => _total = _player.duration ?? Duration.zero);
        }
        await _ensureWebPeaks(bytes);


        await _ensureWebPeaks(bytes);
        _waveOk = false;
        return;
      }

      final dir = await getTemporaryDirectory();
      _tempPath = p.join(
        dir.path,
        'snd_${DateTime.now().microsecondsSinceEpoch}_${widget.hashCode}$ext',
      );
      await File(_tempPath!).writeAsBytes(bytes);

      await _player.setFilePath(_tempPath!);

      try {
        await _wave.preparePlayer(
          path: _tempPath!,
          shouldExtractWaveform: true,
          noOfSamples: 90,
        );
        final maxMs = await _wave.getDuration(aw.DurationType.max);

        if (mounted) {
          setState(() {
            _total = Duration(milliseconds: maxMs > 0 ? maxMs : _wave.maxDuration);
            _waveOk = true;
          });
        }
      } catch (_) {
        _waveOk = false;
      }
    } catch (_) {
      if (mounted) setState(() => _waveOk = false);
    }
  }

  Future<void> _ensureWebPeaks(Uint8List bytes) async {
    const bars = 80;

    final key = bytes.length ^ bytes.first ^ bytes.last;
    final cached = _webPeaksCache[key];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _webPeaks = cached);
      return;
    }

    if (_loadingPeaks) return;
    _loadingPeaks = true;

    final peaks = await extractPeaks(audioBytes: bytes, bars: bars);

    if (!mounted) return;
    _loadingPeaks = false;

    if (peaks != null && peaks.isNotEmpty) {
      _webPeaksCache[key] = peaks;
      setState(() => _webPeaks = peaks);
    }
  }

  Future<void> _toggle() async {
    if (kIsWeb) {
      if (_playing) {
        await _player.pause();
      } else {
        if (_total.inMilliseconds > 0 &&
            _pos >= _total - const Duration(milliseconds: 200)) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
      return;
    }

    if (_playing) {
      await _wave.pausePlayer();
      return;
    }

    await _wave.pauseAllPlayers();

    if (_wave.maxDuration > 0 &&
        _pos.inMilliseconds >= _wave.maxDuration - 200) {
      try {
        await _wave.seekTo(0);
      } catch (_) {}
    }

    await _wave.startPlayer();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String get _durLabel => _total.inMilliseconds == 0 ? '--:--' : _fmt(_total);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.isFromMe ? cs.tertiary.withOpacity(.50) : cs.secondary;

    final ratio = (_total.inMilliseconds > 0)
        ? (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final avatar = widget.avatarUrl.trim();
    final avatarProvider =
        avatar.isNotEmpty ? NetworkImage(proxifyMediaUrl(avatar)) : null;

    // ✅ Badge (só outgoing)
    final st = (widget.senderType ?? '').trim();
    final sn = (widget.senderName ?? '').trim();
    final showBadge = widget.isFromMe &&
        st.isNotEmpty &&
        st != 'lead' &&
        st != 'system';

    final badgeText = (st == 'ai')
        ? '🤖 ${sn.isNotEmpty ? sn : 'Bot'}'
        : (st == 'human')
            ? '👤 ${sn.isNotEmpty ? sn : 'Humano'}'
            : null;

    Widget waveWidget;

    if (!kIsWeb) {
      if (_waveOk) {
        waveWidget = LayoutBuilder(
          builder: (_, c) {
            final w = (c.maxWidth.isFinite ? c.maxWidth : 0).toDouble();
            if (w <= 0) return const SizedBox(height: 34);

            return aw.AudioFileWaveforms(
              playerController: _wave,
              size: Size(w, 34),
              enableSeekGesture: true,
              waveformType: aw.WaveformType.fitWidth,
              playerWaveStyle: aw.PlayerWaveStyle(
                liveWaveColor: cs.primary,
                fixedWaveColor: cs.onSurface.withOpacity(.25),
                waveThickness: 2,
                spacing: 3,
                showSeekLine: false,
              ),
            );
          },
        );
      } else {
        waveWidget = Container(
          height: 34,
          decoration: BoxDecoration(
            color: cs.onSurface.withOpacity(.06),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LinearProgressIndicator(
            value: (_total.inMilliseconds > 0)
                ? (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
                : 0.0,
            minHeight: 4,
          ),
        );
      }
    } else {
      if (_webPeaks != null) {
        waveWidget = WebPeaksWaveform(
          peaks: _webPeaks!,
          progress: ratio,
          height: 34,
          barWidth: 3,
          spacing: 3,
        );
      } else {
        waveWidget = Container(
          height: 34,
          decoration: BoxDecoration(
            color: cs.onSurface.withOpacity(.06),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ BADGE no áudio
          if (showBadge && badgeText != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.0,
                  color: cs.onSurface.withOpacity(.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          Row(
            children: [
              InkWell(
                onTap: _toggle,
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 30,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),

              Expanded(child: waveWidget),

              const SizedBox(width: 10),

              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.inverseSurface,
                    backgroundImage: avatarProvider,
                    child: avatarProvider == null
                        ? Icon(Icons.person, size: 18, color: cs.outline)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: cs.onSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, size: 12, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              Text(
                _durLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withOpacity(.60),
                ),
              ),
              const Spacer(),
              Text(
                widget.sentTime,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withOpacity(.60),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


String _audioExtFromBytes(Uint8List b) {
  if (b.length >= 4) {
    // EBML (WebM/Matroska) = 1A 45 DF A3
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return '.webm';
    }
    // OggS
    if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return '.ogg';
    }
    // MP3 (ID3)
    if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
      return '.mp3';
    }
  }

  // MP3 frame sync
  if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
    return '.mp3';
  }

  // MP4/M4A: "ftyp" costuma aparecer em 4..7
  if (b.length >= 8 &&
      String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
    return '.m4a';
  }

  return '.m4a';
}

String _mimeFromExt(String ext) {
  switch (ext) {
    case '.webm':
      return 'audio/webm';
    case '.ogg':
      return 'audio/ogg';
    case '.mp3':
      return 'audio/mpeg';
    case '.m4a':
      return 'audio/mp4';
    default:
      return 'audio/mp4';
  }
}

/*── helper (mesmo que você já usava) ──*/
String _clean(String src) =>
    src.contains(',') ? src.split(',').last.trim() : src.trim();

class CachedAudio {
  final String localPath;
  final Duration total;
  final aw.PlayerController wave;

  CachedAudio(this.localPath, this.total, this.wave);
}

final _audioCache = <String, CachedAudio>{}; // msgId → CachedAudio

StreamSubscription? _preloadSub;

class _RecordingBar extends StatefulWidget {
  final Duration elapsed;
  final bool paused; // NOVO
  final VoidCallback onTogglePause; // NOVO
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _RecordingBar({
    Key? key,
    required this.elapsed,
    required this.paused, // NOVO
    required this.onTogglePause, // NOVO
    required this.onCancel,
    required this.onSend,
  }) : super(key: key);

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _eq = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _eq.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(1, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.of(context).padding.bottom > 0 ? 8 : 12,
      ),
      child: Material(
        color: cs.secondary,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(.25),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancelar',
                onPressed: widget.onCancel,
                icon: const Icon(Icons.delete_outline),
                color: cs.onSecondary,
              ),
              Text(
                _fmt(widget.elapsed),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedBuilder(
                  animation: _eq,
                  builder: (_, __) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(7, (i) {
                        final t = ((_eq.value + i * 0.12) % 1.0);
                        final h = 6 +
                            (10 *
                                Curves.easeInOut.transform(
                                  t < 0.5 ? t * 2 : (1 - t) * 2,
                                ));
                        return Container(
                          width: 3,
                          height: h,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: cs.onSecondary.withOpacity(.75),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: widget.paused ? 'Retomar' : 'Pausar',
                onPressed: widget.onTogglePause,
                icon: Icon(widget.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded),
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onSend,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.send_rounded, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsideActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  const _InsideActionButton({
    required this.icon,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressMoveUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: cs.primary, // fica “integrado”
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  const _RoundActionButton({
    Key? key,
    required this.icon,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressMoveUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white, // círculo branco (estilo Whats)
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        // 👇 AQUI o ícone passa a respeitar o parâmetro recebido
        child: Icon(icon, color: Colors.black),
      ),
    );
  }
}
