# Echo API Reference

This document specifies every HTTP endpoint and the WebSocket protocol exposed by the Echo server. All REST endpoints are prefixed with `/api`. All request and response bodies use `application/json`. All timestamps are Unix milliseconds.

---

## Authentication

Most endpoints are unauthenticated by design — the authentication *is* the protocol. Endpoints that require a logged-in session read the `echo_session` cookie set by `POST /api/session/claim` or `POST /api/login/recovery`.

---

## Signup and Enrollment

### POST /api/signup

Claim a username and receive a single-use enrollment token. If the username exists but has no enrolled device, the call succeeds and a new token is issued.

**Request Body**

| Field      | Type   | Required | Description                                    |
|------------|--------|----------|------------------------------------------------|
| `username` | string | Yes      | 2–32 characters. Allowed: `a-z 0-9 _ . -`     |

**Example Request**

```json
{ "username": "kwame.a" }
```

**Responses**

| Status | Description                                |
|--------|--------------------------------------------|
| 200    | Username claimed; enrollment token issued  |
| 400    | Username format invalid                    |
| 409    | Username taken and a device is enrolled    |

**Example Response (200)**

```json
{
  "ok": true,
  "username": "kwame.a",
  "enrollToken": "abc123xyz...",
  "ttlMs": 600000
}
```

---

### POST /api/enroll

Redeem a single-use enrollment token and register a device public key. Called by the phone app after key generation.

**Request Body**

| Field          | Type   | Required | Description                              |
|----------------|--------|----------|------------------------------------------|
| `enrollToken`  | string | Yes      | Token received from `POST /api/signup`   |
| `deviceName`   | string | No       | Human-readable device label (max 64 chars) |
| `publicKeyJwk` | object | Yes      | ECDSA P-256 public key in JWK format     |

`publicKeyJwk` must satisfy: `kty === "EC"`, `crv === "P-256"`.

**Example Request**

```json
{
  "enrollToken": "abc123xyz...",
  "deviceName": "Kwame's iPhone",
  "publicKeyJwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "...",
    "key_ops": ["verify"]
  }
}
```

**Responses**

| Status | Description                               |
|--------|-------------------------------------------|
| 200    | Device enrolled; `deviceId` returned      |
| 400    | Missing or malformed fields               |
| 401    | Token invalid, expired, or already used   |

**Example Response (200)**

```json
{
  "ok": true,
  "username": "kwame.a",
  "deviceId": "xY9mNpQr2"
}
```

---

### GET /api/signup/status

Poll the enrollment state of a token. Used by the signup wizard to detect when the phone has finished enrolling.

**Query Parameters**

| Parameter | Type   | Required | Description          |
|-----------|--------|----------|----------------------|
| `token`   | string | Yes      | The enrollment token |

**Responses**

| Status | Description           |
|--------|-----------------------|
| 200    | Status returned       |
| 404    | Token not found       |

**Example Response (200)**

```json
{
  "enrolled": true,
  "deviceId": "xY9mNpQr2",
  "expired": false
}
```

---

## Login

### POST /api/login/start

Issue a single-use nonce bound to a new login session. The nonce is encoded by the laptop and transmitted as sound.

**Request Body**

| Field      | Type   | Required | Description            |
|------------|--------|----------|------------------------|
| `username` | string | Yes      | The account username   |

**Responses**

| Status | Description                                           |
|--------|-------------------------------------------------------|
| 200    | Nonce and session ID returned                         |
| 404    | Username not found or no enrolled device on the account |

**Example Response (200)**

```json
{
  "sessionId": "Lm4nRp7sKq...",
  "nonce": "A8zBxCyDzE1F",
  "ttlMs": 30000
}
```

---

### POST /api/login/verify

Submit the user-approved ECDSA signature over the nonce. Called by the phone app after the user taps **Approve**. On success, the server pushes an `authenticated` event to the waiting laptop WebSocket and returns a one-time claim token embedded in that push.

**Request Body**

| Field       | Type   | Required | Description                                         |
|-------------|--------|----------|-----------------------------------------------------|
| `nonce`     | string | Yes      | The nonce received acoustically                     |
| `deviceId`  | string | Yes      | The device ID stored during enrollment              |
| `signature` | string | Yes      | Base64url ECDSA/SHA-256 signature over the message  |

The signed message is the UTF-8 encoding of:

```
echo-v1|<nonce>|<deviceId>
```

**Responses**

| Status | Description                                                          |
|--------|----------------------------------------------------------------------|
| 200    | Signature valid; laptop WebSocket notified with `claimToken`         |
| 400    | Missing fields                                                       |
| 401    | Nonce unknown, expired, already used, bad signature, or wrong device |

**Example Response (200)**

```json
{ "ok": true }
```

---

### POST /api/session/claim

Exchange the one-time `claimToken` (received by the laptop over WebSocket) for an `echo_session` cookie. This step creates the authenticated server session.

**Request Body**

| Field        | Type   | Required | Description                                              |
|--------------|--------|----------|----------------------------------------------------------|
| `sessionId`  | string | Yes      | The session ID from `POST /api/login/start`              |
| `claimToken` | string | Yes      | The claim token pushed to the laptop over WebSocket      |

