<h1 align="center">OpenRing</h1>

<p align="center">
  <strong>An unofficial native macOS menu bar app for Ring doorbells and cameras</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

OpenRing brings your Ring devices to your Mac's menu bar. View live streams, get notifications, talk to visitors, control your devices, and even ask AI what's happening—all without opening a browser or phone app.

## Why OpenRing?

Ring's official app is phone-first. There's no native Mac app, just a web dashboard that's clunky and slow. OpenRing fixes that:

- **Native performance** — Built with SwiftUI, feels like a first-party Apple app
- **Menu bar access** — One click (or hotkey) to see your cameras
- **Real-time streaming** — WebRTC video with sub-second latency, faster than the phone app
- **Instant access** — No waiting for the Ring app to load—click and stream
- **AI-powered** — Ask "What's at the door?" and get an instant answer
- **Privacy-focused** — Your credentials stay in Keychain, no telemetry

---

## Features

### Live Video Streaming

Stream video from any Ring device in real-time using WebRTC.

- **Multi-camera support** — Switch between cameras with swipe gestures or keyboard shortcuts (⌘1-4)
- **Portrait mode** — Doorbells display in their native vertical orientation
- **Zoom controls** — Use +/- keys or scroll to zoom in/out (1x-3x)
- **Connection status** — Visual indicators for ICE/signaling state
- **Auto-reconnect** — Handles network interruptions gracefully

The video pipeline uses Ring's WebRTC infrastructure with proper ICE candidate handling and codec negotiation (H.264).

### Push-to-Talk

Two-way audio communication with visitors.

- **Hold-to-talk** — Hold the microphone button to speak, release to listen
- **Visual feedback** — Button animates to show when transmitting
- **Low latency** — Audio streams via WebRTC alongside video

### AI Guard

Ask questions about what your cameras see using Claude's vision capabilities.

**Live Analysis:**
- "What's at the door?" — Captures current frame and describes the scene
- "Is there a package?" — Detects objects in view
- "Describe what you see" — General scene understanding

**Event Queries:**
- "Who came today?" — Summarizes events from history
- "Show me the last motion" — Plays back most recent motion event
- "Any deliveries this week?" — Searches event history

**How it works:**
1. Captures a frame from the live WebRTC stream (or fetches from event history)
2. Sends to Anthropic's Claude API with your question
3. Returns natural language response with option to play related video

Requires an Anthropic API key (stored securely in Keychain).

### Device Controls

Control your Ring devices directly from the app.

| Control | Description | Devices |
|---------|-------------|---------|
| **Floodlight** | Toggle flood/spotlight on/off | Spotlight Cam, Floodlight Cam |
| **Siren** | Activate 30-second alarm | Cameras with siren capability |
| **Motion Detection** | Enable/disable motion alerts | All cameras |

Controls appear contextually—doorbells won't show floodlight toggle since they don't have one.

### Event Timeline

Browse and play back recorded events.

