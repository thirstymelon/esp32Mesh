# ESP32 MeshOS — Firmware

ESP32 firmware for the MeshOS distributed mesh communication platform. Written in pure C using the **ESP-IDF 5.x** framework and built with **PlatformIO**.

---

## What This Firmware Does (v2.0 Overhaul)

Each flashed ESP32 becomes an autonomous mesh node that:

- **AODV-lite Routing:** Nodes build a distance-vector routing table. Messages are unicast to the next hop if known, significantly increasing network capacity and reducing collisions.
- **P-256 ECDH Security:** Negotiates unique session keys with the macOS app via Elliptic Curve Diffie-Hellman, replacing static hardcoded keys.
- **Reliable ACK:** End-to-end delivery tracking with mesh-relayed acknowledgements.
- **Mesh Time Protocol:** Synchronises UTC time across all nodes in the mesh.
- **Telemetry Broadcasting:** Periodically shares node health data (battery, uptime).
- **Async NVS:** Decoupled flash writes to prevent mesh timing jitters.

---

## Source Files

```
firmware/
├── main/
│   ├── main.c              # All firmware logic (see breakdown below)
│   └── CMakeLists.txt      # ESP-IDF component registration
├── sdkconfig.defaults      # Kconfig overrides (BLE, mbedTLS, coexistence)
└── platformio.ini          # PlatformIO environment definition
```

### `main/main.c` — Module Breakdown

| Section | Description |
|---------|-------------|
| **AES-GCM helpers** | `aes_gcm_encrypt` / `aes_gcm_decrypt` using `mbedtls_gcm_*`. Nonce generated via `esp_fill_random`. |
| **Chat ring buffer** | 30-slot circular buffer (`ChatMessage[30]`) in BSS — no heap allocation |
| **Peer database** | Fixed `PeerEntry[32]` array with `compact_peer_db()` to recycle offline slots |
| **Duplicate filter** | DJB2-hash sliding window (48 slots) keyed on `sender_id ‖ seq` |
| **NVS persistence** | `save_nick_nvs` / `load_nick_nvs` using short hex keys (`n_<hex id>`) |
| **ESP-NOW receive** | `esp_now_recv_cb` — parses, deduplicates, decrypts, stores, and relays packets |
| **BLE GATT server** | 4 characteristics: Status, Peers, Chat (read/write/notify), CMD |
| **Heartbeat task** | FreeRTOS task (5 s period): broadcasts own presence, marks stale peers offline, relays received heartbeats |

---

## BLE GATT Characteristics

All characteristics share service UUID `DECAFBAD-CAFE-4BEE-B00B-000000000000`.

| UUID | Name | Properties | Payload |
|------|------|------------|---------|
| `…0001` | **Status** | Read, Notify | `[4 node_id][4 uptime_s][2 peer_count][20 nickname]` = 30 bytes |
| `…0002` | **Peers** | Read, Notify | `[2 count]` then per node: `[4 id][1 online][20 nick][1 nb_count][nb_count×4 neighbor_ids]` |
| `…0003` | **Chat** | Read, Write, Notify | Encrypted stream + ACKs (0x80) & Telemetry (0x40) |
| `…0004` | **CMD** | Write | `[1 cmd_id][…payload]` — Nick (1), Sync (3), Time (4), Key Rotate (5) |
| `…0005` | **ECDH** | Read, Write | P-256 Public Key exchange for session keys |

### CMD Reference

| cmd_id | Name | Payload | Action |
|--------|------|---------|--------|
| `1` | Set Nickname | `[ASCII string ≤ 20 chars]` | Updates this node's nickname, saves to NVS, broadcasts `PKT_NICK_SYNC` |
| `3` | Sync Messages | _(none)_ | Pushes full chat history (up to 30 messages) as GATT notifications, 30 ms between each |
| `4` | Time Sync | `[4 Unix timestamp LE]` | Sets `mesh_time_offset_s = client_time − uptime` |
| `5` | Rotate Group Key | _(none)_ | Rotates the broadcast group key epoch and key |

---

## ESP-NOW Packet Format

```c
struct MeshPacket {
    uint16_t magic;        // 0xC0DE
    uint8_t  type;         // 0=PKT_HEARTBEAT, 2=PKT_CHAT, 3=PKT_NICK_SYNC
    uint8_t  seq;          // per-node monotonic counter (wraps at 255)
    uint32_t src_id;       // sender node ID (derived from MAC bytes 2–5)
    uint32_t dest_id;      // 0=broadcast, else target node ID
    uint16_t payload_len;  // number of valid bytes in payload[]
    uint8_t  payload[200]; // chat: [12 nonce][ciphertext][16 GCM tag]
} __attribute__((packed)); // total: 14 + 200 = 214 bytes, fits in ESP-NOW 250-byte limit
```

