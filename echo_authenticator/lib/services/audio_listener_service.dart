import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:ggwave_flutter/ggwave_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioListenerService {
  GGWaveFlutter? _ggwave;
  bool _isListening = false;
  String? _lastNonce;

  final _nonceController = StreamController<String>.broadcast();
  final _spectrumController = StreamController<List<double>>.broadcast();
  Timer? _spectrumSimTimer;

  Stream<String> get onNonceDetected => _nonceController.stream;
  Stream<List<double>> get onSpectrumUpdate => _spectrumController.stream;
  bool get isListening => _isListening;

  AudioListenerService() {
    _initGgwave();
  }

  void _initGgwave() {
    try {
      final callbacks = GGWaveFlutterCallbacks(
        onMessageReceived: (message) {
          debugPrint('[EchoAudio] Received raw message: $message');
          _handleRawMessage(message);
        },
        onPlaybackStart: () {},
        onPlaybackStop: () {},
        onPlaybackComplete: () {},
        onCaptureStart: () {
          debugPrint('[EchoAudio] Capture started.');
        },
        onCaptureStop: () {
          debugPrint('[EchoAudio] Capture stopped.');
        },
      );

      _ggwave = GGWaveFlutter(callbacks);
    } catch (e) {
      debugPrint('[EchoAudio] Error initializing GGWaveFlutter: $e');
    }
  }

  void _handleRawMessage(String raw) {
    // Envelope pattern: E1:<16-char base64url nonce>
    final exp = RegExp(r'^E1:([A-Za-z0-9_-]{16})$');
    final match = exp.firstMatch(raw.trim());
    if (match != null) {
      final nonce = match.group(1)!;
      if (nonce == _lastNonce) return; // Prevent duplicate trigger
      _lastNonce = nonce;
      _nonceController.add(nonce);

      // Trigger visual ultrasound spike in the spectrum stream
      _emitUltrasoundSpike();
    }
  }

  /// Start listening for ultrasonic nonces
  Future<void> startListening() async {
    if (_isListening) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('[EchoAudio] Microphone permission not granted ($status)');
      return;
    }

    _isListening = true;

    try {
      await _ggwave?.toggleCapture();
    } catch (e) {
      debugPrint('[EchoAudio] toggleCapture error: $e');
    }

    _startSpectrumLoop();
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;
    _spectrumSimTimer?.cancel();
    _spectrumSimTimer = null;

    try {
      await _ggwave?.toggleCapture();
    } catch (e) {
      debugPrint('[EchoAudio] stopCapture error: $e');
    }

    // Emit flat baseline
    _spectrumController.add(List.filled(36, 0.04));
  }

  void _startSpectrumLoop() {
    _spectrumSimTimer?.cancel();
    final random = Random();

    // 30fps spectrum animation
    _spectrumSimTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_isListening) return;

      final bins = List<double>.generate(36, (i) {
        // Low frequencies (ambient room noise: 0-4 kHz, bins 0-8)
        if (i < 8) {
          return 0.08 + random.nextDouble() * 0.18;
        }
        // Mid frequencies: 4-16 kHz
        if (i < 26) {
          return 0.03 + random.nextDouble() * 0.06;
        }
        // Ultrasound band: 18-20 kHz (bins 27-32) - quiet during ambient
        return 0.02 + random.nextDouble() * 0.04;
      });

      _spectrumController.add(bins);
    });
  }

  void _emitUltrasoundSpike() {
    final random = Random();
    final bins = List<double>.generate(36, (i) {
      if (i >= 26 && i <= 32) {
        // High resonance peak in 18-20 kHz ultrasound band
        return 0.85 + random.nextDouble() * 0.15;
      }
      return 0.06 + random.nextDouble() * 0.1;
    });
    _spectrumController.add(bins);
  }

  void dispose() {
    stopListening();
    _nonceController.close();
    _spectrumController.close();
  }
}
