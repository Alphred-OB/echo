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

class _ListeningScreenState extends State<ListeningScreen> {
  final AudioListenerService _audioService = AudioListenerService();
  StreamSubscription<String>? _nonceSub;
  StreamSubscription<List<double>>? _spectrumSub;

  List<double> _currentBins = List.filled(36, 0.04);
  bool _isListening = false;
  bool _hasUltrasound = false;
  Timer? _ultrasoundFlashTimer;

  final List<String> _activityLog = [];

  @override
  void initState() {
    super.initState();
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
    HapticFeedback.selectionClick();
    if (_isListening) {
      await _audioService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      await _audioService.startListening();
      if (mounted) setState(() => _isListening = true);
    }
  }

  Future<void> _handleNonceReceived(String nonce) async {
    setState(() => _hasUltrasound = true);
    _ultrasoundFlashTimer?.cancel();
    _ultrasoundFlashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _hasUltrasound = false);
    });

    // 1. Silent pre-flight check
    final isMine = await ApiService.checkNonce(
      serverUrl: widget.credentials.serverUrl,
      nonce: nonce,
      deviceId: widget.credentials.deviceId,
    );

    if (!isMine) {
      debugPrint('[Echo] Nonce $nonce ignored — not for this user.');
      return;
    }

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
          onDismiss: () => Navigator.of(ctx).pop(),
          onApproved: () {
            Navigator.of(ctx).pop();
            setState(() {
              _activityLog.insert(
                0,
                'Sign-in approved · Code $matchCode · ${TimeOfDay.now().format(context)}',
              );
            });
          },
        ),
      );
    }
  }

  void _showUnpairDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
          'This will remove your security key from this phone. You will need to re-scan the QR code to use it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
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
              'echo key',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 19,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Minimalist User & Status Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? EchoTheme.surfaceDark : EchoTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(EchoTheme.rMd),
                  border: Border.all(
                    color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? EchoTheme.ok : EchoTheme.dimLight,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.credentials.username,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _isListening ? 'Listening' : 'Paused',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isListening ? EchoTheme.ok : EchoTheme.dimLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Live Ultrasound Spectrum ──
              LiveSpectrumWidget(
                bins: _currentBins,
                isListening: _isListening,
                hasUltrasound: _hasUltrasound,
              ),
              const SizedBox(height: 18),

              // ── Toggle Listening Button ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleListen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListening ? EchoTheme.bad : EchoTheme.ok,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(EchoTheme.rMd),
                    ),
                  ),
                  icon: Icon(
                    _isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    _isListening ? 'Stop Listening' : 'Start Listening',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Activity History ──
              if (_activityLog.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? EchoTheme.dimDark : EchoTheme.dimLight,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: _activityLog.map((log) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? EchoTheme.surfaceDark : EchoTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(EchoTheme.rSm),
                        border: Border.all(
                          color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: EchoTheme.ok, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              log,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
