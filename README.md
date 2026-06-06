# ⚡ MeshOS — Encrypted ESP32 Mesh Communication Platform

<p align="center">
  <img src="https://img.shields.io/badge/ESP32-ESP--IDF_5.5-red?style=for-the-badge&logo=espressif&logoColor=white">
  <img src="https://img.shields.io/badge/Transport-ESP--NOW_%2B_BLE_GATT-00C853?style=for-the-badge">
  <img src="https://img.shields.io/badge/Encryption-AES--128--GCM-6A1B9A?style=for-the-badge&logo=keycdn&logoColor=white">
  <img src="https://img.shields.io/badge/PlatformIO-Firmware-F5822A?style=for-the-badge&logo=platformio&logoColor=white">
  <img src="https://img.shields.io/badge/SwiftUI-iOS_%26_macOS-000000?style=for-the-badge&logo=apple&logoColor=white">
</p>

> A fully offline, end-to-end encrypted mesh communication system built on ESP32, managed via native iOS and macOS apps over secure Bluetooth Low Energy handshakes.

---

## 📱 Releases & Security Note

> [!IMPORTANT]  
> **Note on App Signing**: The iOS and macOS apps provided in the [Releases](https://github.com/thirstymelon/esp32Mesh/releases) section are **unsigned**. They do not contain Apple Developer certificates.
> - **macOS**: You may need to right-click the app and select "Open" to bypass Gatekeeper, or allow it in System Settings > Privacy & Security.
> - **iOS**: These are provided as source code or `.ipa` files for side-loading (requires AltStore, Sideloadly, or Xcode).

---

## Overview

MeshOS is a decentralised peer-to-peer communication platform with **no cloud, no Wi-Fi router, and no internet required**. ESP32 nodes form a self-healing multi-hop mesh using ESP-NOW and expose themselves to native Apple clients over BLE GATT.

```
┌────────────────┐     BLE GATT     ┌──────────────────────────────────────┐
│ iOS / macOS App│ ←──────────────→ │  ESP32 Node A                        │
│   (SwiftUI)    │  Secure Handshake│  ┌──────────────────────────────┐   │
└────────────────┘  (P-256 ECDH)    │  │  ESP-NOW Mesh (encrypted)    │   │
                                    │  │  Node A ↔ Node B ↔ Node C   │   │
                                    │  └──────────────────────────────┘   │
                                    └──────────────────────────────────────┘
```

---

## Key Features

| Feature | Detail |
|---------|--------|
| **Self-healing mesh** | Nodes build routing tables (AODV-lite) via heartbeat broadcasts |
| **P-256 ECDH Security** | **Dynamic session keys** negotiated via Elliptic Curve Diffie-Hellman on every connection |
| **AES-128-GCM** | Hardware-accelerated authenticated encryption for all mesh traffic |
| **Dual-Platform Apps** | Full-featured native SwiftUI apps for both **iOS** and **macOS** |
| **Mesh Topology View** | Real-time GPU-rendered (Metal) graph of the entire network structure |
| **Reliable Delivery** | End-to-end ACKs and delivery indicators for every message |
| **Mesh Time Sync** | Automatic time distribution across the mesh from the connected app |
| **Node Telemetry** | Monitor battery levels and uptime of every node in the network |
| **OTA Updates** | Wireless firmware updates directly from the iOS/macOS app over BLE |

---

## Repository Structure

```
esp32Mesh/
├── firmware/                   # ESP32 C firmware (ESP-IDF 5.x / PlatformIO)
├── ios/                        # iOS SwiftUI application (Xcode)
└── macos/                      # macOS SwiftUI application (Xcode)
```

---

## Getting Started

### 1. Flash the ESP32 Firmware

**Prerequisites**: [PlatformIO CLI](https://platformio.org/install/cli)

```bash
cd firmware
# Build and flash to connected ESP32
pio run -t upload
# Monitor serial logs (115200 baud)
pio run -t monitor
```

### 2. Install the Apps

#### Option A: Build from Source (Recommended)
- **macOS**: Open `macos/MeshOS.xcodeproj` in Xcode 15+, select the `MeshOS` scheme, and press `⌘R`.
- **iOS**: Open `ios/MeshOSiOS.xcodeproj` in Xcode, connect your iPhone, and deploy to the device.

#### Option B: Download Releases
Download the latest binaries from the [Releases](https://github.com/thirstymelon/esp32Mesh/releases) page. *See the security note above regarding unsigned apps.*

### 3. Usage Steps

1.  **Power on** at least two ESP32 nodes running the MeshOS firmware.
2.  **Open the App** on your iPhone or Mac.
3.  **Scan & Connect**: Click the "Connect" button in the app. It will scan for nodes (named `MeshOS_XXXXXXXX`).
4.  **Secure Handshake**: The app will automatically perform a P-256 ECDH handshake to establish a secure session key.
5.  **Chat**: Once connected, you can send broadcasts (to everyone) or DMs (to specific nodes).
6.  **Monitor**: Switch to the **Network** tab to see a live visual map of your mesh topology.

---

## Technical Specifications

### BLE GATT Interface
- **Service UUID**: `DECAFBAD-CAFE-4BEE-B00B-000000000000`
- **Characteristics**:
    - `...0001` (Status): Node ID, Uptime, Nickname.
    - `...0002` (Peers): Live neighbor topology data.
    - `...0003` (Chat): Encrypted message stream (Write/Notify).
    - `...0005` (ECDH): Public key exchange.
    - `...0006` (OTA): Firmware update control.

### Mesh Protocol
- **Transport**: ESP-NOW (2.4GHz IEEE 802.11 Raw Frames).
- **Routing**: AODV-lite (Distance Vector).
- **Max Hops**: Default 7.
- **Encryption**: AES-128-GCM (mbedTLS hardware-accelerated).

---

## Hardware Requirements
- **ESP32 Dev Board**: ESP32-WROOM, ESP32-WROVER, or any standard ESP32 variant.
- **Apple Device**: iPhone (iOS 17+) or Mac (macOS 13+).

---

## License
MIT

<p align="center"><b>Built for secure, resilient, and independent communication.</b></p>
