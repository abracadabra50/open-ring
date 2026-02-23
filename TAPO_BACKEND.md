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

- RTSP stream access
- ONVIF service
- Local-network connectivity from the Mac running OpenCamera

## Event Pipeline

1. ONVIF PullPoint monitor attempts to ingest camera events.
2. Raw events are normalized to:
   - `motion`
   - `person`
3. If ONVIF repeatedly fails, a snapshot-diff fallback monitor is auto-enabled.
4. Normalized events are:
   - persisted to local storage,
   - displayed in timeline UI,
   - eligible for notifications.

## Notification Behavior

- Notifications are triggered for `motion` and `person`.
- Deduping and recency gates are retained.
- If notifications permission is denied, app continues running without hard failure.

## Current Phase-1 Limitations

- AI features are placeholder-only in Tapo mode.
- Clip playback is placeholder-only in Tapo mode.
- Runtime provider selection is fixed to Tapo in phase 1.
- Ring provider is not user-selectable yet.