**Responses**

| Status | Description                                          |
|--------|------------------------------------------------------|
| 200    | Session created; `echo_session` cookie set           |
| 401    | Session not approved, claim token invalid or reused  |

**Example Response (200)**

Sets `Set-Cookie: echo_session=<token>; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800`

```json
{
  "ok": true,
  "username": "kwame.a"
}
```

---

## Recovery

### POST /api/login/recovery

Authenticate using a one-time recovery code when the enrolled phone is unavailable. Rate-limited to 5 attempts per 15 minutes per account.

**Request Body**

| Field      | Type   | Required | Description                   |
|------------|--------|----------|-------------------------------|
| `username` | string | Yes      | The account username          |
| `code`     | string | Yes      | Recovery code in `XXXX-XXXX` format |

**Responses**

| Status | Description                                           |
|--------|-------------------------------------------------------|
| 200    | Code valid; `echo_session` cookie set                 |
| 401    | Invalid username or code                              |
| 429    | Too many failed attempts; try again in 15 minutes     |

**Example Response (200)**

```json
{
  "ok": true,
  "username": "kwame.a",
  "remainingCodes": 5
}
```

---

### POST /api/recovery/generate

Generate (or regenerate) six single-use recovery codes for the authenticated user. Replaces all existing unused codes. Codes are displayed in plain text exactly once and stored only as SHA-256 hashes.

**Authentication:** Required (`echo_session` cookie)

**Request Body:** None

**Responses**

| Status | Description                  |
|--------|------------------------------|
| 200    | Six codes returned           |
| 401    | Not logged in                |

**Example Response (200)**

```json
{
  "ok": true,
  "codes": [
    "ABCD-EF23",
    "GH45-JK67",
    "MN89-PQ2R",
    "ST3U-VW4X",
    "YZ56-AB78",
    "CD9E-FG23"
  ]
}
```

---

## Device Management

### POST /api/device/token

Issue a new enrollment token so the authenticated user can add a second device. The returned token is used identically to the one from `POST /api/signup`.

**Authentication:** Required (`echo_session` cookie)

**Request Body:** None

**Responses**

| Status | Description                  |
|--------|------------------------------|
| 200    | Enrollment token returned    |
| 401    | Not logged in                |

**Example Response (200)**

```json
{
  "ok": true,
  "enrollToken": "newToken123...",
  "ttlMs": 600000
}
```

---

### POST /api/device/revoke

Remove a device from the account. The device's key is immediately rejected on subsequent login attempts.

**Authentication:** Required (`echo_session` cookie)

**Request Body**

| Field      | Type   | Required | Description         |
|------------|--------|----------|---------------------|
| `deviceId` | string | Yes      | ID of the device to remove |

**Responses**

| Status | Description             |
|--------|-------------------------|
| 200    | Device removed          |
| 401    | Not logged in           |
| 404    | Device not found or does not belong to the account |

**Example Response (200)**

```json
{ "ok": true }
```

---

## Session

### GET /api/me

Return the current user's profile, enrolled devices, and recent authentication history.

**Authentication:** Required (`echo_session` cookie)

**Responses**

| Status | Description         |
|--------|---------------------|
| 200    | Profile returned    |
| 401    | Not logged in       |

**Example Response (200)**

```json
{
  "username": "kwame.a",
  "devices": [
    {
      "id": "xY9mNpQr2",
      "name": "Kwame's iPhone",
      "created_at": 1718000000000
    }
  ],
  "recoveryUnused": 6,
  "recentLogins": [
    {
      "method": "sound",
      "ok": 1,
      "detail": null,
      "created_at": 1718001000000,
      "device_name": "Kwame's iPhone"
    }
  ]
}
```

---

### POST /api/logout

Invalidate the current session. Clears the `echo_session` cookie.

**Authentication:** Required (`echo_session` cookie)

**Request Body:** None

**Responses**

| Status | Description       |
|--------|-------------------|
| 200    | Session destroyed |

**Example Response (200)**

```json
{ "ok": true }
```

---

## WebSocket Protocol

### WS /ws

The laptop login page opens a WebSocket connection after calling `POST /api/login/start`, using the `sessionId` as a query parameter. The server pushes a single message when the phone approves the login.

**Connection URL**

```
ws://localhost:8000/ws?session=<sessionId>
```

For HTTPS deployments, use the `wss://` scheme.

**Connection Rejection**

The server calls `socket.destroy()` immediately if:
- The path is not `/ws`
- The `session` query parameter is absent
- No login session with that ID exists in the database

**Server-to-Client Message: `authenticated`**

Sent when `POST /api/login/verify` succeeds for the session.

```json
{
  "type": "authenticated",
  "claimToken": "one-time-token..."
}
```

The `claimToken` must be submitted to `POST /api/session/claim` immediately. It is single-use and nulled out after the first claim.

---

## Error Format

All error responses follow a consistent structure:

```json
{ "error": "human-readable message describing the failure" }
```

---

## Data Retention

The server automatically purges the following records every 60 seconds:

- Login sessions expired more than 10 minutes ago
- Authenticated sessions past their 8-hour expiry
- Unused enrollment tokens expired more than 10 minutes ago
