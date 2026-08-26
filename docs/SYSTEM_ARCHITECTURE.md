# Echo — System Architecture & Implementation Guide

**Echo** is an ultrasonic, zero-password, physical-proximity authentication platform for the web. It replaces passwords, SMS OTPs, and authenticator codes by leveraging near-ultrasonic sound waves (18–20 kHz) and asymmetric public-key cryptography (ECDSA P-256) between a laptop browser and an enrolled mobile device.

---

## 1. High-Level Architecture & Communication Model

```
   ┌───────────────────────┐                               ┌─────────────────────────┐
   │    Laptop Browser     │                               │      Echo Server        │
   │  (/web/login.html)    │                               │   (Node.js / Express)   │
   └──────────┬────────────┘                               └────────────┬────────────┘
              │                                                         │
              │ 1. POST /api/login/start { username }                   │
              │────────────────────────────────────────────────────────>│
              │ 2. Returns { sessionId, nonce }                         │
              │<────────────────────────────────────────────────────────│
              │                                                         │
              │ 3. Connects WebSocket /ws?session=sessionId             │
              │<═══════════════════════════════════════════════════════>│
              │                                                         │
   4. Encodes nonce with ggwave                                         │
      Plays near-ultrasound (18-20 kHz)                                 │
              │                                                         │
              ▼ ~1-2m Acoustic Air Gap                                  │
   ┌───────────────────────┐                                            │
   │       Phone PWA       │                                            │
   │  (/phone/phone.html)  │                                            │
   └──────────┬────────────┘                                            │
              │                                                         │
              │ 5. Microphone records & ggwave decodes nonce            │
              │ 6. GET /api/login/check?nonce=...&deviceId=...          │
              │────────────────────────────────────────────────────────>│
              │ 7. Pre-flight check OK (nonce belongs to this user)     │
              │<────────────────────────────────────────────────────────│
              │                                                         │
              │ 8. Displays "Approve / Deny" prompt & 2-digit match code│
              │    User taps "Approve"                                  │
              │ 9. Signs "echo-v1|<nonce>|<deviceId>" with ECDSA P-256  │
              │                                                         │
              │ 10. POST /api/login/verify { nonce, deviceId, sig }     │
              │────────────────────────────────────────────────────────>│
              │                                                         │ 11. Burns nonce,
              │                                                         │     verifies ECDSA sig
              │                                                         │     against public key
              │ 12. WebSocket Push: { type: "authenticated", claimToken }│
              │<════════════════════════════════════════════════════════│
              │                                                         │
              │ 13. POST /api/session/claim { sessionId, claimToken }   │
              │────────────────────────────────────────────────────────>│
              │ 14. Sets HttpOnly session cookie & redirects to dashboard│
              │<────────────────────────────────────────────────────────│
```

---

## 2. Project Directory Structure

```
passwordless Auth/
├── docs/
│   ├── API.md                      # Complete REST API & WebSocket specification
│   ├── Echo-PRD.md                 # Product Requirements Document & engineering plan
│   └── SYSTEM_ARCHITECTURE.md      # This comprehensive system guide
├── public/                         # Static frontend assets served by Express
│   ├── web/                        # Desktop / Laptop Web Portal
│   │   ├── home.html               # Main marketing / landing page
│   │   ├── signup.html             # Account creation & QR-based enrollment wizard
│   │   ├── login.html              # Login portal (ultrasonic sender & WS client)
│   │   └── dashboard.html          # Protected user dashboard & device management
│   ├── phone/                      # Mobile Progressive Web App (PWA)
│   │   ├── phone.html              # Mobile key interface (acoustic listener & signer)
│   │   ├── manifest.webmanifest    # PWA installation manifest
│   │   └── sw.js                   # Service Worker for offline capability
│   ├── echo.css                    # Design system (CSS variables, themes, layout)
│   ├── ggwave.js                   # WebAssembly-compiled acoustic data modem
│   ├── jsQR.js                     # In-browser QR code video scanning library
│   ├── qrcode.js                   # QR code generator library (used on desktop)
│   └── icons.js                    # Inline SVG icon spritesheet
├── src/                            # Backend Server Implementation
│   ├── server.js                   # Express REST API, HTTP headers, routes, auth
│   ├── db.js                       # SQLite schema, crypto helpers, password/session ops
│   └── websocket.js                # WebSocket upgrade handler & real-time notification
├── tests/
│   ├── test-flow.js                # 23-step automated end-to-end cryptographic test suite
│   ├── test-cross-talk.js          # Multi-device cross-talk rejection tests
│   └── ultrasonic-auth-test.html   # Standalone acoustic hardware diagnostic page
├── package.json                    # Dependencies and scripts (Node >= 22.5)
└── echo.db                         # SQLite persistent database
```

