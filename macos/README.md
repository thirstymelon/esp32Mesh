# MeshOS — macOS Client

Native **SwiftUI** macOS application for the MeshOS encrypted ESP32 mesh network. Connects to a mesh node over **Bluetooth Low Energy (BLE GATT)**, displays live peer topology, sends and receives **AES-128-GCM encrypted** chat messages, and visualises the multi-hop mesh graph using **Metal**.

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS | 13 Ventura |
| Xcode | 15 |
| Swift | 5.9 |
| Bluetooth | BLE 4.2+ adapter |
| ESP32 | Running MeshOS firmware |

---

## Opening the Project

```bash
open macos/MeshOS.xcodeproj
```

Then **Product → Run** (`⌘R`) or build with:

```bash
xcodebuild -project macos/MeshOS.xcodeproj -scheme MeshOS -configuration Debug build
```

No CocoaPods, no SPM packages, no external dependencies — the app uses only Apple system frameworks.

---

## Source Files

```
macos/MeshOSApp/
├── MeshOSApp.swift              # @main, Scene setup, menu bar commands
├── MeshManager.swift            # CoreBluetooth, AES-GCM, GATT protocol, state
├── ContentView.swift            # Root layout, floating nav, shared design tokens
│
└── Views/
    ├── MessagesView.swift        # Chat UI (broadcast + DM)
    ├── NetworkView.swift         # Mesh topology map container
    ├── MetalTopologyView.swift   # MTKView: GPU-rendered nodes and links
    ├── NodesView.swift           # Peer list, online status, nickname editor
    ├── ConnectionSheet.swift     # BLE scan sheet & node picker
    └── SettingsView.swift        # App preferences (auto-connect, notifications)
```

---

## Architecture

### `MeshManager.swift`

The single source of truth. A `@MainActor ObservableObject` that owns the entire BLE stack and drives all SwiftUI views.

**Key responsibilities:**

| Area | Detail |
|------|--------|
| **BLE scanning** | `CBCentralManager` scans for service UUID `DECAFBAD-CAFE-4BEE-B00B-000000000000` |
| **GATT discovery** | On connect, discovers all 4 characteristics and subscribes to notifications |
| **Time sync** | Immediately writes current Unix epoch via CMD characteristic (cmd_id = 4) |
| **Message sync** | Immediately triggers CMD 3 to pull the 30-message ring buffer from the node |
| **Encryption** | `CryptoKit.AES.GCM` with a 16-byte `SymmetricKey` matching the firmware |
| **Parsing** | `parseStatusData`, `parsePeersData`, `parseChatNotification` decode raw `Data` from GATT |
| **Deduplication** | SHA256(`sender + dest + ts + text`) — stable across process restarts |
| **Message cap** | In-memory list capped at 200 messages to bound RAM usage |

### Encryption

```swift
// Encrypt (send path)
let sealed = try AES.GCM.seal(textData, using: aesKey)
let combined = sealed.combined! // nonce(12) + ciphertext + tag(16)

// Decrypt (receive path)
let box = try AES.GCM.SealedBox(combined: combined)
let plainData = try AES.GCM.open(box, using: aesKey)
```

The `combined` format (`nonce ‖ ciphertext ‖ tag`) maps byte-for-byte to the firmware wire format, so no re-packing is needed on either side.

**Key** (`MeshManager.swift` — must match `AES_KEY[]` in `firmware/main/main.c`):
```swift
private let aesKey = SymmetricKey(data: Data([
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24
]))
```

---

## BLE GATT Protocol

### Characteristics

| UUID suffix | Name | App role | Description |
|-------------|------|----------|-------------|
| `…0001` | Status | Read + subscribe notify | Node ID, uptime, peer count, nickname |
| `…0002` | Peers | Read + subscribe notify | Serialised peer list with neighbor topology |
| `…0003` | Chat | Write + subscribe notify | Encrypted message stream |
| `…0004` | CMD | Write only | Commands (nickname, sync, time) |

### Chat write (app → node)

```
[4 bytes dest_id LE] [12 bytes nonce] [N bytes ciphertext] [16 bytes GCM tag]
```
- `dest_id = 0` → broadcast to all nodes
- `dest_id != 0` → direct message to a specific node ID

### Chat notification (node → app)

```
[4 sender] [4 dest] [4 ts] [1 flags] [12 nonce] [N ciphertext] [16 tag]
```
- Minimum size: 41 bytes (13 header + 28 AES overhead)
- Maximum plaintext: 172 bytes per notification
- `flags` bit 0 = is_me, bit 1 = is_dm

### Peers read format

```
[2 node_count]
  per node:
    [4 id] [1 online] [20 nick (null-padded)] [1 neighbor_count]
    [neighbor_count × 4 neighbor_id LE]
```

---

## UI Overview

### Floating Glass Nav Bar

The app uses a custom floating capsule navigation bar at the bottom of the window with:
- **Chat** / **Network** tab switcher with `matchedGeometryEffect` animation
- **Connection badge** — green dot + node nickname when connected, red when offline
- **↺ Refresh** button — triggers GATT reads for Status and Peers
- **Connect / Disconnect** button

### Messages View

- Chronological chat feed with bubble layout (sent right, received left)
- Sender nickname resolved from the peers list
- DM indicator shown inline
- Text field + send button; Enter key submits

### Network View

- `MetalTopologyView` renders the mesh graph at 60 fps on the GPU
- Nodes drawn as anti-aliased coloured circles; links as cyan semi-transparent lines
- Node colours are deterministically derived from node ID (DJB2 hash → palette)
- Offline nodes drawn at 40% alpha

### Nodes View

- Lists all known peers with online/offline status
- Inline nickname editor — writes CMD 1 to the connected node on confirm
- Nickname changes broadcast mesh-wide via `PKT_NICK_SYNC`

---

## Design System

All shared styling lives in `ContentView.swift`:

| Token | Value |
|-------|-------|
| `AppPalette.ok` | `HSL(140°, 70%, 58%)` — green |
| `AppPalette.error` | `HSL(357°, 100%, 61%)` — red |
| `AppPalette.cyan` | `HSL(200°, 75%, 70%)` — link lines, accents |
| `AppPalette.violet` | `HSL(255°, 48%, 70%)` — radial background glow |
| `AppPalette.amber` | `HSL(38°, 100%, 63%)` — warnings |
| Background | Three-layer radial gradient over near-black base |
| Glass panels | `.regularMaterial` + 1 px white 12% stroke |
| Nav bar | `LiquidGlass` on macOS 26+, `.ultraThinMaterial` fallback |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘D` | Disconnect from node |
| `⌘R` | Refresh data (reads Status + Peers) |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No nodes appear in scan sheet | Bluetooth off or no nodes advertising | Enable Bluetooth; verify firmware is running |
| "AES-GCM decryption failed" in console | Key mismatch | Verify `aesKey` bytes match `AES_KEY[]` in firmware |
| Messages missing after reconnect | CMD 3 sync not triggered | Check that `syncMessages()` is called after `syncTime()` on connect |
| Chat field disabled | Not connected | Connect to a node first via the scan sheet |
| Network view is empty | No peers responded to heartbeat | Wait 5–10 s for heartbeat cycle; check ESP-NOW channel |
| Build error: module 'CryptoKit' not found | Deployment target too low | Set minimum macOS target to 13.0+ in Xcode project settings |
