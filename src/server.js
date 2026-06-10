// Echo — Express Application & API Server
// Assembles middleware, route handlers, and the HTTP/WebSocket server.

const express = require('express');
const http = require('http');
const path = require('path');
const crypto = require('crypto');

const {
  db, now, rand, currentUser, hashCode,
  logLogin, recoveryAllowed, verifySignature,
  NONCE_TTL_MS, SESSION_TTL_MS, SIGN_PREFIX
} = require('./db');
const { attachWebSocket, notifyLaptop } = require('./websocket');

const PORT = process.env.PORT || 8000;
const ENROLL_TTL_MS = 10 * 60_000;
const IS_PROD = process.env.NODE_ENV === 'production';

// Recovery code character set — avoids visually ambiguous characters
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

// ---------------------------------------------------------------- helpers

function makeCode() {
  const pick = () => CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
  return Array.from({ length: 4 }, pick).join('') + '-' + Array.from({ length: 4 }, pick).join('');
}

// ---------------------------------------------------------------- Express

const app = express();
// Trust Render's (and any standard) reverse proxy so that req.protocol
// reflects https and cookies can be marked Secure correctly.
app.set('trust proxy', 1);
app.use(express.json({ limit: '10kb' }));
app.use(express.static(path.join(__dirname, '../public')));

// Health check — Render pings this to confirm the service is alive
app.get('/healthz', (_req, res) => res.json({ ok: true }));

// Root redirect → web app landing page
app.get('/', (_req, res) => res.redirect('/web/home.html'));

// ---------------------------------------------------------------- Signup

