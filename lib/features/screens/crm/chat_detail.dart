import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' as rec;
import 'package:audioplayers/audioplayers.dart';
import 'package:app_io/features/screens/crm/video.dart';
import 'package:app_io/features/screens/crm/tag_manager_sheet.dart';
import 'package:app_io/features/screens/crm/contact_profile_page.dart';

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

class _ChatDetailState extends State<ChatDetail> {
  /* ------------- controle de mensagens ------------- */
  final _messageController = TextEditingController();
  final rec.AudioRecorder   _recorder = rec.AudioRecorder();
  bool  _showEmojiPicker = false;
  bool  _isRecording     = false;

  /* ------------- seleção de mensagens ------------- */
  bool selectionMode = false;
  final Set<String> selectedMessageIds = {};
  final Map<String, bool> _messageFromMeMap = {};

  /* ------------- TAGS ------------- */
  final Map<String, TagItem> _tagMap = {};   // id → TagItem (todas da empresa)
  List<TagItem> _chatTags = [];              // tags atribuídas a ESTE chat
  StreamSubscription? _tagSub;
  StreamSubscription? _chatSub;

  /* ------------- STREAM de mensagens ------------- */
  Stream<QuerySnapshot> get _messagesStream => FirebaseFirestore.instance
      .collection('whatsappChats')
      .doc(widget.chatId)
      .collection('messages')
      .orderBy('timestamp', descending: true)
      .snapshots();

  /* ------------- INIT ------------- */
  @override
  void initState() {
    super.initState();
    _initTags();
  }

  /// Depois que o operador responde, move o chat para "Atendendo"
  Future<void> _markChatAsAttended() async {
    await FirebaseFirestore.instance
        .collection('whatsappChats')
        .doc(widget.chatId)
        .set({'opened': true}, SetOptions(merge: true));
  }

  Future<void> _initTags() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();

    final companyId = (userSnap.exists && (userSnap['createdBy'] ?? '').toString().isNotEmpty)
        ? userSnap['createdBy'] as String
        : uid;

    // 1. Ouve TODAS as tags da empresa
    final tagCol = FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .collection('tags');

    void _refreshChatTags() {
      final ids = _chatTags.map((t) => t.id);
      _chatTags = ids.where(_tagMap.containsKey).map((id) => _tagMap[id]!).toList();
    }

    _tagSub = tagCol.orderBy('name').snapshots().listen((qs) {
      setState(() {
        _tagMap
          ..clear()
          ..addEntries(qs.docs.map((d) => MapEntry(d.id, TagItem.fromDoc(d))));
        _refreshChatTags();
      });
    });

