import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;                // mantém compatível com seu código atual
  final String? sender;                 // ex.: "Você" ou nome do contato
  final DateTime? sentAt;               // para "há 3 minutos"

  const VideoPlayerPage({
    Key? key,
    required this.videoUrl,
    this.sender,
    this.sentAt,
  }) : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _c;
  bool _showChrome = true;
  Timer? _hideTimer;
  bool _starred = false;
  double _speed = 1.0;
  String? _tempPath; // se precisarmos materializar base64
  bool _seekingLeft = false, _seekingRight = false;

  @override
  void initState() {
    super.initState();
    _init();
    // WakelockPlus.enable(); // se usar o pacote opcional
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c?.dispose();
    if (_tempPath != null) File(_tempPath!).delete();
    // WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _init() async {
    final src = widget.videoUrl.trim();

    // 1) URL → usa direto
    if (src.startsWith('http')) {
      _c = VideoPlayerController.networkUrl(Uri.parse(src));
    }
    // 2) data URI → decode
    else if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      final b64 = comma > 0 ? src.substring(comma + 1) : src;
      final bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      _tempPath = p.join(dir.path, 'vid_${DateTime.now().microsecondsSinceEpoch}.mp4');
      await File(_tempPath!).writeAsBytes(bytes);
      _c = VideoPlayerController.file(File(_tempPath!));
    }
    // 3) base64 “cru”
    else if (_looksLikeBase64(src)) {
      final bytes = base64Decode(_padBase64(src));
      final dir = await getTemporaryDirectory();
      _tempPath = p.join(dir.path, 'vid_${DateTime.now().microsecondsSinceEpoch}.mp4');
      await File(_tempPath!).writeAsBytes(bytes);
      _c = VideoPlayerController.file(File(_tempPath!));
    }
    // 4) caminho local
    else if (File(src).existsSync()) {
      _c = VideoPlayerController.file(File(src));
    } else {
      // última tentativa: baixa e usa cache
      final file = await cache.DefaultCacheManager().getSingleFile(src);
      _c = VideoPlayerController.file(file);
    }

    await _c!.initialize();
    await _c!.setLooping(false);
    await _c!.setPlaybackSpeed(_speed);
    setState(() {});
    _c!.play(); // começa tocando
    _restartAutoHide();
  }

  // helpers base64
  bool _looksLikeBase64(String s) =>
      RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s) && s.replaceAll(RegExp(r'\s'), '').length > 64;
  String _padBase64(String s) {
    var c = s.replaceAll(RegExp(r'\s'), '');
    final mod = c.length % 4;
    if (mod != 0) c = c.padRight(c.length + (4 - mod), '=');
    return c;
  }

  // UI helpers
  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) _restartAutoHide();
  }

  void _restartAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _c?.value.isPlaying == true) {
        setState(() => _showChrome = false);
      }
    });
  }

  String _relTime(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'há ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} minutos';
    if (diff.inHours < 24)   return 'há ${diff.inHours} h';
    return 'há ${diff.inDays} d';
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _seekRel(int seconds, {required bool right}) async {
    if (_c == null) return;

    final dur = _c!.value.duration;
    final pos = _c!.value.position;

    // alvo desejado
    var target = pos + Duration(seconds: seconds);

    // clamp manual: 0 ≤ target ≤ dur
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur)          target = dur;

    await _c!.seekTo(target);

    setState(() {
      _seekingLeft  = !right;
      _seekingRight = right;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() { _seekingLeft = _seekingRight = false; });
    });

    _restartAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c?.value;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: v == null || !v.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
        children: [
          // VIDEO
          Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio == 0 ? 16/9 : v.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(_c!),

                  // tap para mostrar/ocultar UI
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: _toggleChrome,
                      child: Row(
                        children: [
                          // double-tap ← 10s
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onDoubleTap: () => _seekRel(-10, right: false),
                              child: AnimatedOpacity(
                                opacity: _seekingLeft ? 1 : 0,
                                duration: const Duration(milliseconds: 120),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 20),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.replay_10, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // double-tap → 10s
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onDoubleTap: () => _seekRel(10, right: true),
                              child: AnimatedOpacity(
                                opacity: _seekingRight ? 1 : 0,
                                duration: const Duration(milliseconds: 120),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 20),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.forward_10, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // botão play/pause central (só quando UI aparece)
                  IgnorePointer(
                    ignoring: !_showChrome,
                    child: AnimatedOpacity(
                      opacity: _showChrome ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Center(
                        child: InkWell(
                          onTap: () async {
                            if (v.isPlaying) {
                              await _c!.pause();
                            } else {
                              await _c!.play();
                            }
                            setState(() {});
                            _restartAutoHide();
                          },
                          child: Container(
                            width: 78, height: 78,
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: Icon(
                                v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 54, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // TOP BAR (voltar, nome, "há X", estrela, compartilhar)
          SafeArea(
            child: AnimatedOpacity(
              opacity: _showChrome ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                height: kToolbarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.black45,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.sender ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              )),
                          if (widget.sentAt != null)
                            Text(_relTime(widget.sentAt),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuButton<double>(
                      tooltip: 'Velocidade',
                      color: Colors.grey[900],
                      icon: Text('${_speed.toStringAsFixed(1)}x',
                          style: const TextStyle(color: Colors.white)),
                      onSelected: (v) async {
                        setState(() => _speed = v);
                        await _c?.setPlaybackSpeed(v);
                        _restartAutoHide();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 0.5, child: Text('0.5x', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 1.0, child: Text('1.0x', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 1.5, child: Text('1.5x', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 2.0, child: Text('2.0x', style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // BOTTOM CONTROLS + "Responder"
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: AnimatedOpacity(
              opacity: _showChrome ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54, Colors.black87],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // timeline
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _c!,
                      builder: (_, value, __) {
                        final pos = value.position;
                        final dur = value.duration;
                        return Row(
                          children: [
                            Text(_fmt(pos),
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: pos.inMilliseconds
                                    .clamp(0, dur.inMilliseconds)
                                    .toDouble(),
                                min: 0,
                                max: dur.inMilliseconds.toDouble().clamp(1, double.infinity),
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                onChanged: (v) {
                                  _c!.seekTo(Duration(milliseconds: v.round()));
                                },
                                onChangeStart: (_) => _hideTimer?.cancel(),
                                onChangeEnd: (_) => _restartAutoHide(),
                              ),
                            ),
                            Text(_fmt(dur),
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    // responder
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}