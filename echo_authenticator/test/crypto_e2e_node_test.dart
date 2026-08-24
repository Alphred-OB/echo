import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_authenticator/services/crypto_service.dart';

void main() {
  test('Signature verified by Node.js WebCrypto subtle.verify', () async {
    final keyPair = await CryptoService.generateKeyPair();
    final jwk = CryptoService.exportPublicKeyJwk(keyPair.publicKey);
    final jwkJson = jsonEncode(jwk);

    const nonce = 'AbCdEf1234567890';
    const deviceId = 'dev_12345678';

    final sig = CryptoService.signLoginChallenge(
      privateKey: keyPair.privateKey,
      nonce: nonce,
      deviceId: deviceId,
    );

    // Call node to verify with WebCrypto
    final nodeScript = '''
    const { subtle } = require('crypto').webcrypto;
    (async () => {
      const jwk = $jwkJson;
      const key = await subtle.importKey(
        'jwk',
        jwk,
        { name: 'ECDSA', namedCurve: 'P-256' },
        true,
        ['verify']
      );
      const data = new TextEncoder().encode('echo-v1|$nonce|$deviceId');
      const sig = Buffer.from('$sig', 'base64url');
      const ok = await subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, data);
      console.log('VERIFY_RESULT:' + ok);
    })();
    ''';

    final result = await Process.run('node', ['-e', nodeScript]);
    expect(result.stdout.toString().contains('VERIFY_RESULT:true'), true);
  });
}