// Step 1: claim a username and receive a single-use enroll token
app.post('/api/signup', (req, res) => {
  const uname = String((req.body || {}).username || '').trim().toLowerCase();
  if (!/^[a-z0-9_.-]{2,32}$/.test(uname)) {
    return res.status(400).json({ error: 'invalid username (2-32 chars: a-z 0-9 _ . -)' });
  }

  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(uname);
  if (user) {
    const hasDevice = db.prepare('SELECT id FROM devices WHERE user_id = ? LIMIT 1').get(user.id);
    if (hasDevice) return res.status(409).json({ error: 'username already taken' });
  }

  db.prepare('INSERT OR IGNORE INTO users (username, created_at) VALUES (?, ?)').run(uname, now());
  const token = rand(16);
  db.prepare('INSERT INTO enroll_tokens (token, username, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(token, uname, now() + ENROLL_TTL_MS, now());

  res.json({ ok: true, username: uname, enrollToken: token, ttlMs: ENROLL_TTL_MS });
});

// Step 2: the phone redeems the enroll token and registers its public key
app.post('/api/enroll', (req, res) => {
  const { enrollToken, deviceName, publicKeyJwk } = req.body || {};
  if (!enrollToken || !publicKeyJwk || publicKeyJwk.kty !== 'EC' || publicKeyJwk.crv !== 'P-256') {
    return res.status(400).json({ error: 'enrollToken and a P-256 publicKeyJwk are required' });
  }

  const t = db.prepare('SELECT * FROM enroll_tokens WHERE token = ?').get(String(enrollToken));
  if (!t) return res.status(401).json({ error: 'invalid enroll token' });
  if (t.expires_at < now()) return res.status(401).json({ error: 'enroll token expired' });

  const burned = db.prepare('UPDATE enroll_tokens SET used = 1 WHERE token = ? AND used = 0').run(t.token);
  if (burned.changes === 0) return res.status(401).json({ error: 'enroll token already used' });

  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(t.username);
  const deviceId = rand(9);
  db.prepare('INSERT INTO devices (id, user_id, name, pubkey_jwk, created_at) VALUES (?, ?, ?, ?, ?)')
    .run(deviceId, user.id, String(deviceName || 'phone').slice(0, 64), JSON.stringify(publicKeyJwk), now());
  db.prepare('UPDATE enroll_tokens SET device_id = ? WHERE token = ?').run(deviceId, t.token);

  res.json({ ok: true, username: t.username, deviceId });
});

// Poll endpoint: the signup wizard checks when the phone has finished enrolling
app.get('/api/signup/status', (req, res) => {
  const t = db.prepare('SELECT used, device_id, expires_at FROM enroll_tokens WHERE token = ?')
    .get(String(req.query.token || ''));
  if (!t) return res.status(404).json({ error: 'unknown token' });
  res.json({ enrolled: !!t.used, deviceId: t.device_id || null, expired: t.expires_at < now() });
});

// ---------------------------------------------------------------- Login

// Step 1: the laptop requests a single-use nonce bound to this session
app.post('/api/login/start', (req, res) => {
  const uname = String((req.body || {}).username || '').trim().toLowerCase();
  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(uname);
  const device = user && db.prepare('SELECT id FROM devices WHERE user_id = ? LIMIT 1').get(user.id);
  if (!user || !device) return res.status(404).json({ error: 'unknown user or no enrolled device' });

  const sessionId = rand(16);
  // 96-bit nonce encodes compactly into a short ggwave transmission
  const nonce = rand(12);
  db.prepare(`INSERT INTO login_sessions (id, username, nonce, expires_at, created_at)
              VALUES (?, ?, ?, ?, ?)`).run(sessionId, uname, nonce, now() + NONCE_TTL_MS, now());

  res.json({ sessionId, nonce, ttlMs: NONCE_TTL_MS });
});

// Step 2: the phone submits the user-approved ECDSA signature over the nonce
app.post('/api/login/verify', async (req, res) => {
  const { nonce, deviceId, signature } = req.body || {};
  if (!nonce || !deviceId || !signature) {
    return res.status(400).json({ error: 'nonce, deviceId, signature required' });
  }

  const ls = db.prepare('SELECT * FROM login_sessions WHERE nonce = ?').get(String(nonce));
  if (!ls) return res.status(401).json({ error: 'unknown nonce' });

  // Burn the nonce atomically before verification to prevent replay attacks (PRD P0-2)
  const burned = db.prepare('UPDATE login_sessions SET used = 1 WHERE nonce = ? AND used = 0').run(String(nonce));
  if (burned.changes === 0) return res.status(401).json({ error: 'nonce already used' });
  if (ls.expires_at < now()) return res.status(401).json({ error: 'nonce expired' });

  const device = db.prepare(
    `SELECT d.*, u.username FROM devices d JOIN users u ON u.id = d.user_id WHERE d.id = ?`
  ).get(String(deviceId));

  if (!device || device.username !== ls.username) {
    db.prepare("UPDATE login_sessions SET status = 'denied' WHERE id = ?").run(ls.id);
    return res.status(401).json({ error: 'device not enrolled for this user' });
  }

  const message = `${SIGN_PREFIX}|${nonce}|${deviceId}`;
  let ok = false;
  try { ok = await verifySignature(device.pubkey_jwk, message, String(signature)); } catch { ok = false; }

  if (!ok) {
    db.prepare("UPDATE login_sessions SET status = 'denied' WHERE id = ?").run(ls.id);
    logLogin(device.user_id, 'sound', device.id, false, 'bad signature');
    return res.status(401).json({ error: 'bad signature' });
  }

  logLogin(device.user_id, 'sound', device.id, true, null);
  const claimToken = rand(24);
  db.prepare("UPDATE login_sessions SET status = 'approved', claim_token = ? WHERE id = ?").run(claimToken, ls.id);
  notifyLaptop(ls.id, { type: 'authenticated', claimToken });

  res.json({ ok: true });
});

// Step 3: the laptop exchanges the one-time claim token for a session cookie
app.post('/api/session/claim', (req, res) => {
  const { sessionId, claimToken } = req.body || {};
  const ls = db.prepare(
    "SELECT * FROM login_sessions WHERE id = ? AND status = 'approved' AND claim_token = ?"
  ).get(String(sessionId || ''), String(claimToken || ''));
  if (!ls) return res.status(401).json({ error: 'invalid claim' });

  db.prepare("UPDATE login_sessions SET claim_token = NULL WHERE id = ?").run(ls.id);
  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(ls.username);
  const token = rand(32);
  db.prepare('INSERT INTO sessions (token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(token, user.id, now() + SESSION_TTL_MS, now());

  const cookieFlags = `HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${IS_PROD ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `echo_session=${token}; ${cookieFlags}`);
  res.json({ ok: true, username: ls.username });
});

// ---------------------------------------------------------------- Recovery

// Generate (or regenerate) recovery codes — requires an active session
app.post('/api/recovery/generate', (req, res) => {
  const user = currentUser(req);
  if (!user) return res.status(401).json({ error: 'not logged in' });

  db.prepare('DELETE FROM recovery_codes WHERE user_id = ?').run(user.id);
  const codes = Array.from({ length: 6 }, makeCode);
  const ins = db.prepare('INSERT INTO recovery_codes (user_id, code_hash, created_at) VALUES (?, ?, ?)');
  for (const c of codes) ins.run(user.id, hashCode(user.username, c), now());

  res.json({ ok: true, codes });
});

// Fallback login path when the phone is unavailable
app.post('/api/login/recovery', (req, res) => {
  const uname = String((req.body || {}).username || '').trim().toLowerCase();
  const code = String((req.body || {}).code || '');
  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(uname);
  if (!user) return res.status(401).json({ error: 'invalid username or code' });
  if (!recoveryAllowed(uname)) return res.status(429).json({ error: 'too many attempts — wait 15 minutes' });

  const h = hashCode(uname, code);
  const row = db.prepare('SELECT id FROM recovery_codes WHERE user_id = ? AND code_hash = ? AND used = 0')
    .get(user.id, h);

  if (!row) {
    logLogin(user.id, 'recovery', null, false, 'bad code');
    return res.status(401).json({ error: 'invalid username or code' });
  }

  db.prepare('UPDATE recovery_codes SET used = 1 WHERE id = ?').run(row.id);
  logLogin(user.id, 'recovery', null, true, null);

  const token = rand(32);
  db.prepare('INSERT INTO sessions (token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(token, user.id, now() + SESSION_TTL_MS, now());
  const cookieFlags = `HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${IS_PROD ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `echo_session=${token}; ${cookieFlags}`);

  const remaining = db.prepare('SELECT COUNT(*) c FROM recovery_codes WHERE user_id = ? AND used = 0').get(user.id).c;
  res.json({ ok: true, username: uname, remainingCodes: remaining });
});

// ---------------------------------------------------------------- Device Management

// Issue a new enroll token so an authenticated user can add a second device
app.post('/api/device/token', (req, res) => {
  const user = currentUser(req);
  if (!user) return res.status(401).json({ error: 'not logged in' });
  const token = rand(16);
  db.prepare('INSERT INTO enroll_tokens (token, username, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(token, user.username, now() + ENROLL_TTL_MS, now());
  res.json({ ok: true, enrollToken: token, ttlMs: ENROLL_TTL_MS });
});

// Remove a device from the account; the device can no longer authenticate
app.post('/api/device/revoke', (req, res) => {
  const user = currentUser(req);
  if (!user) return res.status(401).json({ error: 'not logged in' });
  const deviceId = String((req.body || {}).deviceId || '');
  const r = db.prepare('DELETE FROM devices WHERE id = ? AND user_id = ?').run(deviceId, user.id);
  if (r.changes === 0) return res.status(404).json({ error: 'device not found' });
  res.json({ ok: true });
});

// ---------------------------------------------------------------- Session

// Return the current user's profile, enrolled devices, and recent login history
app.get('/api/me', (req, res) => {
  const user = currentUser(req);
  if (!user) return res.status(401).json({ error: 'not logged in' });
  const devices = db.prepare('SELECT id, name, created_at FROM devices WHERE user_id = ?').all(user.id);
  const recoveryUnused = db.prepare('SELECT COUNT(*) c FROM recovery_codes WHERE user_id = ? AND used = 0').get(user.id).c;
  const recentLogins = db.prepare(
    `SELECT l.method, l.ok, l.detail, l.created_at, d.name AS device_name
     FROM logins l LEFT JOIN devices d ON d.id = l.device_id
     WHERE l.user_id = ? ORDER BY l.id DESC LIMIT 12`
  ).all(user.id);
  res.json({ username: user.username, devices, recoveryUnused, recentLogins });
});

// Invalidate the current session cookie
app.post('/api/logout', (req, res) => {
  const header = req.headers.cookie || '';
  let token = null;
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === 'echo_session') { token = decodeURIComponent(v.join('=')); break; }
  }
  if (token) db.prepare('DELETE FROM sessions WHERE token = ?').run(token);
  res.setHeader('Set-Cookie', 'echo_session=; HttpOnly; Path=/; Max-Age=0');
  res.json({ ok: true });
});

// ---------------------------------------------------------------- HTTP Server

const server = http.createServer(app);
attachWebSocket(server);

// Periodically purge expired rows to keep the database lean
setInterval(() => {
  db.prepare('DELETE FROM login_sessions WHERE expires_at < ?').run(now() - 600_000);
  db.prepare('DELETE FROM sessions WHERE expires_at < ?').run(now());
  db.prepare('DELETE FROM enroll_tokens WHERE expires_at < ? AND used = 0').run(now() - 600_000);
}, 60_000).unref();

server.listen(PORT, () => {
  console.log(`Echo server running → http://localhost:${PORT}`);
  console.log('  web app:         /web/index.html');
  console.log('  login page:      /web/login.html');
  console.log('  phone app:       /phone/phone.html');
});
