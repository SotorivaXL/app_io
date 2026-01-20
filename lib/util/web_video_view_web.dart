// lib/util/web_video_view_web.dart
import 'dart:typed_data';
import 'dart:ui_web' as ui;
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

final Map<String, html.VideoElement> _videos = {};
final Map<String, String> _videoUrls = {};
final Map<String, String> _posterUrls = {};

String _bytesToObjectUrl(Uint8List bytes, {required String mime}) {
  final blob = html.Blob([bytes], mime);
  return html.Url.createObjectUrlFromBlob(blob);
}

// ✅ helpers
void playWebVideoView(String viewId) async {
  final v = _videos[viewId];
  if (v == null) return;
  try {
    v.muted = true; // ajuda MUITO no web
    await v.play();
    html.window.console.log('[web_video][$viewId] play() OK');
  } catch (e) {
    html.window.console.error('[web_video][$viewId] play() FAILED: $e');
  }
}

void pauseWebVideoView(String viewId) {
  final v = _videos[viewId];
  if (v == null) return;
  v.pause();
  html.window.console.log('[web_video][$viewId] pause()');
}

Widget buildWebVideoView({
  required String viewId,
  required Uint8List videoBytes,
  Uint8List? posterBytes,
  String? fileName,
}) {
  // mime melhor por extensão (não resolve codec, mas ajuda)
  String mime = 'video/mp4';
  final lower = (fileName ?? '').toLowerCase();
  if (lower.endsWith('.mov')) mime = 'video/quicktime';
  if (lower.endsWith('.m4v')) mime = 'video/x-m4v';

  if (!_videos.containsKey(viewId)) {
    final video = html.VideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'black'
      ..style.pointerEvents = 'auto'
      ..controls = true
      ..autoplay = false
      ..muted = true // ✅ essencial pra evitar bloqueio de autoplay/play
      ..loop = false
      ..preload = 'auto';

    video.setAttribute('playsinline', 'true');

    // VIDEO URL (blob)
    final vUrl = _bytesToObjectUrl(videoBytes, mime: mime);
    _videoUrls[viewId] = vUrl;
    video.src = vUrl;

    // POSTER
    if (posterBytes != null && posterBytes.isNotEmpty) {
      final pUrl = _bytesToObjectUrl(posterBytes, mime: 'image/jpeg');
      _posterUrls[viewId] = pUrl;
      video.poster = pUrl;
    }

    // força carregar metadata
    video.load();

    // ✅ LOGS IMPORTANTES (vai aparecer no console)
    video.onClick.listen((_) async {
      html.window.console.log('[web_video][$viewId] click');
      try {
        video.muted = true;
        await video.play();
        html.window.console.log('[web_video][$viewId] click->play OK');
      } catch (e) {
        html.window.console.error('[web_video][$viewId] click->play FAILED: $e');
      }
    });

    video.onPlay.listen((_) => html.window.console.log('[web_video][$viewId] onPlay'));
    video.onPlaying.listen((_) => html.window.console.log('[web_video][$viewId] onPlaying'));
    video.onPause.listen((_) => html.window.console.log('[web_video][$viewId] onPause'));
    video.onWaiting.listen((_) => html.window.console.log('[web_video][$viewId] onWaiting'));
    video.onStalled.listen((_) => html.window.console.log('[web_video][$viewId] onStalled'));
    video.onCanPlay.listen((_) => html.window.console.log('[web_video][$viewId] onCanPlay'));
    video.onLoadedMetadata.listen((_) {
      html.window.console.log('[web_video][$viewId] metadata duration=${video.duration}');
    });
    video.onError.listen((_) {
      final err = video.error;
      html.window.console.error('[web_video][$viewId] ERROR code=${err?.code} message=${err?.message}');
    });

    ui.platformViewRegistry.registerViewFactory(viewId, (int _) => video);
    _videos[viewId] = video;
  } else {
    final video = _videos[viewId]!;

    // se ainda não tinha poster e agora chegou, atualiza
    if ((video.poster.isEmpty) && posterBytes != null && posterBytes.isNotEmpty) {
      final pUrl = _bytesToObjectUrl(posterBytes, mime: 'image/jpeg');
      _posterUrls[viewId] = pUrl;
      video.poster = pUrl;
      html.window.console.log('[web_video][$viewId] poster updated');
    }
  }

  return HtmlElementView(viewType: viewId);
}

void disposeWebVideoView(String viewId) {
  final v = _videos.remove(viewId);
  if (v != null) {
    v.pause();
    v.src = '';
    v.load();
  }

  final vUrl = _videoUrls.remove(viewId);
  if (vUrl != null) html.Url.revokeObjectUrl(vUrl);

  final pUrl = _posterUrls.remove(viewId);
  if (pUrl != null) html.Url.revokeObjectUrl(pUrl);

  html.window.console.log('[web_video][$viewId] disposed');
}