# Tapo Backend (Phase 1)

This document describes the phase-1 Tapo-first backend integrated into OpenCamera's menu bar UX.

## Build Preconditions

- `OpenCameraPackage` currently uses `swift-tools-version: 6.1`.
- If your local toolchain is older (for example Swift 6.0.3), package-level builds may fail before app code is compiled.
- Use a Swift 6.1-capable Xcode/toolchain, or temporarily lower tools-version during local validation.

## Runtime Shape

- Provider abstraction is introduced via `CameraDomain.CameraProvider`.
- Phase 1 default provider: `CameraProviders.TapoProvider`.
- Ring code remains in-repo and a `RingProviderAdapter` skeleton is included for phase-2 reactivation.

## Setup Flow

On first launch, the popover shows a Tapo setup form:

- Host/IP
- Username
- Password (stored in Keychain)
- RTSP profile (`main` / `sub`)
- RTSP port (default `554`)
- ONVIF port (default `2020`)

Non-secret configuration is stored locally in app settings, while credentials are stored in Keychain.

## Camera-Side Requirements

Enable these on the Tapo C220:

- **Camera Account** (Tapo App → Advanced Settings → Camera Account) — required for HTTP API and RTSP authentication
- RTSP stream access
- ONVIF service (used as fallback only)
- Local-network connectivity from the Mac running OpenCamera

## Event Pipeline

Three-tier event detection with automatic failover:

1. **Primary — Tapo HTTP API** (`TapoHttpEventMonitor`)
   - Authenticates with the camera's proprietary HTTPS API (port 443) using stok tokens
   - Polls `searchDetectionList` every 5 seconds for motion/person events
   - Same mechanism used by the Tapo mobile app and the pytapo library
2. **Secondary fallback — ONVIF PullPoint** (`OnvifEventMonitor`)
   - Activated if the HTTP API fails 5 consecutive times
   - Creates a PullPoint subscription and polls for events
   - Note: Tapo ONVIF event support is unreliable across firmware versions
3. **Tertiary fallback — Snapshot diff** (`SnapshotDiffEventMonitor`)
   - Activated if ONVIF also fails 3 consecutive times
   - Compares snapshot luminance to detect motion

Detected events are normalized to `motion` or `person`, then:

- Persisted to local storage
- Displayed in the timeline UI
- Eligible for macOS notifications

## Notification Behavior

- Notifications are triggered for `motion` and `person`.
- Deduping and recency gates are retained.
- If notifications permission is denied, app continues running without hard failure.

## Current Phase-1 Limitations

- AI features are placeholder-only in Tapo mode.
- Clip playback is placeholder-only in Tapo mode.
- Runtime provider selection is fixed to Tapo in phase 1.
- Ring provider is not user-selectable yet.
