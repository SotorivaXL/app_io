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
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:logger/logger.dart';
import 'package:just_audio/just_audio.dart';

class AudioWaveCache {
  AudioWaveCache._();                           // private ctor
  static final AudioWaveCache instance = AudioWaveCache._();

  // msgId  →  CachedAudio
  final Map<String, CachedAudio> map = {};
}

final log = Logger(printer: PrettyPrinter());

class ZoomPageRoute extends PageRouteBuilder {
  final Widget page;
  ZoomPageRoute({required this.page})
      : super(
    opaque: false,
    barrierColor: Colors.black,                // fundo já escurece
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

/*───────────────────────────────────────────────────────────*/
/* Tela de imagem em tela cheia ‑ estilo WhatsApp simplificado*/
/*───────────────────────────────────────────────────────────*/
class _ImagePreviewPage extends StatelessWidget {
  final String  content;        // base64 ou URL
  final String  heroTag;
  final String  sender;         // ex.: “Você” ou “Maria”
  final String  sentAt;         // ex.: “18 de julho 15:03”

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
        ? NetworkImage(content)
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
              color: Colors.black.withOpacity(.40),   // leve transparência
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

  /* ------------- INIT ------------- */
  @override
  void initState() {
    super.initState();
    _loadIds();
    _preloadSub = _messagesStream.listen((qs) {
      _precacheAudios(qs);
      if (_preloaded) _preloadSub?.cancel();   // 🔌
    });
  }

  void _precacheAudios(QuerySnapshot qs) async {

    for (final doc in qs.docs) {
      if (doc['type'] != 'audio') continue;
      final id   = doc.id;
      final cont = doc['content'] as String;

      if (_audioCache.containsKey(id)) continue;

      // 1) baixa p/ disco (ou cria a partir do base64)
      final path = await _obterArquivoLocal(cont);

      // 2) prepara o PlayerController e extrai a wave numa isolate
      final pc = PlayerController();
      await pc.preparePlayer(path: path, shouldExtractWaveform: true);

      // 3) pega a duração real
      final player = AudioPlayer();
      await player.setFilePath(path);
      final dur = player.duration ?? Duration.zero;
      await player.dispose();

      _audioCache[id] = CachedAudio(path, dur, pc);
    }

    _preloaded = true;
    if (mounted) setState(() {}); // força rebuild assim que terminar
  }

  Future<String> _obterArquivoLocal(String content) async {
    if (content.startsWith('http')) {
      // usa cache manager → já salva em disco e reutiliza depois
      final file = await cache.DefaultCacheManager().getSingleFile(content);
      return file.path;
    } else {
      // base64 → grava numa tmp (igual você já faz)
      final bytes = base64Decode(_clean(content));
      final dir   = await getTemporaryDirectory();
      final path  = p.join(dir.path,
          'snd_${DateTime.now().microsecondsSinceEpoch}_${content.hashCode}.m4a');
      await File(path).writeAsBytes(bytes);
      return path;
    }
  }

  Future<void> _loadIds() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final empRef   = FirebaseFirestore.instance.collection('empresas').doc(uid);

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
          .collection('empresas').doc(_companyId).collection('phones');

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
            content: Text('Nenhum número encontrado.\nCadastre um telefone em Configurações.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {});          // libera UI

    _initTags();              // usa _companyId
    _markIncomingAsRead();    // usa _companyId/_phoneId
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
      'status': 'atendendo',
      'updatedBy': uid, //  <<< adição
      'updatedAt': FieldValue.serverTimestamp(), //  <<< adição
    }, SetOptions(merge: true));

    // (opcional) salva no histórico ─ só se você quiser
    await chatRef.collection('history').add({
      'status': 'atendendo',
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
      _chatTags = ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();
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
        .collection('empresas').doc(_companyId)
        .collection('phones').doc(_phoneId)
        .collection('whatsappChats').doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final ids  = List<String>.from(data['tags'] ?? const []);
      setState(() {
        _chatTags = ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();
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
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  // INÍCIO DE GRAVAÇÃO DE ÁUDIO
  Future<void> _startRecording() async {
    if (!await _ensureMicPermission()) return;

    final dir = await getTemporaryDirectory();
    _recordPath = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

    await _recorder.start(
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _recordPath,
    );

    _recordCanceled = false;
    _recElapsed = Duration.zero;
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recElapsed += const Duration(seconds: 1));
    });
    _recPaused = false; // NOVO
    setState(() => _isRecording = true);
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordCanceled = true;
    final path = await _recorder.stop();
    _recTimer?.cancel();
    _recPaused = false; // NOVO
    setState(() => _isRecording = false);

    if (path != null) { try { await File(path).delete(); } catch (_) {} }
  }

  // TÉRMINO DE GRAVAÇÃO E ENVIO
  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    _recTimer?.cancel();
    _recPaused = false; // NOVO
    setState(() => _isRecording = false);

    if (_recordCanceled || path == null) return; // não envia

    final bytes = await File(path).readAsBytes();
    final base64Audio = base64Encode(bytes);

    final r = await http.post(
      Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'empresaId': _companyId,
        'phoneId'  : _phoneId,
        'chatId'   : widget.chatId,
        'message'  : '',
        'fileType' : 'audio',
        'fileData' : base64Audio,
      }),
    );

