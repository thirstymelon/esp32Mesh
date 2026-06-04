# 🧭 MeshOS — Futurescope & Audit

> Full codebase audit, known bugs, improvements, and feature roadmap for the MeshOS project.
> 
> **Generated**: June 4, 2026  
> **Scope**: `firmware/`, `macos/`, `ios/`

---

## Table of Contents

1. [Firmware Bugs & Improvements](#1-firmware-bugs--improvements)
2. [macOS App Bugs & Improvements](#2-macos-app-bugs--improvements)
3. [iOS App Bugs & Improvements](#3-ios-app-bugs--improvements)
4. [Cross-Cutting Issues](#4-cross-cutting-issues)
5. [Pro-Grade Improvements](#5-pro-grade-improvements)
6. [Feature Roadmap](#6-feature-roadmap)

---

## 1. Firmware Bugs & Improvements

### 🐞 Bugs

#### 1.1 `my_seq` wraps silently (`uint8_t` overflow)
- **File**: `firmware/main/main.c`
- **Severity**: **Medium**
- **Details**: `my_seq` is `uint16_t` but the heartbeat task increments it indefinitely. At 5-second intervals, it wraps every ~545 hours (~23 days). After wrap, the duplicate filter (`dup_hashes[48]`) might treat old packets as new if the session_id hasn't changed. While each BLE connection generates a new `session_id` (`esp_random()` on boot), the sequence should be `uint32_t` or the duplicate filter should also track a per-node epoch.
- **Fix**: Change `my_seq` to `uint32_t`, or add a wrap-around counter that increments the session context.

#### 1.2 Peer DB compacted but IDs can leak
- **File**: `firmware/main/main.c` — `compact_peer_db()`
- **Severity**: **Low**
- **Details**: `compact_peer_db()` only compacts when `max_peers` is hit, but offline peers remain as stale entries until compaction. If a peer goes offline and comes back with the same ID but new neighbors, the old `neighbor_count`/`neighbors` array persists until the next heartbeat updates it. The `update_peer_heartbeat()` correctly overwrites, so this is minor.

#### 1.3 `esp_log_timestamp()` millisecond rollover for offline detection
- **File**: `firmware/main/main.c` — heartbeat task
- **Severity**: **Low**
- **Details**: `esp_log_timestamp()` returns milliseconds since boot; it wraps after ~50 days. The offline detection logic (`offline_now - last_seen_ms > 15000`) would misbehave after wrap.

#### 1.4 No overflow check on `chat_count` with concurrent operations
- **File**: `firmware/main/main.c` — `add_to_history()`
- **Severity**: **Low**
- **Details**: The ring buffer handles the count correctly (max 30), but there's no bounds check if `chat_count` somehow exceeds `CHAT_HISTORY_MAX` due to a logic error. The current logic is sound but fragile.

#### 1.5 ECDH context leak path
- **File**: `firmware/main/main.c` — `ble_chr_ecdh_cb()`
- **Severity**: **Low**
- **Details**: The `cleanup` label jumps correctly to free resources, but if `mbedtls_ctr_drbg_seed` fails before `mbedtls_ecdh_setup`, the `ecdh` context is still freed. This is fine in practice but the `goto` control flow is fragile for future additions.

#### 1.6 Group key ratchet for past epochs uses `current_group_key`
- **File**: `firmware/main/main.c` — `get_group_key_for_epoch()`
- **Severity**: **High**
- **Details**: When `epoch < group_key_epoch`, the function returns `current_group_key` instead of reconstructing the key for that epoch. This means old group keys cannot be recovered for replay decryption. Since broadcast messages use the current epoch, this only matters for history sync. The function should walk backwards from current to find the key at the requested epoch, or store all epoch keys.
- **Fix**: Store a ring buffer of the last N epoch keys, or reconstruct them deterministically by ratcheting forward from a saved base key.

### 🔧 Improvements

#### 1.7 Use `esp_timer_get_time()` for wall clock instead of `esp_log_timestamp()`
- **File**: `firmware/main/main.c`
- **Severity**: **Medium**
- **Details**: `esp_log_timestamp()` is a logging convenience, not a reliable timing source. The heartbeat task uses it for peer liveness. Switch to `esp_timer_get_time()` everywhere for consistency and accuracy.

#### 1.8 BLE connection state machine hardening
- **File**: `firmware/main/main.c` — `ble_gap_event()`
- **Severity**: **Medium**
- **Details**: If a BLE connection is dropped during an ECDH handshake, `ble_session_established` remains `false`, which is correct. But if the app reconnects, a new ECDH handshake starts. The old `ble_session_key` is never zeroed, it's just overwritten. Add `memset(ble_session_key, 0, 16)` on disconnect.

#### 1.9 Static buffer sizes need documentation/assertion
- **File**: `firmware/main/main.c` — `s_peers_buf[3072]`
- **Severity**: **Low**
- **Details**: The 3072-byte buffer is large enough for ~110 peer entries. The peer DB max is 32. Document the buffer sizing with a `_Static_assert` that `3072 >= 2 + 32 * (26 + 32 * 4)`.

#### 1.10 Heartbeat payload length overflow
- **File**: `firmware/main/main.c` — `mesh_heartbeat_task()`
- **Severity**: **Low**
- **Details**: `pkt.payload_len = 22 + cnt * 4` where `cnt = MIN(dcnt, 40u)`. At 40 neighbors, `22 + 160 = 182` which fits in `MESH_PAYLOAD_MAX` (200). But `MAX_NEIGHBORS` is 16, so `dcnt` never exceeds 32 from `peer_db`. The `MIN(dcnt, 40u)` is a safety guard, but should be `MIN(dcnt, 44)` to match the actual payload budget: `(200 - 22) / 4 = 44.5`. The current values are fine but inconsistent.

#### 1.11 Use `esp_random()` for AES-GCM nonce
- **File**: `firmware/main/main.c` — `aes_gcm_encrypt()`
- **Severity**: **Info**
- **Details**: Already uses `esp_fill_random()` for nonces. This is correct. But nonce reuse across the same session key + group key epoch could be catastrophic for GCM. Consider a counter-based nonce mixed with random.

#### 1.12 No watchdog for heartbeats
- **File**: `firmware/main/main.c`
- **Severity**: **Low**
- **Details**: If `esp_now_send()` fails repeatedly (e.g., Wi-Fi stack issue), the heartbeat task keeps retrying. Add a software watchdog to reboot the ESP32 if ESP-NOW fails for >30 seconds.

#### 1.13 SSD1306 dead code should be removed
- **File**: `firmware/main/ssd1306.c`, `firmware/main/ssd1306.h`
- **Severity**: **Low**
- **Details**: The SSD1306 driver is compiled into the firmware but never called. Remove the files or wrap in a conditional compile flag. Saves ~4KB of flash.

---

## 2. macOS App Bugs & Improvements

### 🐞 Bugs

#### 2.1 `maximumWriteValueLength()` result ignored
- **File**: `macos/MeshOSApp/MeshManager.swift` — `centralManager(_:didConnect:)`
- **Severity**: **Low**
- **Details**: `peripheral.maximumWriteValueLength(for: .withResponse)` is called but the return value is not used. The actual write splitting should use this value to fragment large packets. Currently, BLE writes > MTU size may silently fail or be truncated.

#### 2.2 `showNotification` captures `self` in closure after deinit
- **File**: `macos/MeshOSApp/MeshManager.swift` — `showNotification()`
- **Severity**: **Medium**
- **Details**: Inside `center.getNotificationSettings { settings in ... }`, the closure captures `self` strongly. If `MeshManager` is deallocated before the async callback returns, this will crash. Use `[weak self]`.

#### 2.3 Metal topology view crashes if shader functions not found
- **File**: `macos/MeshOSApp/Views/MetalTopologyView.swift` — `setupPipelines()`
- **Severity**: **Low**
- **Details**: If `device.makeDefaultLibrary()` returns `nil` (e.g., no Metal library embedded), the pipeline setup silently exits, leaving `pointPipelineState` as `nil`. The `draw(in:)` method would crash with a force-unwrap. Add a guard + fallback.

#### 2.4 Physics simulation timer never invalidated
- **File**: `macos/MeshOSApp/Views/NetworkView.swift` — `MetalTopologyMapPanel`
- **Severity**: **Low**
- **Details**: The `timer` publisher uses `.autoconnect()` and is never cancelled. If the view is torn down and recreated, a new timer starts while the old one may still fire. Use `onDisappear { timer.upstream.connect().cancel() }` or store the cancellable.

#### 2.5 `@Published var groupKeyEpoch: UInt8 = 0` accessed before init
- **File**: `macos/MeshOSApp/MeshManager.swift`
- **Severity**: **Low**
- **Details**: The property is `@Published` but never published via `objectWillChange`. It's read from the status characteristic parse. This works but is inconsistent with the rest of the `@Published` properties.

### 🔧 Improvements

#### 2.6 Connection sheet re-scan on disappear should not auto-scan on next appear
- **File**: `macos/MeshOSApp/Views/ConnectionSheet.swift`
- **Severity**: **Low**
- **Details**: When the user dismisses the connection sheet, scanning stops. When they reopen it, scanning starts again. This is correct, but if the user dismissed it because they don't want to connect, re-opening triggers another scan. This is fine UX, but could be optimized with a "Don't auto-scan" toggle.

#### 2.7 NodesView not reachable from navigation
- **File**: `macos/MeshOSApp/ContentView.swift`
- **Severity**: **Info**
- **Details**: The `NodesView` is defined and functional, but there is no navigation tab for it. The `ContentView.Tab` enum only has `.messages`, `.network`, `.dashboard`. NodesView can only be accessed via code. Either add a tab or link from NetworkView.

#### 2.8 macOS Settings window title should be "MeshOS Settings"
- **File**: `macos/MeshOSApp/MeshOSApp.swift`
- **Severity**: **Info**
- **Details**: The `Settings` scene uses `SettingsView()` but the window title defaults to "App Name Settings". Use `.sceneCommandStyle()` or a custom `Window` scene to set the title.

#### 2.9 No keyboard shortcut for sending messages (macOS)
- **File**: `macos/MeshOSApp/Views/MessagesView.swift`
- **Severity**: **Low**
- **Details**: On macOS, `TextField.onSubmit` is used for sending. But `Cmd+Enter` is a common shortcut that's not handled. Add keyboard shortcut.

#### 2.10 Metal shaders have hardcoded point size
- **File**: `macos/MeshOSApp/Shaders.metal` — `vertex_point`
- **Severity**: **Info**
- **Details**: Point size is hardcoded to 24.0 in the vertex shader. For accessibility or dynamic sizing, pass it as a uniform buffer instead.

---

## 3. iOS App Bugs & Improvements

### 🐞 Bugs

#### 3.3 Missing `.scrollContentBackground(.hidden)` on all scroll views
- **Files**: All iOS View files
- **Severity**: **Medium**
- **Details**: iOS 16+ `List` and `Form` have a default white/gray background on the scroll content that conflicts with the dark theme. While the app uses custom `ScrollView` + `VStack` (not List), the `SettingsView` has a `ScrollView` that should use `.scrollContentBackground(.hidden)` if converted to `List`. Currently not an issue since no `List`/`Form` is used, but worth noting.

### 🔧 Improvements

#### 3.8 ChatThreadView scroll-to-bottom behavior
- **File**: `ios/MeshOSiOSApp/Views/MessagesView.swift` — `ChatThreadView`
- **Severity**: **Low**
- **Details**: The `.onChange(of: messages.count)` handler auto-scrolls to the last message, but this happens for every new message while the user might be reading older messages. Add a condition to only auto-scroll if the user is already near the bottom (within ~100px).

---

## 4. Cross-Cutting Issues

### 4.1 Hardcoded AES key
- **Files**: `firmware/main/main.c`, `macos/MeshOSApp/MeshManager.swift`, `ios/MeshOSiOSApp/MeshManager.swift`
- **Severity**: **High**
- **Details**: Both the firmware and client apps hardcode the same static AES-128-GCM key (`MeshOSKey123!@#$`) in source code. While ECDH session keys are negotiated per BLE session, the group broadcast key and fallback path use this static key. **Any attacker with access to the binary can decrypt all group broadcast messages.** For a production system, use:
  - A provisioning tool to generate a unique key per device batch
  - ECDH-derived keys for all paths (broadcast group key exchange via mesh protocol)
  - A key management protocol that rotates keys on a schedule

### 4.2 No BLE pairing/bonding security
- **Files**: `firmware/main/main.c` — `ble_hs_cfg.sm_*` settings
- **Severity**: **Medium**
- **Details**: `sm_bonding = 0`, `sm_mitm = 0`, `sm_sc = 1` (secure connections only, no bonding, no MITM protection). Any BLE scanner can connect to the ESP32 and read/write characteristics without authentication. ECDH handshake provides key agreement, but there's no device authentication.
- **Fix**: Enable `sm_mitm = 1` with passkey entry or numeric comparison, and enable bonding (`sm_bonding = 1`).

### 4.3 No message persistence across app restarts (macOS/iOS)
- **Files**: `macos/MeshOSApp/MeshManager.swift`, `ios/MeshOSiOSApp/MeshManager.swift`
- **Severity**: **Low**
- **Details**: Messages are persisted via `saveLocalData()` as JSON, loaded on init. But on disconnect, `messagesList.removeAll()` clears them. This means historical messages are lost on disconnect or app restart. The persistence correctly saves before clear, but `loadLocalData()` restores them — this is actually fine. But if the app crashes between save and load, messages are lost. Consider Core Data or SQLite for robust persistence.

---

## 5. Pro-Grade Improvements

### 5.1 CI/CD Pipeline
- Add GitHub Actions workflow for:
  - PlatformIO firmware build + unit tests (using Wokwi or QEMU for ESP32)
  - Xcode build for macOS and iOS targets
  - SwiftLint, Clang-Tidy static analysis
  - Automated firmware flashing to test hardware
  - Code signing and notarization for macOS app
  - TestFlight distribution for iOS app

### 5.2 Testing
- **Firmware**: Add ESP-IDF unit tests using `TEST_CASE` macros in `test/` directory. Use Wokwi simulation for integration tests with mesh topology.
- **macOS/iOS**: Add XCTest unit tests for `MeshManager` with mock peripheral. Add XCUITest for UI flows (connect, send message, disconnect).
- **Regression**: Snapshot tests for iOS/macOS UI (using `SnapshotTesting` library).

### 5.3 Error Handling & Logging
- **Firmware**: Structured logging with severity levels, remote log streaming over BLE to the client app
- **macOS/iOS**: Unified logging system (`OSLog`) instead of `print()`, log export in Settings, crash reporting (Crashlytics or Sentry)

### 5.4 Performance Optimization
- **Firmware**:
  - Profile IRAM usage (currently `CONFIG_ESP32_WIFI_IRAM_OPT=n` — saves IRAM but increases latency)
  - Use `esp_timer` callbacks instead of `vTaskDelay` for more precise heartbeat timing
  - Enable Wi-Fi modem sleep when idle (currently always active)
- **macOS/iOS**:
  - Profile `updateMeshData()` for performance — this is called on every GATT notification which can be frequent
  - Use `diffable data sources` for chat message list to reduce SwiftUI body recomputation
  - Lazy loading of large message histories

### 5.5 Accessibility
- Add VoiceOver labels to all interactive elements
- Support Dynamic Type for all text elements
- Add reduced motion support (disable animations)
- Support macOS Voice Control for BLE interaction flow

### 5.6 Internationalization (i18n)
- Extract all user-facing strings into `.xcstrings` (iOS 16+) / `.strings` files
- Support RTL languages in chat bubbles
- Add at least 2-3 major languages (Spanish, French, Chinese)

### 5.7 Security Hardening
- **Firmware**:
  - Enable flash encryption (`CONFIG_SECURE_FLASH_ENC_ENABLED`)
  - Enable secure boot (`CONFIG_SECURE_BOOT`)
  - Set `CONFIG_ESP_TLS_INSECURE=n`
  - Disable JTAG in production (`CONFIG_SECURE_DISABLE_ROM_DL_MODE`)
  - Add rate limiting on BLE write characteristic to prevent DoS
  - HMAC-authenticate command characteristic (cmd_id 1-5)
- **macOS/iOS**:
  - Store AES key in Keychain, not source code
  - Add app sandbox with minimal entitlements
  - Code sign with hardened runtime
  - Validate BLE peripheral identity (check advertisement data signature)

### 5.8 Developer Experience
- Add `firmware/Makefile` with common targets (build, flash, monitor, test, lint)
- Add pre-commit hooks for code formatting (`clang-format` for C, `swift-format` for Swift)
- Add `firmure/sdkconfig.defaults` documentation for each setting
- Add inline documentation for the BLE GATT protocol (service/characteristic UUIDs, wire format)
- Add `CONTRIBUTING.md` with development workflow

---

## 6. Feature Roadmap

### Phase 1 — Hardening (Current)

| Feature | Priority | Effort | Owner |
|---------|----------|--------|-------|
| Fix `my_seq` wrap to `uint32_t` | High | 1 day | Firmware |
| iOS UI full-screen fixes | High | 2 days | iOS |
| iOS keyboard avoidance for composer | High | 1 day | iOS |
| Consistent background pattern across all views | Medium | 1 day | iOS/macOS |
| macOS NodesView navigation tab | Medium | 1 day | macOS |
| Fix ECDH past epoch key recovery | High | 2 days | Firmware |
| Zero session key on BLE disconnect | Medium | 0.5 day | Firmware |
| Remove dead SSD1306 code | Low | 0.5 day | Firmware |
| macOS Metal topology shader fallback | Low | 1 day | macOS |

### Phase 2 — Meshing & Reliability

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **Mesh-wide ACKs** | High | 3 days | End-to-end delivery confirmation across ESP-NOW (not just BLE→node) |
| **Store-and-forward** | High | 5 days | Nodes buffer messages for offline peers, deliver when they come back online |
| **Mesh Time Protocol** | High | 3 days | Mesh-wide time synchronization with a distributed consensus (highest uptime = authoritative) |
| **Reliable transport layer** | Medium | 4 days | Sliding window + retransmission for mesh packets (TCP-like) |
| **Fragmentation** | Medium | 3 days | Split large messages (>200 bytes) across multiple ESP-NOW packets |
| **Per-hop encryption** | High | 4 days | ESP-NOW encrypted peers instead of plaintext broadcast |

### Phase 3 — Security

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **Key provisioning tool** | High | 5 days | CLI/macOS app to generate and flash a unique AES key per device batch |
| **Broadcast group key exchange** | High | 4 days | ECDH-based group key agreement across the mesh (not just BLE client) |
| **BLE pairing with passkey** | Medium | 2 days | Enable MITM protection via BLE passkey display or numeric comparison |
| **Message signing** | Medium | 3 days | HMAC or Ed25519 signatures on chat messages to prevent impersonation |
| **Perfect Forward Secrecy** | Low | 5 days | Rotate session keys on every reconnect or on a timer |
| **Key rotation daemon** | Low | 3 days | Periodic auto-rotation of group key on a configurable schedule |

### Phase 4 — iOS/UI

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **iOS Metal topology view** | Medium | 3 days | Port `MetalTopologyView` from macOS to iOS using `UIViewRepresentable` |
| **Push notifications** | Medium | 2 days | Remote push for new messages when app is backgrounded (requires APNs + server relay) |
| **Watch companion app** | Low | 5 days | Apple Watch app to receive message notifications and send quick replies |
| **iPad multi-tasking** | Low | 2 days | Support for Slide Over, Split View, and Stage Manager |
| **Widgets** | Low | 3 days | iOS Lock Screen/widget showing connected node status and unread count |
| **Dark mode / light mode toggle** | Low | 1 day | Allow user to override system appearance |
| **Message search** | Medium | 2 days | Full-text search across message history with SwiftUI Search API |
| **Message reactions** | Low | 3 days | Emoji reactions on messages (👍❤️😄😢😮) synced via mesh |
| **Read receipts** | Low | 2 days | Show when a DM recipient has read the message |

### Phase 5 — macOS/Desktop

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **Menu bar extra** | Low | 2 days | Menu bar icon showing connection status with quick actions |
| **Notification Center widgets** | Low | 3 days | macOS Notification Center widget for mesh status |
| **Shortcuts integration** | Low | 2 days | Apple Shortcuts actions: send message, get node count, connect/disconnect |
| **Touch Bar support** | Low | 1 day | Touch Bar buttons for common actions on MacBook Pro |

### Phase 6 — Advanced Mesh Features

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **Mesh bridging (Wi-Fi uplink)** | High | 5 days | One node connects to Wi-Fi AP and bridges mesh ↔ internet (for remote monitoring) |
| **Voice messages** | Medium | 5 days | Record and send short voice clips over mesh (Opus codec, chunked via BLE) |
| **File sharing UI** | Medium | 3 days | Dedicated file browser/manager UI on macOS/iOS (not just in-chat attachments) |
| **Mesh-O-Matic** | Low | 10 days | Web-based mesh topology emulator using Wokwi for testing without hardware |
| **LoRa hybrid transport** | Low | 10 days | ESP32-LoRa boards as long-range backbone nodes |
| **Message channels** | Medium | 3 days | Multiple named channels (e.g., "General", "Emergency", "Admin") with topic tracking |
| **Node geolocation** | Medium | 4 days | GPS coordinates broadcast in heartbeat, shown on topology map |
| **Battery-optimized sleep** | Medium | 5 days | ESP32 deep sleep with periodic wake for battery-powered nodes |

### Phase 7 — Analytics & Monitoring

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **Network health dashboard** | Medium | 3 days | Packet loss %, latency histogram, mesh diameter, route flapping detection |
| **Per-node bandwidth tracking** | Low | 3 days | Track bytes sent/received per node, peak throughput |
| **Alerting** | Medium | 2 days | Configurable alerts for: node offline >5min, low battery, high packet loss |
| **Traffic inspection tool** | Low | 4 days | macOS network traffic inspector showing packet-by-packet mesh activity |
| **Export/Share** | Low | 2 days | Export message history as CSV/PDF/plaintext, share topology as PNG |

### Phase 8 — Developer Platform

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| **REST API on firmware** | Medium | 5 days | Optional HTTP server on the ESP32 node for web-based management |
| **Plugin/script system** | Low | 10 days | Lua or WASM micro-scripting on the ESP32 for custom mesh logic |
| **Mesh SDK** | Low | 10 days | Public API for building custom clients (Python, JS, etc.) |
| **CLI tool** | Low | 5 days | Command-line mesh client for power users (connect, send, receive logs) |

---

## Appendix A: Wire Protocol Reference

### BLE GATT Service

```
Service UUID: DECAFBAD-CAFE-4BEE-B00B-000000000000

Characteristics:
  Status (0001) - Read/Notify   - 31 bytes: [4 node_id][4 uptime][2 peer_count][1 epoch][20 nickname]
  Peers  (0002) - Read/Notify   - variable: [2 count][(4 id + 1 online + 20 nick + 1 ncount + n*4 neighbors)...]
  Chat   (0003) - Read/Write/Notify - variable: see below
  CMD    (0004) - Write         - [1 cmd_id][data...]
  ECDH   (0005) - Read/Write    - 65 bytes: [0x04 + 64 P-256 pub key]
```

### Chat Write Format (App → Firmware)
```
[4 dest_id LE][1 channel_id][12 nonce][N ciphertext][16 GCM tag]
```

### Chat Notification Format (Firmware → App)
```
[4 sender LE][4 dest LE][4 ts LE][1 flags][2 session_id LE][2 seq LE][1 channel_id][12 nonce][N ciphertext][16 GCM tag]
```

### ESP-NOW MeshPacket Format
```
[2 magic 0xC0DE][1 type][1 epoch][2 seq LE][2 session_id LE][4 src_id LE][4 dest_id LE][2 payload_len LE][N payload]
```

### Command IDs
| ID | Command | Payload |
|----|---------|---------|
| 1 | Set Nickname | [ASCII nickname bytes] |
| 3 | Sync Messages | [4 timestamp since LE] |
| 4 | Time Sync | [4 unix timestamp LE] |
| 5 | Rotate Group Key | (none) |

---

## Appendix B: Known Limitations (from README)

- Encryption key is hardcoded — ECDH key exchange is implemented per-session but broadcast group key still uses static key
- `my_seq` is `uint16_t` — wraps eventually
- No BLE passkey pairing (open connection to any macOS client that knows the GATT UUIDs)
- No message persistence on disconnect (app side)
- `NodeEntry.battery` and `uptime` use `var` but are internal mutation — should be `let` with a mutating method
