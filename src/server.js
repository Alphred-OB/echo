require('dotenv').config();
const express = require('express');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

const {
  db, now, rand, getCookie, currentUser, hashCode,
  logLogin, recoveryAllowed, verifySignature, hashPassword,
  verifyPassword, NONCE_TTL_MS, SESSION_TTL_MS, SIGN_PREFIX
} = require('./db');
const { attachWebSocket, notifyLaptop } = require('./websocket');

const transporter = nodemailer.createTransport({
  host: process.env.MAIL_HOST || 'mail.eruditeafricanetwork.com',
  port: parseInt(process.env.MAIL_PORT || '465', 10),
  secure: process.env.MAIL_PORT === '465' || process.env.MAIL_ENCRYPTION === 'ssl',
  auth: {
    user: process.env.MAIL_USERNAME,
    pass: process.env.MAIL_PASSWORD
  }
});

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

// ---- Security hardening ----
// Remove framework fingerprint header
app.disable('x-powered-by');

// HTTP security headers — prevents clickjacking, MIME-sniffing, data leakage
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'microphone=(self), camera=(), geolocation=()');
  // Allow ggwave WASM, Google Fonts, and QR code inline scripts
  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'",   // ggwave inline init & wasm
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src 'self' https://fonts.gstatic.com",
      "connect-src 'self' wss:",              // WebSocket sign-in channel
      "img-src 'self' data:",                 // QR code SVG data URIs
      "worker-src 'self'",
      "frame-ancestors 'none'"
    ].join('; ')
  );
  if (IS_PROD) {
    res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  }
  next();
});

app.use(express.json({ limit: '10kb' }));
app.use(express.static(path.join(__dirname, '../public')));

// ---- Login/start rate limiter (per username, in-process) ----
// Mirrors the recovery limiter: 10 attempts per 5 minutes.
const loginStartAttempts = new Map();
function loginStartAllowed(uname) {
  const now = Date.now();
  const e = loginStartAttempts.get(uname);
  if (e && e.resetAt > now && e.n >= 10) return false;
  if (!e || e.resetAt <= now) loginStartAttempts.set(uname, { n: 1, resetAt: now + 5 * 60_000 });
  else e.n++;
  return true;
}

// Health check — Render pings this to confirm the service is alive
app.get('/healthz', (_req, res) => res.json({ ok: true }));

// Root redirect → web app landing page
app.get('/', (_req, res) => res.redirect('/web/home.html'));
// Legacy path from before the home.html rename — keep old links working
app.get('/web/index.html', (_req, res) => res.redirect('/web/home.html'));

// ---------------------------------------------------------------- Signup

// Step 1: claim a username and receive a single-use enroll token
// Intentionally public: entrypoint for initiating registration
app.post('/api/signup', (req, res) => {
  const uname = String((req.body || {}).username || '').trim().toLowerCase();
  const email = String((req.body || {}).email || '').trim().toLowerCase();
  if (!/^[a-z0-9_.-]{2,32}$/.test(uname)) {
    return res.status(400).json({ error: 'invalid username (2-32 chars: a-z 0-9 _ . -)' });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: 'invalid email address' });
  }

  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(uname);
  if (user) {
    const hasDevice = db.prepare('SELECT id FROM devices WHERE user_id = ? LIMIT 1').get(user.id);
    if (hasDevice) return res.status(409).json({ error: 'username already taken' });
  }

  const emailTaken = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (emailTaken && (!user || emailTaken.id !== user.id)) {
    return res.status(409).json({ error: 'email already in use' });
  }

  if (user) {
    db.prepare('UPDATE users SET email = ? WHERE id = ?').run(email, user.id);
  } else {
    db.prepare('INSERT INTO users (username, email, created_at) VALUES (?, ?, ?)').run(uname, email, now());
  }

  const token = rand(16);
  db.prepare('INSERT INTO enroll_tokens (token, username, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(token, uname, now() + ENROLL_TTL_MS, now());

  res.json({ ok: true, username: uname, enrollToken: token, ttlMs: ENROLL_TTL_MS });
});

