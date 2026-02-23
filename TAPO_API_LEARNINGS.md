# Tapo HTTP API Learnings

This document summarizes the findings from reverse-engineering the Tapo C220 HTTP API for use in `open-camera`.

## Why HTTP API over ONVIF?

Initial attempts to use ONVIF PullPoint subscriptions for event monitoring failed. While the Tapo C220 advertises ONVIF support, its event delivery is notoriously unreliable across different firmware versions. The official Tapo app and the open-source `pytapo` library both use the camera's proprietary **HTTPS API on port 443** instead.

## Authentication Protocol

The Tapo HTTPS API uses a secure, non-standard challenge-response mechanism.

### 1. Credentials required

- **Username:** Hardcoded to `admin` for the HTTP API (do NOT use the camera account username).
- **Password:** The **TP-Link Cloud account password** (not the camera account password used for RTSP).

### 2. The Handshake Flow

1. **Probe Request:** POST to `https://<ip>:443/` with `{"method": "login", "params": {"encrypt_type": "3", "username": "admin", "cnonce": "<random>"}}`.
2. **Probe Response:** The camera returns a `nonce` and a `device_confirm` hash.
3. **Hash Validation:** To verify the camera, calculate `MD5(password)` and `SHA256(password)`. Then hash them with the nonces:
   - SHA256 Candidate: `SHA256( SHA256(password) + nonce + cnonce )`
   - MD5 Candidate: `SHA256( MD5(password) + nonce )` (Note: the current `pytapo` uses string concatenation of cnonce + MD5 + nonce).
     If either matches `device_confirm`, the password hash type used for the match becomes the active hash.
4. **Login Request:** Send the final digest (`digest_passwd`) back to the camera.
5. **Login Response:** The camera returns a `stok` (session token) and AES 128 CBC keys (`lsk`, `ivb`).

### 3. Lockouts

The camera implements strict rate limiting.

- If authentication fails repeatedly, the camera enters a **lockout state**.
- The API will return `error_code: -40401` with an inner `code: -40404` and `sec_left: <seconds>`.
- **Crucial:** Once locked out, even requests with the _correct_ password will be rejected until the timer expires. You must stop polling and wait the full `sec_left` duration.

### 4. AES Encrypted Payloads

After successful login, all requests must be AES-128-CBC encrypted.

- The payload is JSON, encrypted with `lsk` and `ivb`, and base64 encoded.
- The request wrapper looks like: `{"method": "securePassthrough", "params": {"request": "<base64>"}}`
- **Sequence Counter:** Requests must include a `Seq` header that increments with every successful request. If the sequence is reused, the camera may drop the request silently.
- **Tapo_tag Header:** A SHA256 HMAC tag of the payload and sequence number must be sent in the `Tapo_tag` header.

## Event Polling

To get events, we poll the `searchDetectionList` endpoint via `multipleRequest`.

### 1. The Endpoint

POST to `https://<ip>:443/stok=<stok>/ds` with the encrypted payload representing a `searchDetectionList` query for a specific time range.

### 2. Parsing the Response

The camera returns a list of detections within the requested time range.

**Key Fields:**

- `start_time` / `end_time`: Unix timestamps.
- **`alarm_type`**: The definitive field for identifying the event kind.
  - `0`: No detection
  - `2`: Motion
  - `4`: Line-crossing
  - `5`: Area intrusion
  - `6`: Person + Motion
  - `8`: Vehicle
- `events_1`: A bitmask representing concurrent event types (e.g., bit 1=motion, bit 5=person). `alarm_type` is preferred for standard classification.

_Note: The `searchDetectionList` endpoint reads from the camera's local SD card recordings. If no SD card is present, or local recording is disabled, this endpoint will return empty._

## Summary of `seq` Behavior

The `seq` (sequence) field is initialized during the secure authentication handshake. It **must be incremented for every subsequent request sent to the camera** using that active session (`stok`). Failing to increment `seq` results in ignored or failed requests.

---

## Referencing `pytapo` for New Features

Our Swift implementation (`TapoAuthenticator` and `TapoHttpEventMonitor`) provides the complete, secure transport layer (AES encryption, hashing, stok session management).

To add new camera controls or features in the future, you **do not** need to write new networking code. You only need to look at the official [pytapo Python source code](https://github.com/JurajNyiri/pytapo/tree/main/pytapo) to find the correct `method` and `params` payload, and pass it into our `TapoAuthenticator.sendRequest()`.

### How to Port a Feature from `pytapo`

1. Open the [`pytapo/__init__.py`](https://github.com/JurajNyiri/pytapo/blob/main/pytapo/__init__.py) file.
2. Search for the desired function (e.g., `setPrivacyMode`).
3. Look at the `executeFunction` call inside that Python method.
4. Note the string used for the `"method"` and the JSON structure used for the `"params"`.
5. In Swift, construct the identical JSON dictionary and call `sendRequest`.

_Example: Pytapo's `setLensMaskConfig` translates directly to our Swift dictionary payload used for Privacy Mode._

## Next Steps & Future Integrations

Based on the `pytapo` feature set, here are the highest-value features we should consider bringing into `open-camera` next:

1. **Time Correction (`getTimeCorrection`)**
   - **Why:** The camera's internal clock can drift from the Mac's local time. If the drift exceeds our 10-minute polling window, we could miss events entirely.
   - **Action:** Port the time sync logic from pytapo to calculate the offset and apply it to our `start_time` / `end_time` polling calculations.

2. **Pan/Tilt/Zoom (PTZ) Controls (`setMotorPosition`, `moveMotorStep`)**
   - **Why:** The C220 is a dome camera. Adding a small D-pad to the UI would allow moving the lens directly from the Mac.

3. **Status LED Toggle (`setLED`)**
   - **Why:** Useful for users who want stealth monitoring or find the green light annoying at night.

4. **Siren / Alarm Trigger (`setAlarm`)**
   - **Why:** Allows triggering the camera's built-in siren/light manually from the Mac menu bar as a panic button.

5. **SD Card Recordings (`getRecordings`)**
   - **Why:** Instead of just sending notifications for live motion, we could allow the user to browse or download the actual video clips triggered by the event via the `downloaderv2` endpoint.
