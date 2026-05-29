# ⚡ MeshOS — Distributed ESP32 Mesh Communication Platform

<p align="center">
  <img src="https://img.shields.io/badge/ESP32-Mesh-111111?style=for-the-badge&logo=espressif&logoColor=white">
  <img src="https://img.shields.io/badge/OTA-Distributed-00C853?style=for-the-badge">
  <img src="https://img.shields.io/badge/OLED-UI-FF6D00?style=for-the-badge">
  <img src="https://img.shields.io/badge/PlatformIO-Firmware-6A1B9A?style=for-the-badge&logo=platformio&logoColor=white">
  <img src="https://img.shields.io/badge/SwiftUI-macOS_App-000000?style=for-the-badge&logo=apple&logoColor=white">
</p>

## Overview

MeshOS is a decentralized ESP32 mesh communication project that combines:

- ESP32 firmware with painlessMesh peer-to-peer networking
- An embedded web dashboard served from each node
- Distributed over-the-air (OTA) updates across the mesh
- A native macOS SwiftUI application for monitoring and control

This repository is split into two main pieces:

- `firmware/` — ESP32 firmware, web UI assets, OTA logic, OLED status display
- `macos/MeshOSApp/` — native macOS client written in SwiftUI

## Key Features

- Self-forming, multi-hop ESP32 mesh network
- Peer discovery, routing, and broadcast message propagation
- Local web dashboard on each node
- Distributed mesh OTA updates with chunked delivery and MD5 verification
- OLED status display with connection, node, and message feedback
- Native macOS control app for connection, monitoring, and diagnostics
- No central server required
- No internet dependency

## Repository Structure

- `firmware/`
  - `platformio.ini` — ESP32 build configuration
  - `src/main.cpp` — mesh logic, web server, OLED UI
  - `src/ota.cpp` — OTA upload, broadcast distribution, flashing
  - `include/secrets.example.h` — mesh and OTA credentials
  - `data/` — dashboard HTML/CSS assets
  - `build.sh` — compress web UI assets for LittleFS
- `macos/MeshOSApp/`
  - `MeshOSApp.swift` — app entry point
  - `MeshManager.swift` — HTTP polling and JSON decoding
  - `ContentView.swift` — main UI and navigation
  - `Views/` — app screens and supporting views

## Firmware Details

The ESP32 firmware uses:

- `painlessMesh` for mesh networking
- `ESPAsyncWebServer` for the local dashboard and OTA endpoints
- `LittleFS` for storing web assets and OTA binaries
- `U8g2` and `Adafruit SSD1306` for the OLED display
- `ArduinoJson` for structured data handling

### Default mesh settings

Defined in `firmware/include/secrets.example.h`:

- `MESH_PREFIX = "ESP32Mesh"`
- `MESH_PASSWORD = "meshpass123"`
- `MESH_PORT = 50003`
- `MESH_CHANNEL = 6`
- `OTA_USER = "admin"`
- `OTA_PASS = "password"`

## macOS App Details

The macOS app connects to a node's HTTP dashboard and polls the `/data` API.

It displays:

- Connected node status
- Active peer count
- Mesh topology and peers
- Recent chat messages
- Device nickname
- Connection and refresh controls

The app is built with SwiftUI and includes a settings panel, keyboard shortcuts, and clean macOS native styling.

## Web API Endpoints

The firmware exposes HTTP endpoints for dashboard and control:

- `GET /` — main web dashboard page
- `GET /nodes` — node list page
- `GET /update` — OTA upload page
- `POST /update` — upload firmware to node or full mesh
- `GET /ota/status` — OTA progress JSON
- `GET /send?msg=...` — broadcast chat messages
- `GET /setnick?id=...&nick=...` — set/update a nickname
- `GET /data` — JSON mesh status used by the macOS app

## Build and Flash Instructions

### Prerequisites

- PlatformIO installed (`pio` CLI)
- `sass` (optional, for compiling SCSS)
- `gzip` available on your system

### Build the web assets

From `firmware/`:

```bash
cd firmware
chmod +x build.sh
./build.sh
```

This generates compressed HTML/CSS under `firmware/data/html_gz/` and `firmware/data/style/`.

### Upload firmware and filesystem

1. Build and upload the ESP32 firmware:

```bash
pio run
pio run -t upload
```

2. Upload the LittleFS filesystem:

```bash
pio run -t uploadfs
```

> If your board uses a different upload port or board target, update `platformio.ini` accordingly.

## Running the macOS App

Open `macos/MeshOSApp/MeshOSApp.swift` in Xcode and run the app.

Then connect to a node by entering its IP address and press Connect.

The app polls the node's `/data` endpoint and displays live mesh state.

## Hardware Setup

Required hardware:

- ESP32 development board
- SSD1306 128×64 I2C OLED display
- Jumper wires

### OLED wiring

