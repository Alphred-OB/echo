import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/enrollment_screen.dart';
import 'screens/listening_screen.dart';
import 'services/storage_service.dart';
import 'theme/echo_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
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
      title: 'Echo Authenticator',
      debugShowCheckedModeBanner: false,
      theme: EchoTheme.lightTheme,
      darkTheme: EchoTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
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
