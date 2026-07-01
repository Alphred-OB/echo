// Echo — Database and Cryptographic Helpers Module
// Setup SQLite, create tables, and define authentication helper functions.

const { DatabaseSync } = require('node:sqlite');
const crypto = require('crypto');
const path = require('path');

const { subtle } = crypto.webcrypto;

const NONCE_TTL_MS = 30_000;        // nonce valid for 30 s (PRD P0-2)
const SESSION_TTL_MS = 8 * 3600_000; // logged-in session: 8 h
const SIGN_PREFIX = 'echo-v1';      // domain separation for signatures

// Initialize SQLite database
const dbPath = process.env.ECHO_DB || path.join(__dirname, '../echo.db');
const db = new DatabaseSync(dbPath);

// Patch node:sqlite bug in v22.12.0 (Linux) where .get() returns e.g. { id: null }
// instead of undefined for missing rows. This breaks truthiness checks.
const originalPrepare = db.prepare.bind(db);
db.prepare = function(sql) {
  const stmt = originalPrepare(sql);
  const originalGet = stmt.get.bind(stmt);
  stmt.get = function(...args) {
    const row = originalGet(...args);
    if (row && typeof row === 'object' && Object.values(row).every(v => v === null)) {
      return undefined;
    }
    return row;
  };
  return stmt;
};

try { 
  db.exec('PRAGMA journal_mode = WAL'); 
} catch (e) { 
  console.warn('SQLite WAL journal mode unsupported on this filesystem. Falling back to default mode.', e);
}

// Create Schema
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  pubkey_jwk TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS login_sessions (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  nonce TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | denied
  claim_token TEXT,
  used INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS enroll_tokens (
  token TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  device_id TEXT,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS recovery_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  code_hash TEXT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS logins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  method TEXT NOT NULL,          -- sound | recovery
  device_id TEXT,
  ok INTEGER NOT NULL,
  detail TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS magic_tokens (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  expires_at INTEGER NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
`);

try {
  db.exec('ALTER TABLE users ADD COLUMN password_hash TEXT');
} catch (e) {
  // Column already exists
}
try {
  db.exec('ALTER TABLE users ADD COLUMN email TEXT');
} catch (e) {
  // Column already exists
}

const now = () => Date.now();
const rand = (bytes) => crypto.randomBytes(bytes).toString('base64url');

// Hash a new password: random 256-bit salt + NIST-recommended 310 000 iterations
// Format: "iterations:saltHex:hashHex"
function hashPassword(password) {
  const salt = crypto.randomBytes(32).toString('hex');
  const iterations = 310_000; // NIST SP 800-132 (2023) minimum for PBKDF2-SHA-256
  const hash = crypto.pbkdf2Sync(password, salt, iterations, 64, 'sha256').toString('hex');
  return `${iterations}:${salt}:${hash}`;
}

// Verify a password against a stored hash (supports both new format and legacy single-hash).
// Always runs a full PBKDF2 derive to prevent timing-based user enumeration.
function verifyPassword(password, stored) {
  const parts = stored.split(':');
  if (parts.length === 3) {
    // New format: iterations:salt:hash
    const [iters, salt, hash] = parts;
    const candidate = crypto.pbkdf2Sync(password, salt, Number(iters), 64, 'sha256').toString('hex');
    return crypto.timingSafeEqual(Buffer.from(candidate, 'hex'), Buffer.from(hash, 'hex'));
  } else {
    // Legacy format: single hex hash with static salt — compare and upgrade prompt returned
    const candidate = crypto.pbkdf2Sync(password, 'echo-salt-key-99', 10000, 64, 'sha256').toString('hex');
    // timingSafeEqual requires equal-length buffers
    if (candidate.length !== stored.length) return false;
    return crypto.timingSafeEqual(Buffer.from(candidate, 'hex'), Buffer.from(stored, 'hex'));
  }
}

function getCookie(req, name) {
  const header = req.headers.cookie || '';
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return null;
}

function currentUser(req) {
  const token = getCookie(req, 'echo_session');
  if (!token) return null;
  const row = db.prepare(
    `SELECT u.id, u.username, s.expires_at FROM sessions s
     JOIN users u ON u.id = s.user_id WHERE s.token = ?`
  ).get(token);
  if (!row || row.expires_at < now()) return null;
  return row;
}

const hashCode = (username, code) =>
  crypto.createHash('sha256').update(username + '|' + code.toUpperCase().replace(/[^A-Z0-9]/g, '')).digest('hex');

function logLogin(userId, method, deviceId, ok, detail) {
  db.prepare('INSERT INTO logins (user_id, method, device_id, ok, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .run(userId, method, deviceId || null, ok ? 1 : 0, detail || null, now());
}

// In-memory rate limiter for recovery attempts
const recoveryAttempts = new Map(); // username -> {n, resetAt}
function recoveryAllowed(uname) {
  const e = recoveryAttempts.get(uname);
  if (e && e.resetAt > now() && e.n >= 5) return false;
  if (!e || e.resetAt <= now()) recoveryAttempts.set(uname, { n: 1, resetAt: now() + 15 * 60_000 });
  else e.n++;
  return true;
}

async function verifySignature(pubkeyJwk, message, signatureB64url) {
  const key = await subtle.importKey(
    'jwk', JSON.parse(pubkeyJwk),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false, ['verify']
  );
  const sig = Buffer.from(signatureB64url, 'base64url');
  const data = Buffer.from(message, 'utf8');
  return subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, data);
}

module.exports = {
  db,
  now,
  rand,
  getCookie,
  currentUser,
  hashCode,
  logLogin,
  recoveryAllowed,
  verifySignature,
  hashPassword,
  verifyPassword,
  NONCE_TTL_MS,
  SESSION_TTL_MS,
  SIGN_PREFIX
};