```txt
OLED VCC → 3.3V
OLED GND → GND
OLED SDA → GPIO 21
OLED SCL → GPIO 22
```

## Notes

- `firmware/include/secrets.example.h` is a template. Copy it to `firmware/include/secrets.h` and customize credentials before flashing.
- The distributed OTA mode saves firmware to LittleFS and then broadcasts chunks to peers.
- The mesh uses dynamic nickname sync and peer relay to propagate messages and metadata.
- The macOS client is local-first and does not require Apple cloud services.

## Recommended Workflow

1. Build the dashboard assets with `firmware/build.sh`
2. Upload the LittleFS filesystem with `pio run -t uploadfs`
3. Flash the firmware with `pio run -t upload`
4. Start the macOS app in Xcode
5. Connect to a node IP and monitor the mesh

---

# 🧰 Software Stack

| Technology | Purpose |
|------------|----------|
| painlessMesh | Mesh networking |
| ESPAsyncWebServer | Async web server |
| AsyncTCP | TCP networking |
| U8g2 | OLED rendering |
| LittleFS | Filesystem |
| PlatformIO | Firmware build system |
| SwiftUI | Native macOS application |

---

# 📁 Project Structure

```txt
esp32Mesh/
├── firmware/
│   ├── data/
│   │   ├── html_gz/
│   │   ├── scss/
│   │   ├── style/
│   │   └── template/
│   │
│   ├── include/
│   │   ├── ota.h
│   │   └── secrets.example.h
│   │
│   ├── lib/
│   ├── src/
│   │   ├── main.cpp
│   │   └── ota.cpp
│   │
│   ├── test/
│   ├── build.sh
│   ├── diagram.json
│   ├── platformio.ini
│   └── wokwi.toml
│
├── macos/
│   ├── MeshOSApp/
│   │   ├── Assets.xcassets/
│   │   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── MeshManager.swift
│   │   └── MeshOSApp.swift
│   │
│   └── app_claude.xcodeproj/
│
├── README.md
└── .gitignore
```

---

# 🚀 Getting Started

## 1. Clone Repository

```bash
git clone https://github.com/thirstymelon/esp32Mesh.git
cd esp32Mesh
```

---

## 2. Configure Mesh

Create:

```txt
firmware/include/secrets.h
```

Example:

```cpp
#define MESH_PREFIX   "MESH_NAME"
#define MESH_PASSWORD "MESH_PASS"
#define MESH_CHANNEL  6

#define OTA_USER      "admin"
#define OTA_PASS      "password"
```

---

## 3. Build Firmware

```bash
cd firmware

chmod +x build.sh
./build.sh
```

---

## 4. Flash ESP32

```bash
cd firmware

pio run -t upload
pio run -t uploadfs
```

---

## 5. Connect to Mesh

Open:

```txt
http://<Node IP address>
```

---

# 🖥️ Building the macOS Application

Open the project:

```bash
cd macos

open app_claude.xcodeproj
```

Requirements:

- macOS
- Xcode 26+
- Apple Silicon Mac (recommended)

Build:

```txt
Product → Build
```

Archive:

```txt
Product → Archive
```

Install:

```txt
MeshOS.app → /Applications
```

### Application Features

- Native SwiftUI interface
- Real-time mesh monitoring
- Node discovery
- OTA management
- Network diagnostics
- Local-first architecture

---

# 🌐 API Endpoints

| Endpoint | Description |
|-----------|-------------|
| `/` | Main chat UI |
| `/nodes` | Network topology |
| `/update` | OTA upload |
| `/ota/status` | OTA progress |
| `/send` | Send messages |
| `/data` | System JSON |

---

# 🧠 Internal Design Highlights

- Fully asynchronous architecture
- Non-blocking OTA distribution
- Deduplicated mesh packet relay
- Hash-based message filtering
- Mesh-wide nickname synchronization
- Simultaneous AP + STA operation
- Distributed firmware replication

---

# ⚠️ Current Limitations

- No persistent storage
- No encryption layer yet
- OTA throughput decreases on large meshes
- Shared WiFi channel constraints

---

# 🔮 Future Roadmap

- End-to-end encryption
- Persistent message storage
- AI-powered mesh assistant nodes
- LoRa hybrid transport
- Voice communication
- Morse-code messaging support
- Native iOS application
- Cross-platform node management

---

# 🧪 Why This Project Matters

MeshOS is more than a firmware project.

It combines:

- Distributed systems
- Embedded networking
- OTA orchestration
- Native desktop software
- Asynchronous communication
- Decentralized topology management

into a complete communication ecosystem.

This project explores how resilient communication systems can be built without relying on centralized infrastructure.

---

# 📜 License

MIT License

---

# ⭐ Support The Project

If you found this project interesting:

- Star the repository
- Share it
- Contribute ideas
- Build your own mesh network

---

<p align="center">
  <b>MeshOS — Distributed systems engineering on embedded hardware.</b>
</p>
