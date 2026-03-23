# ESP32 Mesh Chat

A self-organizing, infrastructure-free chat network built on ESP32. Flash the same firmware onto multiple boards and they automatically discover each other, form a mesh, assign nicknames, synchronize time, and let every node chat with every other node — no router, no internet, no server.

Each node runs a local web server so any phone or laptop on its Wi-Fi AP can open a browser and start chatting. An onboard 0.96″ OLED shows a live status dashboard and incoming messages.

---

## Table of Contents

- [Features](#features)
- [Hardware Requirements](#hardware-requirements)
- [Wiring](#wiring)
- [Software Stack](#software-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Web Interface](#web-interface)
- [OLED Display](#oled-display)
- [Mesh Protocol](#mesh-protocol)
- [Nickname System](#nickname-system)
- [API Reference](#api-reference)
- [How It Works](#how-it-works)
- [Limitations](#limitations)
- [License](#license)

---

## Features

- **Zero-infrastructure mesh** — nodes self-organize using painlessMesh over Wi-Fi. No router or access point needed.
- **Multi-hop messaging** — messages route through intermediate nodes, so range extends with every board added.
- **Broadcast deduplication** — a djb2 hash ring buffer (48 slots) silently drops re-broadcast duplicates so each message appears exactly once.
- **Auto-assigned nicknames** — every node gets a deterministic `AdjectiveAnimal` name (e.g. `SwiftFox`, `BoldHawk`) derived from its node ID. No configuration needed.
- **Mesh-wide nickname sync** — renaming any node broadcasts the change via a `__NK__` sync packet that propagates to every node in the mesh.
- **Mesh-synchronized time** — painlessMesh's internal NTP-like time sync keeps all node clocks aligned. Timestamps on messages and the OLED uptime clock are mesh-relative.
- **Per-node colored borders** — on the chat page, each peer node's messages get a unique colored border so you can visually distinguish senders at a glance.
- **Responsive web UI** — the chat and node-graph pages work on mobile and desktop. The `/nodes` graph stacks below the canvas on small screens.
- **OLED meshOS UI** — a two-screen animated display shows network status, signal strength, uptime, and a live message feed.
- **Live network graph** — `/nodes` renders an animated canvas topology showing self (center) and all peers in orbit, with hover tooltips and a nickname editing sidebar.

---

## Hardware Requirements

| Component | Spec | Notes |
|---|---|---|
| ESP32 development board | Any ESP32 with Wi-Fi | DOIT DevKit V1 used for development |
| SSD1306 OLED display | 128×64 px, I²C | 0.96″ modules are most common |
| Jumper wires | — | 4 wires for OLED |
| USB cable | — | For flashing and serial monitor |

You need **at least two** ESP32 boards to form a mesh. All boards run identical firmware.

---

## Wiring

Connect the SSD1306 OLED to the ESP32 over I²C:

```
OLED VCC  →  3.3V
OLED GND  →  GND
OLED SDA  →  GPIO 21
OLED SCL  →  GPIO 22
```

> The I²C pins are defined in `main.cpp` as `I2C_SDA 21` and `I2C_SCL 22`. Change these if your board variant uses different default I²C pins.

---

## Software Stack

| Library | Version | Purpose |
|---|---|---|
| [painlessMesh](https://gitlab.com/painlessMesh/painlessMesh) | 1.5.7 | Self-organizing mesh networking |
| [ESPAsyncWebServer](https://github.com/ESP32Async/ESPAsyncWebServer) | 3.10.3 | Non-blocking async HTTP server |
| [AsyncTCP](https://github.com/ESP32Async/AsyncTCP) | 3.4.10 | Underlying TCP for ESPAsyncWebServer |
| [U8g2](https://github.com/olikraus/u8g2) | 2.36.18 | OLED rendering (low RAM usage) |
| Arduino framework | — | Base platform via PlatformIO |

All dependencies are declared in `platformio.ini` and installed automatically by PlatformIO.

---

## Project Structure

```
esp32Mesh/
├── include/
│   └── web_page.h          # extern declarations for PROGMEM HTML strings
├── src/
│   ├── main.cpp            # Firmware: mesh, OLED, HTTP routes, nick sync
│   └── web_page.cpp        # Web UI: chat page + nodes page (stored in flash)
├── platformio.ini          # Board, framework, library dependencies
├── diagram.json            # Wokwi simulator wiring diagram
└── wokwi.toml              # Wokwi simulator config
```

### `main.cpp` responsibilities

- Mesh initialization and all five painlessMesh callbacks
- Message deduplication via djb2 hash ring buffer
- Nickname database (`nickDb[]`) with auto-generation and broadcast sync
- Non-blocking OLED state machine (status screen ↔ message screen)
- HTTP route handlers: `/`, `/send`, `/setnick`, `/data`, `/nodes`

### `web_page.cpp` responsibilities

- `index_html` — the chat page UI, stored as a `PROGMEM` string
- `nodes_html` — the network graph + node management UI, stored as a `PROGMEM` string

Both pages are single-file HTML with embedded CSS and JavaScript; they poll `/data` every 1–1.5 seconds via `fetch()`.

---

## Getting Started

### Prerequisites

- [PlatformIO](https://platformio.org/) (VS Code extension or CLI)
- Python 3.x (required by PlatformIO)

### 1. Clone the repository

```bash
git clone https://github.com/your-username/esp32Mesh.git
cd esp32Mesh
```

### 2. Open in VS Code with PlatformIO

Open the folder in VS Code. PlatformIO will detect `platformio.ini` and install all libraries automatically on the first build.

### 3. (Optional) Adjust configuration

Edit the constants at the top of `src/main.cpp`:

```cpp
#define MESH_PREFIX    "ESP32Mesh"    // Wi-Fi SSID prefix for the mesh
#define MESH_PASSWORD  "meshpass123"  // Mesh network password
#define MESH_PORT      5555           // TCP port for mesh communication
#define MESH_CHANNEL   6              // Wi-Fi channel (1–13)
```

All nodes **must share the same** `MESH_PREFIX`, `MESH_PASSWORD`, `MESH_PORT`, and `MESH_CHANNEL` to form a mesh.

### 4. Flash

Connect your ESP32 over USB, then in PlatformIO:

```bash
pio run --target upload
```

Or press the **Upload** button in VS Code. Repeat for every board.

### 5. Connect and chat

After flashing, each ESP32 broadcasts a Wi-Fi access point whose SSID starts with the mesh prefix. Connect any device to one node's AP, then navigate to:

```
http://192.168.4.1
```

Open `http://192.168.4.1/nodes` for the network graph.

> The IP `192.168.4.1` is the default ESP32 SoftAP gateway. If you have modified the AP settings it may differ.

---

## Configuration

All tunable parameters are `#define` constants in `src/main.cpp`.

### Mesh

| Constant | Default | Description |
|---|---|---|
| `MESH_PREFIX` | `"ESP32Mesh"` | Mesh network name / SSID prefix |
| `MESH_PASSWORD` | `"meshpass123"` | Mesh network password |
| `MESH_PORT` | `5555` | TCP port used by painlessMesh |
| `MESH_CHANNEL` | `6` | Wi-Fi channel for the mesh |

### Capacity

| Constant | Default | Description |
|---|---|---|
| `MAX_MESSAGES` | `30` | Maximum chat messages stored per node |
| `MSG_HASH_POOL` | `48` | Deduplication ring buffer size |
| `MAX_NODES` | `16` | Maximum nodes in the nickname database |

### OLED

| Constant | Default | Description |
|---|---|---|
| `I2C_SDA` | `21` | SDA GPIO pin |
| `I2C_SCL` | `22` | SCL GPIO pin |
| `O_FPS_MS` | `75` | OLED redraw interval (≈13 fps) |
| `O_MSG_TIMEOUT` | `10000` | ms before message screen returns to status |
| `O_FLASH_MS` | `1800` | ms the new-message row flashes |

---

## Web Interface

### Chat page — `/`

The default page. Every node runs its own instance, but all chat is shared via mesh broadcast.

- Messages you send appear right-aligned in white on black.
- Messages from peers appear left-aligned with a **unique colored border per node** — each sender node consistently gets the same color so you can tell them apart at a glance.
- Peer names are shown as their auto-assigned nickname (or custom nickname if set).
- The chat box scrolls internally — the page never expands vertically. Auto-scroll snaps to the newest message unless you have scrolled up to read history.

### Nodes page — `/nodes`

A live animated network graph and node manager.

- **Graph** — self node (white filled, labeled `ME`) in the center, peers orbiting it. Animated dashed edges show active connections. Hovering a node shows a tooltip with its nickname and ID.
- **Sidebar** — each node gets a card showing its nickname, short ID, and a rename input. Typing a new name and pressing **Save** (or Enter) pushes the rename across the entire mesh via the `__NK__` broadcast.
- **Mobile** — on screens narrower than 640 px the graph becomes a full-width square and the node cards stack below it.

---

## OLED Display

The display runs a non-blocking state machine with two screens driven at ~13 fps. No `delay()` calls are used in the display code.

### Status screen (default)

```
●  MESH OS              ▐▐▐
────────────────────────────
●  ONLINE
        SwiftFox
        3F8A2150
2 peers                8 msg
      up 00:04:31
```

| Element | Description |
|---|---|
| Pulsing dot | Solid and blinking = online; hollow = scanning |
| Signal bars (top right) | 1–3 bars filled based on peer count |
| Nickname | Auto-assigned or custom name in large font |
| Node ID | Short node ID below the nickname |
| Stats row | Peer count (left) and message count (right) |
| Uptime clock | Mesh-synchronized `HH:MM:SS` |

### Messages screen

Triggered automatically whenever a message is sent or received. Returns to the status screen after 10 seconds.

```
●  MSGS [7]             ▐▐▐
────────────────────────────
>  hello from node A
Bold: hey there!
>  how's signal?
█████████ SwiftFox: good!  ← flash row
─────────────────────────────
NEW          ▓▓▓▓▓▓▓░░░░░
```

| Element | Description |
|---|---|
| Flash row | Newest message inverts (white bg / black text) for 1.8 s |
| `>` prefix | Your own messages |
| `Nick:` prefix | Peer messages, using their nickname |
| Timeout bar | Right-aligned bar shrinks to zero over 10 s |
| `NEW` label | Shown while the flash animation is active |

### Boot splash

Shown during `setup()` before `loop()` starts. Displays `MESH OS`, a loading status, and the node's ID + auto-nickname after mesh initialization completes.

---

## Mesh Protocol

All mesh communication uses `mesh.sendBroadcast()`. Two packet types share the same channel, differentiated by prefix.

### Chat packet

```
<nodeId>|<message text>
```

Example:
```
3821947561|hello from node A
```

### Nickname sync packet

```
__NK__<nodeId>|<nickname>
```

Example:
```
__NK__3821947561|SwiftFox
```

Nickname sync packets are re-broadcast by every receiving node so they propagate through multi-hop meshes. The deduplication buffer prevents infinite loops.

---

## Nickname System

Nicknames are generated deterministically on boot using `autoNick(nodeId)`:

```cpp
String autoNick(uint32_t id) {
    // 10 adjectives × 10 nouns = 100 unique combinations
    const char* ADJS[]  = { "Swift","Bold","Bright","Dark","Fast",
                             "Cool","Sharp","Wild","Keen","Calm" };
    const char* NOUNS[] = { "Fox","Hawk","Wolf","Bear","Lynx",
                             "Kite","Wren","Crab","Moth","Ibis" };
    return String(ADJS[id % 10]) + String(NOUNS[(id >> 4) % 10]);
}
```

Custom nicknames can be set from the `/nodes` page sidebar. The change is:
1. Stored in the local `nickDb[]` array on the receiving node
2. Broadcast as a `__NK__` packet to all mesh peers
3. Re-broadcast by each peer to reach multi-hop nodes

Nicknames are not persisted to flash. They are re-announced on every new connection event, so a restarted node will re-learn peer nicknames within a few seconds of reconnecting.

---

## API Reference

All endpoints are served by the ESPAsyncWebServer on port 80.

### `GET /`
Returns the chat page HTML.

### `GET /nodes`
Returns the network graph page HTML.

### `GET /send?msg=<text>`
Sends a message to the mesh.

| Parameter | Required | Max length | Description |
|---|---|---|---|
| `msg` | Yes | 200 chars | Message text (URL-encoded) |

Returns `200 OK` on success, `400` if `msg` is empty.

### `GET /setnick?id=<nodeId>&nick=<name>`
Sets a nickname for a node and broadcasts it to the mesh.

| Parameter | Required | Max length | Description |
|---|---|---|---|
| `id` | Yes | — | Node ID (decimal uint32) |
| `nick` | Yes | 20 chars | New nickname |

Returns `200 OK` on success, `400` if the nickname is empty or too long.

### `GET /data`
Returns a JSON snapshot of the current node state.

```json
{
  "nodeId": "3821947561",
  "nodeCount": 2,
  "peers": ["1234567890", "9876543210"],
  "topology": { ... },
  "meshTime": 189423000000,
  "nicknames": [
    { "id": "3821947561", "nick": "SwiftFox" },
    { "id": "1234567890", "nick": "BoldHawk" }
  ],
  "messages": [
    {
      "sender": "1234567890",
      "text": "hello!",
      "ts": 189300,
      "me": false
    },
    {
      "sender": "3821947561",
      "text": "hey there",
      "ts": 189350,
      "me": true
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `nodeId` | string | This node's uint32 ID |
| `nodeCount` | number | Number of directly visible peers |
| `peers` | string[] | Peer node IDs |
| `topology` | object | painlessMesh recursive sub-connection tree |
| `meshTime` | number | Mesh-synchronized time in microseconds |
| `nicknames` | object[] | All known `{id, nick}` pairs |
| `messages` | object[] | Chat history, oldest first |
| `messages[].ts` | number | Mesh time in milliseconds at message receipt |
| `messages[].me` | bool | `true` if sent by this node |

---

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│                         ESP32 Node                           │
│                                                              │
│  Wi-Fi (SoftAP + STA)                                        │
│  ┌──────────────┐    ┌───────────────────────────────────┐   │
│  │ painlessMesh │◄──►│  Mesh peers (other ESP32 nodes)   │   │
│  └──────┬───────┘    └───────────────────────────────────┘   │
│         │ callbacks                                          │
│  ┌──────▼────────────────────────────────────────────────┐   │
│  │  main.cpp                                             │   │
│  │  • receivedCallback  → dedup → pushMessage            │   │
│  │  • newConnectionCallback → broadcastOwnNick           │   │
│  │  • nicknames DB (nickDb[])                            │   │
│  │  • chat buffer (chat[])                               │   │
│  └──────┬──────────────────┬────────────────────────────┘    │
│         │                  │                                 │
│  ┌──────▼──────┐   ┌───────▼──────┐                          │
│  │  OLED       │   │  HTTP /data  │                          │
│  │  state      │   │  JSON API    │                          │
│  │  machine    │   └──────┬───────┘                          │
│  └─────────────┘          │ fetch() every 1 s                │
│                    ┌──────▼────────────────────────────┐     │
│                    │  Browser (phone / laptop)          │    │
│                    │  / → chat page                     │    │
│                    │  /nodes → graph page               │    │
│                    └───────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
```

1. On boot every node initializes the mesh in `WIFI_AP_STA` mode — simultaneously an access point (so browsers can connect) and a station (so it can join the mesh).
2. painlessMesh manages peer discovery, connection maintenance, and a distributed time sync automatically.
3. When a peer connects, the node broadcasts its own nickname so the new peer can learn it.
4. Incoming packets are deduped, classified as chat or nick-sync, and handled accordingly.
5. The web pages poll `/data` every second and append only new messages, avoiding full re-renders.
6. The OLED runs a 13 fps non-blocking draw loop driven by `millis()` comparisons in `loop()`.

---

## Limitations

- **No message persistence** — messages and nicknames are stored in RAM and lost on reset. Custom nicknames are re-broadcast on reconnect so peers will re-learn them quickly, but the local chat history is gone.
- **100 auto-nickname combinations** — the `autoNick()` function produces 100 unique names. In a mesh with more than 100 nodes, collisions are possible.
- **Single AP client** — each node's SoftAP supports multiple TCP connections but the ESP32 AP mode works best with a small number of connected clients.
- **No encryption** — mesh traffic is not end-to-end encrypted. The mesh password prevents unauthorized nodes from joining but messages are plaintext within the mesh.
- **Channel contention** — all nodes share the same Wi-Fi channel. Large meshes may see throughput degradation.
- **Range** — limited to standard 2.4 GHz Wi-Fi range (~20–50 m indoors between adjacent nodes). Multi-hop routing extends total coverage.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
