// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';

Future<Uint8List?> generateVideoThumbWeb(Uint8List videoBytes) async {
  try {
    final blob = html.Blob([videoBytes], 'video/mp4');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final video = html.VideoElement()
      ..src = url
      ..muted = true
      ..preload = 'auto';

    // precisa anexar pra alguns browsers renderizarem frame
    video.style.position = 'fixed';
    video.style.left = '-99999px';
    video.style.top = '-99999px';
    html.document.body?.append(video);

    await video.onLoadedMetadata.first;

    final seekTo = (video.duration.isFinite && video.duration > 0)
        ? (video.duration > 0.2 ? 0.2 : 0.0)
        : 0.0;

    final seeked = video.onSeeked.first;
    video.currentTime = seekTo;
    await seeked;

    final w = (video.videoWidth ?? 0);
    final h = (video.videoHeight ?? 0);
    if (w <= 0 || h <= 0) {
      video.remove();
      html.Url.revokeObjectUrl(url);
      return null;
    }

    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    ctx.drawImage(video, 0, 0);

    final dataUrl = canvas.toDataUrl('image/jpeg', 0.75); // qualidade 75%
    final b64 = dataUrl.split(',').last;

    video.remove();
    html.Url.revokeObjectUrl(url);

    return Uint8List.fromList(base64Decode(b64));
  } catch (_) {
    return null;
  }
}