    if (r.statusCode == 200) {
      await _markChatAsAttended();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao enviar áudio')),
        );
      }
    }
  }

  Future<void> _togglePauseResume() async {           // NOVO
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

  // Escolhe imagem (da galeria ou câmera)
  Future<void> _pickImage({required bool fromCamera}) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      final base64Image = base64Encode(bytes);

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
            'fileType': 'image',
            'fileData': base64Image,
          }),
        );
        if (response.statusCode == 200) {
          await _markChatAsAttended(); // << NOVO
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erro ao enviar imagem')));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
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
                leading:
                Icon(Icons.image),
                iconColor: Theme.of(context).colorScheme.onSecondary,
                title: Text("Galeria", style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(fromCamera: false);
                },
              ),
              ListTile(
                leading:
                Icon(Icons.camera_alt),
                iconColor: Theme.of(context).colorScheme.onSecondary,
                title: Text("Câmera", style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
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
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'empresaId': _companyId,
          'phoneId': _phoneId,
          'chatId': widget.chatId,
          'message': text,
          'fileType': 'text',
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
            color: Theme.of(context).colorScheme.onSecondary
        ),
        title: Text('${selectedMessageIds.length} selecionado(s)', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
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
                onPressed: _confirmFinishFlow, // ← chama só o fluxo de conclusão
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

  // Constrói a bolha de mensagem com suporte à seleção
  Widget _buildMessageBubble(String msgId, Map<String, dynamic> data) {
    /*═════════════════════════════════════════════════════════════════════
   * 1. Variáveis auxiliares ‑‑  ✅  Sem mudanças
   *════════════════════════════════════════════════════════════════════*/
    final content   = data['content'] as String? ?? '';
    final type      = data['type']    as String? ?? 'text';
    final fromMe    = data['fromMe']  as bool?   ?? false;
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
        msgId     : msgId,
        inner     : Text(content, style: const TextStyle(fontSize: 15)),
        fromMe    : fromMe,
        timeString: timeString,
        isSelected: isSelected,
        read      : data['read'] == true,
      );
    }

    // ----- IMAGEM / FIGURINHA -----------------------------------------  ✅
    if (type == 'image' || type == 'sticker') {
      final heroTag   = '$msgId-$type';
      final ImageProvider provider = content.startsWith('http')
          ? NetworkImage(content)
          : MemoryImage(base64Decode(content));

      final double maxSide = (type == 'sticker') ? 160 : 250;
      Widget img = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width : maxSide,
          height: maxSide,
          child : Image(image: provider, fit: BoxFit.cover),
        ),
      );

      if (type == 'sticker') {
        img = Stack(children: [
          img,
          Positioned(
            bottom: 4,
            right : 4,
            child : Icon(Icons.emoji_emotions,
                size: 20, color: Colors.white.withOpacity(.8)),
          ),
        ]);
      }

      return _buildRegularBubble(
        msgId     : msgId,
        inner     : GestureDetector(
          onTap: () => Navigator.of(context).push(
            ZoomPageRoute(
              page: _ImagePreviewPage(
                content: content,
                heroTag: heroTag,
                sender : fromMe ? 'Você' : widget.chatName,
                sentAt : DateFormat("d 'de' MMMM HH:mm", 'pt_BR')
                    .format((timestamp as Timestamp).toDate()),
              ),
            ),
          ),
          child: Hero(tag: heroTag, child: img),
        ),
        fromMe    : fromMe,
        timeString: timeString,
        isSelected: isSelected,
        read      : data['read'] == true,
      );
    }

    if (type == 'audio') {
      final cached = _audioCache[msgId];
      final audioWidget = AudioMessageBubble(
        key           : ValueKey(content),
        base64Audio   : content,
        isFromMe      : fromMe,
        sentTime      : timeString,
        avatarUrl     : fromMe ? _myAvatarUrl : widget.contactPhoto,
        preloadedPath : cached?.localPath,
        preloadedWave : cached?.wave,
        preloadedDur  : cached?.total,
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
              child: ConstrainedBox(                       // 75-80 % fica parecido
                     constraints: BoxConstraints(
                   maxWidth: MediaQuery.of(context).size.width * .60,
                 ),
              child: audioWidget,
            ),
          ),
        ),
      );
    }

    // ----- VÍDEO ou outros -------------------------------------------- ✅
    if (type == 'video') {
      final videoPreview = GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(
              videoUrl: content,
              sender: fromMe ? 'Você' : widget.chatName,
              sentAt: (timestamp is Timestamp) ? timestamp.toDate() : null,
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width : 220,
            height: 140,
            color : Colors.black45,
            child : const Center(
              child: Icon(Icons.play_circle_outline,
                  size: 42, color: Colors.white),
            ),
          ),
        ),
      );

      return _buildRegularBubble(
        msgId     : msgId,
        inner     : videoPreview,
        fromMe    : fromMe,
        timeString: timeString,
        isSelected: isSelected,
        read      : data['read'] == true,
      );
    }

    /* default: texto genérico caso algum tipo novo apareça ------------- */
    return _buildRegularBubble(
      msgId     : msgId,
      inner     : Text(content, style: const TextStyle(fontSize: 15)),
      fromMe    : fromMe,
      timeString: timeString,
      isSelected: isSelected,
      read      : data['read'] == true,
    );
  }

