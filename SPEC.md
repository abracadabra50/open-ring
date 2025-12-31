# open-ring

**A local-first Ring control room for macOS**

---

## 0. What open-ring Is

A native macOS application that connects directly to your Ring account, ingests events (doorbell presses, motion, packages), caches snapshots/clips locally, and provides:

- **Menubar app** (`open-ring.app`) — primary interface with live video, quick actions, notifications
- **CLI/TUI** (`open-ring`) — power-user terminal interface for scripting and deep dives
- **Daemon** (`open-ringd`) — optional background service for automation, plugins, and API access

Core design: **menubar is the product, CLI is the platform**. Most users interact via menubar. Hackers and automation enthusiasts use the CLI, daemon, and plugin system.

---

## 1. Goals

- **Fast**: UI renders from local cache; network calls happen in background
- **Useful**: "What happened?", "Show me live", "Snooze", "Export"
- **Hackable**: Documented API, Lua plugins, webhooks, open source
- **Secure**: Tokens in macOS Keychain; no plaintext secrets
- **Resilient**: Graceful degradation, re-auth prompts, works when Ring is flaky

## 2. Non-Goals (v0)

- Face recognition / person identification
- Public clip sharing
- Multi-account support
- Ring Alarm integration (sensors, arming modes)
- Spotlight/floodlight controls (v1)

---

## 2.5. Design System

**Philosophy**: Native macOS that feels like a first-party Apple app, with the polish of Raycast, the clarity of Linear, the attention to detail of CleanShot X, and the personality of Ivory.

### Inspiration

| App | What to steal |
|-----|---------------|
| **Raycast** | Speed, keyboard-first, command palette density, dark mode excellence |
| **Linear** | Typography hierarchy, monospace accents, professional calm |
| **CleanShot X** | Floating window design, subtle shadows, thoughtful hover states |
| **Ivory** | Native feel with personality, beautiful iconography, timeline layout |

### Color System

**Accent color**: Ring Blue `#1C96E8`
- Used sparingly: buttons, selection, live indicator
- Works in both light and dark modes

**Semantic colors**:
| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `ring.accent` | `#1C96E8` | `#1C96E8` | Primary actions, live indicator |
| `ring.ring` | `#1C96E8` | `#4AA8F0` | Ring press events |
| `ring.motion` | `#8E8E93` | `#98989D` | Motion events |
| `ring.package` | `#34C759` | `#30D158` | Package events |
| `ring.error` | `#FF3B30` | `#FF453A` | Auth expired, errors |
| `ring.success` | `#34C759` | `#30D158` | Connected, online |

**Backgrounds** (respect system appearance):
```swift
// Light mode
Color.primary           // #000000
Color.secondary         // #3C3C43 @ 60%
Color.tertiary          // #3C3C43 @ 30%
Color.background        // System background
Color.secondaryBg       // System secondary background

// Dark mode
Color.primary           // #FFFFFF
Color.secondary         // #EBEBF5 @ 60%
Color.tertiary          // #EBEBF5 @ 30%
Color.background        // System background
Color.secondaryBg       // System secondary background
```

### Typography

**Font stack**: SF Pro (body) + SF Mono (accents)

| Style | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| `title` | SF Pro | 13pt | Semibold | Popover header |
| `headline` | SF Pro | 12pt | Medium | Section headers |
| `body` | SF Pro | 12pt | Regular | Primary text |
| `caption` | SF Pro | 11pt | Regular | Secondary info |
| `timestamp` | SF Mono | 11pt | Regular | Times, IDs, technical |
| `mono` | SF Mono | 11pt | Medium | Device names in events |

**Hierarchy example**:
```
Front Door                     ← headline, SF Pro Medium 12pt
├─ 14:36  RING                 ← timestamp SF Mono 11pt + body SF Pro 12pt
├─ 14:12  MOTION
└─ 12:02  PACKAGE
```

### Spacing Scale

Based on 4pt grid:
```
xs:   4pt    (tight padding)
sm:   8pt    (list item gaps)
md:  12pt    (section padding)
lg:  16pt    (card padding)
xl:  24pt    (major sections)
```

### Layout

