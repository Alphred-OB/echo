import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/echo_theme.dart';
import '../widgets/echo_wave_indicator.dart';

class FullScreenSuccessScreen extends StatefulWidget {
  final String username;
  final String deviceName;
  final VoidCallback onDismiss;

  const FullScreenSuccessScreen({
    super.key,
    required this.username,
    required this.deviceName,
    required this.onDismiss,
  });

  @override
  State<FullScreenSuccessScreen> createState() => _FullScreenSuccessScreenState();
}

class _FullScreenSuccessScreenState extends State<FullScreenSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );

    _pulseAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
    );

    _animController.forward();

    // Trigger double celebration haptic pulse
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 180), () {
      HapticFeedback.mediumImpact();
    });

    _dismissTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EchoTheme.bgDark : EchoTheme.bgLight,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Top Logo
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EchoWaveIndicator(height: 18),
                    SizedBox(width: 8),
                    Text(
                      'echo',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // Animated Checkmark Orb with Expanding Green Waves
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final pulseVal = _pulseAnimation.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer Halo Wave
                        Container(
                          width: 140 + 60 * pulseVal,
                          height: 140 + 60 * pulseVal,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: EchoTheme.ok.withValues(alpha: (1.0 - pulseVal) * 0.25),
                          ),
                        ),

                        // Middle Glow Wave
                        Container(
                          width: 130 + 30 * pulseVal,
                          height: 130 + 30 * pulseVal,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: EchoTheme.ok.withValues(alpha: (1.0 - pulseVal) * 0.4),
                          ),
                        ),

                        // Center Icon Orb
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: EchoTheme.ok,
                              boxShadow: [
                                BoxShadow(
                                  color: EchoTheme.ok.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 64,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 38),

                // Main Confirmation Text
                const Text(
                  'Connected & Signed In!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: EchoTheme.ok,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Text(
                  'Cryptographic ultrasound signature verified',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Authenticated Account Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? EchoTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(EchoTheme.rMd),
                    border: Border.all(
                      color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: EchoTheme.ok,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Authenticated as ',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                        ),
                      ),
                      Text(
                        widget.username,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                // Close Button
                TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