/*═════════════════════════════════════════════════════════════════════
 * Helper para “bolhas normais” (texto / imagem / vídeo …)
 * Nada mudou aqui; só isolei para evitar repetição no áudio.
 *════════════════════════════════════════════════════════════════════*/
  Widget _buildRegularBubble({
    required String msgId,
    required Widget inner,
    required bool   fromMe,
    required String timeString,
    required bool   isSelected,
    required bool   read,                 // só para exibir o ícone ✓✓
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
              maxWidth: MediaQuery.of(context).size.width * .80,
            ),

            // ⏬ Envolvemos a bolha com IntrinsicWidth
            child: IntrinsicWidth(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                    : Theme.of(context).colorScheme.surfaceBright,
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
      when = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
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
                      return const SizedBox.expand();   // << evita o crash
                    }
                    return ListView.builder(
                      reverse: true,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final msgId = docs[index].id;
                        final data  = docs[index].data()! as Map<String, dynamic>;
                        return Builder(
                          builder: (context) {
                            try {
                              return _buildMessageBubble(msgId, data);
                            } catch (e, st) {
                              debugPrint('ERRO na mensagem $msgId – $e\n$st');
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('Erro ao exibir mensagem', style: TextStyle(color: Colors.red)),
                              );
                            }
                          },
                        );
                      },
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
                      onToggleEmoji: () => setState(() => _showEmojiPicker = !_showEmojiPicker),
                      onAttachOptions: _openAttachOptions,
                      onPickImage: _pickImage,
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

