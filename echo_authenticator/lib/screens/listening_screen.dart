import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/audio_listener_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../theme/echo_theme.dart';
import '../widgets/approve_sheet.dart';
import '../widgets/echo_wave_indicator.dart';
import '../widgets/live_spectrum_widget.dart';

class ListeningScreen extends StatefulWidget {
  final DeviceCredentials credentials;
  final VoidCallback onUnpaired;

  const ListeningScreen({
    super.key,
    required this.credentials,
    required this.onUnpaired,
  });

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen>
    with SingleTickerProviderStateMixin {
  final AudioListenerService _audioService = AudioListenerService();
  StreamSubscription<String>? _nonceSub;
  StreamSubscription<List<double>>? _spectrumSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<double> _currentBins = List.filled(36, 0.04);
  bool _isListening = false;
  bool _hasUltrasound = false;
  Timer? _ultrasoundFlashTimer;
  bool _isButtonPressed = false;

  final List<String> _activityLog = [];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );

    _startListeningAuto();

    _spectrumSub = _audioService.onSpectrumUpdate.listen((bins) {
      if (mounted) {
        setState(() {
          _currentBins = bins;
        });
      }
    });

    _nonceSub = _audioService.onNonceDetected.listen(_handleNonceReceived);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nonceSub?.cancel();
    _spectrumSub?.cancel();
    _ultrasoundFlashTimer?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _startListeningAuto() async {
    await _audioService.startListening();
    if (mounted) {
      setState(() => _isListening = true);
    }
  }

  Future<void> _toggleListen() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _audioService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      await _audioService.startListening();
      if (mounted) setState(() => _isListening = true);
    }
  }

  Future<void> _handleNonceReceived(String nonce) async {
    // 📳 Tactile Ultrasound Capture Bump
    HapticFeedback.heavyImpact();

    setState(() => _hasUltrasound = true);
    _ultrasoundFlashTimer?.cancel();
    _ultrasoundFlashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _hasUltrasound = false);
    });

    // 1. Silent pre-flight check
    final isMine = await ApiService.checkNonce(
      serverUrl: widget.credentials.serverUrl,
      nonce: nonce,
      deviceId: widget.credentials.deviceId,
    );

    if (!isMine) {
      debugPrint('[Echo] Nonce $nonce ignored — belongs to another session.');
      return;
    }

    // Secondary haptic alert for match code prompt
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.mediumImpact();

    // 2. Match code derivation
    final matchCode = CryptoService.computeMatchCode(nonce);

    // 3. Open prompt bottom sheet
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => ApproveSheet(
          nonce: nonce,
          matchCode: matchCode,
          credentials: widget.credentials,
          onDismiss: () {
            HapticFeedback.lightImpact();
            Navigator.of(ctx).pop();
          },
          onApproved: () {
            HapticFeedback.heavyImpact();
            Navigator.of(ctx).pop();
            setState(() {
              _activityLog.insert(
                0,
                'Approved · Code $matchCode · ${TimeOfDay.now().format(context)}',
              );
            });
          },
        ),
      );
    }
  }

  void _showUnpairDialog() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
          'This will remove your security key from this phone. You will need to re-scan the QR code to use it again.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              HapticFeedback.heavyImpact();
              Navigator.of(ctx).pop();
              await StorageService.clear();
              widget.onUnpaired();
            },
            style: ElevatedButton.styleFrom(backgroundColor: EchoTheme.bad),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EchoTheme.bgDark : EchoTheme.bgLight,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EchoWaveIndicator(height: 16),
            SizedBox(width: 8),
            Text(
              'echo',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 21,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: _showUnpairDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Minimalist User Badge ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? EchoTheme.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? EchoTheme.ok : EchoTheme.dimLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.credentials.username,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '· ${widget.credentials.deviceName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // ── Interactive Central Acoustic Pulse Core (Fixed 220x220 Frame) ──
              SizedBox(
                width: 220,
                height: 220,
                child: Center(
                  child: GestureDetector(
                    onTapDown: (_) {
                      setState(() => _isButtonPressed = true);
                      HapticFeedback.lightImpact();
                    },
                    onTapUp: (_) {
                      setState(() => _isButtonPressed = false);
                      _toggleListen();
                    },
                    onTapCancel: () {
                      setState(() => _isButtonPressed = false);
                    },
                    child: AnimatedScale(
                      scale: _isButtonPressed ? 0.92 : 1.0,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Harmonic Breathing Pulse Rings (Continuous Physics)
                          if (_isListening)
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                final v = _pulseAnimation.value;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer Soft Expanding Halo
                                    Container(
                                      width: 170 + 38 * v,
                                      height: 170 + 38 * v,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (_hasUltrasound ? EchoTheme.accent : EchoTheme.accent)
                                            .withValues(alpha: _hasUltrasound ? 0.25 : 0.03 + 0.05 * v),
                                      ),
                                    ),
                                    // Middle Focused Harmonic Wave
                                    Container(
                                      width: 144 + 18 * v,
                                      height: 144 + 18 * v,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (_hasUltrasound ? EchoTheme.accent : EchoTheme.accent)
                                            .withValues(alpha: _hasUltrasound ? 0.35 : 0.06 + 0.06 * v),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                          // Outer Static Ring
                          Container(
                            width: 156,
                            height: 156,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? (_hasUltrasound
                                      ? EchoTheme.accent.withValues(alpha: 0.15)
                                      : EchoTheme.accentSoft)
                                  : const Color(0xFFF1F5F9),
                              border: Border.all(
                                color: _isListening
                                    ? (_hasUltrasound
                                        ? EchoTheme.accent
                                        : EchoTheme.accent.withValues(alpha: 0.25))
                                    : const Color(0xFFE2E8F0),
                                width: 2,
                              ),
                            ),
                          ),

                          // Core Button Center
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening ? EchoTheme.accent : const Color(0xFF64748B),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isListening ? EchoTheme.accent : const Color(0xFF64748B))
                                      .withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                                color: Colors.white,
                                size: 44,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Status Text
              Text(
                _hasUltrasound
                    ? 'Acoustic Nonce Detected!'
                    : (_isListening ? 'Listening for sound…' : 'Listening Paused'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _hasUltrasound
                      ? EchoTheme.accent
                      : (_isListening
                          ? (isDark ? EchoTheme.textDark : EchoTheme.textLight)
                          : EchoTheme.dimLight),
                ),
              ),
              const SizedBox(height: 4),

              Text(
                _isListening
                    ? 'Hold phone near your computer screen'
                    : 'Tap the button to start listening',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                ),
              ),

              const Spacer(flex: 1),

              // ── Live Micro Spectrum Bar ──
              LiveSpectrumWidget(
                bins: _currentBins,
                isListening: _isListening,
                hasUltrasound: _hasUltrasound,
              ),

              const SizedBox(height: 16),

              // ── Recent Activity Pill ──
              if (_activityLog.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? EchoTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: EchoTheme.ok, size: 15),
                      const SizedBox(width: 8),
                      Text(
                        _activityLog.first,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
