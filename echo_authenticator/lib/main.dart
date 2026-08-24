import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/enrollment_screen.dart';
import 'screens/listening_screen.dart';
import 'services/storage_service.dart';
import 'theme/echo_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Request runtime microphone and camera permissions on startup
  try {
    await [
      Permission.microphone,
      Permission.camera,
    ].request();
  } catch (e) {
    debugPrint('Permission request error: $e');
  }

  runApp(const EchoAuthenticatorApp());
}

class EchoAuthenticatorApp extends StatefulWidget {
  const EchoAuthenticatorApp({super.key});

  @override
  State<EchoAuthenticatorApp> createState() => _EchoAuthenticatorAppState();
}

class _EchoAuthenticatorAppState extends State<EchoAuthenticatorApp> {
  DeviceCredentials? _credentials;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkEnrollment();
  }

  Future<void> _checkEnrollment() async {
    final creds = await StorageService.getCredentials();
    if (mounted) {
      setState(() {
        _credentials = creds;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo Key',
      debugShowCheckedModeBanner: false,
      theme: EchoTheme.lightTheme,
      themeMode: ThemeMode.light, // Set pure white light mode as requested
      home: _isLoading
          ? const Scaffold(
              backgroundColor: EchoTheme.bgLight,
              body: Center(
                child: CircularProgressIndicator(color: EchoTheme.accent),
              ),
            )
          : (_credentials != null
              ? ListeningScreen(
                  credentials: _credentials!,
                  onUnpaired: () {
                    setState(() => _credentials = null);
                  },
                )
              : EnrollmentScreen(
                  onEnrolled: () {
                    _checkEnrollment();
                  },
                )),
    );
  }
}
