# ESP32 MeshOS — Firmware

High-performance, secure firmware for ESP32 mesh nodes. Built with **ESP-IDF 5.x** and **PlatformIO**, featuring hardware-accelerated encryption and intelligent routing.

---

## Key Features (v2.1)

-   **AODV-lite Routing**: Intelligent distance-vector routing table management. Messages are unicast to the next-hop node, significantly reducing airtime and collisions compared to simple flooding.
-   **Secure Handshake (P-256 ECDH)**: Each connection with an app negotiates a fresh **AES-128 session key** using Elliptic Curve Diffie-Hellman. The server keypair is generated once at boot for maximum stability.
-   **Hardware-Accelerated AES-128-GCM**: All mesh traffic is authenticated and encrypted using the ESP32's hardware crypto engine via mbedTLS.
-   **Mesh Time Protocol (MTP)**: Automatic synchronization of network-wide Unix time, distributed from the connected client app.
-   **Reliable Acknowledgements**: End-to-end delivery tracking with mesh-relayed ACKs.
-   **Robust Task Scheduling**: NimBLE BLE stack and WiFi/Mesh stacks are pinned to separate CPU cores (Core 1 and Core 0 respectively) to prevent contention and ensure real-time responsiveness.
-   **OTA over BLE**: Full support for wireless firmware updates via the native apps.

---

## Technical Architecture

### Component Breakdown
-   `main/crypto.c`: Manages ECP key generation, ECDH shared secret computation, and AES-GCM encryption/decryption.
-   `main/ble_mesh.c`: NimBLE GATT server implementation handling 6 characteristics (Status, Peers, Chat, CMD, ECDH, OTA).
-   `main/wifi_mesh.c`: ESP-NOW driver and MeshPacket relay/routing logic.
-   `main/peer_db.c`: In-memory database of all discovered mesh nodes and their neighbor links.
-   `main/chat_history.c`: Circular buffer for recently received messages to support app synchronization.

### BLE GATT Specification
Service: `DECAFBAD-CAFE-4BEE-B00B-000000000000`

| Characteristic | UUID Suffix | Properties | Description |
| :--- | :--- | :--- | :--- |
| **Status** | `...0001` | Read, Notify | Node ID, uptime, peer count, nickname. |
| **Peers** | `...0002` | Read, Notify | Serialized peer list and neighbor topology. |
| **Chat** | `...0003` | Read, Write, Notify | Secure message stream + ACKs & Telemetry. |
| **CMD** | `...0004` | Write | Commands (Nick, Sync, Time, Key Rotate). |
| **ECDH** | `...0005` | Read, Write | Public Key exchange for secure sessions. |
| **OTA** | `...0006` | Write, Notify | Firmware update control and data stream. |

---

## Build & Flash

### Prerequisites
-   [PlatformIO Core](https://platformio.org/install/cli)
-   ESP32 Development Board (e.g., WROOM-32)

### Commands
```bash
# Build the project
pio run

# Upload to ESP32
pio run -t upload

# Open serial monitor (115200 baud)
pio run -t monitor
```

### Configuration
The project is optimized via `sdkconfig`. Key optimizations include:
-   **NimBLE Host Task**: 8KB Stack, pinned to Core 1.
-   **Main Task**: 8KB Stack, pinned to Core 0.
-   **MbedTLS**: Hardware-acceleration enabled for AES and ECP.

---

## Troubleshooting

-   **Handshake Failures**: If the app fails to connect, check the serial logs for `mbedtls_ecdh_*` errors. Ensure the public key buffer is 4-byte aligned.
-   **Peers Not Appearing**: Ensure all nodes are on **WiFi Channel 1**.
-   **NVS Errors**: If you see flash errors on boot, perform a full erase: `pio run -t erase`.

---

## License
MIT
