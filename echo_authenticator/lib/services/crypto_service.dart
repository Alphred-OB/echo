import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:pointycastle/export.dart';

/// Cryptographic service implementing NIST ECDSA P-256 (secp256r1) & SHA-256
/// Exactly matches Web Cryptography API & Echo Node.js server verification
class CryptoService {
  static final ECDomainParameters _domain = ECDomainParameters('secp256r1');

  /// Generate a fresh ECDSA P-256 Keypair
  static Future<AsymmetricKeyPair<ECPublicKey, ECPrivateKey>> generateKeyPair() async {
    final secureRandom = _getSecureRandom();
    final keyParams = ECKeyGeneratorParameters(_domain);
    final generator = ECKeyGenerator();
    generator.init(ParametersWithRandom(keyParams, secureRandom));

    final pair = generator.generateKeyPair();
    return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(
      pair.publicKey,
      pair.privateKey,
    );
  }

  /// Export Public Key as a JSON Web Key (JWK) map
  static Map<String, dynamic> exportPublicKeyJwk(ECPublicKey publicKey) {
    final xBytes = _bigIntTo32Bytes(publicKey.Q!.x!.toBigInteger()!);
    final yBytes = _bigIntTo32Bytes(publicKey.Q!.y!.toBigInteger()!);

    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _base64UrlNoPadding(xBytes),
      'y': _base64UrlNoPadding(yBytes),
      'key_ops': ['verify'],
    };
  }

  /// Export Private Key raw scalar d (32 bytes) as base64url
  static String exportPrivateKey(ECPrivateKey privateKey) {
    final dBytes = _bigIntTo32Bytes(privateKey.d!);
    return _base64UrlNoPadding(dBytes);
  }

  /// Recreate Keypair from stored private key d-string
  static AsymmetricKeyPair<ECPublicKey, ECPrivateKey> importPrivateKey(String base64UrlD) {
    final dBytes = _base64UrlDecode(base64UrlD);
    final d = _bytesToBigInt(dBytes);
    final privKey = ECPrivateKey(d, _domain);
    final pubPoint = _domain.G * d;
    final pubKey = ECPublicKey(pubPoint, _domain);

    return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(pubKey, privKey);
  }

  /// Sign the exact string: `echo-v1|<nonce>|<deviceId>` using ECDSA P-256 SHA-256
  /// Returns 64-byte raw IEEE P1363 (r || s) signature formatted as base64url
  static String signLoginChallenge({
    required ECPrivateKey privateKey,
    required String nonce,
    required String deviceId,
  }) {
    final message = 'echo-v1|$nonce|$deviceId';
    final messageBytes = Uint8List.fromList(utf8.encode(message));

    // Sign using SHA-256 Digest and deterministic HMAC
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64));
    signer.init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));

    final sig = signer.generateSignature(messageBytes) as ECSignature;

    final rBytes = _bigIntTo32Bytes(sig.r);
    final sBytes = _bigIntTo32Bytes(sig.s);

    final rawSig = Uint8List(64);
    rawSig.setRange(0, 32, rBytes);
    rawSig.setRange(32, 64, sBytes);

    return _base64UrlNoPadding(rawSig);
  }

  /// Compute the 2-digit match code: SHA-256(nonce)[0] % 90 + 10
  static String computeMatchCode(String nonce) {
    final hash = crypto_pkg.sha256.convert(utf8.encode(nonce)).bytes;
    final code = (hash[0] % 90) + 10;
    return code.toString();
  }

  // ── Cryptographic Helpers ──
  static SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  static Uint8List _bigIntTo32Bytes(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    final result = Uint8List(32);
    if (bytes.length >= 32) {
      result.setRange(0, 32, bytes.sublist(bytes.length - 32));
    } else {
      final pad = 32 - bytes.length;
      result.setRange(pad, 32, bytes);
    }
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static String _base64UrlNoPadding(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Uint8List _base64UrlDecode(String source) {
    var normalized = source.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return Uint8List.fromList(base64.decode(normalized));
  }
}
