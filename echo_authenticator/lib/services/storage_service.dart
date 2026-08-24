import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Models stored device authentication credentials backed by hardware Keystore / Keychain
class DeviceCredentials {
  final String privateKey;
  final String deviceId;
  final String username;
  final String deviceName;
  final String serverUrl;

  const DeviceCredentials({
    required this.privateKey,
    required this.deviceId,
    required this.username,
    required this.deviceName,
    required this.serverUrl,
  });
}

/// Secure storage service using iOS Keychain / Android Keystore
class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kPrivateKey = 'echo_priv_key';
  static const _kDeviceId = 'echo_device_id';
  static const _kUsername = 'echo_username';
  static const _kDeviceName = 'echo_device_name';
  static const _kServerUrl = 'echo_server_url';

  /// Save enrolled device credentials securely
  static Future<void> saveCredentials({
    required String privateKey,
    required String deviceId,
    required String username,
    required String deviceName,
    required String serverUrl,
  }) async {
    await _storage.write(key: _kPrivateKey, value: privateKey);
    await _storage.write(key: _kDeviceId, value: deviceId);
    await _storage.write(key: _kUsername, value: username);
    await _storage.write(key: _kDeviceName, value: deviceName);
    await _storage.write(key: _kServerUrl, value: serverUrl);
  }

  /// Retrieve stored credentials
  static Future<DeviceCredentials?> getCredentials() async {
    final privKey = await _storage.read(key: _kPrivateKey);
    final deviceId = await _storage.read(key: _kDeviceId);
    final username = await _storage.read(key: _kUsername);
    final deviceName = await _storage.read(key: _kDeviceName);
    final serverUrl = await _storage.read(key: _kServerUrl);

    if (privKey == null || deviceId == null || username == null || serverUrl == null) {
      return null;
    }

    return DeviceCredentials(
      privateKey: privKey,
      deviceId: deviceId,
      username: username,
      deviceName: deviceName ?? 'Mobile Key',
      serverUrl: serverUrl,
    );
  }

  /// Check if device is enrolled
  static Future<bool> isEnrolled() async {
    final deviceId = await _storage.read(key: _kDeviceId);
    final privKey = await _storage.read(key: _kPrivateKey);
    return deviceId != null && privKey != null;
  }

  /// Delete credentials on device unpair / reset
  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
