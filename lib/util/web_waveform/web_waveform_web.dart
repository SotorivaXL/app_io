import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_util' as js_util;
import 'package:web/web.dart' as web;

Future<List<double>?> extractPeaks({
  required Uint8List audioBytes,
  required int bars,
}) async {
  web.AudioContext? ctx;

  try {
    ctx = web.AudioContext();

    // Uint8List -> JSUint8Array
    final jsU8 = audioBytes.toJS;

    // ✅ pega o ArrayBuffer via JS: jsU8.buffer
    final jsBuf = js_util.getProperty<JSAny>(jsU8, 'buffer');

    // decodeAudioData(ArrayBuffer) -> Promise<AudioBuffer>
    final web.AudioBuffer audioBuffer =
    await js_util.promiseToFuture<web.AudioBuffer>(
      ctx.decodeAudioData(jsBuf as dynamic),
    );

    final channels = audioBuffer.numberOfChannels.toInt();
    if (channels <= 0) return null;

    // getChannelData(i) -> JSFloat32Array (typed array JS)
    final ch0 = audioBuffer.getChannelData(0);
    final ch1 = channels > 1 ? audioBuffer.getChannelData(1) : null;

    // ✅ length via JS: ch0.length
    final totalSamples =
    js_util.getProperty<num>(ch0 as dynamic, 'length').toInt();
    if (totalSamples <= 0) return null;

    final win = (totalSamples / bars).floor().clamp(1, totalSamples);

    final peaks = List<double>.filled(bars, 0.0);
    int idx = 0;
    double maxRms = 1e-9;

    for (int b = 0; b < bars; b++) {
      final start = idx;
      final end = math.min(start + win, totalSamples);
      if (start >= end) break;

      double sumSq = 0.0;

      for (int i = start; i < end; i++) {
        // ✅ ler amostra via JS: ch0[i]
        final v0 = js_util.getProperty<num>(ch0 as dynamic, i).toDouble();

        double v = v0;
        if (ch1 != null) {
          final v1 = js_util.getProperty<num>(ch1 as dynamic, i).toDouble();
          v = (v0 + v1) * 0.5;
        }

        sumSq += v * v;
      }

      final rms = math.sqrt(sumSq / (end - start));
      peaks[b] = rms;
      if (rms > maxRms) maxRms = rms;

      idx = end;
    }

    // normaliza 0..1
    for (int i = 0; i < peaks.length; i++) {
      peaks[i] = (peaks[i] / maxRms).clamp(0.0, 1.0);
    }

    try {
      ctx.close();
    } catch (_) {}

    return peaks;
  } catch (_) {
    try {
      ctx?.close();
    } catch (_) {}
    return null;
  }
}