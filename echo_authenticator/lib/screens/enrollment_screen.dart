import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../theme/echo_theme.dart';
import '../widgets/echo_wave_indicator.dart';

class EnrollmentScreen extends StatefulWidget {
  final VoidCallback onEnrolled;

  const EnrollmentScreen({super.key, required this.onEnrolled});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _nameController = TextEditingController(text: 'My Phone');
  final List<TextEditingController> _pinControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isProcessing = false;
  bool _isManualMode = false;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    _nameController.dispose();
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _pinFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _processEnrollUrl(rawValue);
        break;
      }
    }
  }

  void _processEnrollUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final token = uri.queryParameters['token'] ?? uri.queryParameters['enrollToken'];
      if (token == null || token.isEmpty) {
        setState(() {
          _errorMessage = 'Invalid QR code: missing enroll token';
        });
        return;
      }

      final serverUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      _performEnrollment(serverUrl: serverUrl, enrollToken: token);
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not parse QR code: $e';
      });
    }
  }

  String _getEnteredCode() {
    return _pinControllers.map((c) => c.text.trim()).join();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // User pasted multiple characters (e.g. 6-digit code)
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) {
        for (int i = 0; i < 6 && i < digits.length; i++) {
          _pinControllers[i].text = digits[i];
        }
        final targetIndex = (digits.length < 6) ? digits.length : 5;
        _pinFocusNodes[targetIndex].requestFocus();

        if (digits.length >= 6) {
          _submitManualCode();
        }
        return;
      }
    }

    if (value.isNotEmpty) {
      HapticFeedback.selectionClick();
      if (index < 5) {
        _pinFocusNodes[index + 1].requestFocus();
      } else {
        _pinFocusNodes[index].unfocus();
        _submitManualCode();
      }
    }
  }

  void _submitManualCode() {
    final code = _getEnteredCode();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits');
      return;
    }
    _performEnrollment(serverUrl: 'http://localhost:8000', enrollToken: code);
  }

  Future<void> _performEnrollment({
    required String serverUrl,
    required String enrollToken,
  }) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final keyPair = await CryptoService.generateKeyPair();
      final publicKeyJwk = CryptoService.exportPublicKeyJwk(keyPair.publicKey);
      final privateKeyStr = CryptoService.exportPrivateKey(keyPair.privateKey);

      final deviceName = _nameController.text.trim().isEmpty ? 'Phone Key' : _nameController.text.trim();

      final result = await ApiService.enroll(
        serverUrl: serverUrl,
        enrollToken: enrollToken,
        deviceName: deviceName,
        publicKeyJwk: publicKeyJwk,
      );

      if (!result.success) {
        HapticFeedback.vibrate();
        setState(() {
          _isProcessing = false;
          _errorMessage = result.error ?? 'Enrollment failed';
        });
        return;
      }

      HapticFeedback.heavyImpact();
      await StorageService.saveCredentials(
        privateKey: privateKeyStr,
        deviceId: result.deviceId!,
        username: result.username!,
        deviceName: deviceName,
        serverUrl: serverUrl,
      );

      widget.onEnrolled();
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Enrollment failed: $e';
      });
    }
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
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Pair with Computer',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isManualMode
                    ? 'Enter the 6-digit code shown on your screen'
                    : 'Scan the QR code on your computer screen',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Error banner
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: EchoTheme.badSoft,
                    borderRadius: BorderRadius.circular(EchoTheme.rSm),
                    border: Border.all(color: EchoTheme.bad.withValues(alpha: 0.3)),
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

              if (!_isManualMode) ...[
                // QR Scanner Viewport
                ClipRRect(
                  borderRadius: BorderRadius.circular(EchoTheme.rLg),
                  child: Container(
                    width: double.infinity,
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(EchoTheme.rLg),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: _onDetect,
                        ),
                        // Scanner reticle
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            border: Border.all(color: EchoTheme.accent, width: 2.5),
                            borderRadius: BorderRadius.circular(EchoTheme.rMd),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Switch to 6-digit manual entry
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isManualMode = true);
                  },
                  icon: const Icon(Icons.dialpad_rounded, size: 18),
                  label: const Text(
                    'Enter 6-digit code manually',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ] else ...[
                // ── 6-Digit Individual Pin Input Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: isDark ? EchoTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(EchoTheme.rLg),
                    border: Border.all(
                      color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 6 Individual Digit Boxes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < 6; i++) ...[
                            _buildDigitBox(i, isDark),
                            if (i == 2) const SizedBox(width: 12) else if (i < 5) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Pair Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _submitManualCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EchoTheme.accent,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(EchoTheme.rMd),
                            ),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Pair Device',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isManualMode = false);
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text(
                    'Switch back to camera scanner',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitBox(int index, bool isDark) {
    return SizedBox(
      width: 44,
      height: 52,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _pinControllers[index].text.isEmpty &&
              index > 0) {
            _pinFocusNodes[index - 1].requestFocus();
          }
        },
        child: TextField(
          controller: _pinControllers[index],
          focusNode: _pinFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontFamily: 'JetBrains Mono',
            color: EchoTheme.accent,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? EchoTheme.borderDark : const Color(0xFFCBD5E1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? EchoTheme.borderDark : const Color(0xFFE2E8F0),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: EchoTheme.accent,
                width: 2.0,
              ),
            ),
          ),
          onChanged: (val) => _onDigitChanged(index, val),
        ),
      ),
    );
  }
}
