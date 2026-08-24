import 'package:flutter/material.dart';
import '../theme/echo_theme.dart';

class EchoWaveIndicator extends StatefulWidget {
  final bool isAnimated;
  final double height;
  final Color? color;

  const EchoWaveIndicator({
    super.key,
    this.isAnimated = true,
    this.height = 18.0,
    this.color,
  });

  @override
  State<EchoWaveIndicator> createState() => _EchoWaveIndicatorState();
}

class _EchoWaveIndicatorState extends State<EchoWaveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? EchoTheme.accent;

    if (!widget.isAnimated || MediaQuery.of(context).disableAnimations) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(6, (i) {
          final heights = [0.4, 0.7, 1.0, 0.8, 0.5, 0.9];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3.0,
            height: widget.height * heights[i],
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(2.0),
            ),
          );
        }),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(6, (i) {
            final phase = (i * 0.15);
            final progress = (_controller.value + phase) % 1.0;
            // Smooth sine bounce
            final factor = 0.35 + 0.65 * (0.5 + 0.5 * (1 - (2 * (progress - 0.5)).abs()));

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.0,
              height: widget.height * factor,
              decoration: BoxDecoration(
                color: effectiveColor,
                borderRadius: BorderRadius.circular(2.0),
              ),
            );
          }),
        );
      },
    );
  }
}
