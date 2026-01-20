// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List> readRecordedBytes(String pathOrUrl) async {
  // record_web costuma retornar blob:<...>
  final req = await html.HttpRequest.request(
    pathOrUrl,
    responseType: 'arraybuffer',
  );

  final buffer = req.response as ByteBuffer;
  return buffer.asUint8List();
}

Future<void> deleteLocalIfExists(String path) async {
  // no-op no web
}

Future<void> revokeIfBlobUrl(String url) async {
  if (url.startsWith('blob:')) {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  }
}
