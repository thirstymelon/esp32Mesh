# MeshOS — macOS Client

Native **SwiftUI** macOS application for the MeshOS encrypted mesh network. Featuring a modern "Glassmorphism" UI and GPU-accelerated network visualization.

---

## Key Features

-   **Secure Handshake**: Implements P-256 ECDH to establish a secure, unique session key with the connected ESP32 node.
-   **Metal Topology View**: A GPU-rendered (MTKView) interactive graph showing the real-time structure of the multi-hop mesh.
-   **Encrypted Chat**: End-to-end AES-128-GCM encryption for broadcasts and direct messages.
-   **Time Synchronization**: Automatically syncs the entire mesh network to the Mac's system time upon connection.
-   **Peer Management**: View all online nodes, monitor their battery levels, and edit their nicknames mesh-wide.
-   **OTA Updates**: Wirelessly update ESP32 firmware by dragging and dropping `.bin` files into the app.

---

## Requirements

-   **macOS**: 13.0 (Ventura) or later.
-   **Xcode**: 15.0+ (for building from source).
-   **Hardware**: Mac with Bluetooth LE support.

---

## Installation & Security

> [!CAUTION]  
> **Unsigned Application**: The pre-built `.app` in the Releases section is **not signed** with an Apple Developer certificate.
> 1.  Download `MeshOS.app.zip` from Releases.
> 2.  Extract and move to `/Applications`.
> 3.  **To open**: Right-click the app and select **Open**, then click **Open** again in the security dialog. You may need to visit *System Settings > Privacy & Security* to "Allow Anyway".

---

## Architecture

-   **`MeshManager.swift`**: The central engine handling CoreBluetooth state, GATT interactions, and CryptoKit-based encryption.
-   **`MetalTopologyView.swift`**: High-performance rendering of the mesh graph nodes and links using the Metal API.
-   **`ContentView.swift`**: Implements the floating glass navigation system and shared UI styling.

---

## Keyboard Shortcuts

-   `⌘D`: Disconnect from the current node.
-   `⌘R`: Manually refresh status and peer data.
-   `⌘,`: Open Settings.

---

## Build from Source

```bash
cd macos
open MeshOS.xcodeproj
# Select 'MeshOS' scheme and press ⌘R
```

---

## License
MIT
