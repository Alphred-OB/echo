import 'dart:convert';
import 'package:http/http.dart' as http;

class EnrollResult {
  final bool success;
  final String? username;
  final String? deviceId;
  final String? error;

  EnrollResult({required this.success, this.username, this.deviceId, this.error});
}

class VerifyResult {
  final bool success;
  final String? error;

  VerifyResult({required this.success, this.error});
}

/// HTTP API client communicating with the Echo Node.js backend
class ApiService {
  /// Normalize base server URL
  static String normalizeUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Step 2: Enroll new device with public key JWK
  static Future<EnrollResult> enroll({
    required String serverUrl,
    required String enrollToken,
    required String deviceName,
    required Map<String, dynamic> publicKeyJwk,
  }) async {
    try {
      final base = normalizeUrl(serverUrl);
      final uri = Uri.parse('$base/api/enroll');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'enrollToken': enrollToken,
          'deviceName': deviceName,
          'publicKeyJwk': publicKeyJwk,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        return EnrollResult(
          success: true,
          username: data['username'],
          deviceId: data['deviceId'],
        );
      } else {
        return EnrollResult(
          success: false,
          error: data['error'] ?? 'Enrollment failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      return EnrollResult(success: false, error: e.toString());
    }
  }

  /// Pre-flight check: validates if nonce is genuine and belongs to this device's user
  /// Silently returns false if response is not 200 OK
  static Future<bool> checkNonce({
    required String serverUrl,
    required String nonce,
    required String deviceId,
  }) async {
    try {
      final base = normalizeUrl(serverUrl);
      final uri = Uri.parse('$base/api/login/check?nonce=$nonce&deviceId=$deviceId');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ok'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Verify login challenge: posts ECDSA P-256 signature to authorize laptop session
  static Future<VerifyResult> verifyLogin({
    required String serverUrl,
    required String nonce,
    required String deviceId,
    required String signature,
  }) async {
    try {
      final base = normalizeUrl(serverUrl);
      final uri = Uri.parse('$base/api/login/verify');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nonce': nonce,
          'deviceId': deviceId,
          'signature': signature,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['ok'] == true) {
        return VerifyResult(success: true);
      } else {
        return VerifyResult(
          success: false,
          error: data['error'] ?? 'Authentication failed (${response.statusCode})',
        );
      }
    } catch (e) {
      return VerifyResult(success: false, error: e.toString());
    }
  }

  /// Explicitly deny login challenge: informs backend to cancel session and alert laptop
  static Future<bool> denyLogin({
    required String serverUrl,
    required String nonce,
    String? deviceId,
  }) async {
    try {
      final base = normalizeUrl(serverUrl);
      final uri = Uri.parse('$base/api/login/deny');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nonce': nonce,
          if (deviceId != null) 'deviceId': deviceId,
        }),
      );

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
