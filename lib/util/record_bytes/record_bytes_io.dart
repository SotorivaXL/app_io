import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readRecordedBytes(String pathOrUrl) async {
  return File(pathOrUrl).readAsBytes();
}

Future<void> deleteLocalIfExists(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<void> revokeIfBlobUrl(String url) async {
  // no-op no mobile/desktop
}