---

## 3. Core Subsystems Breakdown

### A. Backend Services (`src/`)

1. **Database & Crypto Helpers (`src/db.js`)**:
   - **Persistence**: Employs Node.js native `node:sqlite` (`DatabaseSync`) with Write-Ahead Logging (`WAL` mode).
   - **Schema Definitions**:
     - `users`: Core identity table (`id`, `username`, `email`, `created_at`).
     - `devices`: Registered authentication devices per user (`id`, `user_id`, `name`, `pubkey_jwk`, `created_at`).
     - `login_sessions`: Pending and approved login attempts (`id`, `username`, `nonce`, `status`, `claim_token`, `used`, `expires_at`).
     - `sessions`: Active authenticated user sessions (`token`, `user_id`, `expires_at`).
     - `enroll_tokens`: Single-use tokens for registering devices (`token`, `username`, `used`, `device_id`, `expires_at`).
     - `magic_tokens`: Out-of-band email fallback tokens (`token`, `user_id`, `expires_at`, `used`).
     - `logins`: Audit log capturing all authentication attempts (`method`, `ok`, `detail`, `device_id`, `created_at`).
   - **Cryptographic Operations**:
     - Verifies ECDSA P-256 signatures with WebCrypto (`crypto.webcrypto.subtle`).
     - Password hashing / verification via PBKDF2-SHA-256 with 310,000 iterations (NIST SP 800-132) and constant-time buffer comparisons (`crypto.timingSafeEqual`).

2. **HTTP API & Security (`src/server.js`)**:
   - **Security Headers**: Enforces strict headers: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, and `Permissions-Policy: microphone=(self)`.
   - **Rate Limiting**: Per-username rate-limit maps preventing brute-force login requests and recovery abuse.
   - **Endpoints**:
     - `POST /api/signup`: Issues single-use enrollment token.
     - `POST /api/enroll`: Pairs device public key with user account.
     - `GET /api/signup/status`: Polling endpoint for signup wizard.
     - `POST /api/login/start`: Issues 96-bit base64url nonce with 30s TTL.
     - `GET /api/login/check`: Pre-flight check verifying nonce ownership.
     - `POST /api/login/verify`: Verifies ECDSA signature, burns nonce, generates claim token.
     - `POST /api/session/claim`: Issues `HttpOnly`, `SameSite=Strict` cookie (`echo_session`).
     - `POST /api/login/magic-request` & `GET /api/login/magic`: Email magic link fallback via SMTP.
     - `GET /api/me`, `POST /api/device/revoke`, `POST /api/logout`: Account & device management.

3. **WebSocket Manager (`src/websocket.js`)**:
   - Manages upgrade requests on `/ws?session=<sessionId>`.
   - Binds active WebSocket connections to session IDs.
   - Instantly notifies the laptop browser when authentication is granted (`notifyLaptop()`).

---

### B. Mobile PWA Key (`public/phone/phone.html`)

