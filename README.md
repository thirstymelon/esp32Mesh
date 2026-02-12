# 🚀 ESP32 Mesh Chat with OLED + Web UI

A decentralized **ESP32 Mesh Network Chat System** built using `painlessMesh`, featuring:

- 📡 Self-forming WiFi Mesh Network
- 💬 Real-time Web Chat Interface
- 🖥️ On-device OLED Message Display
- 🌐 Async Web Server
- 🔄 Auto-updating browser UI

---

## ✨ Features

- 🔗 Automatic ESP32 mesh formation
- 📡 Broadcast messaging to all nodes
- 🌍 Web-based chat interface hosted on each node
- 🖥️ OLED displays:
  - Node ID
  - Connected peer count
  - Last 4 messages
- ⚡ Fully asynchronous (no delay blocking)
- 📱 Responsive UI (mobile-friendly)

---

## 🧠 How It Works

Each ESP32:

1. Connects to a WiFi mesh network
2. Hosts a local web server
3. Displays chat messages on OLED
4. Broadcasts messages to all nodes
5. Syncs chat history via `/data` endpoint

Message format:

```
<nodeId>|<message>
```

---

## 🛠️ Hardware Required

- ESP32 (any dev board)
- 0.96" SSD1306 OLED (I2C)
- Jumper wires
- Breadboard (optional)

### 📌 OLED Wiring

| OLED Pin | ESP32 Pin |
|----------|-----------|
| VCC      | 3.3V      |
| GND      | GND       |
| SDA      | GPIO 21   |
| SCL      | GPIO 22   |

---

## 📦 Libraries Used

Install from Arduino Library Manager:

- painlessMesh
- ESPAsyncWebServer
- AsyncTCP
- Adafruit GFX
- Adafruit SSD1306

---

## ⚙️ Configuration

```cpp
#define MESH_PREFIX     "ESP32Mesh"
#define MESH_PASSWORD   "meshpass123"
#define MESH_PORT       5555
#define MESH_CHANNEL    6
```

You can modify:

- Mesh name
- Password
- Channel
- Port

---

## 🌐 How To Use

### 1️⃣ Upload to Multiple ESP32 Boards

Flash the same firmware to all devices.

### 2️⃣ Power Them On

They automatically form a mesh network.

### 3️⃣ Connect From Phone/Laptop

- Connect to the WiFi AP created by any node
- Open browser
- Visit:

```
http://192.168.4.1
```

### 4️⃣ Start Chatting 🎉

Messages:

- Broadcast to all nodes
- Appear instantly in browser
- Show on OLED screen

---

## 🖥️ OLED Display Layout

```
Node 1234 | 3
----------------
Me: Hello
5678: Hi
9012: Test
```

- Shows first 4 characters of sender ID
- Displays last 4 messages
- Updates instantly

---

## 🔄 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/`      | GET    | Web interface |
| `/send?msg=TEXT` | GET | Send message |
| `/data`  | GET    | Returns JSON chat data |

Example JSON:

```json
{
  "nodeId": "12345678",
  "nodeCount": "3",
  "messages": [
    {
      "sender": "1234",
      "text": "Hello",
      "me": true
    }
  ]
}
```

---

## 🧩 Architecture

```
Browser UI
     ↓
ESPAsyncWebServer
     ↓
painlessMesh
     ↓
Broadcast to all nodes
     ↓
OLED + Web UI update
```

---

## 🔐 Notes

- Messages are broadcast to all nodes
- Designed for local mesh communication
- Works without internet
- Fully decentralized

---

## 📈 Future Improvements

- End-to-end encryption
- Private messaging
- Node nicknames
- Message timestamps
- Persistent chat history (SPIFFS / SD card)
- WebSocket real-time updates (instead of polling)

---

## 🧑‍💻 Author

**Lokesh Panditi**
3rd Year BTech | Low Level, Assembly & Systems Enthusiast

GitHub: https://github.com/thirstymelon

---

## 🏁 Final Result

- ✔ Real-time decentralized chat
- ✔ OLED UI + Web UI
- ✔ Mesh-based communication
