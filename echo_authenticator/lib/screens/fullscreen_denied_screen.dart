import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/echo_theme.dart';
import '../widgets/echo_wave_indicator.dart';

class FullScreenDeniedScreen extends StatefulWidget {
  final String username;
  final String deviceName;
  final VoidCallback onDismiss;

  const FullScreenDeniedScreen({
    super.key,
    required this.username,
    required this.deviceName,
    required this.onDismiss,
  });

  @override
  State<FullScreenDeniedScreen> createState() => _FullScreenDeniedScreenState();
}

class _FullScreenDeniedScreenState extends State<FullScreenDeniedScreen>
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

    // Trigger reject buzz haptic pulse
    HapticFeedback.vibrate();

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

                // Animated Reject Orb with Expanding Red Waves
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
                            color: EchoTheme.bad.withValues(alpha: (1.0 - pulseVal) * 0.25),
                          ),
                        ),

                        // Middle Glow Wave
                        Container(
                          width: 130 + 30 * pulseVal,
                          height: 130 + 30 * pulseVal,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: EchoTheme.bad.withValues(alpha: (1.0 - pulseVal) * 0.4),
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
                              color: EchoTheme.bad,
                              boxShadow: [
                                BoxShadow(
                                  color: EchoTheme.bad.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.close_rounded,
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

                // Main Denied Text
                const Text(
                  'Sign-in Denied',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: EchoTheme.bad,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Text(
                  'The authentication request was rejected.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Account Card
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
                          color: EchoTheme.bad,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Account: ',
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