**Popover dimensions**:
- Width: 400pt (comfortable density)
- Max height: 600pt
- Corner radius: 12pt (matches macOS)
- Padding: 16pt (lg)

**Video area**:
- Aspect ratio: 16:9
- Corner radius: 8pt
- Within popover: full-width with 12pt margin

**Timeline**:
- Left gutter: 48pt (timestamps)
- Icon size: 16pt
- Row height: 36pt
- Row gap: 2pt

### Components

#### Popover

```
┌────────────────────────────────────────┐  ← 12pt corner radius
│ ╭──────────────────────────────────╮   │  ← 16pt padding
│ │                                  │   │
│ │          VIDEO AREA              │   │  ← 16:9, 8pt radius
│ │          (live or snapshot)      │   │
│ │                                  │   │
│ ╰──────────────────────────────────╯   │
│                                        │
│  Front Door ▾              ◉ Live  ⤢   │  ← device picker, live indicator, detach
│ ─────────────────────────────────────  │  ← subtle divider (1pt, tertiary)
│                                        │
│  14:36   🔔  Ring press               │  ← timeline row
│  14:12   👤  Motion detected          │
│  12:02   📦  Package delivered        │
│                                        │
│ ─────────────────────────────────────  │
│  ⏸ Snooze ▾          🔔 Motion: ON    │  ← action bar
└────────────────────────────────────────┘
```

#### Floating Video Window

```
╭────────────────────────────────────────╮
│                                        │  ← Frameless (no title bar)
│                                        │  ← Large shadow (radius: 40pt, opacity: 0.3)
│              VIDEO                     │  ← 12pt corner radius
│                                        │  ← Drag anywhere to move
│                                        │
│  Front Door              ◉ LIVE  1:42  │  ← Overlay bar (appears on hover)
╰────────────────────────────────────────╯
```

**Floating window specs**:
- Default size: 480×270pt (16:9)
- Min size: 320×180pt
- Corner radius: 12pt
- Shadow: `NSShadow` with blur 40pt, offset (0, -10), color black @ 30%
- Always on top (floating window level)
- Overlay controls: fade in/out on hover (0.2s ease)

#### Timeline Row

```
┌─────────────────────────────────────────────────┐
│  14:36   🔔   Ring press                    →   │
│    ↑      ↑        ↑                        ↑   │
│  mono   icon    body                   chevron  │
│  11pt   16pt    12pt                    on hover│
└─────────────────────────────────────────────────┘

Hover state: subtle background tint (tertiary @ 50%)
Selected state: accent background tint
```

#### Buttons

**Primary** (accent filled):
- Background: `ring.accent`
- Text: white, SF Pro Medium 12pt
- Corner radius: 6pt
- Padding: 8pt horizontal, 6pt vertical
- Hover: brightness +10%
- Active: brightness -10%

**Secondary** (bordered):
- Background: transparent
- Border: 1pt tertiary
- Text: primary color
- Same dimensions as primary
- Hover: background tertiary @ 30%

**Icon button**:
- Size: 28×28pt
- Icon: 14pt SF Symbol
- Corner radius: 6pt
- Hover: background tertiary @ 50%

### Icons

Use **SF Symbols** exclusively:
| Concept | Symbol |
|---------|--------|
| Ring press | `bell.fill` |
| Motion | `figure.walk` |
| Package | `shippingbox.fill` |
| Live | `video.fill` |
| Snooze | `moon.fill` |
| Settings | `gearshape` |
| Detach/PiP | `pip.enter` |
| Close | `xmark` |
| Camera | `camera.fill` |
| Mute | `speaker.slash.fill` |
| Unmute | `speaker.wave.2.fill` |

**Icon colors**:
- Ring: `ring.accent`
- Motion: `ring.motion` (gray)
- Package: `ring.package` (green)
- Actions: primary color

### Menubar Icon

Custom SF Symbol-compatible icon:
- Template image (adapts to system appearance)
- 18×18pt canvas
- Ring outline shape

**States**:
| State | Appearance |
|-------|------------|
| Normal | Outline only |
| New event | Filled + small badge (accent dot) |
| Live active | Filled, subtle pulse animation |
| Auth expired | Outline + red dot badge |
| Offline | Outline, 50% opacity |

### Animations

