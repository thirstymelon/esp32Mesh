# ⚡ MeshOS — Encrypted ESP32 Mesh Communication Platform

<p align="center">
  <img src="https://img.shields.io/badge/ESP32-ESP--IDF_5.5-red?style=for-the-badge&logo=espressif&logoColor=white">
  <img src="https://img.shields.io/badge/Transport-ESP--NOW_%2B_BLE_GATT-00C853?style=for-the-badge">
  <img src="https://img.shields.io/badge/Encryption-AES--128--GCM-6A1B9A?style=for-the-badge&logo=keycdn&logoColor=white">
  <img src="https://img.shields.io/badge/PlatformIO-Firmware-F5822A?style=for-the-badge&logo=platformio&logoColor=white">
  <img src="https://img.shields.io/badge/SwiftUI-macOS_App-000000?style=for-the-badge&logo=apple&logoColor=white">
</p>

> A fully offline, end-to-end encrypted mesh communication system built on ESP32 and managed from a native macOS app over Bluetooth Low Energy.

---

## Overview

MeshOS is a decentralised peer-to-peer communication platform with **no cloud, no Wi-Fi router, and no internet required**. ESP32 nodes form a self-healing multi-hop mesh using ESP-NOW and expose themselves to the macOS client over BLE GATT. All chat messages are encrypted with **AES-128-GCM** (hardware-accelerated on ESP32).

```
┌─────────────┐     BLE GATT     ┌──────────────────────────────────────┐
│  macOS App  │ ←──────────────→ │  ESP32 Node A                        │
│  (SwiftUI)  │  Read/Write/Notify│  ┌──────────────────────────────┐   │
└─────────────┘                  │  │  ESP-NOW Mesh (encrypted)    │   │
                                 │  │  Node A ↔ Node B ↔ Node C   │   │
                                 │  └──────────────────────────────┘   │
                                 └──────────────────────────────────────┘
```

---

## Key Features

| Feature | Detail |
|---------|--------|
| **Self-healing mesh** | Nodes build routing tables (AODV-lite) via heartbeat broadcasts |
| **AODV-lite Routing** | Intelligent unicast-aware relaying replaces simple flooding for better scalability |
| **AES-128-GCM + ECDH** | Session keys negotiated via P-256 ECDH over BLE replace static hardcoded keys |
| **Reliable Delivery** | End-to-end ACKs and delivery indicators (Pending → Delivered) |
| **Mesh Time Protocol** | Nodes synchronise Unix epoch mesh-wide via high-authority time distribution |
| **Telemetry Monitor** | Real-time monitoring of node battery, uptime, and signal strength |
| **Zero heap allocation** | Firmware uses static buffers even for complex routing and crypto |
| **Offline-first** | Fully decentralised; local message persistence on macOS |

---

## Repository Structure

```
esp32Mesh/
├── firmware/                   # ESP32 firmware (ESP-IDF / PlatformIO)
│   ├── main/
│   │   ├── main.c              # Mesh logic, BLE GATT server, ESP-NOW relay
│   │   ├── CMakeLists.txt      # Component build file
│   │   └── ssd1306.{c,h}       # SSD1306 driver (kept for reference, unused)
│   ├── sdkconfig.defaults      # ESP-IDF Kconfig overrides
│   └── platformio.ini          # PlatformIO build config
│
├── macos/                      # macOS SwiftUI client (Xcode)
│   └── MeshOSApp/
│       ├── MeshManager.swift   # CoreBluetooth + AES-GCM + GATT protocol
│       ├── MeshOSApp.swift     # App entry point, menu bar commands
│       ├── ContentView.swift   # Floating glass nav, shared design system
│       └── Views/
│           ├── MessagesView.swift       # Chat UI with DM support
│           ├── NetworkView.swift        # Metal topology map
│           ├── NodesView.swift          # Peer list & nickname editor
│           ├── MetalTopologyView.swift  # GPU-rendered mesh graph
│           ├── ConnectionSheet.swift    # BLE scan & connect flow
│           └── SettingsView.swift       # App preferences
│
├── futurescope.md              # Full bug tracker & feature roadmap
├── README.md                   # This file
└── .gitignore
```

---

## Architecture

### Firmware

The ESP32 firmware runs as a single C source (`main/main.c`) on top of ESP-IDF 5.x with FreeRTOS:

- **Wi-Fi** runs in AP mode (channel 1, WPA2) purely to keep the radio active for ESP-NOW
- **ESP-NOW** carries all mesh traffic as `MeshPacket` structs (magic, type, seq, src, dest, payload)
- **NimBLE GATT** exposes 5 characteristics to the macOS client:

| UUID suffix | Name | Properties | Description |
|-------------|------|------------|-------------|
| `…0001` | Status | Read, Notify | Node ID, uptime, peer count, nickname |
| `…0002` | Peers | Read, Notify | Serialised peer list with neighbor topology |
| `…0003` | Chat | Read, Write, Notify | Encrypted message stream + ACKs & Telemetry |
| `…0004` | CMD | Write | Commands: set nickname (1), sync messages (3), time sync (4), OTA (5) |
| `…0005` | ECDH | Read, Write | P-256 Public Key exchange for session keys |

- **Security (v2)**: All chat payloads use dynamic session keys negotiated via P-256 ECDH.
- **Routing**: AODV-lite logic uses heartbeat hop counts to build optimal routing paths.
- **Reliability**: End-to-end ACKs ensure messages are received; "Pending" status in app transitions to "Delivered" on ACK.

