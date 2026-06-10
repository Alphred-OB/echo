# Echo — Ultrasonic Passwordless Authentication
**Product Requirements Document (internal build plan)**
Version 0.1 · 10 June 2026 · Project: CY384 Team One, Topic 16 (Passwordless Authentication)

> Note: this PRD is an engineering planning document for building the artefact.
> The course proposal and final report must be written independently by the author.

---

## 1. Problem statement

Passwords remain the weakest link in authentication: they are phished, reused, and forgotten. Existing passwordless methods each trade something away — OTP and magic links are phishable and depend on a second channel the user must manually operate; QR-code login requires camera aiming and screen real estate; passkeys solve the crypto but still require explicit user interaction with browser prompts on the right device. There is no widely deployed method where simply *being physically present* with your trusted phone logs you in.

Echo closes that gap: the login machine proves "the user's enrolled phone is here, and its owner approved" using an inaudible acoustic channel plus public-key cryptography — no typing, no scanning, no codes.

## 2. How it works (concept)

1. **Enroll (once):** user registers; their phone (PWA) generates a non-extractable keypair and registers the public key with the Echo server.
2. **Login:** user opens the login page on a laptop and enters their username.
3. Server issues a single-use, short-TTL **nonce** bound to that login session.
4. Laptop browser encodes the nonce with ggwave and plays it at ~18–20 kHz (near-ultrasound, inaudible).
5. The phone PWA, listening, decodes the nonce, asks the user to **verify** (biometric via WebAuthn / screen unlock), then **signs** the nonce and POSTs the signature to the server over HTTPS.
6. Server verifies the signature against the enrolled public key → pushes "authenticated" to the laptop session over WebSocket. The laptop is logged in.

Security intuition: nothing secret ever travels over sound. The nonce is public and single-use (replay-proof); the private key never leaves the phone; ultrasound's short range (~1–2 m) is the proximity proof.

## 3. Goals

- **G1 — Working end-to-end login:** a user with an enrolled phone can log in to a demo web app with zero typing beyond username, in under 10 seconds end-to-end.
- **G2 — Real security, not a toy:** replay attacks and signature forgery are cryptographically impossible; a stolen (locked) phone cannot authenticate.
- **G3 — Measurable effectiveness:** documented evaluation of success rate vs. distance (0.3 m–3 m) and ambient noise (quiet / speech / music), plus latency distribution. Target: ≥90 % success at 1 m in a quiet room.
- **G4 — Course milestones met:** demonstrable transfer by the July presentation; full system + evaluation by the August demo and 30 Aug report.

## 4. Non-goals (v1)

- **Native mobile apps (iOS/Android).** PWA chosen for build speed; native keystore is a documented future hardening step.
- **Relay-attack distance bounding.** Acknowledged in the threat model; precise time-of-flight defenses need hardware control a browser doesn't give. Discussed, not built.
- **Production-grade account management.** No password reset flows, email verification, admin panels — the demo needs login only.
- **Sound-channel encryption.** Unnecessary by design: the acoustic payload is a public nonce.
- **Multi-device / device revocation UX.** Single enrolled phone per user in v1; revocation = delete row.

## 5. Users and user stories

Persona: **end user** (demo audience / examiner stands in for them).

- As a user, I want to log in by just having my phone nearby and touching its fingerprint sensor, so that I never type or remember a password.
- As a user, I want login to fail safely when my phone is absent or locked, so that someone at my laptop cannot impersonateate me.
- As a user, I want a clear audible/visual fallback when ultrasound fails (cheap speakers, noise), so that I am never locked out.
- As a user enrolling a new phone, I want setup to take under a minute, so that adoption is realistic.
- As an attacker (negative story), if I record the login sound and replay it, I gain nothing, because the nonce is single-use and already consumed.

## 6. Requirements

### P0 — must have (cannot demo without)

| # | Requirement | Acceptance criteria |
|---|------------|---------------------|
| P0-1 | Node.js (Express) server with user + device registry (SQLite) | Enroll, login-start, login-verify endpoints work; data survives restart |
| P0-2 | Nonce issuance: 128-bit random, single-use, 30 s TTL, bound to session | Reusing or expiring a nonce returns 401; verified by automated test |
| P0-3 | Laptop login page: username → plays ggwave ultrasound nonce; retransmit button | Nonce audible to decoder at ≥1 m; auto-retransmit up to 3× |
| P0-4 | Phone PWA: mic listening, ggwave decode, approve screen | Decodes within 5 s at 1 m in quiet room |
| P0-5 | Phone signing: WebCrypto ECDSA P-256, non-extractable key in IndexedDB | Private key non-exportable; signature over nonce + origin + username |
| P0-6 | Server signature verification + WebSocket push logs the laptop in | Wrong key, tampered nonce, expired nonce all rejected; demo app session created |
| P0-7 | Audible fallback protocol toggle | Same flow completes using audible ggwave protocol |
| P0-8 | Evaluation harness: scripted runs logging success/fail, distance, noise, latency | CSV output; ≥30 trials per condition for the report |