// Step 2: the phone redeems the enroll token and registers its public key
// Intentionally public: verify the enroll token and register a device
app.post('/api/enroll', (req, res) => {
  const { enrollToken, deviceName, publicKeyJwk } = req.body || {};
  if (!enrollToken || !publicKeyJwk || publicKeyJwk.kty !== 'EC' || publicKeyJwk.crv !== 'P-256') {
    return res.status(400).json({ error: 'enrollToken and a P-256 publicKeyJwk are required' });
  }

  const t = db.prepare('SELECT * FROM enroll_tokens WHERE token = ?').get(String(enrollToken));
  if (!t) return res.status(401).json({ error: 'invalid enroll token' });
  if (t.expires_at < now()) return res.status(401).json({ error: 'enroll token expired' });

  const burned = db.prepare('UPDATE enroll_tokens SET used = 1 WHERE token = ? AND used = 0').run(t.token);
  if (burned.changes < 1) return res.status(401).json({ error: 'enroll token already used' });

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
// Intentionally public: anyone can request a sign-in session for a username
app.post('/api/login/start', (req, res) => {
  const uname = String((req.body || {}).username || '').trim().toLowerCase();

  // Rate-limit per username: 10 start attempts per 5 minutes
  if (uname && !loginStartAllowed(uname)) {
    return res.status(429).json({ error: 'too many attempts — please wait a few minutes' });
  }

  const user = db.prepare('SELECT id FROM users WHERE username = ?').get(uname);
  const device = user && db.prepare('SELECT id FROM devices WHERE user_id = ? LIMIT 1').get(user.id);
  // Return the same generic error for unknown user OR no device to prevent username enumeration
  if (!user || !device) return res.status(404).json({ error: 'unknown user or no enrolled device' });

  const sessionId = rand(16);
  // 96-bit nonce encodes compactly into a short ggwave transmission
  const nonce = rand(12);

  // Expire all previous pending sessions for this user instantly to prevent concurrent code harvesting
  db.prepare(`UPDATE login_sessions SET used = 1 WHERE username = ? AND used = 0`).run(uname);

  db.prepare(`INSERT INTO login_sessions (id, username, nonce, expires_at, created_at)
              VALUES (?, ?, ?, ?, ?)`).run(sessionId, uname, nonce, now() + NONCE_TTL_MS, now());

  res.json({ sessionId, nonce, ttlMs: NONCE_TTL_MS });
});

// Pre-flight check: the phone silently checks if the nonce belongs to this device's owner
// Intentionally public: called by the phone to confirm the nonce is meant for this device
app.get('/api/login/check', (req, res) => {
  const nonce    = String(req.query.nonce    || '');
  const deviceId = String(req.query.deviceId || '');
  console.log(`[CHECK] Incoming pre-flight check - Nonce: "${nonce}", DeviceId: "${deviceId}"`);

  if (!nonce || !deviceId) {
    console.log('[CHECK] Missing nonce or deviceId');
    return res.status(400).json({ error: 'nonce and deviceId required' });
  }

  const ls = db.prepare('SELECT * FROM login_sessions WHERE nonce = ?').get(nonce);

  // Log active nonces to diagnose host/timezone mismatches
  const activeSessions = db.prepare('SELECT username, nonce, expires_at FROM login_sessions WHERE used = 0').all();
  console.log(`[CHECK] Active nonces in database:`, activeSessions.map(s => `(${s.username}: "${s.nonce}", expires: ${s.expires_at})`));

  if (!ls) {
    console.log(`[CHECK] Nonce "${nonce}" NOT FOUND in database.`);
    return res.status(404).json({ error: 'unknown nonce' });
  }
  if (ls.used) {
    console.log(`[CHECK] Nonce "${nonce}" has already been used.`);
    return res.status(410).json({ error: 'nonce already used' });
  }
  if (ls.expires_at < now()) {
    console.log(`[CHECK] Nonce "${nonce}" expired at ${ls.expires_at} (current time: ${now()}).`);
    return res.status(410).json({ error: 'nonce expired' });
  }

  const device = db.prepare(
    `SELECT d.*, u.username FROM devices d JOIN users u ON u.id = d.user_id WHERE d.id = ?`
  ).get(deviceId);

  if (!device) {
    console.log(`[CHECK] Device "${deviceId}" not found in database.`);
    return res.status(403).json({ error: 'mismatched user device' });
  }

  if (device.username !== ls.username) {
    console.log(`[CHECK] Mismatch! Device belongs to "${device.username}", but session belongs to "${ls.username}"`);
    return res.status(403).json({ error: 'mismatched user device' });
  }

  console.log(`[CHECK] Pre-flight SUCCESS for user "${ls.username}" on device "${deviceId}"`);
  res.json({ ok: true, username: ls.username });
});

// Step 2: the phone submits the user-approved ECDSA signature over the nonce
// Intentionally public: phone posts signature to authenticate the laptop session
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
// Intentionally public: laptop exchanges the claim token for a session cookie
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

  const cookieFlags = `HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${IS_PROD ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `echo_session=${token}; ${cookieFlags}`);
  res.json({ ok: true, username: ls.username });
});

// ---------------------------------------------------------------- Recovery

// Request a passwordless magic login link to be sent via email
app.post('/api/login/magic-request', async (req, res) => {
  const input = String((req.body || {}).usernameOrEmail || '').trim().toLowerCase();
  if (!input) {
    return res.status(400).json({ error: 'Please enter your username or email address' });
  }

  // Find user by username or email
  const user = db.prepare('SELECT id, username, email FROM users WHERE username = ? OR email = ?').get(input, input);
  if (!user || !user.email) {
    // Return success message even if user not found to prevent user enumeration attacks
    return res.json({ ok: true, message: 'If the account exists, a magic link has been sent to the registered email.' });
  }

  if (!recoveryAllowed(user.username)) {
    return res.status(429).json({ error: 'too many attempts — wait 15 minutes' });
  }

  const magicToken = rand(32);
  const expiration = now() + 15 * 60_000; // 15 minutes TTL

  db.prepare('INSERT INTO magic_tokens (token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(magicToken, user.id, expiration, now());

  // Determine host for construction of verification URL
  const protocol = req.headers['x-forwarded-proto'] || req.protocol || 'http';
  const host = req.headers['x-forwarded-host'] || req.get('host');
  const magicLink = `${protocol}://${host}/api/login/magic?token=${magicToken}`;

  const mailOptions = {
    from: `"${process.env.MAIL_FROM_NAME || 'Echo Auth'}" <${process.env.MAIL_FROM_ADDRESS}>`,
    to: user.email,
    subject: 'Your Echo Magic Sign-in Link 🪄',
    text: `Hello ${user.username},\n\nClick the link below to sign in to your Echo account on this computer. This link is only valid for 15 minutes:\n\n${magicLink}\n\nIf you did not request this, you can ignore this email.\n\nBest,\nEcho Authentication Team`,
    html: `
      <div style="font-family: sans-serif; max-width: 500px; margin: 0 auto; border: 1px solid #e2e8f0; border-radius: 12px; padding: 24px; background: #ffffff;">
        <h2 style="color: #2563eb; margin-top: 0;">Echo Sign-in</h2>
        <p>Hello <strong>${user.username}</strong>,</p>
        <p>You requested a backup login link because your phone is unavailable. Click the button below to sign in to your account instantly on this computer:</p>
        <div style="margin: 24px 0; text-align: center;">
          <a href="${magicLink}" style="background: #2563eb; color: #ffffff; text-decoration: none; padding: 12px 24px; border-radius: 8px; font-weight: bold; display: inline-block;">Sign in to Echo</a>
        </div>
        <p style="font-size: 13px; color: #64748b;">This link is valid for 15 minutes and can only be used once.</p>
        <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;">
        <p style="font-size: 11px; color: #94a3b8; text-align: center;">Echo Passwordless Auth Project</p>
      </div>
    `
  };

  try {
    await transporter.sendMail(mailOptions);
    logLogin(user.id, 'recovery_request', null, true, 'magic link sent');
    res.json({ ok: true, message: 'If the account exists, a magic link has been sent to the registered email.' });
  } catch (err) {
    console.error('SMTP sending error (falling back to console logging):', err.message);
    console.log('\n======================================================');
    console.log('[DEMO/FALLBACK] Magic link generated for ' + user.username + ':');
    console.log(magicLink);
    console.log('======================================================\n');
    logLogin(user.id, 'recovery_request', null, true, 'magic link generated (SMTP fallback)');
    res.json({ 
      ok: true, 
      message: 'Magic link generated! (Demo Fallback: check terminal console for link)',
      debugLink: magicLink 
    });
  }
});

