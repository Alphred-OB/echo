// End-to-end protocol test for Echo (no audio — exercises the crypto + API).
// Run: node test-flow.js   (server must be running)
const { subtle } = require('crypto').webcrypto;
const BASE = process.env.ECHO_URL || 'http://localhost:8000';

const b64url = (buf) => Buffer.from(buf).toString('base64url');
let pass = 0, failCount = 0;
function check(name, cond) {
  if (cond) { pass++; console.log('  ✓ ' + name); }
  else { failCount++; console.log('  ✗ ' + name); }
}

async function api(path, body, opts = {}) {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(opts.headers || {}) },
    body: JSON.stringify(body)
  });
  return { status: r.status, json: await r.json().catch(() => ({})), headers: r.headers };
}

(async () => {
  console.log('Echo protocol test against ' + BASE + '\n');
  const username = 'testuser_' + Date.now();
  const password = 'testpassword123';

  // 1. signup + enroll
  const keys = await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
  const publicKeyJwk = await subtle.exportKey('jwk', keys.publicKey);

  const signup = await api('/api/signup', { username, password });
  check('signup returns enroll token', signup.status === 200 && signup.json.enrollToken);
  const enrollToken = signup.json.enrollToken;

  const noToken = await api('/api/enroll', { deviceName: 'rogue', publicKeyJwk });
  check('enroll WITHOUT token rejected', noToken.status === 400 || noToken.status === 401);

  const enroll = await api('/api/enroll', { enrollToken, deviceName: 'test-device', publicKeyJwk });
  check('enroll with token succeeds', enroll.status === 200 && enroll.json.deviceId);
  const deviceId = enroll.json.deviceId;

  const reuse = await api('/api/enroll', { enrollToken, deviceName: 'rogue2', publicKeyJwk });
  check('enroll token single-use', reuse.status === 401);

  const taken = await api('/api/signup', { username, password });
  check('taken username rejected', taken.status === 409);

  const status = await fetch(BASE + '/api/signup/status?token=' + enrollToken);
  const statusJson = await status.json();
  check('signup status shows enrolled', status.status === 200 && statusJson.enrolled === true);

  // 2. login start
  const start = await api('/api/login/start', { username });
  check('login/start returns nonce + session', start.status === 200 && start.json.nonce && start.json.sessionId);
  const { nonce, sessionId } = start.json;

  // 3. sign and verify (happy path)
  const message = `echo-v1|${nonce}|${deviceId}`;
  const sig = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey, Buffer.from(message));
  const verify = await api('/api/login/verify', { nonce, deviceId, signature: b64url(sig) });
  check('valid signature accepted', verify.status === 200);

  // 4. replay attack: same nonce again
  const replay = await api('/api/login/verify', { nonce, deviceId, signature: b64url(sig) });
  check('REPLAY rejected (nonce single-use)', replay.status === 401);

  // 5. forged signature on a fresh nonce
  const start2 = await api('/api/login/start', { username });
  const evil = await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
  const evilSig = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, evil.privateKey,
    Buffer.from(`echo-v1|${start2.json.nonce}|${deviceId}`));
  const forged = await api('/api/login/verify', { nonce: start2.json.nonce, deviceId, signature: b64url(evilSig) });
  check('FORGED signature rejected', forged.status === 401);

  // 6. wrong user's device
  const mallory = 'mallory_' + Date.now();
  const mkeys = await subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign', 'verify']);
  const msignup = await api('/api/signup', { username: mallory, password: 'mallorypassword123' });
  const menroll = await api('/api/enroll', {
    enrollToken: msignup.json.enrollToken, deviceName: 'mallory-phone',
    publicKeyJwk: await subtle.exportKey('jwk', mkeys.publicKey)
  });
  const start3 = await api('/api/login/start', { username }); // victim's login
  const msig = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, mkeys.privateKey,
    Buffer.from(`echo-v1|${start3.json.nonce}|${menroll.json.deviceId}`));
  const cross = await api('/api/login/verify',
    { nonce: start3.json.nonce, deviceId: menroll.json.deviceId, signature: b64url(msig) });
  check("ANOTHER user's device rejected", cross.status === 401);

  // 7. session claim with the approved login from step 3
  // claim token was sent over WS; simulate by reading it is not possible via API (by design).
  // Instead run one more full login and capture WS message.
  const start4 = await api('/api/login/start', { username });
  const WebSocket = require('ws');
  const ws = new WebSocket(BASE.replace('http', 'ws') + '/ws?session=' + start4.json.sessionId);
  const wsMsg = new Promise((res) => { ws.on('message', (d) => res(JSON.parse(d))); });
  await new Promise((res) => ws.on('open', res));
  const sig4 = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey,
    Buffer.from(`echo-v1|${start4.json.nonce}|${deviceId}`));
  await api('/api/login/verify', { nonce: start4.json.nonce, deviceId, signature: b64url(sig4) });
  const msg = await wsMsg;
  check('websocket push received', msg.type === 'authenticated' && !!msg.claimToken);

  const claim = await api('/api/session/claim', { sessionId: start4.json.sessionId, claimToken: msg.claimToken });
  const cookie = claim.headers.get('set-cookie') || '';
  check('session claim sets cookie', claim.status === 200 && cookie.includes('echo_session='));

  // 8. /api/me with cookie
  const me = await fetch(BASE + '/api/me', { headers: { cookie: cookie.split(';')[0] } });
  const meJson = await me.json();
  check('/api/me returns user', me.status === 200 && meJson.username === username);

  // 9. claim token cannot be reused
  const reclaim = await api('/api/session/claim', { sessionId: start4.json.sessionId, claimToken: msg.claimToken });
  check('claim token single-use', reclaim.status === 401);

  // 10. fallback password login
  const rec = await api('/api/login/recovery', { username, password });
  check('fallback password login works', rec.status === 200 && rec.json.username === username);

  const recBad = await api('/api/login/recovery', { username, password: 'wrongpassword' });
  check('wrong fallback password rejected', recBad.status === 401);

  // device management
  const authCookie = cookie.split(';')[0];
  const devToken = await fetch(BASE + '/api/device/token', { method: 'POST', headers: { cookie: authCookie } });
  const devTokenJson = await devToken.json();
  check('add-device token issued (auth)', devToken.status === 200 && devTokenJson.enrollToken);

  const noAuthToken = await fetch(BASE + '/api/device/token', { method: 'POST' });
  check('add-device token requires auth', noAuthToken.status === 401);

  const revoke = await fetch(BASE + '/api/device/revoke', {
    method: 'POST', headers: { 'Content-Type': 'application/json', cookie: authCookie },
    body: JSON.stringify({ deviceId })
  });
  check('device revoked', revoke.status === 200);

  // revoked device can no longer authenticate
  const start5 = await api('/api/login/start', { username }).catch(() => null);
  if (start5 && start5.status === 200) {
    const sig5 = await subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey,
      Buffer.from(`echo-v1|${start5.json.nonce}|${deviceId}`));
    const dead = await api('/api/login/verify', { nonce: start5.json.nonce, deviceId, signature: b64url(sig5) });
    check('REVOKED device rejected', dead.status === 401);
  } else {
    check('REVOKED device cannot even start login', start5.status === 404);
  }

  ws.close();
  console.log(`\n${pass} passed, ${failCount} failed`);
  process.exit(failCount ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