**Principle**: Subtle, functional, not decorative.

**Timing functions**:
- Default: `easeInOut` (0.2s)
- Spring: `spring(response: 0.3, dampingFraction: 0.7)`

**Transitions**:
| Element | Animation |
|---------|-----------|
| Popover appear | Scale 0.95→1 + fade, spring |
| Floating window | Scale 0.9→1 + fade, spring |
| Row hover | Background fade (0.15s) |
| Live indicator | Subtle pulse (scale 1→1.05, opacity 1→0.8, 1s loop) |
| Video controls | Fade in/out (0.2s) |
| Mode switch (light↔dark) | Crossfade (0.3s) |

**What NOT to animate**:
- List scrolling (native)
- Text changes
- Icon swaps (instant)

### Dark Mode & Light Mode

Both modes are first-class citizens. Test every component in both.

**Light mode**:
- Clean, bright backgrounds
- Subtle shadows for depth
- Ring blue pops as accent

**Dark mode**:
- True blacks where appropriate
- Softer shadows (less contrast)
- Ring blue slightly brighter for visibility

### Accessibility

- All text: minimum 11pt
- Contrast ratios: WCAG AA compliant
- Full keyboard navigation in popover
- VoiceOver labels for all interactive elements
- Reduce Motion: disable pulse animations, use fades only
- High Contrast: respect system setting

### Empty States

**Iconographic style** (SF Symbols):
```
┌────────────────────────────────────────┐
│                                        │
│              📷                        │  ← 48pt SF Symbol
│                                        │
│         No events yet                  │  ← headline
│    Events will appear here when        │  ← caption, secondary color
│    your Ring detects activity          │
│                                        │
└────────────────────────────────────────┘
```

### Loading States

**System spinner** (NSProgressIndicator):
- Centered in container
- Small size for inline loading
- Regular size for full-area loading

**Video loading**:
- Show last snapshot as placeholder
- Spinner overlay
- "Connecting..." label

### Error States

**Silent badge** for auth expiry:
- Menubar icon shows red dot
- Popover shows inline banner: "Session expired. [Re-login]"
- No intrusive alerts

**Connection error**:
- Inline banner in popover
- Gray out video area
- "Offline — showing cached events"

### Notifications (System)

**Text-only** (no thumbnails):
```
┌────────────────────────────────────────┐
│ 🔔  open-ring                          │
│ Ring — Front Door                      │
│ Someone is at the door                 │
│                            just now    │
└────────────────────────────────────────┘
```

**Actions**:
- "View" (opens popover)
- "Snooze 1h"

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Ring Cloud                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Swift Ring Client                             │
│         (auth, devices, events, snapshots, live view)           │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌──────────────────────┐          ┌──────────────────────┐
│   Menubar App        │          │   Daemon (optional)  │
│   (Swift, primary)   │          │   (enables TUI,      │
│                      │◄────────►│    plugins, API)     │
│   • Live video       │          │                      │
│   • Quick actions    │          │   • Local REST API   │
│   • Notifications    │          │   • WebSocket events │
│   • Popover + float  │          │   • Lua plugins      │
└──────────────────────┘          │   • Webhooks         │
                                  └──────────────────────┘
                                              │
                                              ▼
                                  ┌──────────────────────┐
                                  │   CLI / TUI          │
                                  │   (open-ring)        │
                                  │                      │
                                  │   • Interactive mode │
                                  │   • Scripting        │
                                  │   • Export/analysis  │
                                  └──────────────────────┘
