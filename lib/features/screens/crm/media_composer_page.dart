import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../../util/video_thumb/video_thumb.dart';
import 'package:app_io/util/web_video_view.dart';

enum PendingMediaType { image, video }

class PendingMedia {
  final String fileName;
  final PendingMediaType type;
  final String id; // ✅ usado como viewId no web

  /// bytes originais (imagem/vídeo)
  Uint8List bytes;

  /// bytes editados da imagem (se editar). Para vídeo fica null.
  Uint8List? editedImageBytes;

  /// thumb do vídeo (jpeg/png) em bytes (opcional)
  Uint8List? videoThumbBytes;

  /// caption por item
  String caption;

  PendingMedia({
    required this.fileName,
    required this.type,
    required this.bytes,
    this.editedImageBytes,
    this.videoThumbBytes,
    this.caption = '',
  }) : id = '${DateTime.now().microsecondsSinceEpoch}_${fileName.hashCode}';

  Uint8List get effectiveImageBytes => editedImageBytes ?? bytes;
}

class MediaComposerPage extends StatefulWidget {
  final String empresaId;
  final String phoneId;
  final String chatId;

  /// callback opcional pra você mover chat para "atendendo" depois do envio
  final Future<void> Function()? onSentOk;

  final List<PendingMedia> initial;

  const MediaComposerPage({
    super.key,
    required this.empresaId,
    required this.phoneId,
    required this.chatId,
    required this.initial,
    this.onSentOk,
  });

  @override
  State<MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<MediaComposerPage> {
  final PageController _page = PageController();
  final TextEditingController _captionCtrl = TextEditingController();
  VideoPlayerController? _vCtrl;
  bool _vReady = false;

  late List<PendingMedia> _items;
  int _index = 0;

  bool _sending = false;
  double _progress = 0; // 0..1

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initial);
    for (final it in _items) {
      if (it.type == PendingMediaType.video) {
        _ensureThumb(it);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVideoForCurrentIfNeeded());
    _captionCtrl.text = _items.isNotEmpty ? _items[0].caption : '';
    _captionCtrl.addListener(() {
      if (_items.isEmpty) return;
      _items[_index].caption = _captionCtrl.text;
    });
  }

  @override
  void dispose() {
    if (kIsWeb) {
      for (final it in _items) {
        if (it.type == PendingMediaType.video) {
          disposeWebVideoView('mc_video_${it.id}');
        }
      }
    }
    _vCtrl?.dispose();
    _captionCtrl.dispose();
    _page.dispose();
    super.dispose();
  }

  void _setIndex(int i) {
    setState(() => _index = i);
    _captionCtrl.text = _items[i].caption;
    _captionCtrl.selection = TextSelection.collapsed(offset: _captionCtrl.text.length);

    // ✅ carrega vídeo se for vídeo
    _loadVideoForCurrentIfNeeded();
  }

  Future<void> _ensureThumb(PendingMedia it) async {
    if (it.type != PendingMediaType.video) return;
    if (it.videoThumbBytes != null && it.videoThumbBytes!.isNotEmpty) return;

    try {
      Uint8List? thumb;
      if (kIsWeb) {
        thumb = await generateVideoThumbWeb(it.bytes);
      } else {
        // mobile/desktop: tenta via plugin se tiver path (não obrigatório)
        // Se você não tiver path aqui, pode deixar só web mesmo.
        thumb = null;
      }

      if (!mounted) return;
      if (thumb != null && thumb.isNotEmpty) {
        setState(() => it.videoThumbBytes = thumb);
      }
    } catch (_) {
      // ignora falha de thumb
    }
  }

  Future<void> _loadVideoForCurrentIfNeeded() async {
    _vCtrl?.dispose();
    _vCtrl = null;
    _vReady = false;

    if (_items.isEmpty) return;
    final it = _items[_index];
    if (it.type != PendingMediaType.video) {
      setState(() {});
      return;
    }

    try {
      if (kIsWeb) {
        // ✅ no web, por simplicidade: mantém thumb (play abre player full)
        // (Se você quiser inline no web, eu te passo o helper de blob-url com import condicional)
        setState(() {});
        return;
      }

      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'composer_play_${DateTime.now().microsecondsSinceEpoch}_${it.fileName}.mp4'));
      await f.writeAsBytes(it.bytes, flush: true);

      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.setLooping(true);

