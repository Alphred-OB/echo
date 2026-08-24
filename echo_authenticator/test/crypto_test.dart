import 'package:flutter_test/flutter_test.dart';
import 'package:echo_authenticator/services/crypto_service.dart';

void main() {
  test('CryptoService match code calculation matches spec', () {
    final code = CryptoService.computeMatchCode('testnonce123456');
    expect(code.length, 2);
    final numVal = int.parse(code);
    expect(numVal >= 10 && numVal <= 99, true);
  });

  test('CryptoService generates valid P-256 keypair, JWK export, import, and sign', () async {
    final keyPair = await CryptoService.generateKeyPair();
    final jwk = CryptoService.exportPublicKeyJwk(keyPair.publicKey);

    expect(jwk['kty'], 'EC');
    expect(jwk['crv'], 'P-256');
    expect(jwk['x'] != null, true);
    expect(jwk['y'] != null, true);
    expect(jwk['key_ops'], ['verify']);

    final privKeyStr = CryptoService.exportPrivateKey(keyPair.privateKey);
    expect(privKeyStr.isNotEmpty, true);

    // Test import
    final importedKeyPair = CryptoService.importPrivateKey(privKeyStr);
    final importedJwk = CryptoService.exportPublicKeyJwk(importedKeyPair.publicKey);
    expect(importedJwk['x'], jwk['x']);
    expect(importedJwk['y'], jwk['y']);

    final sig = CryptoService.signLoginChallenge(
      privateKey: keyPair.privateKey,
      nonce: 'AbCdEf1234567890',
      deviceId: 'dev_12345678',
    );

    expect(sig.isNotEmpty, true);
    expect(sig.contains('+'), false);
    expect(sig.contains('/'), false);
    expect(sig.contains('='), false);
  });
}
