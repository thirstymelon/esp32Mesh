# ⚡ ESP32 Mesh Chat — OTA + OLED + Zero-Infra Network

<p align="center">
  <b>A fully self-organizing mesh chat system with OTA firmware distribution</b><br>
  No router 🚫 • No internet 🌐❌ • No server 🖥️❌ • Just ESP32 swarm energy 🐝⚡
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ESP32-Mesh-0A0A0A?style=flat-square&logo=espressif&logoColor=white">
  <img src="https://img.shields.io/badge/OTA-MultiNode-00C853?style=flat-square">
  <img src="https://img.shields.io/badge/OLED-UI-FF6D00?style=flat-square">
  <img src="https://img.shields.io/badge/PlatformIO-Build-6A1B9A?style=flat-square&logo=platformio&logoColor=white">
  <img src="https://img.shields.io/badge/License-MIT-111111?style=flat-square">
</p>

---

## 🎥 Demo (aka "this feels illegal but works")

Flash 3–5 ESP32s.

They instantly:
- find each other 🤝
- build a network 🧠
- sync time ⏱️
- start chatting 💬

Now hit **OTA → Entire Mesh**…

💥 Every node updates itself like a distributed organism.

---

## 🚀 Features (why this is not a basic project)

### 🧠 Core Mesh System

- ⚡ **Zero infra** → no router needed
- 🔁 **Multi-hop routing** → distance = number of nodes
- 🛑 **Deduplication engine** → no loops, no spam
- ⏱️ **Mesh-synced time** → all nodes share one clock
- 🏷️ **Auto + custom nicknames** → globally synced

---

### 🌐 Web Interface

- 💬 Real-time chat UI
- 🎨 Color-coded nodes (instant visual clarity)
- 📡 `/nodes` → animated topology graph
- 📱 Mobile-first, smooth AF

---

### 🖥️ OLED UI (meshOS)

- 🔵 Live connection state
- 📊 Peer count + uptime + signal
- 💬 Message preview system
- ⚡ Fully non-blocking animations (no lag, no delay())

---

## ⚡ OTA (THIS IS THE CRAZY PART)

This is where your project stops being “ESP32 project”
and becomes **distributed system engineering**

---

### 🔥 Modes

| Mode | What happens |
|------|------------|
| 🟢 This Node | normal OTA |
| 🌐 Entire Mesh | ONE upload → ALL nodes update |

---

## 🧠 OTA Protocol (actual system design)

```txt
__OTA__|ANNOUNCE|size|md5|chunks
__OTA__|CHUNK|seq|base64_data
__OTA__|END|md5
__OTA__|ACK|nodeId
```

---

## ⚙️ Internal Flow (what is happening under the hood)

1. User uploads `.bin` → `/update`
2. Firmware saved → **LittleFS**
3. Sender broadcasts:
   - ANNOUNCE
   - CHUNKs (512B)
   - END
4. All nodes:
   - Start OTA mode
   - Receive chunks
   - Decode base64
   - Write to flash
   - Verify MD5
   - Send ACK
   - Reboot

Meanwhile:
👉 Mesh keeps running
👉 UI keeps updating
👉 System never blocks

---

## 💡 Why This Is Actually Powerful

- 📡 Works **offline**
- 🔁 Self-healing distribution
- 🧩 Chunk-based OTA (safe AF)
- 🔐 MD5 integrity check
- 📊 `/ota/status` → live progress tracking
- ⚙️ Fully async (no blocking hell)

---

## 🧰 Hardware

| Component | Notes |
|----------|------|
| ESP32 | any board |
| OLED SSD1306 | 128×64 I²C |
| Wires | 4 only |

---

## 🔌 Wiring

```txt
OLED VCC → 3.3V
OLED GND → GND
OLED SDA → GPIO 21
OLED SCL → GPIO 22
```

---

## 🧠 Software Stack

- painlessMesh (mesh brain 🧠)
- ESPAsyncWebServer (non-blocking web)
- AsyncTCP (network core)
- U8g2 (OLED rendering)
- PlatformIO (build system)

---

## 📁 Project Structure

```txt
esp32Mesh/
├── data/
│   ├── html_gz/      # compressed UI ⚡
│   ├── style/        # CSS
│   ├── template/     # HTML
├── src/
│   ├── main.cpp      # mesh + UI + logic
│   └── ota.cpp       # OTA engine 🔥
├── include/
│   ├── ota.h
│   └── secrets.example.h
```

---

## 🚀 Getting Started

### 1. Clone

```bash
git clone https://github.com/your-username/esp32Mesh.git
cd esp32Mesh
```

---

### 2. Build & Upload

```bash
chmod +x build.sh
./build.sh

pio run -t upload
pio run -t uploadfs
```

---

### 3. Connect

```
http://192.168.4.1 (Router IP)
```

---

## ⚙️ Config

```cpp
#define MESH_PREFIX   "MESH_NAME"
#define MESH_PASSWORD "MESH_PASS"
#define MESH_CHANNEL  6
```

---

## 🌐 Endpoints

| Endpoint | Use |
|----------|----|
| `/` | Chat UI |
| `/nodes` | Graph UI |
| `/update` | OTA |
| `/ota/status` | OTA progress |
| `/send` | Send msg |
| `/data` | Full system JSON |

---

## 🧠 Architecture (clean mental model)

```txt
          📱 Browser
              │
        ┌─────▼─────┐
        │ Web Server │
        └─────┬─────┘
              │
     ┌────────▼────────┐
     │   Mesh Engine   │◄────────► ESP32 Nodes
     └────────┬────────┘
              │
     ┌────────▼────────┐
     │   OTA Engine    │🔥
     └────────┬────────┘
              │
         ┌────▼────┐
         │  OLED   │
         └─────────┘
```

---

## 🧠 How It Actually Works

- Mesh runs on WiFi AP + STA simultaneously
- Each node = router + client
- Messages = broadcast packets
- Deduplication = hash ring buffer
- Nicknames = synced via special packets
- OTA = chunked distributed update system

👉 You basically built a **mini distributed network stack**

---

## ⚠️ Limitations

- No persistence (RAM only)
- No encryption (yet 😏)
- OTA slower on big meshes
- Shared WiFi channel

---

## 🧠 Future Ideas

- 🔐 End-to-end encryption
- 📦 Message persistence
- 🧠 AI assistant nodes
- 📡 LoRa hybrid mesh
- 🔊 Morse messaging

---

## ⭐ Why This Hits Different

- Not just ESP32
- Not just mesh
- Not just OTA

👉 This is **distributed systems on embedded hardware**

---

## 📜 License

MIT License

---