      _vCtrl = c;
      _vReady = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<Uint8List?> _makeThumbForVideoBytes(Uint8List bytes, {String? name}) async {
    try {
      if (kIsWeb) {
        return await generateVideoThumbWeb(bytes);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, 'composer_${DateTime.now().microsecondsSinceEpoch}_${name ?? 'vid'}.mp4'));
        await file.writeAsBytes(bytes, flush: true);

        final thumb = await VideoThumbnail.thumbnailData(
          video: file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 480,
          quality: 75,
        );

        try { await file.delete(); } catch (_) {}
        return thumb;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _editCurrentImage() async {
    final item = _items[_index];
    if (item.type != PendingMediaType.image) return;

    // abre editor (draw/crop/text/emoji)
    final edited = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditor(
          image: item.effectiveImageBytes,
        ),
      ),
    );

    if (edited != null) {
      setState(() {
        item.editedImageBytes = edited;
      });
    }
  }

  Future<void> _addFromGallery() async {
    // ✅ multi seleção (imagem/vídeo) com file_picker (funciona no Web também)
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'm4v'],
    );
    if (res == null || res.files.isEmpty) return;

    final added = <PendingMedia>[];

    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;

      final name = f.name;
      final lower = name.toLowerCase();

      final isVideo = lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.m4v');
      final type = isVideo ? PendingMediaType.video : PendingMediaType.image;

      added.add(PendingMedia(
        fileName: name,
        type: type,
        bytes: bytes,
      ));

      if (type == PendingMediaType.video) {
        final t = await _makeThumbForVideoBytes(bytes, name: name);
        added.last.videoThumbBytes = t;
      }
    }

    if (added.isEmpty) return;

    setState(() => _items.addAll(added));

    for (final it in added) {
      if (it.type == PendingMediaType.video) {
        _ensureThumb(it);
      }
    }

    // pula para o primeiro item recém adicionado
    final go = _items.length - added.length;
    _page.jumpToPage(go);
    _setIndex(go);
  }

  Future<void> _addFromCamera({required bool video}) async {
    final picker = ImagePicker();

    if (video) {
      final XFile? picked = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      final item = PendingMedia(
        fileName: picked.name,
        type: PendingMediaType.video,
        bytes: bytes,
      );

      setState(() => _items.add(item));

      // gera thumb (web + mobile)
      final t = await _makeThumbForVideoBytes(bytes, name: picked.name);
      if (t != null && mounted) {
        setState(() => item.videoThumbBytes = t);
      }

      final last = _items.length - 1;
      _page.jumpToPage(last);
      _setIndex(last);
      return;
    }

    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _items.add(PendingMedia(
        fileName: picked.name,
        type: PendingMediaType.image,
        bytes: bytes,
      ));
    });

    final last = _items.length - 1;
    _page.jumpToPage(last);
    _setIndex(last);
  }

  void _removeCurrent() {
    if (_items.isEmpty) return;
    final removing = _index;

    setState(() {
      _items.removeAt(removing);
      if (_items.isEmpty) {
        Navigator.pop(context);
        return;
      }
      _index = (_index.clamp(0, _items.length - 1));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _page.jumpToPage(_index);
      _captionCtrl.text = _items[_index].caption;
    });
  }

  Future<void> _sendAll() async {
    if (_items.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _progress = 0;
    });

    final url = Uri.parse('https://sendmessage-5a3yl3wsma-uc.a.run.app');

    try {
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];

        // Atualiza caption atual antes de enviar
        item.caption = (i == _index) ? _captionCtrl.text : item.caption;

        final body = <String, dynamic>{
          'empresaId': widget.empresaId,
          'phoneId': widget.phoneId,
          'chatId': widget.chatId,
          'caption': item.caption,
          'message': item.caption,
          'fileName': item.fileName,
          'viewOnce': false,
        };

        if (item.type == PendingMediaType.image) {
          // envia imagem editada (se tiver) ou original
          final b64 = base64Encode(item.effectiveImageBytes);
          body['fileType'] = 'image';
          body['fileData'] = b64;
        } else {
          // vídeo: sem edição aqui, mas com caption
          final b64 = base64Encode(item.bytes);
          body['fileType'] = 'video';
          body['fileData'] = b64;

          // thumb opcional (se você gerar depois, pluga aqui)
          if (item.videoThumbBytes != null) {
            body['thumbData'] = base64Encode(item.videoThumbBytes!);
            body['thumbMime'] = 'image/jpeg';
          }
        }

        final resp = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );

        if (resp.statusCode != 200) {
          throw Exception('Falha ao enviar (${resp.statusCode}): ${resp.body}');
        }

        setState(() => _progress = (i + 1) / _items.length);
      }

      // opcional: marca como atendido no seu fluxo
      if (widget.onSentOk != null) await widget.onSentOk!();

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = _items[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Adicionar mais',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _addFromGallery,
          ),
          IconButton(
            tooltip: 'Câmera (foto)',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => _addFromCamera(video: false),
          ),
          IconButton(
            tooltip: 'Câmera (vídeo)',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _addFromCamera(video: true),
          ),
          IconButton(
            tooltip: 'Remover',
            icon: const Icon(Icons.delete_outline),
            onPressed: _removeCurrent,
          ),
        ],

        // ✅ TOOLBAR NO TOPO (CENTRALIZADA) — só quando for imagem
        bottom: (_items.isNotEmpty && _items[_index].type == PendingMediaType.image)
            ? PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Center(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Desenhar / Editar',
                      icon: const Icon(Icons.brush_outlined, size: 20),
                      color: Colors.white,
                      onPressed: _editCurrentImage,
                    ),
                    IconButton(
                      tooltip: 'Cortar / Ajustar',
                      icon: const Icon(Icons.crop, size: 20),
                      color: Colors.white,
                      onPressed: _editCurrentImage,
                    ),
                    IconButton(
                      tooltip: 'Texto',
                      icon: const Icon(Icons.text_fields, size: 20),
                      color: Colors.white,
                      onPressed: _editCurrentImage,
                    ),
                    IconButton(
                      tooltip: 'Emoji / Stickers',
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                      color: Colors.white,
                      onPressed: _editCurrentImage,
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // PREVIEW
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _items.length,
                onPageChanged: _setIndex,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  if (it.type == PendingMediaType.image) {
                    return Center(
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4,
                        child: Image.memory(it.effectiveImageBytes, fit: BoxFit.contain),
                      ),
                    );
                  }

                  if (kIsWeb) {
                    if (it.videoThumbBytes == null) {
                      _ensureThumb(it);
                    }

                    final viewId = 'mc_video_${it.id}';

                    return Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: buildWebVideoView(
                            viewId: viewId,
                            videoBytes: it.bytes,
                            posterBytes: it.videoThumbBytes,
                            fileName: it.fileName, // ✅ ajuda mime
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      Center(
                        child: it.videoThumbBytes != null
                            ? Image.memory(it.videoThumbBytes!, fit: BoxFit.contain)
                            : const Icon(Icons.movie, color: Colors.white54, size: 120),
                      ),
                      const Positioned.fill(
                        child: Center(
                          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 72),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // THUMBS + CAPTION + SEND
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.65),
                border: const Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thumbs
                  SizedBox(
                    height: 62,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        final selected = i == _index;

                        Widget thumb;
                        if (it.type == PendingMediaType.image) {
                          thumb = Image.memory(it.effectiveImageBytes, fit: BoxFit.cover);
                        } else {
                          thumb = it.videoThumbBytes != null
                              ? Image.memory(it.videoThumbBytes!, fit: BoxFit.cover)
                              : const ColoredBox(
                            color: Colors.white10,
                            child: Center(
                              child: Icon(Icons.movie, color: Colors.white70),
                            ),
                          );
                        }

                        return GestureDetector(
                          onTap: () {
                            _page.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                            _setIndex(i);
                          },
                          child: Container(
                            width: 62,
                            height: 62,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? cs.primary : Colors.white24,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                thumb,
                                if (it.type == PendingMediaType.video)
                                  const Align(
                                    alignment: Alignment.center,
                                    child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _captionCtrl,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: 'Adicionar legenda...',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // enviar
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _sending ? null : _sendAll,
                          child: _sending
                              ? Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: (_progress > 0) ? _progress : null,
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                              const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ],
                          )
                              : const Icon(Icons.send_rounded, color: Colors.white),
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
}