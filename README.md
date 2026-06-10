# Echo

Ultrasonic passwordless authentication for the web. The laptop plays a single-use cryptographic nonce at 18–20 kHz — above human hearing but within range of a smartphone microphone. An enrolled phone hears it, requests user approval, signs the nonce using a device-bound ECDSA P-256 private key, and the server authenticates the laptop session in real time over a WebSocket. No password is ever created, stored, or transmitted.

---

## How It Works

1. **Enroll (once):** The user registers a username. Their phone opens the enrollment link, generates a non-exportable ECDSA P-256 key pair using the Web Cryptography API, and registers the public key with the Echo server. The private key never leaves the phone.
2. **Login:** The user enters their username on the laptop. The server issues a 96-bit random nonce bound to the session.
3. **Sound transmission:** The laptop browser encodes the nonce using `ggwave` and plays it at near-ultrasonic frequency. The nonce is not secret; it is single-use and short-lived.
4. **Phone decodes and approves:** The phone PWA, listening via the microphone, decodes the nonce and shows an approve/deny prompt to the user.
5. **Signature and verification:** On approval, the phone signs `echo-v1|<nonce>|<deviceId>` with ECDSA/SHA-256 and posts the signature to the server over HTTPS.
6. **Session granted:** The server verifies the signature, pushes an `authenticated` event to the laptop over WebSocket, and the laptop claims a session cookie.

---

## Requirements

- Node.js 22.5 or later (uses the built-in `node:sqlite` module — no native add-on compilation required)
- npm 10 or later

---

## Installation

### 1. Clone the repository

```bash
git clone <repository-url>
cd "passwordless Auth"
```

### 2. Install dependencies

```bash
npm install
```

### 3. Start the server

```bash
npm start
```

The server listens on `http://localhost:8000` by default.

---

## Configuration

The server reads these environment variables at startup. All are optional.

| Variable   | Description                                      | Default                |
|------------|--------------------------------------------------|------------------------|
| `PORT`     | TCP port the HTTP server binds to                | `8000`                 |
| `ECHO_DB`  | Path to the SQLite database file                 | `./echo.db` (at root)  |

---

## Project Structure

```
.
├── docs/
│   ├── API.md                  API endpoint specification
│   └── Echo-PRD.md             Internal product requirements document
├── public/                     Static frontend assets served by Express
│   ├── web/                    Web application (laptop/browser side)
│   │   ├── index.html          Landing page
│   │   ├── signup.html         Account registration wizard
│   │   ├── login.html          Login page — broadcasts ultrasonic nonce
│   │   └── dashboard.html      Authenticated user dashboard
│   ├── phone/                  Phone PWA (mobile key app)
│   │   ├── phone.html          Listens, decodes sound, approve/deny UI
│   │   ├── manifest.webmanifest  PWA install manifest
│   │   ├── sw.js               Service worker for offline caching
│   │   ├── icon-192.png        PWA icon
│   │   └── icon-512.png        PWA icon
│   ├── echo.css                Shared design system stylesheet
│   ├── ggwave.js               Acoustic encoding/decoding library (WASM)
│   ├── qrcode.js               QR code generator library
│   └── icons.js                Inline SVG icon definitions
├── src/                        Backend server source code
│   ├── db.js                   SQLite schema, connection, and helper functions
│   ├── server.js               Express application and REST API routes
│   └── websocket.js            WebSocket upgrade handler and push notifications
├── tests/
│   ├── test-flow.js            End-to-end protocol test suite (23 tests)
│   └── ultrasonic-auth-test.html   Hardware feasibility test page (send/receive)
├── .node-version               Node.js version pin
├── package.json
└── README.md
```

---

## Usage

### First-time setup on a single machine (development)

1. Start the server: `npm start`
2. Open `http://localhost:8000/web/signup.html`
3. Choose a username and click **Continue**
4. On the enrollment step, click **Enroll this device instead (dev)** — this opens the phone app in a new browser tab on the same machine
5. In the phone tab, click **Make this my key**
6. Return to `http://localhost:8000/web/login.html`, enter your username, and click **Sign in with Echo**
7. Approve the request on the phone tab

### Testing with a real phone

The phone PWA requires a microphone, which browsers permit only over HTTPS or localhost. To expose the local server over HTTPS, use a tunnel:

```bash
npm start
npx ngrok http 8000
```

Open the ngrok HTTPS URL on the laptop, complete signup at `/web/signup.html`, and scan the QR code with the phone camera. The phone will open `/phone/phone.html` over HTTPS.

---

## Running Tests

The automated test suite exercises every cryptographic and protocol path without requiring audio hardware.

Start the server in one terminal:

```bash
npm start
```

Run the tests in a second terminal:

```bash
npm test
```

Expected output: **23 passed, 0 failed**

Test coverage includes: happy-path signup and enrollment, replay attack rejection, signature forgery rejection, cross-user device rejection, WebSocket push delivery, claim-token single-use enforcement, recovery code generation and consumption, rate limiting, and device revocation.

---

## Security Model

| Threat                  | Defence                                                               | Status        |
|-------------------------|-----------------------------------------------------------------------|---------------|
| Replay of recorded sound | Single-use 96-bit nonce, 30-second TTL, burned before verification   | Implemented   |
| Signature forgery        | ECDSA P-256 / SHA-256; private key non-exportable from the phone      | Implemented   |
| Phishing redirect        | Signature includes a domain-separation prefix and device ID; goes phone → server only | Implemented |
| Stolen unlocked phone    | User approval prompt required before every signature                 | Implemented   |
| Recovery code brute force | Codes stored as SHA-256 hashes; 5 attempts per 15 minutes per account | Implemented |
| Relay attack             | Documented limitation; short ultrasound range (~1–2 m) provides soft mitigation | Accepted v1 risk |

---

## Account Recovery

If the enrolled phone is unavailable:

1. Navigate to `http://localhost:8000/login.html`
2. Click **Use a recovery code**
3. Enter your username and one of the six recovery codes generated from the dashboard

Each recovery code is valid for a single use. Codes are stored on the server only as SHA-256 hashes and are never retrievable after initial generation. Generate new codes from the dashboard after signing in.

---

## License

CY384 research artefact. Internal use only.
