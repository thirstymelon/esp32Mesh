# MeshOS — iOS Client

Native **SwiftUI** iOS application for the MeshOS encrypted mesh network. Secure, offline communication directly from your iPhone.

---

## Key Features

-   **P-256 ECDH Handshake**: Establishes a secure encrypted session with mesh nodes over Bluetooth LE.
-   **Mobile Mesh Map**: Real-time visualization of the ESP32 mesh topology.
-   **Secure Messaging**: Full support for encrypted broadcasts and private Direct Messages (DMs).
-   **Live Telemetry**: Monitor battery status and uptime of every node in the mesh network.
-   **Native Experience**: Built entirely in SwiftUI with support for Dark Mode and Haptic Feedback.
-   **OTA Updates**: Flash new firmware to your mesh nodes directly from your iPhone.

---

## Requirements

-   **iOS**: 17.0 or later.
-   **Xcode**: 15.0+ (for building from source).
-   **Hardware**: iPhone with Bluetooth LE support.

---

## Installation & Security

> [!IMPORTANT]  
> **Note on Signing**: This app is provided as source code and is **not signed**. 
> - To install on a physical iPhone, you must use Xcode with your own Apple ID (Free or Paid) to sign the build.
> - Open `ios/MeshOSiOS.xcodeproj`, select your development team in "Signing & Capabilities", and deploy to your device.

---

## Architecture

-   **`MeshManager.swift`**: Handles the BLE lifecycle, GATT characteristic synchronization, and `CryptoKit` encryption logic.
-   **`Views/`**:
    -   `MessagesView`: The primary chat interface.
    -   `NetworkView`: Interactive mesh topology map.
    -   `ConnectionSheet`: Node discovery and connection flow.
    -   `SettingsView`: App configuration and node renaming.

---

## Usage

1.  Launch the app and ensure Bluetooth is enabled.
2.  Tap **Connect** in the navigation bar.
3.  Select a node from the discovered list (e.g., `MeshOS_eb35`).
4.  Wait for the "Secure Handshake" to complete.
5.  Start messaging!

---

## License
MIT