### macOS App

Built with SwiftUI + CoreBluetooth + CryptoKit + Metal:

- `MeshManager` is the central `@MainActor` `ObservableObject` — owns the `CBCentralManager`, parses all GATT notifications, and drives `@Published` state
- **Encryption**: `CryptoKit.AES.GCM` with the same 16-byte key as the firmware. The `combined` format (`nonce ‖ ciphertext ‖ tag`) maps directly to the firmware wire format
- **Message deduplication**: SHA256 of `sender + dest + ts + text` — stable across process restarts and handles rapid messages in the same second
- **Metal topology map**: `MTKView` renders nodes as GPU points and links as anti-aliased lines at 60 fps

---

## Encryption Key

The shared AES-128-GCM key is currently hardcoded in both places. **They must match exactly:**

**Firmware** (`firmware/main/main.c`):
```c
static const uint8_t AES_KEY[16] = {
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24
}; // "MeshOSKey123!@#$"
```

**macOS app** (`macos/MeshOSApp/MeshManager.swift`):
```swift
private let aesKey = SymmetricKey(data: Data([
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24
]))
```

> **⚠️ Change this key before deployment.** Future versions will negotiate a per-session key via ECDH over BLE.

---

## Getting Started

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| PlatformIO CLI | Latest | Build & flash firmware |
| Xcode | 15+ | Build macOS app |
| macOS | 13 Ventura+ | Run macOS app |
| ESP32 dev board | Any rev | Hardware |

### 1. Clone

```bash
git clone https://github.com/thirstymelon/esp32Mesh.git
cd esp32Mesh
```

### 2. Flash Firmware

```bash
cd firmware

# Build
pio run

# Flash to connected ESP32
pio run -t upload

# Monitor serial output (115200 baud)
pio run -t monitor
```

> If you change `sdkconfig.defaults`, delete the `.pio/build` directory first to force a full rebuild: `rm -rf .pio/build`

### 3. Build & Run the macOS App

```bash
open macos/MeshOS.xcodeproj
```

Then **Product → Run** (`⌘R`).

The app will scan for nearby `MeshOS_XXXXXXXX` BLE peripherals. Tap the **Connect** button in the floating navbar to open the scan sheet.

### 4. Using the App

| Action | How |
|--------|-----|
| **Connect to node** | Click `Connect` in the nav bar → select node from scan sheet |
| **Send a broadcast** | Type in the message box and press Enter or click Send |
| **Send a DM** | Select a peer in the Nodes tab, click their name, send from the DM view |
| **Rename a node** | Nodes tab → click the edit (pencil) icon next to the node |
| **Refresh data** | Click the `↺` button in the nav bar or press `⌘R` |
| **Disconnect** | Click `Disconnect` in the nav bar or press `⌘D` |

---

## BLE Protocol Reference

### Chat write (app → firmware)

```
[4 bytes dest_id LE] [12 bytes nonce] [N bytes ciphertext] [16 bytes GCM tag]
```
- `dest_id = 0` → broadcast to all nodes
- `dest_id != 0` → DM to specific node ID

### Chat notification (firmware → app)

```
[4 sender] [4 dest] [4 ts] [1 flags] [12 nonce] [N ciphertext] [16 GCM tag]
```
- `flags` bit 0 = is_me, bit 1 = is_dm
- Minimum notification size = 41 bytes (13-byte header + 28-byte AES overhead)
- Maximum plaintext = 172 bytes per packet

### ESP-NOW MeshPacket

```c
struct MeshPacket {
    uint16_t magic;        // 0xC0DE
    uint8_t  type;         // 0=heartbeat, 2=chat, 3=nick_sync
    uint8_t  seq;          // per-node sequence counter (duplicate filter)
    uint32_t src_id;
    uint32_t dest_id;      // 0 = broadcast
    uint16_t payload_len;
    uint8_t  payload[200]; // chat: [12 nonce][ciphertext][16 tag]
};
```

---

## Hardware

### Required

- Any **ESP32** development board (ESP32-D0WD, WROOM, WROVER, etc.)

### Optional / Previously Supported

- **SSD1306 OLED** (128×64 I2C) — the `ssd1306.c` driver is retained in the repo but the firmware no longer calls it. Re-integrating the display is a single task in `futurescope.md`.

### Tested Boards

- ESP32 DevKitC v4 (WROOM-32)
- ESP32 DevKit v1

---

## Software Stack

| Component | Technology |
|-----------|-----------|
| Mesh transport | ESP-NOW (IEEE 802.11 raw frames) |
| BLE stack | NimBLE (via ESP-IDF) |
| Encryption | AES-128-GCM (mbedTLS hardware-accelerated) |
| Build system | PlatformIO + ESP-IDF 5.5 |
| macOS UI | SwiftUI |
| macOS BLE | CoreBluetooth |
| macOS crypto | CryptoKit (`AES.GCM`) |
| macOS GPU | Metal (`MTKView`) |
| Persistence | ESP32 NVS (nicknames, uptime offset) |

---

## Known Limitations

See [`futurescope.md`](./futurescope.md) for the full audit. Key items:

- Encryption key is hardcoded — ECDH key exchange is planned
- `my_seq` is `uint8_t` — wraps at 255 (tracked in futurescope)
- No message persistence on the macOS side between sessions
- No BLE passkey pairing (open connection to any macOS client that knows the GATT UUIDs)

---

## License

MIT

---

<p align="center"><b>MeshOS — Encrypted distributed communication on embedded hardware.</b></p>
