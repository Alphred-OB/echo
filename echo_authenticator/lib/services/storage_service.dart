import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Models stored device authentication credentials backed by hardware Keystore / Keychain
class DeviceCredentials {
  final String privateKey;
  final String deviceId;
  final String username;
  final String deviceName;
  final String serverUrl;
  final int createdAt;

  const DeviceCredentials({
    required this.privateKey,
    required this.deviceId,
    required this.username,
    required this.deviceName,
    required this.serverUrl,
    int? createdAt,
  }) : createdAt = createdAt ?? 0;

  Map<String, dynamic> toJson() => {
        'privateKey': privateKey,
        'deviceId': deviceId,
        'username': username,
        'deviceName': deviceName,
        'serverUrl': serverUrl,
        'createdAt': createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : createdAt,
      };

  factory DeviceCredentials.fromJson(Map<String, dynamic> json) => DeviceCredentials(
        privateKey: json['privateKey'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        username: json['username'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? 'Mobile Key',
        serverUrl: json['serverUrl'] as String? ?? 'http://localhost:8000',
        createdAt: json['createdAt'] as int? ?? 0,
      );
}

/// Secure storage service using iOS Keychain / Android Keystore
class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAccounts = 'echo_multi_accounts';
  static const _kActiveId = 'echo_active_account_id';
  static const _kThemeMode = 'echo_theme_mode'; // 'system', 'light', 'dark'

  // Legacy keys for migration
  static const _kLegacyPrivKey = 'echo_priv_key';
  static const _kLegacyDeviceId = 'echo_device_id';
  static const _kLegacyUsername = 'echo_username';
  static const _kLegacyDeviceName = 'echo_device_name';
  static const _kLegacyServerUrl = 'echo_server_url';

  /// Retrieve all enrolled accounts (auto-migrating legacy single account if needed)
  static Future<List<DeviceCredentials>> getAccounts() async {
    final rawJson = await _storage.read(key: _kAccounts);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(rawJson);
        return list
            .map((item) => DeviceCredentials.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // Check for legacy single-account migration
    final legacyPrivKey = await _storage.read(key: _kLegacyPrivKey);
    final legacyDeviceId = await _storage.read(key: _kLegacyDeviceId);
    final legacyUsername = await _storage.read(key: _kLegacyUsername);
    final legacyDeviceName = await _storage.read(key: _kLegacyDeviceName);
    final legacyServerUrl = await _storage.read(key: _kLegacyServerUrl);

    if (legacyPrivKey != null && legacyDeviceId != null && legacyUsername != null) {
      final migrated = DeviceCredentials(
        privateKey: legacyPrivKey,
        deviceId: legacyDeviceId,
        username: legacyUsername,
        deviceName: legacyDeviceName ?? 'Mobile Key',
        serverUrl: legacyServerUrl ?? 'http://localhost:8000',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await saveAccount(migrated);
      return [migrated];
    }

    return [];
  }

  /// Save or update an account
  static Future<void> saveAccount(DeviceCredentials creds) async {
    final accounts = await getAccounts();
    final index = accounts.indexWhere((a) => a.deviceId == creds.deviceId);
    if (index >= 0) {
      accounts[index] = creds;
    } else {
      accounts.add(creds);
    }

    final rawJson = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _kAccounts, value: rawJson);
    await setActiveAccountId(creds.deviceId);
  }

  /// Save newly enrolled device credentials
  static Future<void> saveCredentials({
    required String privateKey,
    required String deviceId,
    required String username,
    required String deviceName,
    required String serverUrl,
  }) async {
    final creds = DeviceCredentials(
      privateKey: privateKey,
      deviceId: deviceId,
      username: username,
      deviceName: deviceName,
      serverUrl: serverUrl,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await saveAccount(creds);
  }

  /// Remove an account by deviceId
  static Future<void> removeAccount(String deviceId) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.deviceId == deviceId);
    final rawJson = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _kAccounts, value: rawJson);

    final activeId = await getActiveAccountId();
    if (activeId == deviceId) {
      if (accounts.isNotEmpty) {
        await setActiveAccountId(accounts.first.deviceId);
      } else {
        await _storage.delete(key: _kActiveId);
      }
    }
  }

  /// Get active selected account ID
  static Future<String?> getActiveAccountId() async {
    return await _storage.read(key: _kActiveId);
  }

  /// Set active selected account ID
  static Future<void> setActiveAccountId(String deviceId) async {
    await _storage.write(key: _kActiveId, value: deviceId);
  }

  /// Retrieve currently active account credentials
  static Future<DeviceCredentials?> getCredentials() async {
    final accounts = await getAccounts();
    if (accounts.isEmpty) return null;

    final activeId = await getActiveAccountId();
    if (activeId != null) {
      final found = accounts.where((a) => a.deviceId == activeId);
      if (found.isNotEmpty) return found.first;
    }

    return accounts.first;
  }

  /// Check if at least one account is enrolled
  static Future<bool> isEnrolled() async {
    final accounts = await getAccounts();
    return accounts.isNotEmpty;
  }

  /// Theme Mode management ('light', 'dark', 'system')
  static Future<String> getThemeMode() async {
    final mode = await _storage.read(key: _kThemeMode);
    return mode ?? 'light';
  }

  static Future<void> setThemeMode(String mode) async {
    await _storage.write(key: _kThemeMode, value: mode);
  }

  /// Delete all credentials on full reset
  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
