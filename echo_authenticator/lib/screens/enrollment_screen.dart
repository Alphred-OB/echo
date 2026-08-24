import 'package:flutter/material.dart';
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
  final TextEditingController _urlController = TextEditingController(text: 'http://localhost:8000');
  final TextEditingController _tokenController = TextEditingController();

  bool _isProcessing = false;
  bool _isManualMode = false;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
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
        setState(() {
          _isProcessing = false;
          _errorMessage = result.error ?? 'Enrollment failed';
        });
        return;
      }

      await StorageService.saveCredentials(
        privateKey: privateKeyStr,
        deviceId: result.deviceId!,
        username: result.username!,
        deviceName: deviceName,
        serverUrl: serverUrl,
      );

      widget.onEnrolled();
    } catch (e) {
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
              const SizedBox(height: 8),
              Text(
                'Pair with Computer',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? EchoTheme.textDark : EchoTheme.textLight,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                'Scan the QR code on your computer screen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                ),
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EchoTheme.badSoft,
                    borderRadius: BorderRadius.circular(EchoTheme.rSm),
                    border: Border.all(color: EchoTheme.bad.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: EchoTheme.bad,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (!_isManualMode) ...[
                // Viewfinder Card
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(EchoTheme.rLg),
                    border: Border.all(
                      color: isDark ? EchoTheme.borderDark : EchoTheme.borderStrongLight,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: EchoTheme.accent.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                      ),
                      Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          border: Border.all(color: EchoTheme.accent, width: 2.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                TextButton(
                  onPressed: () => setState(() => _isManualMode = true),
                  child: const Text(
                    'Enter pairing token manually',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ] else ...[
                // Manual Entry Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Server URL',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'http://localhost:8000',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(EchoTheme.rSm),
                              borderSide: BorderSide(
                                color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        const Text(
                          'Enroll Token',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _tokenController,
                          decoration: InputDecoration(
                            hintText: 'Paste token from signup link',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(EchoTheme.rSm),
                              borderSide: BorderSide(
                                color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isProcessing
                                ? null
                                : () {
                                    final token = _tokenController.text.trim();
                                    final url = _urlController.text.trim();
                                    if (token.isEmpty) {
                                      setState(() => _errorMessage = 'Please enter an enroll token');
                                      return;
                                    }
                                    _performEnrollment(serverUrl: url, enrollToken: token);
                                  },
                            child: _isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text('Pair Device'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextButton(
                  onPressed: () => setState(() => _isManualMode = false),
                  child: const Text(
                    'Switch back to camera scanner',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
