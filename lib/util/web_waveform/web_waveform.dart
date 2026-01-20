import 'web_waveform_io.dart'
if (dart.library.html) 'web_waveform_web.dart' as impl;
import 'dart:typed_data';

Future<List<double>?> extractPeaks({
  required Uint8List audioBytes,
  required int bars,
}) => impl.extractPeaks(audioBytes: audioBytes, bars: bars);
