import 'record_bytes_io.dart'
if (dart.library.html) 'record_bytes_web.dart' as impl;

import 'dart:typed_data';

Future<Uint8List> readRecordedBytes(String pathOrUrl) =>
    impl.readRecordedBytes(pathOrUrl);

Future<void> deleteLocalIfExists(String path) =>
    impl.deleteLocalIfExists(path);

Future<void> revokeIfBlobUrl(String url) =>
    impl.revokeIfBlobUrl(url);
