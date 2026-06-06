# ⚡ MeshOS — Comprehensive System Documentation & Technical Report

MeshOS is a fully offline, end-to-end encrypted, peer-to-peer mesh communication platform. The system operates without reliance on cellular networks, Wi-Fi routers, or the internet. Instead, it leverages a self-healing multi-hop mesh network formed by ESP32 nodes via ESP-NOW, which are monitored and managed by native macOS and iOS applications over Bluetooth Low Energy (BLE) GATT.

---

## Table of Contents

1. [System Architecture Overview](#1-system-architecture-overview)
2. [ESP32 Firmware Implementation (`firmware/`)](#2-esp32-firmware-implementation-firmware)
3. [BLE GATT Wire Protocol Specification](#3-ble-gatt-wire-protocol-specification)
4. [Mesh Routing & Transport Protocol (ESP-NOW)](#4-mesh-routing--transport-protocol-esp-now)
5. [Security & Cryptography Design](#5-security--cryptography-design)
6. [macOS Client Application (`macos/`)](#6-macos-client-application-macos)
7. [iOS Client Application (`ios/`)](#7-ios-client-application-ios)
8. [Libraries, SDKs, & Component Dependencies](#8-libraries-sdks--component-dependencies)
9. [Known Limitations, Security Vulnerabilities, & Engineering Debt](#9-known-limitations-security-vulnerabilities--engineering-debt)
10. [Developer Setup & Compilation Guide](#10-developer-setup--compilation-guide)

---

## 1. System Architecture Overview

The MeshOS architecture operates in a layered format separating the physical, transport, security, and presentation layers.

```
┌─────────────────┐             BLE GATT              ┌──────────────────────────────────────┐
│  Native Client  │ <───────────────────────────────> │  ESP32 Gateway Node                  │
│ (macOS/iOS App) │   Read / Write / Notifications    │  ┌────────────────────────────────┐  │
└─────────────────┘                                   │  │       ESP-NOW Mesh Network     │  │
                                                      │  │   Node A ↔ Node B ↔ Node C     │  │
                                                      │  └────────────────────────────────┘  │
                                                      └──────────────────────────────────────┘
```

1. **Native Client Apps (SwiftUI)**: Run on macOS and iOS, using `CoreBluetooth` to scan for and connect to a single local ESP32 "Gateway Node". The client transmits and receives encrypted chat messages, issues commands, and reads the status and network topology.
2. **Local Gateway Node (ESP32)**: Acts as the bridge between the client and the wider mesh. It maintains a BLE GATT server for the app client, a local peer database of the mesh, a message history ring buffer, and handles ESP-NOW mesh packet processing.
3. **Mesh Nodes (ESP32)**: Commute packets hop-by-hop across the physical network. If a packet is not addressed to the receiving node and is not a duplicate, it is re-transmitted (relayed).

---

## 2. ESP32 Firmware Implementation (`firmware/`)

The firmware is written in native C on top of the **ESP-IDF v5.x** framework using **FreeRTOS** for task scheduling and multitasking. The entire logic is centralized in [main.c](file:///Users/lokesh/Desktop/esp32Mesh/firmware/main/main.c) to minimize heap fragmentation, utilizing static memory buffers.

### Core Modules and Control Flow
* **NVS (Non-Volatile Storage)**: Persists node configurations (e.g., node nickname mappings, gateway offset time).
* **Wi-Fi Subsystem**: Initialized in Access Point (AP) mode on Channel 1 (WPA2-PSK) to activate the Wi-Fi radio core for raw packet transmission.
* **ESP-NOW**: Handles low-latency, connectionless raw IEEE 802.11 frames. Registered callbacks filter incoming packets by a magic signature and pass validated frames to the routing engine.
* **NimBLE Stack**: A lightweight, memory-efficient Bluetooth Low Energy host stack. Configures advertising parameters, connection intervals, and the GATT database definition.
* **mbedTLS Cryptography**: Implements AES-128-GCM hardware-accelerated encryption/decryption, SHA-256 hash functions, and ECDH P-256 key exchange.
* **FreeRTOS Semaphores**: Mutexes (`chat_mutex`, `peer_mutex`, `hash_mutex`, `peers_buf_mutex`) protect shared state in multi-threaded contexts (GATT callbacks running on the NimBLE task vs. mesh reception callbacks running on the Wi-Fi task).

---

## 3. BLE GATT Wire Protocol Specification

The local Gateway Node exposes a single primary BLE service and five characteristics.

### Service UUID: `DECAFBAD-CAFE-4BEE-B00B-000000000000`

| Characteristic | UUID Suffix | Properties | Data Size / Layout | Description |
|---|---|---|---|---|
| **Status** | `...0001` | Read, Notify | 31 bytes | Gateway telemetry (ID, uptime, online peer count, group key epoch, nickname). |
| **Peers** | `...0002` | Read, Notify | Variable | Serialized list of online peers and their direct neighbor graphs. |
| **Chat** | `...0003` | Read, Write, Notify | Variable | Encrypted stream of messages, delivery ACKs, and node telemetry alerts. |
| **CMD** | `...0004` | Write | Max 64 bytes | Controls gateway configuration and triggers actions. |
| **ECDH** | `...0005` | Read, Write | 65 bytes | Uncompressed P-256 public key exchange (`0x04` + 64 bytes). |

### Wire Formats

#### 1. Status Payload (31 bytes)
```
[4 bytes: Node ID LE] [4 bytes: Uptime (s) LE] [2 bytes: Peer Count LE] [1 byte: Group Key Epoch] [20 bytes: Nickname ASCII]
```

#### 2. Peers Payload (Variable)
```
[2 bytes: Node Count (N) LE]
For each node (1 to N):
  [4 bytes: Node ID LE]
  [1 byte: Online Status (0/1)]
  [20 bytes: Nickname ASCII]
  [1 byte: Neighbor Count (M)]
  [M * 4 bytes: List of Neighbor Node IDs LE]
```

#### 3. Chat Write Format (App → Gateway)
```
[4 bytes: Destination Node ID LE] [1 byte: Channel ID] [12 bytes: GCM Nonce] [N bytes: Ciphertext] [16 bytes: GCM Tag]
```
*Destination Node ID = `0` represents a broadcast message.*

#### 4. Chat Notification Format (Gateway → App)
```
[4 bytes: Sender ID LE] [4 bytes: Dest ID LE] [4 bytes: Timestamp LE] [1 byte: Flags] [2 bytes: Session ID LE] [2 bytes: Seq LE] [1 byte: Channel ID] [12 bytes: Nonce] [N bytes: Ciphertext] [16 bytes: Tag]
```
- **Flags Bitmask**:
  - `Bit 0` (`0x01`): Message is sent by me (`is_me`).
  - `Bit 1` (`0x02`): Message is a unicast Direct Message (`is_dm`).
  - `Bit 6` (`0x40`): Frame contains Telemetry rather than chat (payload changes to Uptime and Battery).
  - `Bit 7` (`0x80`): Frame is a message delivery ACK.

#### 5. Command Frame Payload
Commands are formatted as `[1 byte: Command ID] [Variable Data]`.
- **Command 1 (Set Nickname)**: `[0x01] [N bytes: Nickname String]` (Max 20 bytes).
- **Command 3 (Sync Messages)**: `[0x03] [4 bytes: Epoch Timestamp LE]`. Re-notifies all messages newer than the timestamp and broadcasts a history request to the mesh.
- **Command 4 (Time Sync)**: `[0x04] [4 bytes: Unix Time LE]`. Synchronizes the mesh wall-clock offset.
- **Command 5 (Rotate Group Key)**: `[0x05]`. Forces the gateway to ratchet its local group key.

---

## 4. Mesh Routing & Transport Protocol (ESP-NOW)

All mesh nodes communicate asynchronously using raw ESP-NOW packets formatted under the `MeshPacket` structure.

### Packet Struct Layout (`MeshPacket`)
```c
struct MeshPacket {
    uint16_t magic;        // Must be 0xC0DE
    uint8_t  type;         // PKT_HEARTBEAT (0), PKT_CHAT (2), PKT_NICK_SYNC (3), PKT_HISTORY_REQ (4)
    uint8_t  epoch;        // Current group key epoch of sender
    uint16_t seq;          // Sequence counter per node session
    uint16_t session_id;   // Random 16-bit session token generated on boot
    uint32_t src_id;       // Sending Node ID
    uint32_t dest_id;      // Target Node ID (0 = Broadcast)
    uint16_t payload_len;  // Length of variable payload
    uint8_t  payload[200]; // Payload payload buffer
} __attribute__((packed));
```

### Routing & Network Membership (AODV-Lite)
* **Membership Heartbeats**: Every 5 seconds, each active node broadcasts a `PKT_HEARTBEAT` packet containing its nickname and its direct neighbor list (up to 32 nodes). Nodes listening to these heartbeats populate their local routing tables.
* **Relay Protocol**: 
  - Broadcasts (`dest_id = 0`) are forwarded by all nodes.
  - Unicasts (`dest_id != 0`) are forwarded only if the node is on the shortest path or has no route entry (fallback flood).
* **Duplicate Detection**: The framework uses a sliding log buffer (`dup_hashes[48]`) tracking the DJB2 hash of the tuple `(sender_id, session_id, seq)`. If a packet matches an existing entry, it is discarded to prevent broadcast loops.

---

## 5. Security & Cryptography Design

MeshOS utilizes hybrid cryptography to provide confidentiality, integrity, and forward secrecy while operating fully offline.

```
                  ECDH P-256 Handshake
  Native Client ──────────────────────── Gateway Node (ESP32)
                Derives Session Key (HKDF)
                            │
              Encrypted BLE GATT Channel (AES-GCM)
                            │
  Native Client <──────────────────────> Gateway Node
                            │
               Mesh Hop Encryption (AES-GCM)
                         (ESP-NOW)
```

### 1. BLE Session Handshake (ECDH)
Upon BLE connection, the native client generates an ephemeral P-256 private key and writes its public key (65 bytes in uncompressed format) to characteristic `0x0005`. The ESP32:
1. Receives the client's public key.
2. Generates its own ephemeral P-256 keypair.
3. Computes the shared ECDH secret.
4. Derives a 16-byte symmetric key using HKDF-SHA256.
5. Saves the key as `ble_session_key`.
6. Exposes its own public key for the client to read and complete the handshake.
Once derived, all sub-sequent BLE reads/writes to the chat characteristic (`0x0003`) are encrypted using this dynamic session key.

### 2. Mesh Payload Encryption (AES-128-GCM)
Chat messages are encrypted using hardware-accelerated **AES-128-GCM**.
- **Unicast (DMs)**: Encrypted using a static fallback key (`AES_KEY`), ensuring only nodes holding the firmware binary can read them.
- **Broadcasts**: Encrypted using a dynamic `current_group_key`.

### 3. Group Key Ratchet & Forward Secrecy
To protect broadcast messages from recovery in the event of a future node compromise, the broadcast key undergoes a hashing ratchet:
$$\text{key}_{\text{epoch}+1} = \text{SHA-256}(\text{key}_{\text{epoch}})[0..15]$$
The firmware tracks the current epoch and maintains a sliding ring buffer (`epoch_key_ring[16]`) of historical keys. This enables the node to decrypt historical messages requested during synchronization without sacrificing forward secrecy.

### 4. Dynamic SSID Hiding
On startup, each node runs a visible Wi-Fi Access Point (`MeshOS_XXXXXXXX`) to advertise itself to nearby nodes. Once heartbeats verify that mesh pathways have successfully formed, nodes programmatically set `ap.ssid_hidden = 1` and restart the Wi-Fi stack. This reduces the RF visibility of the mesh to unauthorized observers.

---

## 6. macOS Client Application (`macos/`)

The macOS desktop dashboard is written in Swift using SwiftUI, Metal Kit, and CoreBluetooth.

### Core Architecture
* **`MeshManager`**: The core `@MainActor` controller managing the lifecycle of the `CBCentralManager` state, connection handshakes, and GATT serialization.
* **State Management**: Publishes data using Combine (`@Published`) to update the SwiftUI views automatically on BLE frame arrivals.
* **Local Storage**: Caches mesh settings and node nicknames to a local JSON file (`mesh_data.json`) under the Application Support directory. To preserve security and privacy, **no chat logs are saved to disk**.

### GPU Mesh Topology Visualizer
The topology screen uses a custom [MetalTopologyView.swift](file:///Users/lokesh/Desktop/esp32Mesh/macos/MeshOSApp/Views/MetalTopologyView.swift) subclassing `NSViewRepresentable`.

```
                  Vertex Buffers (Position, Color)
  SwiftUI Model ──────────────────────────────────> Metal Pipeline
                                                          │
   Draw Call <──────────────────────────────────── Render Encoder
  (60 FPS Loop)
```

1. **Vertex Buffers**: Feeds position arrays (`SIMD2<Float>`) and color arrays (`SIMD4<Float>`) representing nodes and connection vectors.
2. **Animation Loop**: A force-directed layout runs locally. If a new message is received, it triggers a `PacketAnimation` sequence that interpolates the position of a virtual particle moving from the sender vertex to the receiver vertex.
3. **Metal Shaders ([Shaders.metal](file:///Users/lokesh/Desktop/esp32Mesh/macos/MeshOSApp/Shaders.metal))**:
   - `vertex_point` / `vertex_packet`: Projects vertex locations to clip space and binds point sizes.
   - `fragment_point`: Generates smooth, antialiased circular nodes using `point_coord` distance evaluations and the `discard_fragment` call.
   - `vertex_line` / `fragment_line`: Renders connection links between neighbors.

---

## 7. iOS Client Application (`ios/`)

The iOS mobile client is optimized for battery efficiency and touch targets.

### Implementation Details
* **UI Layout**: Employs custom card-based lists using SwiftUI views to display metric statistics (battery, active node indices, direct connections, and uptime parameters) rather than a continuous GPU pipeline to conserve phone batteries.
* **GATT Integration**: Shares the core logic of `MeshManager.swift` with the macOS application, supporting ECDH negotiation, message history synchronization, and custom commands.
* **UI Responsiveness**: Utilizes custom iOS keyboard avoidance sheets for message composition and a floating header glassmorphism design system.

---

## 8. Libraries, SDKs, & Component Dependencies

### C/C++ Firmware Dependencies
- **ESP-IDF Core (v5.5)**: System libraries (`esp_wifi`, `esp_now`, `nvs_flash`, `esp_timer`, `esp_event`).
- **NimBLE (Apache Mynewt)**: Bluetooth Low Energy host stack.
- **mbedTLS**: Cryptographic backend library (used for GCM encryption, SHA-256, and ECC math).

### Apple Swift Dependencies
- **SwiftUI**: Layout and presentation framework.
- **Combine**: Reactive framework for data stream management.
- **CoreBluetooth**: Apple framework for BLE client communication.
- **CryptoKit**: Implements cryptographic functions matching the firmware (ECDH key derivation, SHA-256, and AES-GCM primitives).
- **Metal / MetalKit (macOS)**: Low-overhead GPU graphics rendering.
- **UserNotifications**: Drives native operating system alerts for background notifications.

---

## 9. Known Limitations, Security Vulnerabilities, & Engineering Debt

1. **Static Fallback Key**: Direct Messages (DMs) and initial handshakes use a static hardcoded key (`MeshOSKey123!@#$`). An attacker reversing the client binary or firmware flash can read unicast traffic.
2. **Unauthenticated BLE Access**: The BLE server does not enforce pairing or bonding (`sm_bonding = 0`, `sm_mitm = 0`). Any BLE client can connect to the GATT server and interact with theCharacteristics.
3. **Sequence Wraps**: The sequence counter `my_seq` overflows after 65,535 increments, which can lead to duplicate filtering conflicts or replay exposures on high-traffic meshes.
4. **Transient App Memory**: Since chat logs are not persisted to disk, disconnecting from a node or quitting the application wipes local chat history.
5. **Epoch Rollover for Uptime**: Node online checks calculate uptime differences with millisecond counts that roll over every 50 days, which can cause transient node offline reports.

---

## 10. Developer Setup & Compilation Guide

### ESP32 Firmware Build (PlatformIO)
Prerequisites: PlatformIO CLI installed.

```bash
cd firmware

# Clean build artifacts
rm -rf .pio/build

# Compile the project
pio run

# Flash the binary to a connected board
pio run -t upload

# Open serial telemetry monitor (115200 baud)
pio run -t monitor
```

### Apple macOS / iOS Projects Build (Xcode)
Prerequisites: macOS, Xcode 15+ installed.

```bash
# To compile the macOS application
open macos/MeshOS.xcodeproj

# To compile the iOS application
open ios/MeshOSiOS.xcodeproj
```
Press `⌘R` in Xcode to build and run the target application. Ensure Bluetooth permissions are granted in System Settings.
