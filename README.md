# ⚡ MeshOS — Distributed ESP32 Mesh Chat + OTA System

<p align="center">
  <img src="https://img.shields.io/badge/ESP32-Mesh-111111?style=for-the-badge&logo=espressif&logoColor=white">
  <img src="https://img.shields.io/badge/OTA-Distributed-00C853?style=for-the-badge">
  <img src="https://img.shields.io/badge/OLED-UI-FF6D00?style=for-the-badge">
  <img src="https://img.shields.io/badge/PlatformIO-Build-6A1B9A?style=for-the-badge&logo=platformio&logoColor=white">
  <img src="https://img.shields.io/badge/macOS-Desktop_App-000000?style=for-the-badge&logo=apple&logoColor=white">
  <img src="https://img.shields.io/badge/License-MIT-161616?style=for-the-badge">
</p>

<p align="center">
  <b>A fully self-organizing ESP32 mesh communication platform with distributed OTA firmware updates, OLED telemetry, and a native macOS control application.</b>
</p>

---

# ✨ Overview

MeshOS is a distributed communication system built entirely on ESP32 nodes.

No router.  
No internet.  
No central server.

Each ESP32 dynamically becomes:
- a client
- a router
- a relay node
- an OTA distributor

The system automatically forms a resilient multi-hop mesh network capable of:
- real-time messaging
- topology synchronization
- distributed firmware propagation
- live telemetry visualization
- decentralized communication

---

# 🖥️ Native macOS Application

MeshOS includes a dedicated native macOS desktop application for:
- network monitoring
- firmware management
- OTA distribution
- node visualization
- live mesh diagnostics

## Features

- Native Apple Silicon support
- Lightweight standalone `.app`
- Local-first architecture
- No cloud dependency
- Zero telemetry

## Installation

Download the latest release from:

```txt
GitHub → Releases
```

Extract:

```txt
MeshOS-macOS.zip
```

Move:

```txt
MeshOS.app → /Applications
```

Then:
- Right click the app
- Select **Open**
- Confirm the security dialog

> The app is currently distributed without Apple notarization.

---

# 🚀 Core Features

## 🌐 Self-Organizing Mesh Networking

- Zero infrastructure deployment
- Multi-hop packet routing
- Dynamic peer discovery
- Self-healing topology
- Broadcast synchronization
- Automatic reconnection

---

## ⚡ Distributed OTA Firmware Updates

Upload firmware once.

Entire mesh updates itself autonomously.

### OTA Modes

| Mode | Description |
|---|---|
| This Node | Standard local OTA |
| Entire Mesh | Distributed firmware propagation |

### OTA Capabilities

- Chunk-based transport
- MD5 integrity verification
- Multi-node synchronization
- Non-blocking update engine
- Live OTA progress tracking
- Automatic reboot coordination

---

## 🖥️ OLED Mesh Interface

Each node includes a fully animated OLED telemetry interface.

### OLED Features

- Connection status
- Peer count
- Mesh uptime
- Live message preview
- Signal visualization
- Non-blocking animations

---

## 🌍 Web Dashboard

Built-in asynchronous web interface accessible directly from any node.

### Dashboard Features

- Real-time chat UI
- Node topology graph
- Live system JSON API
- OTA upload panel
- Mobile-friendly interface

---

# 🧠 System Architecture

```txt
                ┌─────────────────┐
                │  Browser / App    │
                └────────┬────────┘
                         │
                ┌────────▼────────┐
                │ Async Web Layer │
                └────────┬────────┘
                         │
          ┌──────────────▼──────────────┐
          │       MeshOS Engine            │
          │  Routing • Sync • Messaging    │
          └──────────────┬──────────────┘
                         │
          ┌──────────────▼──────────────┐
          │ Distributed OTA Subsystem      │
          └──────────────┬──────────────┘
                         │
                 ┌───────▼───────┐
                 │ ESP32 Nodes     │
                 └───────────────┘
```

---

# ⚡ OTA Protocol

```txt
__OTA__|ANNOUNCE|size|md5|chunks
__OTA__|CHUNK|seq|base64_data
__OTA__|END|md5
__OTA__|ACK|nodeId
```

---

# 🔧 Hardware Requirements

| Component | Notes |
|---|---|
| ESP32 | Any compatible board |
| SSD1306 OLED | 128×64 I²C |
| Jumper Wires | 4-wire setup |

---

# 🔌 OLED Wiring

```txt
OLED VCC → 3.3V
OLED GND → GND
OLED SDA → GPIO 21
OLED SCL → GPIO 22
```

---

# 🧰 Software Stack

| Technology | Purpose |
|---|---|
| painlessMesh | Mesh networking |
| ESPAsyncWebServer | Async web server |
| AsyncTCP | TCP networking |
| U8g2 | OLED rendering |
| LittleFS | Filesystem |
| PlatformIO | Build system |

---

# 📁 Project Structure

```txt
MeshOS/
├── data/
│   ├── html_gz/
│   ├── style/
│   └── template/
├── include/
│   ├── ota.h
│   └── secrets.example.h
├── src/
│   ├── main.cpp
│   ├── ota.cpp
│   └── ui/
├── desktop/
│   └── MeshOS.app
├── build.sh
└── platformio.ini
```

---

# 🚀 Getting Started

## 1. Clone Repository

```bash
git clone https://github.com/your-username/MeshOS.git
cd MeshOS
```

---

## 2. Configure Mesh

Create:

```txt
include/secrets.h
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
chmod +x build.sh
./build.sh
```

---

## 4. Flash ESP32

```bash
pio run -t upload
pio run -t uploadfs
```

---

## 5. Connect to Mesh

Open:

```txt
http://192.168.4.1
```

---

# 🌐 API Endpoints

| Endpoint | Description |
|---|---|
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
- Native Linux + Windows desktop apps

---

# 📸 Screenshots

```txt
Add:
- Web UI screenshots
- OLED interface photos
- Mesh topology graph
- macOS application screenshots
```

---

# 🧪 Why This Project Matters

MeshOS is not a basic ESP32 demo.

It combines:
- distributed systems
- embedded networking
- OTA orchestration
- asynchronous communication
- decentralized topology management

into a fully functioning embedded mesh platform.

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