### P1 — nice to have (fast follow before August demo)

| # | Requirement | Notes |
|---|------------|-------|
| P1-1 | Biometric gate: WebAuthn user-verification on phone before signing | This is the stolen-phone defense — high priority within P1 |
| P1-2 | Login page shows live status (transmitting → phone heard it → approved) | Makes the demo legible to the audience |
| P1-3 | Rate limiting + lockout on failed attempts | Cheap, strengthens security chapter |
| P1-4 | QR-code enrollment hand-off (laptop → phone URL) | Enrollment convenience only — login stays sound-based |

### P2 — future considerations (design for, don't build)

- Native Android app with hardware keystore + `setUserAuthenticationRequired` keys.
- Relay mitigation: amplitude/RTT heuristics, ambient-sound co-presence check as a second signal.
- Bidirectional sound (phone responds acoustically) for network-less laptops.
- Multi-device enrollment and revocation UI.

## 7. Architecture

```
[Laptop browser]                    [Echo server (Node.js)]              [Phone PWA]
 login page                          Express + SQLite + ws                listener + signer
   |-- POST /login/start --------------->|                                   |
   |<-- { sessionId, nonce } ------------|                                   |
   |== plays nonce via ggwave 18-20kHz ==)))  ~1-2 m air gap  ((( == mic ==  |
   |                                     |<-- POST /login/verify ------------|
   |                                     |    { username, nonce, signature } |
   |<== WebSocket "authenticated" =======|                                   |
```

Stack: Node.js + Express + better-sqlite3 + ws · ggwave (WASM) on both browser ends · WebCrypto ECDSA P-256 · vanilla JS front ends (no framework needed).

## 8. Threat model summary

| Threat | Defense | Status |
|---|---|---|
| Replay of recorded login sound | Single-use 30 s nonce | P0 |
| Signature forgery | ECDSA P-256, key never leaves phone | P0 |
| Phishing site triggers login | Signature binds origin + session; signature goes phone→server only | P0 |
| Stolen unlocked phone nearby | WebAuthn biometric before signing | P1 |
| Relay attack (audio streamed to remote phone) | Documented limitation; heuristics in P2 | Accepted v1 risk |
| DoS via nonce flooding | Rate limiting | P1 |

## 9. Success metrics

**Leading (measure at each milestone):**
- Decode success rate: ≥90 % at 1 m quiet (target), ≥70 % at 2 m quiet (stretch)
- End-to-end login latency: median <10 s, p95 <20 s
- Replay/forgery test suite: 100 % rejected

**Lagging (for the report):**
- Full evaluation matrix (3 distances × 3 noise conditions × ≥30 trials)
- Demo reliability: 3 consecutive clean runs on presentation hardware

## 10. Timeline (mapped to CY384 deadlines)

| Phase | Dates | Deliverable |
|---|---|---|
| Phase 0 — feasibility | done | ggwave hardware test page working |
| Phase 1 — core pipeline | 10–28 June | Server + nonce flow + laptop sender + phone decoder (P0-1…P0-4) |
| Phase 2 — crypto complete | 29 June–10 July | Signing + verification + WebSocket login (P0-5, P0-6) → **initial implementation demo 13–17 July** |
| Phase 3 — hardening | 18 July–10 Aug | Biometric gate, fallback, status UI, rate limiting (P0-7, P1) |
| Phase 4 — evaluation | 11–21 Aug | Evaluation harness + data collection (P0-8) → **final demo 24–28 Aug** |
| Phase 5 — report buffer | 22–30 Aug | Author writes report → **due 30 Aug** |

Course-fixed dates: proposal **14 June**, proposal presentation 15–19 June, initial demo 13–17 July, final demo 24–28 Aug, report 30 Aug.

## 11. Open questions

- **(Hardware, blocking Phase 1)** Does the author's actual laptop/phone pair sustain ULTRASOUND_NORMAL at ≥1 m? → answered by the Phase 0 test page; rerun on presentation hardware early.
- **(Engineering, non-blocking)** iOS Safari mic + WebAuthn quirks if the demo phone is an iPhone — verify which phone will be used.
- **(Engineering, non-blocking)** WebSocket vs. polling for the laptop result push — decide in Phase 1 (WebSocket preferred).
- **(Course, blocking proposal)** Confirm with the instructor that a PWA artefact (vs. native app) is acceptable.

## 12. Demo script (target)

1. Show the demo web app's login page — no password field exists.
2. Enter username, click "Log in with Echo." Page shows "transmitting…" (nothing audible).
3. Phone on the desk lights up: "Login request — approve?" → fingerprint touch.
4. Laptop is logged in. Total ~8 seconds.
5. Kill shot: replay a recording of the login sound from another phone → server rejects, screen shows "expired nonce."
