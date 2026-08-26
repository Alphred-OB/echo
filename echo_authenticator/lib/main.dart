import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/accounts_screen.dart';
import 'screens/biometric_lock_screen.dart';
import 'screens/enrollment_screen.dart';
import 'services/biometric_service.dart';
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
  ThemeMode _themeMode = ThemeMode.light;
  bool _isLocked = true;
  bool _isLoading = true;
  bool _hasAccounts = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 1. Load saved theme preference
    final savedTheme = await StorageService.getThemeMode();
    _themeMode = (savedTheme == 'dark') ? ThemeMode.dark : ThemeMode.light;

    // 2. Check if accounts exist
    final accounts = await StorageService.getAccounts();
    _hasAccounts = accounts.isNotEmpty;

    // 3. Check biometric availability
    final biometricAvail = await BiometricService.isBiometricAvailable();
    // If no accounts yet or biometric unsupported, skip initial lock
    _isLocked = _hasAccounts && biometricAvail;

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleTheme() async {
    final nextMode = (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;
    setState(() {
      _themeMode = nextMode;
    });
    await StorageService.setThemeMode((nextMode == ThemeMode.dark) ? 'dark' : 'light');
  }

  void _lockApp() {
    setState(() {
      _isLocked = true;
    });
  }

  void _unlockApp() {
    setState(() {
      _isLocked = false;
    });
  }

  Future<void> _refreshAccounts() async {
    final accounts = await StorageService.getAccounts();
    if (mounted) {
      setState(() {
        _hasAccounts = accounts.isNotEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = (_themeMode == ThemeMode.dark);

    return MaterialApp(
      title: 'Echo Authenticator',
      debugShowCheckedModeBanner: false,
      theme: EchoTheme.lightTheme,
      darkTheme: EchoTheme.darkTheme,
      themeMode: _themeMode,
      home: _isLoading
          ? Scaffold(
              backgroundColor: isDark ? EchoTheme.bgDark : EchoTheme.bgLight,
              body: const Center(
                child: CircularProgressIndicator(color: EchoTheme.accent),
              ),
            )
          : (_isLocked
              ? BiometricLockScreen(onUnlocked: _unlockApp)
              : (_hasAccounts
                  ? AccountsScreen(
                      isDark: isDark,
                      onToggleTheme: _toggleTheme,
                      onLockApp: _lockApp,
                    )
                  : EnrollmentScreen(
                      onEnrolled: () async {
                        await _refreshAccounts();
                        _unlockApp();
                      },
                    ))),
    );
  }
}
