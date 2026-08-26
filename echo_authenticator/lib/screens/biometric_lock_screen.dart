import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/biometric_service.dart';
import '../theme/echo_theme.dart';
import '../widgets/echo_wave_indicator.dart';

class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const BiometricLockScreen({super.key, required this.onUnlocked});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerBiometricPrompt();
    });
  }

  Future<void> _triggerBiometricPrompt() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final success = await BiometricService.authenticate(
      reason: 'Scan your fingerprint or face to unlock your Echo security keys',
    );

    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
    });

    if (success) {
      HapticFeedback.heavyImpact();
      widget.onUnlocked();
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = 'Biometric verification required to access keys.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EchoTheme.bgDark : EchoTheme.bgLight,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Brand Header
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EchoWaveIndicator(height: 22),
                    SizedBox(width: 10),
                    Text(
                      'echo',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Security Shield & Fingerprint Orb
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EchoTheme.accentSoft,
                    border: Border.all(
                      color: EchoTheme.accent.withValues(alpha: 0.25),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: EchoTheme.accent.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.fingerprint_rounded,
                      color: EchoTheme.accent,
                      size: 58,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'Echo Authenticator Locked',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                Text(
                  'Prove your identity with biometrics to unlock and access your ultrasonic signing keys.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: EchoTheme.badSoft,
                      borderRadius: BorderRadius.circular(EchoTheme.rSm),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: EchoTheme.bad,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const Spacer(flex: 2),

                // Unlock Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAuthenticating ? null : _triggerBiometricPrompt,
                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                    label: Text(
                      _isAuthenticating ? 'Scanning Biometrics…' : 'Unlock Authenticator',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EchoTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(EchoTheme.rMd),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