// GET endpoint verifying the magic link token
app.get('/api/login/magic', (req, res) => {
  const token = String(req.query.token || '').trim();
  if (!token) return res.status(400).send('<h1>Invalid or missing token</h1>');

  const record = db.prepare('SELECT * FROM magic_tokens WHERE token = ? AND used = 0').get(token);
  if (!record) {
    return res.status(401).send('<h1>Link has expired or already been used. Please request a new one.</h1>');
  }

  if (record.expires_at < now()) {
    return res.status(401).send('<h1>This magic link has expired. Please request a new one.</h1>');
  }

  // Mark token as used
  db.prepare('UPDATE magic_tokens SET used = 1 WHERE token = ?').run(token);

  logLogin(record.user_id, 'recovery', null, true, 'magic link verified');

  const sessionToken = rand(32);
  db.prepare('INSERT INTO sessions (token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(sessionToken, record.user_id, now() + SESSION_TTL_MS, now());

  const cookieFlags = `HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${IS_PROD ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `echo_session=${sessionToken}; ${cookieFlags}`);

  // Redirect to dashboard
  res.redirect('/web/dashboard.html');
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
  const recentLogins = db.prepare(
    `SELECT l.method, l.ok, l.detail, l.created_at, d.name AS device_name
     FROM logins l LEFT JOIN devices d ON d.id = l.device_id
     WHERE l.user_id = ? ORDER BY l.id DESC LIMIT 12`
  ).all(user.id);
  const fullUser = db.prepare('SELECT email FROM users WHERE id = ?').get(user.id);
  res.json({ username: user.username, devices, email: (fullUser ? fullUser.email : null), recentLogins });
});

// Invalidate the current session cookie
// Intentionally public: allows any client to clear their active session cookie
app.post('/api/logout', (req, res) => {
  const token = getCookie(req, 'echo_session');
  if (token) db.prepare('DELETE FROM sessions WHERE token = ?').run(token);
  const clearFlags = `HttpOnly; SameSite=Strict; Path=/; Max-Age=0${IS_PROD ? '; Secure' : ''}`;
  res.setHeader('Set-Cookie', `echo_session=; ${clearFlags}`);
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
  console.log('  web app:         /web/home.html');
  console.log('  login page:      /web/login.html');
  console.log('  phone app:       /phone/phone.html');
});
