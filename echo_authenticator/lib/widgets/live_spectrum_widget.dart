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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? EchoTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUltrasound
              ? EchoTheme.accent
              : (isDark ? EchoTheme.borderDark : const Color(0xFFE2E8F0)),
          width: hasUltrasound ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasUltrasound
                ? EchoTheme.accent.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: 38,
        width: double.infinity,
        child: CustomPaint(
          painter: _CleanSpectrumPainter(
            bins: bins,
            isListening: isListening,
            hasUltrasound: hasUltrasound,
          ),
        ),
      ),
    );
  }
}

class _CleanSpectrumPainter extends CustomPainter {
  final List<double> bins;
  final bool isListening;
  final bool hasUltrasound;

  _CleanSpectrumPainter({
    required this.bins,
    required this.isListening,
    required this.hasUltrasound,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;

    final barCount = bins.length;
    final totalBarWidth = size.width / barCount;
    const barSpacing = 2.5;
    final barWidth = (totalBarWidth - barSpacing).clamp(2.0, 8.0);

    final idlePaint = Paint()..color = const Color(0xFFF1F5F9);
    final ambientPaint = Paint()..color = const Color(0xFFCBD5E1);
    final accentPaint = Paint()..color = EchoTheme.accent;
    final accentSoftPaint = Paint()..color = EchoTheme.accent.withValues(alpha: 0.35);

    for (int i = 0; i < barCount; i++) {
      final x = i * totalBarWidth + (barSpacing / 2);
      final rawVal = bins[i].clamp(0.04, 1.0);
      final h = (rawVal * size.height).clamp(3.0, size.height);
      final y = size.height - h;

      final isUltrasoundBin = (i >= (barCount * 0.70) && i <= (barCount * 0.92));

      Paint paint;
      if (!isListening) {
        paint = idlePaint;
      } else if (isUltrasoundBin) {
        paint = (rawVal > 0.22 || hasUltrasound) ? accentPaint : accentSoftPaint;
      } else {
        paint = (rawVal > 0.08) ? ambientPaint : idlePaint;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(3),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CleanSpectrumPainter oldDelegate) {
    return true;
  }
}
