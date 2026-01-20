import 'dart:math' as math;
import 'package:flutter/material.dart';

class WebPeaksWaveform extends StatelessWidget {
  final List<double> peaks;        // 0..1
  final double progress;           // 0..1
  final double height;
  final double barWidth;
  final double spacing;
  final BorderRadius radius;

  const WebPeaksWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.height = 34,
    this.barWidth = 3,
    this.spacing = 3,
    this.radius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: radius,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _PeaksPainter(
          peaks: peaks,
          progress: progress,
          bg: cs.onSurface.withOpacity(.08),
          fixed: cs.onSurface.withOpacity(.28),
          live: cs.primary,
          barWidth: barWidth,
          spacing: spacing,
        ),
      ),
    );
  }
}

class _PeaksPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color bg;
  final Color fixed;
  final Color live;
  final double barWidth;
  final double spacing;

  _PeaksPainter({
    required this.peaks,
    required this.progress,
    required this.bg,
    required this.fixed,
    required this.live,
    required this.barWidth,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // fundo
    final bgPaint = Paint()..color = bg;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // quantas barras cabem de verdade
    final step = barWidth + spacing;
    final maxBars = (size.width / step).floor().clamp(1, peaks.length);
    final startIndex = 0;

    // progress em barras
    final progBars = (progress * maxBars).clamp(0.0, maxBars.toDouble());

    final fixedPaint = Paint()
      ..color = fixed
      ..style = PaintingStyle.fill;

    final livePaint = Paint()
      ..color = live
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;

    for (int i = 0; i < maxBars; i++) {
      final p = peaks[startIndex + i];
      // altura mínima pra não sumir e máxima pra não estourar
      final h = math.max(4.0, p * (size.height - 2));
      final top = centerY - h / 2;

      final x = i * step;

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, h),
        const Radius.circular(2),
      );

      canvas.drawRRect(r, i < progBars ? livePaint : fixedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PeaksPainter old) {
    return old.peaks != peaks ||
        old.progress != progress ||
        old.bg != bg ||
        old.fixed != fixed ||
        old.live != live ||
        old.barWidth != barWidth ||
        old.spacing != spacing;
  }
}