- **Filter chips** — View All, Ring (doorbell presses), or Motion events
- **Inline playback** — Tap any event to play its recording without leaving the app
- **Export** — Save any recording to disk (downloads MP4 from Ring's servers)
- **Relative timestamps** — "2 min ago", "Yesterday at 3:42 PM"

### Notifications

Get alerted when something happens.

- **Native macOS notifications** — Integrates with Notification Center
- **Motion & ring alerts** — Separate toggles for each type
- **Snooze** — Temporarily silence notifications
- **Background polling** — Checks for new events every 15-120 seconds (configurable)

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘`** | Open OpenRing (global, works from any app) |
| **⌘1-4** | Switch to camera 1/2/3/4 |
| **+/-** | Zoom in/out |
| **←/→** | Previous/next camera |
| **Space** | Toggle push-to-talk |

The global hotkey is customizable in Settings (⌘⇧R, ⌘⌥O, ⌃⌥Space, etc.).

### Settings

| Setting | Options | Default |
|---------|---------|---------|
| Polling interval | 15s, 30s, 60s, 2min | 30s |
| Motion alerts | On/Off | On |
| Notification sound | On/Off | On |
| Global hotkey | ⌘`, ⌘⇧R, ⌘⌥O, ⌃⌥Space | ⌘` |
| Show battery level | On/Off | On |
| Anthropic API key | Securely stored | — |

---

## Installation

### Download (Recommended)

1. Go to [Releases](https://github.com/abracadabra50/open-ring/releases)
2. Download `OpenRing-x.x.x.dmg`
3. Open the DMG and drag OpenRing to Applications
4. Launch from Applications (you may need to right-click → Open the first time)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/abracadabra50/open-ring.git
cd open-ring/app

# Open in Xcode
open OpenRing.xcworkspace

# Build and run (⌘R)
```

**Requirements:**
- Xcode 15.0+
- macOS 14.0+ (Sonoma)
- Swift 5.9+

---

## First Launch

1. **Login** — Enter your Ring email and password
2. **2FA** — Ring will send an SMS code, enter it in the app
3. **Grant Permissions:**
   - **Notifications** — For motion/ring alerts
   - **Accessibility** — For global hotkey (optional but recommended)
4. **Done** — Your devices appear automatically

Your credentials are stored in macOS Keychain. The app maintains a session token and refreshes it automatically.

---

## Architecture

```
open-ring/
├── app/
│   ├── OpenRing/                    # macOS app shell
│   │   └── OpenRingApp.swift        # App entry, MenuBarExtra, Settings
│   │
│   └── OpenRingPackage/             # Swift Package with all modules
│       │
│       ├── Sources/
│       │   ├── OpenRingFeature/     # Main UI and features
│       │   │   ├── PopoverView.swift
│       │   │   ├── MultiStreamVideoView.swift
│       │   │   ├── LoginView.swift
│       │   │   ├── EventTimelineView.swift
│       │   │   ├── AIOverlayPanel.swift
│       │   │   ├── DrawerPanel.swift
│       │   │   ├── KeyboardShortcutManager.swift
│       │   │   └── NotificationManager.swift
│       │   │
│       │   ├── RingClient/          # Ring API client (reusable)
│       │   │   ├── RingClient.swift     # API methods
│       │   │   ├── RingTypes.swift      # Data models
│       │   │   ├── RingWebRTC.swift     # WebRTC session
│       │   │   ├── LiveViewSession.swift
│       │   │   └── KeychainManager.swift
│       │   │
│       │   ├── DesignSystem/        # UI components & tokens
│       │   │   ├── Colors.swift
│       │   │   ├── Typography.swift
│       │   │   └── Components/
│       │   │
│       │   └── Storage/             # Local persistence (GRDB)
│       │
│       └── Package.swift
```

### Key Modules

**RingClient** — The Ring API wrapper. Handles:
- OAuth2 authentication with 2FA
- Device discovery (`/clients_api/ring_devices`)
- Event history (`/clients_api/doorbots/{id}/history`)
- Live streaming via WebRTC
- Device controls (floodlight, siren, motion detection)

**OpenRingFeature** — All UI and app logic:
- SwiftUI views for every screen
- WebRTC video rendering with Metal
- AI integration with Anthropic
- Notification handling
- Keyboard shortcut management

**DesignSystem** — Consistent styling:
- Ring-inspired color palette
- Typography scale
- Reusable components (chips, buttons, cards)

---

## RingClient API

The `RingClient` module can be used independently in your own projects.

### Authentication

```swift
import RingClient

// Initial login (triggers 2FA)
try await RingClient.shared.login(email: "you@example.com", password: "secret")

// Complete 2FA
try await RingClient.shared.verify2FA(code: "123456")

// Session persists in Keychain
// On subsequent launches:
let restored = try await RingClient.shared.restoreSession()
if restored {
    // Good to go
}

// Logout
try await RingClient.shared.logout()
```

### Devices

```swift
// Fetch all devices (doorbells, cameras, chimes)
let devices = try await RingClient.shared.fetchDevices()

for device in devices {
    print("\(device.name) - \(device.deviceType)")
    print("  Battery: \(device.batteryLevel ?? -1)%")
    print("  Online: \(device.isOnline)")
}
```

### Events

```swift
// Get recent events for all devices
let events = try await RingClient.shared.fetchAllRecentEvents(limit: 20)

for event in events {
    print("\(event.kind.displayName) at \(event.createdAt)")
    print("  Device: \(event.deviceName ?? "Unknown")")
}

// Get recording URL for an event
let url = try await RingClient.shared.getEventVideoURL(eventId: event.id)
```

### Live Streaming

```swift
// Create a live view session
let session = LiveViewSession(
    device: device,
    onVideoTrack: { track in
        // Attach to your video view
    },
    onAudioTrack: { track in
        // Handle audio
    },
    onConnectionState: { state in
        print("WebRTC state: \(state)")
    }
)

// Start streaming
session.start()

// Push-to-talk
session.startTalking()
session.stopTalking()

// Stop
session.stop()
```

### Device Controls

```swift
// Floodlight (for Spotlight/Floodlight cameras)
try await RingClient.shared.setFloodlight(deviceId: device.id, enabled: true)

// Siren (30-second alarm)
try await RingClient.shared.setSiren(deviceId: device.id, enabled: true)

// Motion detection
try await RingClient.shared.setMotionDetection(deviceId: device.id, enabled: false)
```

---

## How It Works

### Authentication Flow

1. POST to Ring OAuth endpoint with email/password
2. Ring responds with `tsv_state` indicating 2FA required
3. User enters SMS code
4. POST code + tsv_state to complete auth
5. Receive `access_token` and `refresh_token`
6. Tokens stored in Keychain
7. Access token used in `Authorization: Bearer` header
8. Refresh token used when access token expires

### WebRTC Streaming

1. Request live view ticket from Ring API
2. Receive SDP offer and ICE servers
3. Create local peer connection with answer
4. Exchange ICE candidates via Ring's signaling
5. Video track attached to `RTCMTLVideoView`
6. Audio handled via WebRTC's audio session

### AI Integration

1. User types question or taps capture button
2. App captures current frame from WebRTC video track
3. Frame encoded as base64 JPEG
4. Sent to Anthropic Claude API with vision capability
5. Response streamed back and displayed
6. If response references an event, show "Play" button

---

## Privacy & Security

- **Credentials** — Stored in macOS Keychain, never on disk
- **API Keys** — Anthropic key stored in Keychain separately
- **Network** — All traffic over HTTPS
- **No Telemetry** — Zero analytics, tracking, or phone-home
- **Open Source** — Audit the code yourself
- **Local Only** — No cloud backend, speaks directly to Ring

---

## Known Limitations

- **No subscription management** — Can't change Ring Protect plan
- **No device setup** — Add new devices via official app
- **No geofencing** — Home/Away modes not implemented
- **macOS only** — No iOS/Windows/Linux versions
- **Ring account required** — Doesn't work with Ring alternatives

---

## Troubleshooting

**"Session expired" after closing app**
- This is normal. Ring tokens expire. Re-login to refresh.

**Video not loading**
- Check your internet connection
- Try a different device
- Ring's servers occasionally have issues

**Global hotkey not working**
- Grant Accessibility permission in System Settings
- Check if another app uses the same shortcut

**2FA code not arriving**
- Ring sends via SMS only
- Check your phone number is correct in Ring account

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/abracadabra50/open-ring.git
cd open-ring/app
open OpenRing.xcworkspace
```

The project uses Swift Package Manager. Dependencies are resolved automatically.

---

## Disclaimer

**This is an unofficial app.** OpenRing is not affiliated with, endorsed by, or connected to Ring LLC or Amazon.com, Inc. Ring is a trademark of Ring LLC. Use at your own risk.

This app uses Ring's private API, which is undocumented and may change without notice. Ring could block access at any time.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with SwiftUI, WebRTC, and Claude
</p>
