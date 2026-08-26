import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../theme/echo_theme.dart';
import 'echo_wave_indicator.dart';

class ApproveSheet extends StatefulWidget {
  final String nonce;
  final String matchCode;
  final DeviceCredentials credentials;
  final VoidCallback onDismiss;
  final VoidCallback onApproved;
  final VoidCallback onDenied;

  const ApproveSheet({
    super.key,
    required this.nonce,
    required this.matchCode,
    required this.credentials,
    required this.onDismiss,
    required this.onApproved,
    required this.onDenied,
  });

  @override
  State<ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<ApproveSheet> with SingleTickerProviderStateMixin {
  bool _isSigning = false;
  bool _isDenying = false;
  String? _errorMessage;

  late AnimationController _springController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _springController,
      curve: EchoTheme.springCurve,
    );

    _springController.forward();
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  Future<void> _handleDeny() async {
    if (_isSigning || _isDenying) return;

    HapticFeedback.mediumImpact();
    setState(() => _isDenying = true);

    // Fire and notify backend to cancel the waiting laptop session
    ApiService.denyLogin(
      serverUrl: widget.credentials.serverUrl,
      nonce: widget.nonce,
      deviceId: widget.credentials.deviceId,
    );

    // Immediately trigger Denied Screen
    if (mounted) {
      widget.onDenied();
    }
  }

  Future<void> _handleApprove() async {
    if (_isSigning || _isDenying) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isSigning = true;
      _errorMessage = null;
    });

    try {
      // 1. Recreate KeyPair from hardware Keystore
      final keyPair = CryptoService.importPrivateKey(widget.credentials.privateKey);

      // 2. Sign challenge message: echo-v1|<nonce>|<deviceId>
      final signature = CryptoService.signLoginChallenge(
        privateKey: keyPair.privateKey,
        nonce: widget.nonce,
        deviceId: widget.credentials.deviceId,
      );

      // 3. Post to verification server
      final result = await ApiService.verifyLogin(
        serverUrl: widget.credentials.serverUrl,
        nonce: widget.nonce,
        deviceId: widget.credentials.deviceId,
        signature: signature,
      );

      if (result.success) {
        // Immediately pop sheet and trigger Full-Screen Success Screen
        if (mounted) {
          widget.onApproved();
        }
      } else {
        HapticFeedback.vibrate();
        if (mounted) {
          setState(() {
            _isSigning = false;
            _errorMessage = result.error ?? 'Authentication rejected';
          });
        }
      }
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) {
        setState(() {
          _isSigning = false;
          _errorMessage = 'Signing failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: isDark ? EchoTheme.surfaceDark : EchoTheme.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(EchoTheme.rLg)),
          border: Border.all(
            color: isDark ? EchoTheme.borderDark : EchoTheme.borderStrongLight,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? EchoTheme.dimDark : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            const EchoWaveIndicator(height: 18),
            const SizedBox(height: 14),

            Text(
              'Sign-in Request',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? EchoTheme.textDark : EchoTheme.textLight,
              ),
            ),
            const SizedBox(height: 4),

            Text(
              'Confirm the 2-digit code on your computer screen',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
              ),
            ),
            const SizedBox(height: 20),

            // ── Match Code Hero Card ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF06090F) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(EchoTheme.rMd),
                border: Border.all(
                  color: EchoTheme.accent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'MATCH CODE',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: EchoTheme.dimLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.matchCode,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4.0,
                      color: EchoTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: EchoTheme.badSoft,
                  borderRadius: BorderRadius.circular(EchoTheme.rSm),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: EchoTheme.bad, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ── Actions ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_isSigning || _isDenying) ? null : _handleDeny,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(EchoTheme.rMd),
                      ),
                      side: BorderSide(
                        color: isDark ? EchoTheme.borderDark : EchoTheme.borderStrongLight,
                      ),
                    ),
                    child: _isDenying
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(EchoTheme.bad),
                            ),
                          )
                        : Text(
                            'Deny',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark ? EchoTheme.textDark : EchoTheme.textLight,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isSigning || _isDenying) ? null : _handleApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EchoTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(EchoTheme.rMd),
                      ),
                    ),
                    child: _isSigning
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_open_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Approve & Sign',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