- **Key Generation & Storage**:
  - Uses `window.crypto.subtle.generateKey` to create an **ECDSA P-256** key pair.
  - The private key is created with `extractable: false` and stored securely in **IndexedDB** (`echo-keys` database, `kv` store).
- **Acoustic Receiver**:
  - Accesses raw microphone input via `navigator.mediaDevices.getUserMedia`.
  - Decodes near-ultrasonic sound frames via `ggwave.decode()` (WASM).
  - Listens for envelope packets formatted as `E1:<16-char base64url nonce>`.
- **Pre-Flight Cross-Talk Filtering**:
  - Calls `GET /api/login/check?nonce=<nonce>&deviceId=<deviceId>`.
  - Silently discards nonces originating from nearby laptops belonging to other users.
- **Signing & Verification**:
  - Generates a visual 2-digit confirmation code (`SHA-256(nonce)[0] % 90 + 10`).
  - Prompts user to Approve / Deny.
  - On approval, signs `echo-v1|<nonce>|<deviceId>` using `crypto.subtle.sign` and posts to `/api/login/verify`.
- **Integrated QR Scanner**:
  - In-browser camera scanning powered by `jsQR.js` to scan enrollment QR codes from desktop screens.

---

### C. Desktop Web Client (`public/web/login.html` & `signup.html`)

- **Acoustic Transmitter**:
  - Fetches the single-use nonce from `/api/login/start`.
  - Encodes the envelope `E1:<nonce>` using `ggwave.encode()` targeting `ULTRASOUND_NORMAL` (18–20 kHz).
  - Plays the synthesized audio buffer through an `AudioContext`.
  - Provides a toggle to switch to `AUDIBLE_NORMAL` (audible chirps) for hardware with limited ultrasonic frequency response.
- **Real-Time Login Claim**:
  - Opens WebSocket to `/ws?session=<sessionId>`.
  - Upon receiving the `authenticated` message, exchanges the one-time `claimToken` via `POST /api/session/claim` to acquire the session cookie.

---

## 4. Threat Model & Security Controls

| Threat Scenario | Defense Mechanism | Implementation Details |
|---|---|---|
| **Acoustic Replay Attack** | Single-use 96-bit nonce + 30s TTL | The server burns the nonce (`UPDATE login_sessions SET used = 1 WHERE nonce = ? AND used = 0`) *before* signature verification. An audio recording replayed a second later is rejected. |
| **Signature Forgery** | Non-exportable ECDSA P-256 | The private key is created in WebCrypto with `extractable = false` and stored in IndexedDB. An attacker cannot forge signatures without physical access to an unlocked device. |
| **Man-in-the-Middle / Phishing** | Domain Separation | Signatures bind the protocol version and device ID (`echo-v1|<nonce>|<deviceId>`). Signatures travel exclusively from Phone $\rightarrow$ Server over TLS. |
| **Office Cross-Talk / Multiple Users** | Pre-Flight Session Ownership Check | The phone queries `/api/login/check` with its `deviceId`. If the broadcasted nonce was initiated by a colleague's laptop, the phone silently ignores it. |
| **Physical Relay Attack** | Acoustic Attenuation + Visual Match Code | Ultrasonic audio attenuates rapidly over air (~1–2 meters). Both screens display an identical 2-digit confirmation code derived from `SHA-256(nonce)`. |
| **Lost Phone / Hardware Failure** | Magic Link Fallback | Users can request a time-limited (15-minute) single-use magic login link sent to their verified email address. |

---

## 5. Automated Test Suite

The test suite in [`tests/test-flow.js`](../tests/test-flow.js) tests all cryptographic flows:
- **Test 1–6**: Signup, token issuance, single-use token enforcement, device enrollment with P-256 JWK.
- **Test 7–10**: Nonce issuance, signature verification, happy-path session claiming.
- **Test 11–14**: Replay attack rejection, forged signature rejection, cross-user device rejection.
- **Test 15–23**: WebSocket push notifications, rate limiting, magic link generation, and token expiration.