    // 2. Ouve o próprio chat para saber a lista de ids atribuídos
    _chatSub = FirebaseFirestore.instance
        .collection('whatsappChats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;

      // ❶ obtém o map de dados – pode vir null
      final data = snap.data() as Map<String, dynamic>? ?? {};

      // ❷ converte com segurança
      final ids = List<String>.from(data['tags'] ?? const []);

      setState(() {
        _chatTags = ids.where(_tagMap.containsKey)
            .map((id) => _tagMap[id]!)
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _tagSub?.cancel();
    _chatSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  // INÍCIO DE GRAVAÇÃO DE ÁUDIO
  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de microfone negada')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final filePath = p.join(
      dir.path,
      'gravacao_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    setState(() => _isRecording = true);

    await _recorder.start(
      // 1) Passa RecordConfig como primeiro argumento posicional
      const rec.RecordConfig(
        encoder: rec.AudioEncoder.aacLc, // antes era AudioEncoder.AAC
        bitRate: 128000,
        sampleRate: 44100,               // nome correto: sampleRate
      ),
      // 2) Em seguida, o named parameter path:
      path: filePath,
    );
  }

  // TÉRMINO DE GRAVAÇÃO E ENVIO
  Future<void> _stopRecordingAndSend() async {
    final path = await _recorder.stop(); // retorna o caminho gerado
    setState(() => _isRecording = false);

    if (path != null) {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);

      try {
        final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'chatId': widget.chatId,
            'message': '',
            'fileType': 'audio',
            'fileData': base64Audio,
          }),
        );
        if (response.statusCode == 200) {
          await _markChatAsAttended();              // << NOVO
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Erro ao enviar áudio')));
        }
      } catch (e) {
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
    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      try {
        final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'chatId': widget.chatId,
            'message': '',
            'fileType': 'image',
            'fileData': base64Image,
          }),
        );
        if (response.statusCode == 200) {
          await _markChatAsAttended();              // << NOVO
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Erro ao enviar imagem')));
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
          title: const Text("Excluir Mensagens"),
          content: const Text("Deseja realmente excluir as mensagens?"),
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
                leading: const Icon(Icons.image),
                title: const Text("Galeria"),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(fromCamera: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Câmera"),
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
          'chatId': widget.chatId,
          'message': text,
          'fileType': 'text',
        }),
      );
      if (response.statusCode == 200) {
        await _markChatAsAttended();          // move para “Atendendo”
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
            'chatId': widget.chatId,
            'docId': msgId,      // <-- aqui troquei para 'docId': ...
            'owner': true,       // se você quer sempre apagar 'para todos'
          }),
        );

        if (response.statusCode == 200) {
          await FirebaseFirestore.instance
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
            name:   widget.chatName,
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
        ),
        title: Text('${selectedMessageIds.length} selecionado(s)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Excluir',
            onPressed: _showDeleteOptions,
          ),
          IconButton(
            icon: const Icon(Icons.sell_outlined),
            tooltip: 'Etiquetas',
            onPressed: _openTagManager,
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
                  size: 20,
                  color: Theme.of(context).colorScheme.outline)
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
                        final displayTags = _chatTags.take(2).toList();
                        final extra      = _chatTags.length - displayTags.length;

                        return Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            ...displayTags.map((tag) {
                              final onDark = ThemeData
                                  .estimateBrightnessForColor(tag.color) ==
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
        IconButton(
          icon: const Icon(Icons.sell_outlined),
          tooltip: 'Etiquetas',
          onPressed: _openTagManager,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Mais opções',
          onSelected: (v) {
            if (v == 'limpar') {
              // TODO: limpar conversa
            } else if (v == 'arquivar') {
              // TODO: arquivar
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'limpar',  child: Text('Limpar conversa')),
            PopupMenuItem(value: 'arquivar', child: Text('Arquivar')),
          ],
        ),
      ],
    );
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

  // Constrói a bolha de mensagem com suporte à seleção
  Widget _buildMessageBubble(String msgId, Map<String, dynamic> data) {
    final content = data['content'] as String? ?? '';
    final type = data['type'] as String? ?? 'text';
    final fromMe = data['fromMe'] as bool? ?? false;
    final timestamp = data['timestamp'];
    String timeString = '';

    // Salva no map se a mensagem é do próprio usuário
    _messageFromMeMap[msgId] = fromMe;

    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      timeString =
      "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    }

    bool isSelected = selectedMessageIds.contains(msgId);
    Widget messageWidget;

    if (type == 'text') {
      messageWidget = Text(content, style: const TextStyle(fontSize: 15));
    } else if (type == 'image' || type == 'sticker') {
      // Para imagens e figurinhas, exibe a imagem.
      Widget imageWidget;
      if (content.startsWith("http")) {
        imageWidget = Image.network(content, fit: BoxFit.cover);
      } else {
        try {
          final decodedBytes = base64Decode(content);
          imageWidget = Image.memory(decodedBytes, fit: BoxFit.cover);
        } catch (e) {
          imageWidget = const Text(
            "Erro ao carregar imagem",
            style: TextStyle(fontSize: 15),
          );
        }
      }
      // Se for figurinha, sobrepõe um ícone
      if (type == 'sticker') {
        messageWidget = Stack(
          children: [
            imageWidget,
            Positioned(
              bottom: 4,
              right: 4,
              child: Icon(
                Icons.emoji_emotions,
                size: 20,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        );
      } else {
        messageWidget = imageWidget;
      }
    } else if (type == 'audio') {
      messageWidget = AudioMessageBubble(
        key: ValueKey(content),
        base64Audio: content,
        senderPhoto: data['senderPhoto'] as String?,
        isFromMe: fromMe,
        sentTime: timeString,
      );
    } else if (type == 'video') {
      // Em vez de tentar carregar o vídeo como imagem, exibimos um container placeholder.
      messageWidget = GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                videoUrl: content, // URL do vídeo
              ),
            ),
          );
        },
        child: Container(
          width: 200, // Dimensões ajustáveis conforme seu design
          height: 120,
          color: Colors.black45,
          child: const Center(
            child: Icon(
              Icons.play_circle_outline,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      messageWidget = Text(content, style: const TextStyle(fontSize: 15));
    }

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
              if (selectedMessageIds.isEmpty) {
                selectionMode = false;
              }
            } else {
              selectedMessageIds.add(msgId);
            }
          });
        }
      },
      child: Container(
        color: (selectionMode && isSelected)
            ? Colors.blue.withOpacity(0.3)
            : Colors.transparent,
        padding: const EdgeInsets.all(5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment:
          fromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
              ),
              decoration: BoxDecoration(
                color: fromMe
                    ? Theme.of(context).colorScheme.tertiary.withOpacity(0.5)
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
                crossAxisAlignment:
                fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  messageWidget,
                  if (type != 'audio') ...[
                    const SizedBox(height: 4),
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondary
                            .withOpacity(0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1) deixe o Scaffold sem cor de fundo
      backgroundColor: Colors.transparent,

      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(),

      // 2) aplique o papel de parede aqui ─ ele “forra” toda a tela
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/chats/mobile2.webp'),
            fit: BoxFit.cover,        // cobre toda a área
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
                    return ListView.builder(
                      reverse: true,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final msgId = docs[index].id;
                        final data  = docs[index].data() as Map<String, dynamic>;
                        return _buildMessageBubble(msgId, data);
                      },
                    );
                  },
                ),
              ),
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
                      showEmojiPicker : _showEmojiPicker,
                      onToggleEmoji   : () =>
                          setState(() => _showEmojiPicker = !_showEmojiPicker),
                      onAttachOptions : _openAttachOptions,
                      onPickImage     : _pickImage,
                      onSendText      : _sendTextMessage,
                      onStartRecording: _startRecording,
                      onStopRecording : _stopRecordingAndSend,
                    ),
                    if (_showEmojiPicker)
                      SizedBox(
                        height: 250,
                        child: EmojiPicker(
                          onEmojiSelected: (c,e) =>
                          _messageController.text += e.emoji,
                          config: const Config(),
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

/// Widget para a barra de entrada de mensagens.
class MessageInputBar extends StatelessWidget {
  final TextEditingController messageController;
  final bool showEmojiPicker;
  final VoidCallback onToggleEmoji;
  final VoidCallback onAttachOptions;
  final Future<void> Function({required bool fromCamera}) onPickImage;
  final VoidCallback onSendText;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  const MessageInputBar({
    Key? key,
    required this.messageController,
    required this.showEmojiPicker,
    required this.onToggleEmoji,
    required this.onAttachOptions,
    required this.onPickImage,
    required this.onSendText,
    required this.onStartRecording,
    required this.onStopRecording,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: messageController,
      builder: (context, value, child) {
        final hasText = value.text.trim().isNotEmpty;
        return Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined),
                onPressed: onToggleEmoji,
              ),
              Expanded(
                child: TextField(
                  controller: messageController,
                  onTap: () {
                    if (showEmojiPicker) onToggleEmoji();
                  },
                  decoration: const InputDecoration(
                    hintText: 'Mensagem',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: onAttachOptions,
              ),
              IconButton(
                icon: const Icon(Icons.camera_alt),
                onPressed: () => onPickImage(fromCamera: true),
              ),
              hasText
                  ? IconButton(
                icon: const Icon(Icons.send),
                onPressed: onSendText,
              )
                  : GestureDetector(
                onLongPress: onStartRecording,
                onLongPressUp: onStopRecording,
                child: const Icon(Icons.mic),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Widget para reprodução de áudio com layout semelhante ao WhatsApp.
/// Bolha de áudio sem foto do contato para mensagens recebidas.
class AudioMessageBubble extends StatefulWidget {
  final String base64Audio;
  final String? senderPhoto; // (não será usado mais no layout)
  final bool isFromMe;
  final String sentTime; // horário de envio do áudio

  const AudioMessageBubble({
    Key? key,
    required this.base64Audio,
    this.senderPhoto,
    this.isFromMe = false,
    required this.sentTime,
  }) : super(key: key);

  @override
  _AudioMessageBubbleState createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _localAudioSource;

  @override
  void initState() {
    super.initState();
    _listenToAudioChanges();
    _prepareAudio();
  }

  void _listenToAudioChanges() {
    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() => _totalDuration = duration);
    });
    _audioPlayer.onPositionChanged.listen((position) {
      setState(() => _currentPosition = position);
      if (position >= _totalDuration && _totalDuration != Duration.zero) {
        setState(() {
          isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        isPlaying = false;
        _currentPosition = Duration.zero;
      });
    });
  }

  Future<void> _prepareAudio() async {
    try {
      final trimmedAudio = widget.base64Audio.trim();

      // Se a string estiver vazia, simplesmente não faz nada (ou exibe msg de erro).
      if (trimmedAudio.isEmpty) {
        debugPrint("Áudio está vazio. Abortando _prepareAudio().");
        return;
      }

      if (trimmedAudio.startsWith('http')) {
        // Se for link http, reproduz direto da URL
        _localAudioSource = trimmedAudio;
      } else {
        // Se for base64, decodifica e salva local para reproduzir
        final bytes = base64Decode(trimmedAudio);
        final dir = await getTemporaryDirectory();
        final filePath = p.join(
          dir.path,
          'received_audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        _localAudioSource = filePath;
      }

      if (_localAudioSource != null) {
        await _setAudioSource();
      }
    } catch (e) {
      debugPrint("Erro ao preparar áudio: $e");
    }
  }

  Future<void> _setAudioSource() async {
    if (_localAudioSource == null) return;
    if (_localAudioSource!.startsWith('http')) {
      await _audioPlayer.setSourceUrl(_localAudioSource!);
      // Toca rapidamente e pausa para "preparar" o Player e obter a duração
      await _audioPlayer.resume();
      await Future.delayed(const Duration(milliseconds: 100));
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.setSourceDeviceFile(_localAudioSource!);
    }
    final duration = await _audioPlayer.getDuration();
    if (duration != null) {
      setState(() {
        _totalDuration = duration;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_localAudioSource == null) return;
    if (!isPlaying) {
      if (_localAudioSource!.startsWith('http')) {
        await _audioPlayer.play(UrlSource(_localAudioSource!));
      } else {
        await _audioPlayer.play(DeviceFileSource(_localAudioSource!));
      }
      setState(() => isPlaying = true);
    } else {
      await _audioPlayer.pause();
      setState(() => isPlaying = false);
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressTime = isPlaying
        ? _formatDuration(_currentPosition)
        : _formatDuration(_totalDuration);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isFromMe
            ? Theme.of(context).colorScheme.tertiary.withOpacity(0.5)
            : Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _togglePlayPause,
            child: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      final totalWidth = constraints.maxWidth;
                      final fraction = (_totalDuration.inMilliseconds == 0)
                          ? 0.0
                          : _currentPosition.inMilliseconds /
                          _totalDuration.inMilliseconds;
                      final progressWidth = totalWidth * fraction;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: progressWidth,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                  Center(
                    child: Text(
                      progressTime,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Ao invés de exibir a foto do contato, mostra apenas o horário
          Text(
            widget.sentTime,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }
}