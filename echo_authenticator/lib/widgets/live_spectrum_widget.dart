import 'package:flutter/material.dart';
import '../theme/echo_theme.dart';

class LiveSpectrumWidget extends StatelessWidget {
  final List<double> bins;
  final bool isListening;
  final bool hasUltrasound;

  const LiveSpectrumWidget({
    super.key,
    required this.bins,
    required this.isListening,
    this.hasUltrasound = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF06090F) : const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(EchoTheme.rMd),
        border: Border.all(
          color: hasUltrasound
              ? EchoTheme.accent
              : (isDark ? EchoTheme.borderDark : EchoTheme.borderStrongLight),
          width: hasUltrasound ? 2 : 1,
        ),
        boxShadow: hasUltrasound
            ? [
                BoxShadow(
                  color: EchoTheme.accent.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Canvas spectrum
          SizedBox(
            height: 52,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumPainter(
                bins: bins,
                isListening: isListening,
                hasUltrasound: hasUltrasound,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Frequency scale markers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '0 kHz',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: EchoTheme.dimLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hasUltrasound
                      ? EchoTheme.accent
                      : EchoTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '18–20 kHz Ultrasound',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hasUltrasound ? Colors.white : EchoTheme.accent,
                  ),
                ),
              ),
              const Text(
                '24 kHz',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  color: EchoTheme.dimLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> bins;
  final bool isListening;
  final bool hasUltrasound;

  _SpectrumPainter({
    required this.bins,
    required this.isListening,
    required this.hasUltrasound,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;

    final barCount = bins.length;
    final totalBarWidth = size.width / barCount;
    final barSpacing = 2.0;
    final barWidth = (totalBarWidth - barSpacing).clamp(1.0, 12.0);

    final bgPaint = Paint()..color = const Color(0x3364748B);
    final slatePaint = Paint()..color = const Color(0xFF64748B);
    final accentPaint = Paint()..color = EchoTheme.accent;
    final accentDimPaint = Paint()..color = EchoTheme.accent.withValues(alpha: 0.45);

    for (int i = 0; i < barCount; i++) {
      final x = i * totalBarWidth + (barSpacing / 2);
      final rawVal = bins[i].clamp(0.02, 1.0);
      final h = rawVal * size.height;
      final y = size.height - h;

      final isUltrasoundBin = (i >= (barCount * 0.72) && i <= (barCount * 0.90));

      Paint paint;
      if (!isListening) {
        paint = bgPaint;
      } else if (isUltrasoundBin) {
        paint = (rawVal > 0.25 || hasUltrasound) ? accentPaint : accentDimPaint;
      } else {
        paint = (rawVal > 0.08) ? slatePaint : bgPaint;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(1.5),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return true;
  }
}
