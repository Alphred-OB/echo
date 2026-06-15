// Test validation of GET /api/login/check endpoint (cross-talk prevention).
// Run: node tests/test-cross-talk.js   (server must be running)
const { subtle } = require('crypto').webcrypto;
const BASE = process.env.ECHO_URL || 'http://localhost:8000';

let pass = 0, failCount = 0;
function check(name, cond) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { failCount++; console.log('  ✗ ' + name); }
}

async function api(method, path, body = null) {
  const opts = { method, headers: {} };
  if (body) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(BASE + path, opts);
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

async function enrollUser(username) {
  const keys = await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
  const publicKeyJwk = await subtle.exportKey('jwk', keys.publicKey);
  const signup = await api('POST', '/api/signup', { username, password: 'testpassword123' });
  const enroll = await api('POST', '/api/enroll', {
    enrollToken: signup.json.enrollToken,
    deviceName: username + '-device',
    publicKeyJwk
  });
  return { deviceId: enroll.json.deviceId, keys };
}

(async () => {
  console.log('Testing cross-talk prevention against ' + BASE + '\n');

  // 1. Create two test users: User A (Kwame) and User B (Kofi)
  const userA = 'kwame_' + Date.now();
  const userB = 'kofi_' + Date.now();

  const { deviceId: deviceIdA } = await enrollUser(userA);
  const { deviceId: deviceIdB } = await enrollUser(userB);

  console.log(`Enrolled Kwame (Device: ${deviceIdA}) and Kofi (Device: ${deviceIdB})`);

  // 2. Start login session for Kofi (User B)
  const startB = await api('POST', '/api/login/start', { username: userB });
  check('Kofi login starts successfully', startB.status === 200 && startB.json.nonce);
  const nonceB = startB.json.nonce;

  // 3. Test Kwame's device (User A) performing a pre-flight check on Kofi's nonce
  const checkA = await api('GET', `/api/login/check?nonce=${nonceB}&deviceId=${deviceIdA}`);
  check('Kwame device pre-flight check is REJECTED with 403', checkA.status === 403);
  check('Mismatched user error message', checkA.json.error === 'mismatched user device');

  // 4. Test Kofi's device (User B) performing a pre-flight check on Kofi's nonce
  const checkB = await api('GET', `/api/login/check?nonce=${nonceB}&deviceId=${deviceIdB}`);
  check('Kofi device pre-flight check succeeds with 200', checkB.status === 200 && checkB.json.ok === true);
  check('Succeeding response returns username', checkB.json.username === userB);

  // 5. Test check with non-existent nonce
  const checkFake = await api('GET', `/api/login/check?nonce=nonexistent12&deviceId=${deviceIdA}`);
  check('Fake nonce check returns 404', checkFake.status === 404);

  // 6. Test verify still works for matching device
  const message = `echo-v1|${nonceB}|${deviceIdB}`;
  const sig = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, (await enrollUser(userB)).keys.privateKey, Buffer.from(message));
  // Wait, the signature must be signed by the keys used to enroll Kofi's device. Let's do that:
  // But wait, the keys are returned by enrollUser. Let's register a clean flow:
  const userC = 'userc_' + Date.now();
  const { deviceId: deviceIdC, keys: keysC } = await enrollUser(userC);
  const startC = await api('POST', '/api/login/start', { username: userC });
  const nonceC = startC.json.nonce;
  
  // Verify check works
  const checkC = await api('GET', `/api/login/check?nonce=${nonceC}&deviceId=${deviceIdC}`);
  check('User C pre-flight check passes', checkC.status === 200);

  // Sign and verify
  const msgC = `echo-v1|${nonceC}|${deviceIdC}`;
  const sigC = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keysC.privateKey, Buffer.from(msgC));
  const b64url = (buf) => Buffer.from(buf).toString('base64url');
  const verifyC = await api('POST', '/api/login/verify', { nonce: nonceC, deviceId: deviceIdC, signature: b64url(sigC) });
  check('User C signature verification succeeds', verifyC.status === 200);

  // 7. Check if verification burns the nonce for future checks
  const checkBurned = await api('GET', `/api/login/check?nonce=${nonceC}&deviceId=${deviceIdC}`);
  check('Used nonce check returns 410', checkBurned.status === 410);

  console.log(`\n${pass} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
})().catch(e => {
  console.error(e);
  process.exit(1);
});