/// Barra de entrada com botão redondo separado (mic/enviar)
class MessageInputBar extends StatelessWidget {
  final bool recPaused;
  final VoidCallback onTogglePause;
  final Duration recElapsed;
  final VoidCallback onCancelRecording;

  final TextEditingController messageController;
  final bool showEmojiPicker;
  final VoidCallback onToggleEmoji;
  final VoidCallback onAttachOptions;
  final Future<void> Function({required bool fromCamera}) onPickImage;
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
    required this.onAttachOptions,
    required this.onPickImage,
    required this.onSendText,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.isRecording,
    required this.recPaused,
    required this.onTogglePause,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: messageController,
      builder: (context, value, child) {
        // HUD de gravação (igual você já tem)
        if (isRecording) {
          return _RecordingBar(
            elapsed: recElapsed,
            paused: recPaused,
            onTogglePause: onTogglePause,
            onCancel: onCancelRecording,
            onSend: onStopRecording,
          );
        }

        final hasText = value.text.trim().isNotEmpty;

        return Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              // --- Pílula do campo (emoji, texto, clipe, câmera) ---
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.secondary
                        : cs.secondary.withOpacity(.95),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onPressed: onToggleEmoji,
                        color: cs.onSecondary,
                        splashRadius: 22,
                      ),
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          onTap: () {
                            if (showEmojiPicker) onToggleEmoji();
                          },
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
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: onAttachOptions,
                        color: cs.onSecondary,
                        splashRadius: 22,
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt_outlined),
                        onPressed: () => onPickImage(fromCamera: true),
                        color: cs.onSecondary,
                        splashRadius: 22,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // --- Botão redondo separado (mic OU enviar) ---
              hasText
                  ? _RoundActionButton(
                icon: Icons.send_rounded,
                onTap: onSendText,
              )
                  : _RoundActionButton(
                icon: Icons.mic_rounded,
                // Whats: segurar para gravar
                onLongPressStart: (_) => onStartRecording(),
                onLongPressEnd: (_) => onStopRecording(),
                onLongPressMoveUpdate: (d) {
                  if (d.offsetFromOrigin.dx < -120) {
                    onCancelRecording();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class AudioMessageBubble extends StatefulWidget {
  final String base64Audio;              // base64  ou  http/https
  final bool   isFromMe;
  final String sentTime;
  final String avatarUrl;// HH:mm  final String?          preloadedPath;
  final String?          preloadedPath;
  final PlayerController? preloadedWave;
  final Duration?        preloadedDur;


  const AudioMessageBubble({
    super.key,
    required this.base64Audio,
    required this.isFromMe,
    required this.sentTime,
    required this.avatarUrl,
    this.preloadedPath,
    this.preloadedWave,
    this.preloadedDur,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  late final PlayerController _wave;
  final AudioPlayer _player = AudioPlayer();

  Duration _pos   = Duration.zero;       // posição atual
  Duration _total = Duration.zero;       // duração real
  bool     _playing = false;
  String?  _temp;                        // arquivo tmp se vier base64

  /*──────────────────────────────────────────────*/
  /* 1. PREPARO                                   */
  /*──────────────────────────────────────────────*/
  @override
  void initState() {
    super.initState();
    _wave = widget.preloadedWave ?? PlayerController();
    _prepare();
  }

  @override
  void dispose() {
    _player.dispose();
    _wave.dispose();
    if (_temp != null) File(_temp!).delete();
    super.dispose();
  }

  Future<void> _prepare() async {
    String path;

    if (widget.preloadedPath != null) {
      await _player.setFilePath(widget.preloadedPath!);
      _total = widget.preloadedDur ?? Duration.zero;
      // _wave já veio pronto ou será preparado rapidinho
      if (widget.preloadedWave == null) {
        await _wave.preparePlayer(
          path: widget.preloadedPath!,
          shouldExtractWaveform: true,
        );
      }
      return;
    }

    /*──────────────────────── 1. SE VIER URL ────────────────────────*/
    if (widget.base64Audio.startsWith('http')) {
      // baixa o áudio
      final bytes = (await http.get(Uri.parse(widget.base64Audio))).bodyBytes;

      // pasta temporária + extensão original (.ogg, .m4a…)
      final dir  = await getTemporaryDirectory();
      final ext  = p.extension(widget.base64Audio);          // ".ogg"…
      _temp = p.join(
        dir.path,
        'snd_${DateTime.now().microsecondsSinceEpoch}_${widget.hashCode}$ext',
      );
      await File(_temp!).writeAsBytes(bytes);

      // usa o caminho local
      await _player.setFilePath(_temp!);
      path = _temp!;
    }

    /*────────────── 2. SE VIER BASE64 (mesma lógica que já existia) ─────────────*/
    else {
      final bytes = base64Decode(_clean(widget.base64Audio));
      final dir   = await getTemporaryDirectory();
      _temp = p.join(
        dir.path,
        'snd_${DateTime.now().microsecondsSinceEpoch}_${widget.hashCode}.m4a',
      );
      await File(_temp!).writeAsBytes(bytes);
      await _player.setFilePath(_temp!);
      path = _temp!;
    }

    /*────────────── 3. Listeners + Waveform (inalterados) ─────────────*/
    _player.positionStream.listen((d) => setState(() => _pos = d));
    _player.durationStream.listen((d) { if (d != null) _total = d; });
    _player.playerStateStream
        .listen((st) => setState(() => _playing = st.playing));
    _player.processingStateStream.listen((st) async {
      if (st == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
        await _wave.seekTo(0);
        setState(() { _playing = false; _pos = Duration.zero; });
      }
    });

    // AGORA o plugin tem um arquivo local para gerar a wave 👇
    await _wave.preparePlayer(
      path: path,
      shouldExtractWaveform: true,
    );
  }

  /*──────────────────────────────────────────────*/
  /* 2. PLAY / PAUSE                              */
  /*──────────────────────────────────────────────*/
  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_pos >= _total - const Duration(milliseconds: 200) ||
          _player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        await _wave.seekTo(0);
      }
      await _player.play();
    }
  }

  /*──────────────────────────────────────────────*/
  /* 3. UI                                        */
  /*──────────────────────────────────────────────*/
  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
          '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String get _durLabel =>
      _total.inMilliseconds == 0 ? '--:--' : _fmt(_total);

  @override
  Widget build(BuildContext context) {
    const double waveH    = 36.0;   // altura da waveform
    const double knob     = 8.0;
    const double labelPad = 4.0;    // << padding extra que você pediu
    final cs = Theme.of(context).colorScheme;
    final bg = widget.isFromMe
        ? cs.tertiary.withOpacity(.50)
        : cs.secondary;

    // 👉 espaço extra embaixo só p/ caber os rótulos (±14 px)
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 18 + labelPad), // 18 → 22
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          /*────────────────  LINHA PRINCIPAL (player + wave + avatar) ────────────────*/
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: _toggle,
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 30,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 4),

              /* waveform + bolinha + duração */
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) {
                    const knob = 8.0;

                    // -- 1. largura realmente utilizável --
                    final double width = c.maxWidth.isFinite ? c.maxWidth : 0;
                    final double travel = (width - knob).clamp(0.0, double.infinity);

                    // -- 2. ratio seguro --
                    final double ratio = (_total.inMilliseconds > 0)
                        ? _pos.inMilliseconds / _total.inMilliseconds
                        : 0.0;

                    final double left = travel * ratio;          // sempre finito

                    return Stack(
                      children: [
                        /* 1. waveform --------------------------------------------------- */
                        AudioFileWaveforms(
                          playerController : _wave,
                          size             : Size(width, 36),
                          enableSeekGesture: true,
                          waveformType     : WaveformType.fitWidth,
                          playerWaveStyle  : PlayerWaveStyle(
                            liveWaveColor  : cs.primary,
                            fixedWaveColor : cs.onSurface.withOpacity(.25),
                            waveThickness  : 2,
                            spacing        : 3,
                            showSeekLine   : false,
                          ),
                        ),

                        /* 2. knob (móvel) ------------------------------------------------ */
                        Positioned(
                          left: left,                         // ← calculado pelo ratio
                          top : 36 / 2 - knob / 2,            // centrado na linha
                          child: Container(
                            width : knob,
                            height: knob,
                            decoration: BoxDecoration(
                              color: cs.onSurface,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),

                        /* 3. duração (fixa) --------------------------------------------- */
                        Positioned(
                          left: knob + 2,
                          top: 27,
                          child: Text(
                            _durLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(.60),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(width: 8),

              /* avatar com ícone de mic */
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.inverseSurface,
                    backgroundImage: widget.avatarUrl.isNotEmpty
                        ? NetworkImage(widget.avatarUrl)
                        : null,
                    child: widget.avatarUrl.isEmpty
                        ? Icon(Icons.person, size: 18, color: cs.outline)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right : -2,
                    child: Container(
                      width : 15,
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

          /*────────────────  HORÁRIO – ancorado ao fim da wave ────────────────*/
          Positioned(
            top: 27,
            bottom: 0,
            right : 40,            // 32 (avatar) + 8 (spacer)
            child: Text(
              widget.sentTime,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withOpacity(.60),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/*── helper (mesmo que você já usava) ──*/
String _clean(String src) =>
    src.contains(',') ? src.split(',').last.trim() : src.trim();

class CachedAudio {
  final String localPath;
  final Duration total;
  final PlayerController wave;

  CachedAudio(this.localPath, this.total, this.wave);
}

final _audioCache = <String, CachedAudio>{}; // msgId → CachedAudio

StreamSubscription? _preloadSub;

class _RecordingBar extends StatefulWidget {
  final Duration elapsed;
  final bool paused;                 // NOVO
  final VoidCallback onTogglePause;  // NOVO
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _RecordingBar({
    Key? key,
    required this.elapsed,
    required this.paused,            // NOVO
    required this.onTogglePause,     // NOVO
    required this.onCancel,
    required this.onSend,
  }) : super(key: key);

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _eq =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
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

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Lixeira (cancelar)
          IconButton(
            tooltip: 'Cancelar',
            onPressed: widget.onCancel,
            icon: const Icon(Icons.delete_outline),
            color: cs.onSecondary,
          ),

          // Timer
          Text(
            _fmt(widget.elapsed),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSecondary,
            ),
          ),
          const SizedBox(width: 12),

          // “Equalizer” central (leve animação)
          Expanded(
            child: AnimatedBuilder(
              animation: _eq,
              builder: (_, __) {
                // 7 barrinhas em fase defasada
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(7, (i) {
                    // altura oscila entre 6 e 16
                    final t = ( (_eq.value + i * 0.12) % 1.0 );
                    final h = 6 + (10 * Curves.easeInOut.transform(
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

          // Pausar/Retomar (|| / ▶)
          IconButton(
            tooltip: widget.paused ? 'Retomar' : 'Pausar',
            onPressed: widget.onTogglePause,
            icon: Icon(widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            color: Theme.of(context).colorScheme.error, // vermelhinho como no print
          ),
          const SizedBox(width: 8),

          // Botão redondo de ENVIAR (grande)
          GestureDetector(
            onTap: widget.onSend,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,         // círculo branco (como no print)
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.send_rounded, color: Colors.black),
            ),
          ),
        ],
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
          color: Colors.white,               // círculo branco (estilo Whats)
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