```

### Components

**A. Menubar App (Swift)** — Primary interface
- Native Swift application
- Ring API client embedded (no daemon required for basic operation)
- Video playback via AVPlayer
- System notifications with thumbnails
- Popover panel + detachable floating window for video
- Stores auth tokens in macOS Keychain
- Caches events/snapshots to SQLite

**B. Daemon (`open-ringd`)** — Optional, enables power features
- Exposes documented REST API on `127.0.0.1:8199`
- WebSocket for real-time event streaming
- Lua plugin runtime for custom rules/actions
- Webhook dispatch to external services
- Shared cache with menubar app
- Required for TUI operation

**C. CLI/TUI (`open-ring`)** — Terminal interface
- Talks to daemon's local API
- Interactive curses-style TUI (`open-ring --tui` or `open-ring tui`)
- CLI commands for scripting (`open-ring events`, `open-ring snooze 1h`)
- Export capabilities (CSV, JSON)

---

## 4. Supported Devices (v0)

| Device | Capabilities |
|--------|-------------|
| Video Doorbell (all models) | Ring press, motion, live view, snapshots, clips |
| Spotlight Cam / Floodlight Cam | Motion, live view, snapshots, clips |

**v1 additions**: Indoor cams, light controls, siren trigger

---

## 5. Authentication

Ring uses a proprietary auth flow (not standard OAuth). The Swift client implements:

### Login Flow
1. User runs `open-ring login` (terminal) or clicks "Login" in menubar preferences
2. Prompt: email + password
3. Ring returns 2FA challenge (SMS or email code)
4. **Terminal fallback**: If launched from menubar, show "Complete login in terminal"
5. User enters 2FA code in terminal
6. Tokens stored in macOS Keychain:
   - `open-ring.refresh-token`
   - `open-ring.hardware-id` (device fingerprint)

### Token Refresh
- Refresh token automatically before expiry
- If refresh fails → menubar shows silent badge (icon changes)
- User clicks to re-authenticate

### Security
- No plaintext credentials anywhere
- Hardware ID generated once, persisted
- Tokens scoped to this "device" from Ring's perspective

---

## 6. Local Storage

**Location**: `~/Library/Application Support/open-ring/`

```
open-ring/
├── open-ring.db          # SQLite database
├── snapshots/            # Cached snapshot images
│   └── 2024-01-15/
│       └── abc123.jpg
├── clips/                # Downloaded video clips (optional)
├── logs/                 # Application logs
└── plugins/              # User Lua plugins
```

### Database Schema

```sql
-- Devices discovered from Ring account
CREATE TABLE devices (
    id TEXT PRIMARY KEY,           -- Ring device ID
    name TEXT NOT NULL,            -- "Front Door", "Backyard"
    type TEXT NOT NULL,            -- "doorbell", "spotlight_cam"
    location TEXT,                 -- User-defined location
    capabilities_json TEXT,        -- JSON: ["ring", "motion", "live_view"]
    firmware_version TEXT,
    last_seen_at INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Events from Ring (motion, ring press, package)
CREATE TABLE events (
    id TEXT PRIMARY KEY,           -- Ring event ID
    device_id TEXT NOT NULL,
    kind TEXT NOT NULL,            -- "ring", "motion", "package"
    created_at INTEGER NOT NULL,   -- Unix timestamp
    metadata_json TEXT,            -- JSON: confidence, duration, etc.
    ring_clip_id TEXT,             -- Reference to Ring's clip
    snapshot_path TEXT,            -- Local path to snapshot
    important INTEGER DEFAULT 0,   -- User-marked important
    processed_at INTEGER,
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

-- Cached video clips
CREATE TABLE clips (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    event_id TEXT,
    created_at INTEGER NOT NULL,
    duration_seconds INTEGER,
    ring_url TEXT,                 -- Ring's signed URL (expires)
    local_path TEXT,               -- Downloaded path (optional)
    expires_at INTEGER,            -- URL expiry
    FOREIGN KEY (device_id) REFERENCES devices(id),
    FOREIGN KEY (event_id) REFERENCES events(id)
);

-- Cached snapshots
CREATE TABLE snapshots (
    id TEXT PRIMARY KEY,
    event_id TEXT,
    device_id TEXT NOT NULL,
    path TEXT NOT NULL,            -- Local file path
    created_at INTEGER NOT NULL,
    sha256 TEXT,
    FOREIGN KEY (event_id) REFERENCES events(id),
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

-- User preferences
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Automation rules (Lua-based)
CREATE TABLE rules (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    enabled INTEGER DEFAULT 1,
    predicate_lua TEXT,            -- Lua function returning boolean
    action_lua TEXT,               -- Lua function to execute
    last_triggered_at INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Webhook configurations
CREATE TABLE webhooks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    events_json TEXT,              -- ["ring", "motion"] or ["*"]
    headers_json TEXT,             -- Custom headers
    enabled INTEGER DEFAULT 1,
    last_triggered_at INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Index for common queries
CREATE INDEX idx_events_device_created ON events(device_id, created_at DESC);
CREATE INDEX idx_events_kind ON events(kind);
CREATE INDEX idx_clips_device ON clips(device_id, created_at DESC);
```

### Cache Policy
- **Snapshots**: Keep 72 hours, configurable
- **Clips**: Store URL only by default; optional download
- **Events**: Keep indefinitely (they're small)

---

## 7. Menubar App

### Icon States
| State | Icon | Meaning |
|-------|------|---------|
| Normal | Ring icon (outline) | Connected, no new events |
| New event | Ring icon (filled) + badge | Unread event |
| Live active | Ring icon (pulsing) | Live view in progress |
| Auth expired | Ring icon (red dot) | Need to re-login |
| Offline | Ring icon (grayed) | No network / Ring down |

### Popover Panel
Clicking menubar icon opens a popover with:

```
┌─────────────────────────────────────────┐
│  open-ring                    ⚙️  ✕     │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │      [Live Video / Snapshot]   │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│  Front Door ▼         🔴 Live  📤       │
├─────────────────────────────────────────┤
│  Recent Events                          │
│  ─────────────────────────────────────  │
│  🔔 Ring      Front Door    2 min ago   │
│  👤 Motion    Backyard     15 min ago   │
│  📦 Package   Front Door    1 hr ago    │
├─────────────────────────────────────────┤
│  [🔕 Snooze ▼]  [🔔 Motion: ON]         │
└─────────────────────────────────────────┘
```

### Quick Actions (accessible without opening panel)
Right-click menubar icon:
- **Snooze** → 15 min / 1 hour / Until morning
- **Open Live** → Immediate live view in floating window
- **Toggle Motion Alerts** → On/Off
- **View Last Event** → Open most recent clip/snapshot
- **Switch Camera** → Submenu with device list

### Floating Video Window
- Click "📤" (detach) button in popover
- Opens resizable, always-on-top floating window
- Picture-in-picture style
- Window controls: close, resize, drag
- Shows device name + live/playback indicator

### Live View
- 2-minute auto-timeout (Ring's limit)
- "Extend" button appears at 1:45
- Smooth reconnection if stream drops
- Audio toggle (mute by default)

---

## 8. Notifications

### Event Triggers (all user-configurable)
| Event | Default | Notification |
|-------|---------|--------------|
| Ring press | ON | Always notify |
| Motion | ON | Notify |
| Package | ON | Notify |

### Notification Content (text-only, no thumbnails)
```
┌────────────────────────────────────┐
│ 🔔 open-ring                       │
│ Ring — Front Door                  │
│ Someone is at the door             │
│                          2:36 PM   │
│                                    │
│ [View]  [Snooze 1h]               │
└────────────────────────────────────┘
```

*Design rationale: Text-only notifications are faster, cleaner, and avoid the visual clutter of thumbnails. Users who want to see the snapshot can click "View" to open the popover.*

### Quiet Hours & Snooze
- Quiet hours: configurable time range (e.g., 23:00–07:00)
- Snooze presets: 15 min, 1 hour, until morning
- Per-device snooze option
- Motion-only snooze (still get ring alerts)

---

## 9. Daemon API

When daemon is running, exposes HTTP API on `127.0.0.1:8199`.

### Endpoints

#### Health & Status
```
GET /v1/health
→ { "status": "ok", "version": "0.1.0", "uptime_seconds": 3600 }

GET /v1/auth/status
→ { "authenticated": true, "expires_at": "2024-01-16T12:00:00Z" }
```

#### Devices
```
GET /v1/devices
→ [
    {
      "id": "12345",
      "name": "Front Door",
      "type": "doorbell",
      "capabilities": ["ring", "motion", "live_view", "snapshot"],
      "online": true,
      "battery_level": 85,
      "last_event_at": "2024-01-15T14:30:00Z"
    }
  ]

GET /v1/devices/:id
→ { ...device details... }
```

#### Events
```
GET /v1/events?device_id=&since=&until=&kind=&limit=50
→ {
    "events": [...],
    "cursor": "abc123"
  }

GET /v1/events/:id
→ { ...event details with snapshot_url, clip_url... }
```

#### Media
```
GET /v1/snapshots/:id
→ (image/jpeg bytes)

GET /v1/clips/:id
→ { "url": "...", "expires_at": "...", "local_path": "..." }

POST /v1/clips/:id/download
→ { "status": "downloading", "progress": 0.45 }
```

#### Live View
```
POST /v1/live/start
Body: { "device_id": "12345" }
→ { "session_id": "...", "stream_url": "...", "expires_at": "..." }

POST /v1/live/stop
Body: { "session_id": "..." }
→ { "status": "stopped" }
```

#### Actions
```
POST /v1/snooze
Body: { "minutes": 60 }  // or { "until": "2024-01-16T07:00:00Z" }
→ { "snoozed_until": "..." }

POST /v1/snooze/cancel
→ { "status": "cancelled" }

POST /v1/export
Body: { "format": "csv", "scope": "events", "since": "...", "until": "..." }
→ { "file_path": "/path/to/export.csv" }
```

#### Rules & Webhooks
```
GET /v1/rules
POST /v1/rules
PUT /v1/rules/:id
DELETE /v1/rules/:id
POST /v1/rules/:id/test

GET /v1/webhooks
POST /v1/webhooks
PUT /v1/webhooks/:id
DELETE /v1/webhooks/:id
POST /v1/webhooks/:id/test
```

### WebSocket Stream
```
WS /v1/stream

Messages:
← { "type": "event.created", "event": {...} }
← { "type": "device.updated", "device": {...} }
← { "type": "auth.expired" }
← { "type": "live.started", "session": {...} }
← { "type": "live.ended", "session_id": "..." }
```

---

## 10. CLI / TUI

### CLI Commands

```bash
# Authentication
open-ring login                    # Interactive login with 2FA
open-ring logout                   # Clear stored credentials
open-ring auth status              # Check auth state

# Devices
open-ring devices                  # List all devices
open-ring devices show <id>        # Device details

# Events
open-ring events                   # Recent events (default: 24h)
open-ring events --since 7d        # Last 7 days
open-ring events --device "Front Door"
open-ring events --kind ring       # Only ring events

# Live View
open-ring live                     # Live view of default device
open-ring live "Front Door"        # Specific device
open-ring live --mpv               # Force mpv player

# Clips & Snapshots
open-ring clips                    # List recent clips
open-ring clips download <id>      # Download a clip
open-ring snapshot <device>        # Capture current snapshot

# Notifications
open-ring snooze 1h                # Snooze for 1 hour
open-ring snooze --until 07:00     # Snooze until time
open-ring snooze cancel            # Cancel snooze

# Export
open-ring export events --format csv --output events.csv
open-ring export clips --since 7d --output clips/

# Rules & Webhooks
open-ring rules list
open-ring rules add --name "Late night ring" --file rule.lua
open-ring rules test <id>
open-ring webhooks list
open-ring webhooks add --url https://example.com/hook --events ring,motion

# Daemon
open-ring daemon start             # Start daemon in background
open-ring daemon stop              # Stop daemon
open-ring daemon status            # Check daemon status

# Interactive TUI
open-ring tui                      # Launch interactive TUI
open-ring --tui                    # Alias
```

### Interactive TUI

```
╔══════════════════════════════════════════════════════════════════╗
║ open-ring                                        snooze: OFF     ║
╠══════════════════════════════════════════════════════════════════╣
║ [1] Devices  [2] Events  [3] Live  [4] Clips  [5] Rules  [?] Help║
╚══════════════════════════════════════════════════════════════════╝

┌─ Devices ─────────────────────────────────────────────────────────┐
│                                                                   │
│  ● Front Door          doorbell     Last: Ring 2 min ago         │
│    Backyard Cam        spotlight    Last: Motion 15 min ago      │
│                                                                   │
│  [Enter] Events  [l] Live  [s] Snapshot  [r] Refresh             │
└───────────────────────────────────────────────────────────────────┘
```

**Events View**:
```
╔══════════════════════════════════════════════════════════════════╗
║ Events — Front Door                              showing: 24h    ║
╠══════════════════════════════════════════════════════════════════╣

  14:36  🔔 RING      [p] preview  [o] open clip  [d] download
  14:12  👤 MOTION    [p] preview
  12:02  📦 PACKAGE   [p] preview  [o] open clip

  ┌─ Preview ─────────────────────────────────────────────────────┐
  │                                                                │
  │                    (snapshot image)                           │
  │                                                                │
  └────────────────────────────────────────────────────────────────┘

  [j/k] navigate  [Enter] details  [l] live  [c] copy link  [q] back
```

---

## 11. Webhooks

Events trigger HTTP POST to configured URLs.

### Payload Format
```json
{
  "event_type": "ring",
  "event_id": "abc123",
  "device_id": "12345",
  "device_name": "Front Door",
  "timestamp": "2024-01-15T14:36:00Z",
  "metadata": {
    "confidence": "high",
    "snapshot_url": "http://127.0.0.1:8199/v1/snapshots/xyz"
  }
}
```

### Configuration
```bash
open-ring webhooks add \
  --name "Home Assistant" \
  --url http://homeassistant.local:8123/api/webhook/ring \
  --events ring,motion,package \
  --header "Authorization: Bearer xxx"
```

### Retry Policy
- 3 retries with exponential backoff (1s, 5s, 30s)
- Log failures, don't block event processing

---

## 12. Lua Plugin System

Plugins enable custom automation rules.

### Plugin Location
`~/Library/Application Support/open-ring/plugins/`

### Plugin Structure
```lua
-- plugins/late_night_alert.lua

-- Metadata
plugin = {
  name = "Late Night Ring Alert",
  version = "1.0.0",
  description = "Extra loud notification for rings after midnight"
}

-- Predicate: when should this rule fire?
function match(event)
  if event.kind ~= "ring" then
    return false
  end

  local hour = os.date("*t", event.timestamp).hour
  return hour >= 0 and hour < 6
end

-- Action: what to do when rule fires
function execute(event, context)
  -- Send system notification with custom sound
  context.notify({
    title = "🚨 Late Night Ring!",
    body = event.device_name .. " at " .. os.date("%H:%M"),
    sound = "alarm"
  })

  -- Also trigger webhook
  context.webhook("late_night_hook", {
    device = event.device_name,
    time = event.timestamp
  })

  -- Log for debugging
  context.log("Late night ring detected at " .. event.device_name)
end
```

### Plugin API (context object)
```lua
context.notify({ title, body, sound, thumbnail })  -- System notification
context.webhook(name, payload)                      -- Trigger webhook
context.log(message)                                -- Debug logging
context.get_device(id)                              -- Device info
context.get_setting(key)                            -- User settings
context.snooze(minutes)                             -- Snooze notifications
context.http_get(url, headers)                      -- HTTP request (async)
context.http_post(url, body, headers)               -- HTTP request (async)
```

### Built-in Rules (examples)
- **Motion storm**: If >5 motion events in 2 minutes, consolidate notifications
- **Late night ring**: Extra prominent notification between midnight and 6am
- **Away mode**: When no motion on indoor cam for 1 hour, assume away

---

## 13. Distribution

### Homebrew Cask
```ruby
cask "open-ring" do
  version "0.1.0"
  sha256 "..."

  url "https://github.com/user/open-ring/releases/download/v#{version}/open-ring-#{version}.dmg"
  name "open-ring"
  desc "Local-first Ring control room for macOS"
  homepage "https://github.com/user/open-ring"

  app "open-ring.app"
  binary "#{appdir}/open-ring.app/Contents/MacOS/open-ring-cli", target: "open-ring"

  zap trash: [
    "~/Library/Application Support/open-ring",
    "~/Library/Preferences/com.open-ring.plist",
    "~/Library/Caches/com.open-ring"
  ]
end
```

### Installation
```bash
brew install --cask open-ring

# First run
open-ring login
```

### No Auto-Start
App does not install launch agent by default. User can add to Login Items manually if desired.

---

## 14. Project Structure

```
open-ring/
├── app/                          # Swift menubar app (Xcode project)
│   ├── open-ring/
│   │   ├── App.swift
│   │   ├── MenuBarController.swift
│   │   ├── PopoverView.swift
│   │   ├── FloatingVideoWindow.swift
│   │   ├── RingClient/          # Swift Ring API client
│   │   │   ├── Auth.swift
│   │   │   ├── Devices.swift
│   │   │   ├── Events.swift
│   │   │   ├── LiveView.swift
│   │   │   └── Snapshots.swift
│   │   ├── Storage/
│   │   │   ├── Database.swift
│   │   │   └── Keychain.swift
│   │   └── Notifications/
│   └── open-ring.xcodeproj
├── daemon/                       # Optional daemon (Swift or Rust)
│   ├── src/
│   │   ├── main.swift
│   │   ├── api/                 # REST API handlers
│   │   ├── plugins/             # Lua runtime
│   │   └── webhooks/
│   └── Package.swift
├── cli/                          # CLI/TUI (Swift)
│   ├── src/
│   │   ├── main.swift
│   │   ├── Commands/
│   │   └── TUI/
│   └── Package.swift
├── docs/
│   ├── SPEC.md                  # This file
│   ├── API.md                   # API documentation
│   ├── PLUGINS.md               # Plugin development guide
│   └── SECURITY.md              # Security considerations
├── scripts/
│   ├── build.sh
│   ├── release.sh
│   └── install-dev.sh
├── Casks/
│   └── open-ring.rb             # Homebrew cask formula
├── LICENSE                       # MIT
├── README.md
└── CHANGELOG.md
```

---

## 15. Security Considerations

### Credentials
- Ring credentials never stored; only refresh tokens
- All tokens in macOS Keychain (encrypted at rest)
- Hardware ID persisted to appear as consistent device to Ring

### Local API
- Daemon binds to `127.0.0.1` only
- No authentication required (local trust model)
- Optional: require API key for localhost access

### Plugins
- Lua sandbox: no file system access, no shell execution
- Network access limited to HTTP GET/POST
- Plugins reviewed before loading (hash verification optional)

### Data
- Snapshots/clips stored unencrypted (rely on macOS disk encryption)
- No data leaves device except to Ring and configured webhooks
- Export requires explicit user action

---

## 16. v0 Acceptance Criteria

- [ ] Login + 2FA works; tokens stored in Keychain
- [ ] Devices list loads and displays in menubar
- [ ] Events timeline updates within 30s polling interval
- [ ] Snapshot preview displays in popover
- [ ] Live view plays in floating window (AVPlayer)
- [ ] Detach button opens floating PiP-style window
- [ ] Camera switching works in live view
- [ ] System notifications fire (text-only, actionable)
- [ ] Snooze (15m/1h/morning) stops notifications
- [ ] Quiet hours respected
- [ ] Motion alert toggle works
- [ ] Silent badge on auth expiry (no intrusive alert)
- [ ] CLI: `open-ring login`, `devices`, `events`, `snooze` work
- [ ] Daemon starts and exposes API
- [ ] Webhooks fire on events
- [ ] Basic Lua plugin loads and executes
- [ ] Offline mode shows cached events
- [ ] Homebrew cask installs cleanly

### Design Acceptance Criteria
- [ ] Popover uses 400pt width, 12pt corners, proper spacing
- [ ] SF Pro + SF Mono typography hierarchy implemented
- [ ] Ring blue (#1C96E8) accent used consistently
- [ ] Light and dark mode both polished and tested
- [ ] Floating window is frameless with shadow, draggable anywhere
- [ ] Timeline uses monospace timestamps, proper row height
- [ ] Animations are subtle (spring 0.3s), no jarring transitions
- [ ] All icons are SF Symbols
- [ ] Menubar icon has correct states (normal, event, live, error, offline)
- [ ] Empty states use iconographic style
- [ ] Error states use inline banners, not dialogs
- [ ] Keyboard navigation works throughout popover
- [ ] VoiceOver labels present on all interactive elements

---

## 17. v1 Roadmap

- [ ] Spotlight/floodlight controls
- [ ] Indoor camera support
- [ ] Kitty/iTerm2 inline video in TUI
- [ ] Rich plugin ecosystem
- [ ] HomeAssistant integration
- [ ] Clip editing/trimming
- [ ] Multi-account support
- [ ] iOS companion app (maybe)

---

## License

MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