### Heartbeat payload (type = 0)

```
[21 bytes nickname (null-padded)] [1 byte neighbor_count] [neighbor_count × 4 bytes neighbor_ids]
```

---

## Encryption

- **Algorithm**: AES-128-GCM via `mbedtls_gcm_*` (hardware-accelerated on ESP32)
- **Key**: 16 bytes, hardcoded in `AES_KEY[]` — must match the macOS app
- **Nonce**: 12 bytes of TRNG output via `esp_fill_random` — unique per message
- **Tag**: 16 bytes GCM authentication tag appended after ciphertext
- **Wire format**: `[12 nonce][N ciphertext][16 tag]` — identical to CryptoKit `AES.GCM.SealedBox.combined`

Packets that fail authentication (wrong key, bit-flip, replay from another network) are **silently dropped** in `esp_now_recv_cb`.

---

## Memory Layout

All runtime buffers are statically allocated (BSS) — zero `malloc`/`free` calls at runtime:

| Buffer | Size | Purpose |
|--------|------|---------|
| `chat_history[30]` | ~5.6 KB | Ring buffer of decrypted messages |
| `peer_db[32]` | ~3.0 KB | Peer table with nickname + neighbor list |
| `s_peers_buf[3072]` | 3.0 KB | Serialisation scratch for GATT peers read |
| `s_sync_snap[30]` | ~5.6 KB | Snapshot for CMD 3 message sync (avoids holding mutex during notify) |
| `s_notify_buf[213]` | 213 B | Per-message notify buffer for CMD 3 |
| `s_chat_read_buf[213]` | 213 B | Chat characteristic read response buffer |
| `dup_hashes[48]` | 192 B | Duplicate-filter hash ring |

**Total BSS added**: ~17.6 KB  
**RAM usage**: ~18% of 320 KB (verified by PlatformIO size report)

---

## Build Requirements

| Tool | Version |
|------|---------|
| PlatformIO CLI | Any recent |
| ESP-IDF (via PlatformIO) | 5.5.x |
| Host OS | macOS / Linux / Windows |

---

## Build & Flash

```bash
cd firmware

# Build only
pio run

# Flash to connected ESP32 (auto-detects port)
pio run -t upload

# Monitor serial output at 115200 baud
pio run -t monitor

# Flash and monitor in one step
pio run -t upload -t monitor
```

> **Full rebuild after sdkconfig change**: ESP-IDF caches Kconfig. If you edit `sdkconfig.defaults`, wipe the build cache first:
> ```bash
> rm -rf .pio/build && pio run
> ```

---

## Configuration

All Kconfig overrides live in `sdkconfig.defaults`. Notable settings:

| Key | Value | Reason |
|-----|-------|--------|
| `CONFIG_BT_NIMBLE_MAX_CONNECTIONS` | `3` | Support up to 3 simultaneous BLE clients |
| `CONFIG_ESP_COEX_SW_COEXIST_ENABLE` | `y` | Software coexistence for BLE + Wi-Fi on shared radio |
| `CONFIG_MBEDTLS_AES_C` | `y` | AES primitive for GCM |
| `CONFIG_MBEDTLS_GCM_C` | `y` | GCM mode for authenticated encryption |
| `CONFIG_COMPILER_OPTIMIZATION_SIZE` | `y` | Optimise for flash size |
| `CONFIG_LOG_DEFAULT_LEVEL_WARN` | `y` | Suppress verbose logs in production |

---

## FreeRTOS Tasks

| Task | Stack | Priority | Period |
|------|-------|----------|--------|
| `mesh_heartbeat_task` | 4096 B | 5 | 5 s |
| NimBLE host task | (NimBLE default) | (NimBLE default) | Event-driven |

All mutex operations (`chat_mutex`, `peer_mutex`, `hash_mutex`, `peers_buf_mutex`) are brief and never held across blocking calls or `vTaskDelay`.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Auth decrypt failed log | Key mismatch between firmware and app | Verify `AES_KEY[]` bytes match in both |
| Peers not appearing | Heartbeat not reaching node | Check ESP-NOW channel (must be 1); ensure both nodes powered |
| BLE not advertising | NimBLE init failed | Check `sdkconfig.defaults` has `CONFIG_BT_ENABLED=y` |
| NVS corrupt on flash | Old NVS layout | Erase flash: `pio run -t erase` then re-flash |
| Flash size warning | Board has 2 MB flash | Add `board_upload.flash_size = 2MB` to `platformio.ini` |
