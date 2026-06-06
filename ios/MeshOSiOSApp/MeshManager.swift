//
//  MeshManager.swift
//  Mesh OS - macOS Client
//

import Foundation
import Combine
import CoreBluetooth
import CryptoKit
import UserNotifications
import UIKit
import SwiftUI

// MARK: - Data Models
struct MeshData: Codable {
    let nodeId: String
    let nodeCount: Int
    let meshTime: Int64?
    let topology: TopologyData?
    let peers: [String]
    let nicknames: [Nickname]
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case nodeId
        case nodeCount
        case meshTime
        case topology
        case peers
        case nicknames
        case messages
    }

    init(nodeId: String, nodeCount: Int, meshTime: Int64?, topology: TopologyData?, peers: [String], nicknames: [Nickname], messages: [Message]) {
        self.nodeId = nodeId
        self.nodeCount = nodeCount
        self.meshTime = meshTime
        self.topology = topology
        self.peers = peers
        self.nicknames = nicknames
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        nodeId = try container.decode(String.self, forKey: .nodeId)
        nodeCount = Self.decodeInt(from: container, forKey: .nodeCount) ?? 0
        meshTime = Self.decodeInt64(from: container, forKey: .meshTime)
        topology = try container.decodeIfPresent(TopologyData.self, forKey: .topology)
        peers = try container.decodeIfPresent([String].self, forKey: .peers) ?? []
        nicknames = try container.decodeIfPresent([Nickname].self, forKey: .nicknames) ?? []
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
    }

    private static func decodeInt(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }

    private static func decodeInt64(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(String.self, forKey: key) {
            return Int64(value)
        }

        return nil
    }
    
    struct TopologyData: Codable {
        let subs: [TopologyNode]?
    }
    
    struct TopologyNode: Codable {
        let nodeId: UInt32
        let subs: [TopologyNode]?
    }
    
    struct Nickname: Codable, Identifiable {
        let id: String
        let nick: String
    }
    
    struct MessageReaction: Codable, Identifiable, Equatable {
        var id: String { emoji }
        let emoji: String
        var count: Int
        var reactedByMe: Bool
    }
    
    struct Message: Codable, Identifiable {
        // Stable, unique key for mesh messages: sender + sessionId + seq.
        // For local optimistic messages, sessionId/seq will be 0, so we fallback to a hash of content+ts.
        var id: String {
            if sessionId != 0 || seq != 0 {
                return "\(sender)-\(sessionId)-\(seq)"
            }
            let combined = "\(sender)\(dest)\(ts)\(text)"
            let digest = SHA256.hash(data: Data(combined.utf8))
            return "opt-\(digest.map { String(format: "%02x", $0) }.joined().prefix(16))"
        }

        let sender: String
        let dest: String
        let text: String
        let ts: Int64
        let dm: Bool
        let me: Bool
        let sessionId: UInt16
        let seq: UInt16
        var delivered: Bool = true
        let channelId: UInt8
        
        // Media/File sharing
        let isMedia: Bool
        let mediaPath: String?
        let mediaName: String?
        
        // Reactions (local only, not synced over mesh)
        var reactions: [MessageReaction]

        enum CodingKeys: String, CodingKey {
            case sender
            case dest
            case text
            case ts
            case dm
            case me
            case sessionId
            case seq
            case delivered
            case channelId
            case isMedia
            case mediaPath
            case mediaName
            case reactions
        }

        init(sender: String, dest: String, text: String, ts: Int64, dm: Bool, me: Bool, sessionId: UInt16 = 0, seq: UInt16 = 0, delivered: Bool = true, channelId: UInt8 = 0, isMedia: Bool = false, mediaPath: String? = nil, mediaName: String? = nil, reactions: [MessageReaction] = []) {
            self.sender = sender
            self.dest = dest
            self.text = text
            self.ts = ts
            self.dm = dm
            self.me = me
            self.sessionId = sessionId
            self.seq = seq
            self.delivered = delivered
            self.channelId = channelId
            self.isMedia = isMedia
            self.mediaPath = mediaPath
            self.mediaName = mediaName
            self.reactions = reactions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            sender = try container.decodeIfPresent(String.self, forKey: .sender) ?? "Unknown"
            dest = try container.decodeIfPresent(String.self, forKey: .dest) ?? "0"
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            ts = Self.decodeTimestamp(from: container) ?? 0
            dm = try container.decodeIfPresent(Bool.self, forKey: .dm) ?? false
            me = try container.decodeIfPresent(Bool.self, forKey: .me) ?? false
            sessionId = try container.decodeIfPresent(UInt16.self, forKey: .sessionId) ?? 0
            seq = try container.decodeIfPresent(UInt16.self, forKey: .seq) ?? 0
            delivered = try container.decodeIfPresent(Bool.self, forKey: .delivered) ?? true
            channelId = try container.decodeIfPresent(UInt8.self, forKey: .channelId) ?? 0
            isMedia = try container.decodeIfPresent(Bool.self, forKey: .isMedia) ?? false
            mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
            mediaName = try container.decodeIfPresent(String.self, forKey: .mediaName)
            reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
        }

        private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>) -> Int64? {
            if let value = try? container.decode(Int64.self, forKey: .ts) {
                return value
            }

            if let value = try? container.decode(String.self, forKey: .ts) {
                return Int64(value)
            }

            return nil
        }
    }
}

// MARK: - Discovered Node Model
struct DiscoveredNode: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

// MARK: - Internal Peer Node Entry
struct NodeEntry {
    let id: UInt32
    let isOnline: Bool
    let nickname: String
    let neighbors: [UInt32]
    var battery: Int?
    var uptime: Int64?
}

// MARK: - Mesh Manager
@MainActor
class MeshManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var scanDidTimeout = false
    @Published var discoveredNodes: [DiscoveredNode] = []
    @Published var meshData: MeshData?
    @Published var errorMessage: String?
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var isSyncingMessages = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    // Auto-reconnect: stores the UUID of the last connected peripheral
    private var lastConnectedPeripheralID: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: "lastConnectedPeripheralID") else { return nil }
            return UUID(uuidString: str)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: "lastConnectedPeripheralID")
        }
    }
    private var isAutoReconnecting = false
    
    // OTA State Properties
    @Published var isUpdatingOTA = false
    @Published var otaProgress: Float = 0.0
    @Published var otaStatusMessage = ""
    @Published var selectedBinURL: URL?
    @Published var selectedBinData: Data?
    private var otaImageSize: UInt32 = 0
    private var otaStartTime: CFAbsoluteTime = 0
    private var scanTimeoutTask: Task<Void, Never>?
    private var reconnectScanTask: Task<Void, Never>?
    private var otaTask: Task<Void, Never>?
    private var otaWriteContinuation: CheckedContinuation<Void, Error>?
    
    // OTA speed tracking
    private var lastSpeedPointBytes: Int = 0
    private var lastSpeedPointTime: Date = .now
    
    // CoreBluetooth properties
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var maxWriteLength: Int = 512
    
    // GATT Characteristics
    private let serviceUUID = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000000")
    private let statusUUID  = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000001")
    private let peersUUID   = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000002")
    private let chatUUID    = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000003")
    private let cmdUUID     = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000004")
    private let ecdhUUID    = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000005")
    private let otaUUID     = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000006")

    private var statusCharacteristic: CBCharacteristic?
    private var peersCharacteristic: CBCharacteristic?
    private var chatCharacteristic: CBCharacteristic?
    private var cmdCharacteristic: CBCharacteristic?
    private var ecdhCharacteristic: CBCharacteristic?
    private var otaCharacteristic: CBCharacteristic?

    // Parsed states
    private var localNodeId: String?
    private var localNodeNickname = "Unknown"
    private var localNodeUptime: Int64 = 0
    private var nodesList: [NodeEntry] = []
    private var messagesList: [MeshData.Message] = []
    @Published var groupKeyEpoch: UInt8 = 0
    
    struct TelemetryDataPoint: Identifiable, Codable {
        var id: UUID
        let timestamp: Date
        let nodeId: String
        let battery: Int
        let uptime: Int64
        
        init(id: UUID = UUID(), timestamp: Date, nodeId: String, battery: Int, uptime: Int64) {
            self.id = id
            self.timestamp = timestamp
            self.nodeId = nodeId
            self.battery = battery
            self.uptime = uptime
        }
    }
    
    struct NetworkSnapshotPoint: Identifiable, Codable {
        var id: UUID
        let timestamp: Date
        let activeNodeCount: Int
        let directPeerCount: Int
        
        init(id: UUID = UUID(), timestamp: Date, activeNodeCount: Int, directPeerCount: Int) {
            self.id = id
            self.timestamp = timestamp
            self.activeNodeCount = activeNodeCount
            self.directPeerCount = directPeerCount
        }
    }
    
    struct OTASpeedDataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let speedBytesPerSec: Double
    }
    
    // Reaction notification banner
    struct ReactionNotification: Identifiable {
        let id = UUID()
        let emoji: String
        let fromNickname: String
        let messageText: String
    }
    
    @Published var currentReactionNotification: ReactionNotification?
    private var reactionDismissTask: Task<Void, Never>?
    
    @Published var telemetryHistory: [TelemetryDataPoint] = []
    @Published var networkHistory: [NetworkSnapshotPoint] = []
    @Published var otaSpeedHistory: [OTASpeedDataPoint] = []

    // Security
    private var sessionKey: SymmetricKey?
    private var myPrivateKey = P256.KeyAgreement.PrivateKey()

    // Timeout helper: races the operation against a CancellationError after `seconds`
    private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    
    var currentNodeNickname: String {
        return localNodeNickname
    }
    
    var activeNodes: [NodeEntry] {
        return nodesList
    }
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.loadLocalData()
        self.checkNotificationPermission()
    }
    
    // MARK: - Scanning
    func startScanning() {
        guard centralManager != nil else { return }
        self.bluetoothState = centralManager.state
        
        // Stop any active scanning to reset duplicate filter caches cleanly
        if centralManager.state == .poweredOn {
            centralManager.stopScan()
        }
        
        guard centralManager.state == .poweredOn else {
            let stateString: String
            switch centralManager.state {
            case .poweredOff:
                stateString = "Bluetooth turned OFF"
            case .unauthorized:
                stateString = "Bluetooth permission denied. Please authorize Bluetooth in System Settings."
            case .unsupported:
                stateString = "Bluetooth is unsupported or restricted by App Sandbox."
            case .resetting:
                stateString = "Bluetooth is resetting..."
            default:
                stateString = "Bluetooth is unavailable (State \(centralManager.state.rawValue))."
            }
            errorMessage = stateString
            isScanning = false
            return
        }
        errorMessage = nil
        isScanning = true
        scanDidTimeout = false
        discoveredNodes.removeAll()
        // Allow duplicates to dynamically update RSSI and handle quick re-advertisements on disconnect
        // Wrap in a tiny delay of 100ms to ensure the stopScan state propagates fully
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.isScanning, self.centralManager.state == .poweredOn else { return }
            self.centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            print("[MeshManager] Started scanning for MeshOS nodes...")
        }
        
        // Schedule automatic stop after 15 seconds if no nodes are discovered
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self = self else { return }
                if self.isScanning && self.discoveredNodes.isEmpty {
                    self.isScanning = false
                    self.scanDidTimeout = true
                    if self.centralManager != nil && self.centralManager.state == .poweredOn {
                        self.centralManager.stopScan()
                    }
                    print("[MeshManager] Scan timed out after 15s — no nodes discovered.")
                }
            } catch {
                // Task was cancelled, exit cleanly without marking timeout
            }
        }
    }
    
    func stopScanning() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        reconnectScanTask?.cancel()
        reconnectScanTask = nil
        isScanning = false
        scanDidTimeout = false
        isAutoReconnecting = false
        if centralManager != nil && centralManager.state == .poweredOn {
            centralManager.stopScan()
        }
        print("[MeshManager] Stopped scanning.")
    }
    
    // MARK: - Connection
    func connect(to node: DiscoveredNode) {
        // Guard against duplicate connections
        guard !isLoading, !isConnected else {
            print("[MeshManager] Ignoring connect — already connecting or connected.")
            return
        }
        // Store peripheral UUID for auto-reconnect
        self.lastConnectedPeripheralID = node.peripheral.identifier
        stopScanning()
        isLoading = true
        errorMessage = nil
        // Regenerate ECDH private key for a fresh handshake
        self.myPrivateKey = P256.KeyAgreement.PrivateKey()
        targetPeripheral = node.peripheral
        targetPeripheral?.delegate = self
        centralManager.connect(node.peripheral, options: nil)
        print("[MeshManager] Connecting to \(node.name)...")
    }
    
    // Auto reconnect to the last connected peripheral if it is rediscovered
    private func attemptAutoReconnect(for peripheral: CBPeripheral) {
        guard let lastID = lastConnectedPeripheralID,
              peripheral.identifier == lastID,
              !isConnected, !isLoading, !isAutoReconnecting,
              targetPeripheral == nil else { return }
        isAutoReconnecting = true
        print("[MeshManager] Auto-reconnecting to \(peripheral.name ?? "Node")...")
        isLoading = true
        errorMessage = nil
        // Regenerate ECDH private key for a fresh handshake
        self.myPrivateKey = P256.KeyAgreement.PrivateKey()
        targetPeripheral = peripheral
        targetPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    // compatibility function for original view logic if needed
    func connect(to ip: String) async {
        // Since we are no longer using IP, scan for matching nodes instead
        errorMessage = "BLE mode active. Please select a node from the list."
    }
    
    func disconnect(clearAutoReconnect: Bool = false) {
        self.selectedBinURL = nil
        self.selectedBinData = nil
        
        if clearAutoReconnect {
            self.lastConnectedPeripheralID = nil
        }
        
        guard let p = targetPeripheral else {
            // Never connected or already disconnected, clean up and scan immediately
            self.isConnected = false
            self.isLoading = false
            self.isSyncingMessages = false
            self.targetPeripheral = nil
            self.statusCharacteristic = nil
            self.peersCharacteristic = nil
            self.chatCharacteristic = nil
            self.cmdCharacteristic = nil
            self.ecdhCharacteristic = nil
            self.otaCharacteristic = nil
            self.sessionKey = nil
            self.nodesList.removeAll()
            self.localNodeId = nil
            self.localNodeNickname = "Unknown"
            self.meshData = nil
            
            if centralManager != nil && centralManager.state == .poweredOn {
                self.startScanning()
            }
            return
        }
        
        self.isConnected = false
        self.isLoading = false
        self.isSyncingMessages = false
        centralManager.cancelPeripheralConnection(p)
        print("[MeshManager] Initiated manual connection cancellation for \(p.name ?? "Node").")
    }
    
    // MARK: - Handshake
    private func performHandshake(peripheral: CBPeripheral) {
        guard let ecdhChar = ecdhCharacteristic else { return }
        // 1. Send our public key
        let myPub = myPrivateKey.publicKey.rawRepresentation
        // Raw representation of P256 is 64 bytes. Firmware expects 0x04 + 64 bytes.
        var fullPub = Data([0x04])
        fullPub.append(myPub)
        peripheral.writeValue(fullPub, for: ecdhChar, type: .withResponse)
    }
    
     private func parseECDHData(_ data: Data) {
        print("[MeshManager] Received ECDH data: \(data.count) bytes. Prefix: \(data.isEmpty ? "none" : String(format: "0x%02X", data[0]))")
        guard data.count == 65 else { 
            print("[MeshManager] Invalid ECDH data length!")
            return 
        }
        let peerPubData = data.dropFirst() // remove 0x04
        do {
            let peerPub = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPubData)
            let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPub)
            
            // Use simple SHA256 of the shared secret to match firmware's derivation
            let hash = sharedSecret.withUnsafeBytes { SHA256.hash(data: $0) }
            let derivedKey = SymmetricKey(data: Data(hash.prefix(16)))
            
            self.sessionKey = derivedKey
            print("[MeshManager] ECDH Handshake successful. Session key derived.")
            
            // Connection is now secure and fully operational
            self.isConnected = true
            self.isLoading = false
            
            // Restore cached messages from disk to the UI immediately
            self.updateMeshData()
            
            // Sync time and history after secure handshake
            self.syncTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.syncMessages()
            }
        } catch {
            print("[MeshManager] ECDH Handshake failed: \(error.localizedDescription)")
            self.errorMessage = "Handshake failed: \(error.localizedDescription)"
            self.disconnect()
        }
    }
    
    // MARK: - Data Fetching (GATT Reads)
    func fetchData() async {
        guard let p = targetPeripheral else { return }
        if let statusChar = statusCharacteristic {
            p.readValue(for: statusChar)
        }
        if let peersChar = peersCharacteristic {
            p.readValue(for: peersChar)
        }
    }
    
    // MARK: - Message Sending
    func sendMessage(_ text: String) async {
        await sendMessage(text, to: nil, channelId: 0)
    }
    
    func sendMessage(_ text: String, to destinationId: String? = nil, channelId: UInt8 = 0) async {
        var destId: UInt32 = 0
        if let destStr = destinationId, let id = UInt32(destStr) {
            destId = id
        }
        
        guard let p = targetPeripheral, let chatChar = chatCharacteristic else {
            print("[MeshManager] Cannot send message: not connected")
            return
        }
        
        guard let textData = text.data(using: .utf8) else { return }
        // AES-128-GCM: combined = nonce(12) + ciphertext + tag(16)
        let keyToUse = sessionKey ?? aesKey
        guard let sealed = try? AES.GCM.seal(textData, using: keyToUse),
              let combined = sealed.combined else {
            print("[MeshManager] Encryption failed")
            return
        }
        var payload = Data()
        var dest = destId.littleEndian
        payload.append(Data(bytes: &dest, count: 4))
        payload.append(channelId) // channel_id at byte 4
        payload.append(combined) // [12 nonce][ciphertext][16 tag]
        
        p.writeValue(payload, for: chatChar, type: .withResponse)
        print("[MeshManager] Sent encrypted message to \(destId) (channel \(channelId)) (len: \(payload.count))")

        // Optimistic UI insert
        let myId = localNodeId ?? "0"
        let now = Int64(Date().timeIntervalSince1970)
        let newMessage = MeshData.Message(
            sender: myId,
            dest: String(destId),
            text: text,
            ts: now,
            dm: destId != 0,
            me: true,
            delivered: destId == 0, // Broadcasts are "delivered" immediately
            channelId: channelId
        )
        
        if !messagesList.contains(where: { $0.id == newMessage.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                messagesList.append(newMessage)
            }
            updateMeshData()
        }
    }
    
    // MARK: - Message Reactions
    
    func toggleReaction(_ emoji: String, for messageId: String) {
        guard let idx = messagesList.firstIndex(where: { $0.id == messageId }) else { return }
        var msg = messagesList[idx]
        var didAddReaction = false
        if let reactionIdx = msg.reactions.firstIndex(where: { $0.emoji == emoji }) {
            if msg.reactions[reactionIdx].reactedByMe {
                if msg.reactions[reactionIdx].count <= 1 {
                    msg.reactions.remove(at: reactionIdx)
                } else {
                    msg.reactions[reactionIdx].count -= 1
                    msg.reactions[reactionIdx].reactedByMe = false
                }
            } else {
                msg.reactions[reactionIdx].count += 1
                msg.reactions[reactionIdx].reactedByMe = true
                didAddReaction = true
            }
        } else {
            msg.reactions.append(MeshData.MessageReaction(emoji: emoji, count: 1, reactedByMe: true))
            didAddReaction = true
        }
        messagesList[idx] = msg
        updateMeshData()
        
        // Show reaction notification banner when adding a reaction to a received message
        if didAddReaction && !msg.me {
            let nick = meshData?.nicknames.first(where: { $0.id == msg.sender })?.nick ?? String(msg.sender.prefix(6))
            // Cancel any previous auto-dismiss task to avoid overwriting stale handlers
            self.reactionDismissTask?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentReactionNotification = ReactionNotification(emoji: emoji, fromNickname: nick, messageText: msg.text)
            }
            // Auto-dismiss after 3 seconds
            reactionDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    self.currentReactionNotification = nil
                }
            }
        }
        
        // Sync the reaction change across the mesh
        sendReactionSync(emoji: emoji, for: msg, added: didAddReaction)
    }
    
    // MARK: - Reaction Sync (Send as chat message with __R: prefix)
    
    /// Format: __R:<action>:<msgSenderHex>:<msgSidHex>:<msgSeqHex>:<emoji>
    /// action: "+" for add, "-" for remove
    private func sendReactionSync(emoji: String, for msg: MeshData.Message, added: Bool) {
        guard let p = targetPeripheral, let chatChar = chatCharacteristic,
              let textData = sendReactionText(emoji: emoji, for: msg, added: added).data(using: .utf8) else { return }
        
        let keyToUse = sessionKey ?? aesKey
        guard let sealed = try? AES.GCM.seal(textData, using: keyToUse),
              let combined = sealed.combined else { return }
        
        var payload = Data()
        // Send as broadcast if the original message was a broadcast, otherwise DM to sender
        let destId: UInt32 = msg.dm ? (UInt32(msg.sender) ?? 0) : 0
        var dest = destId.littleEndian
        payload.append(Data(bytes: &dest, count: 4))
        payload.append(UInt8(0)) // channel_id
        payload.append(combined)
        
        p.writeValue(payload, for: chatChar, type: .withResponse)
        print("[MeshManager] Sent reaction sync: \(added ? "add" : "remove") \(emoji) on msg from \(msg.sender)")
    }
    
    private func sendReactionText(emoji: String, for msg: MeshData.Message, added: Bool) -> String {
        let senderHex = String(UInt32(msg.sender) ?? 0, radix: 16)
        let sidHex = String(msg.sessionId, radix: 16)
        let seqHex = String(msg.seq, radix: 16)
        let action = added ? "+" : "-"
        return "__R:\(action):\(senderHex):\(sidHex):\(seqHex):\(emoji)"
    }
    
    /// Parse a __R: reaction message and apply it locally
    private func applyReceivedReaction(_ reactionText: String, from senderId: UInt32) {
        // Format: __R:<action>:<msgSenderHex>:<msgSidHex>:<msgSeqHex>:<emoji>
        let parts = reactionText.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count == 6,
              parts[0] == "__R",
              let targetSender = UInt32(parts[2], radix: 16),
              let targetSid = UInt16(parts[3], radix: 16),
              let targetSeq = UInt16(parts[4], radix: 16) else { return }
        let action = parts[1]
        let emoji = String(parts[5])
        
        let targetId = "\(targetSender)-\(targetSid)-\(targetSeq)"
        guard let idx = messagesList.firstIndex(where: { $0.id == targetId }) else { return }
        
        var msg = messagesList[idx]
        if action == "+" {
            // Add or increment reaction from another node
            if let reactionIdx = msg.reactions.firstIndex(where: { $0.emoji == emoji }) {
                msg.reactions[reactionIdx].count += 1
            } else {
                msg.reactions.append(MeshData.MessageReaction(emoji: emoji, count: 1, reactedByMe: false))
            }
        } else if action == "-" {
            // Remove or decrement reaction from another node
            if let reactionIdx = msg.reactions.firstIndex(where: { $0.emoji == emoji }) {
                if msg.reactions[reactionIdx].count <= 1 {
                    msg.reactions.remove(at: reactionIdx)
                } else {
                    msg.reactions[reactionIdx].count -= 1
                }
            }
        }
        messagesList[idx] = msg
        updateMeshData()
        
        // Show banner if someone reacted to one of our messages
        if action == "+", msg.me {
            // Find who sent this reaction (the sender is NOT in msg, it's the reaction message's sender)
            // We can infer it from the mesh data
            self.reactionDismissTask?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentReactionNotification = ReactionNotification(
                    emoji: emoji,
                    fromNickname: meshData?.nicknames.first(where: { $0.id == String(senderId) })?.nick ?? String(senderId).prefix(6).description,
                    messageText: msg.text
                )
            }
            reactionDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    self.currentReactionNotification = nil
                }
            }
        }
    }
    
    // MARK: - Sync Messages Command
    func syncMessages() {
        guard let p = targetPeripheral, let cmdChar = cmdCharacteristic else { return }
        
        isSyncingMessages = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds sync window
            isSyncingMessages = false
        }
        
        var payload = Data()
        let cmdId: UInt8 = 3 // Sync Request
        payload.append(cmdId)
        
        // Hardcode timestamp to 0 to pull all history
        var latestTsLe = UInt32(0).littleEndian
        payload.append(Data(bytes: &latestTsLe, count: 4))
        
        p.writeValue(payload, for: cmdChar, type: .withResponse)
        print("[MeshManager] Sent sync messages request with latest timestamp: 0")
    }
    
    // MARK: - Time Synchronization Command
    func syncTime() {
        guard let p = targetPeripheral, let cmdChar = cmdCharacteristic else { return }
        let nowSecs = UInt32(Date().timeIntervalSince1970)
        var payload = Data()
        let cmdId: UInt8 = 4 // Time Sync
        payload.append(cmdId)
        var timeLe = nowSecs.littleEndian
        payload.append(Data(bytes: &timeLe, count: 4))
        p.writeValue(payload, for: cmdChar, type: .withResponse)
        print("[MeshManager] Sent time sync command: \(nowSecs)")
    }
    
    // MARK: - Group Key Rotation Command
    func rotateGroupKey() {
        guard let p = targetPeripheral, let cmdChar = cmdCharacteristic else { return }
        var payload = Data()
        let cmdId: UInt8 = 5 // Rotate Group Key
        payload.append(cmdId)
        p.writeValue(payload, for: cmdChar, type: .withResponse)
        print("[MeshManager] Sent rotate group key command")
    }
    
    func startFirmwareOTA(data: Data) {
        // Cancel any existing OTA task
        otaTask?.cancel()
        // Resume any pending continuation from the previous OTA session so it exits cleanly
        if let continuation = otaWriteContinuation {
            otaWriteContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        // Store the task in MeshManager so it outlives the calling view's lifecycle.
        // The task is independent of any tab/view — it will complete even if the user
        // switches tabs because MeshManager is a shared environment object.
        // Completion notifications are sent from parseOTAData when the firmware
        // reports success (0x02) or error (0xFF) via GATT notification.
        otaTask = Task { [weak self] in
            guard let self = self else { return }
            await self.otaUpload(data: data)
        }
    }
    
    private func sendOTACompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let progressPct = Int(self.otaProgress * 100)
            let isError = self.otaStatusMessage.contains("Error")
            let content = UNMutableNotificationContent()
            if isError {
                content.title = "OTA Update Failed (\(progressPct)%)"
                content.body = self.otaStatusMessage
                content.sound = .default
            } else if self.otaStatusMessage.contains("Succeeded") || self.otaStatusMessage.contains("Rebooting") {
                content.title = "OTA Update Succeeded (100%)"
                content.body = "Firmware update completed successfully at \(progressPct)%. Node is rebooting."
                content.sound = .default
            } else {
                // Generic completion (e.g. cancelled)
                return
            }
            
            let request = UNNotificationRequest(
                identifier: "ota-completion-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
    
    // MARK: - BLE OTA Firmware Update (internal, runs on stored Task)
    private func otaUpload(data: Data) async {
        guard let peripheral = targetPeripheral, let otaChar = otaCharacteristic else {
            errorMessage = "No node connected or OTA service not found."
            return
        }
        
        isUpdatingOTA = true
        otaProgress = 0.0
        otaStartTime = CFAbsoluteTimeGetCurrent()
        otaSpeedHistory.removeAll()
        lastSpeedPointBytes = 0
        lastSpeedPointTime = .now
        otaStatusMessage = "Preparing OTA Update..."
        otaImageSize = UInt32(data.count)
        
        // Re-query maxWriteLength after MTU exchange has completed
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        self.maxWriteLength = mtu > 0 ? mtu : 512
        print("[MeshManager] OTA maxWriteLength: \(self.maxWriteLength) bytes")
        
        // 1. Send Begin command: [0x01][4 bytes size]
        var beginPayload = Data([0x01])
        var sizeBytes = otaImageSize
        withUnsafeBytes(of: &sizeBytes) { beginPayload.append(contentsOf: $0) }
        
        peripheral.writeValue(beginPayload, for: otaChar, type: .withResponse)
        print("[MeshManager] Sent OTA start packet (size: \(otaImageSize) bytes)")
        
        // Wait for ready notification or simple delay
        do {
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        } catch {}
        
        // 2. Upload chunks in loop — use the negotiated MTU / max write length
        // Use withResponse max write length for safety since we mix both write types
        let mtuForWrite = peripheral.maximumWriteValueLength(for: .withResponse)
        let mtuForWriteWithout = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let effectiveChunkSize = min(mtuForWrite > 0 ? mtuForWrite : 512, mtuForWriteWithout > 0 ? mtuForWriteWithout : 512)
        let chunkSize = min(effectiveChunkSize - 1, 512) // -1 for command byte prefix, capped at firmware max 512
        var offset = 0
        var chunkIndex = 0
        
        while offset < data.count {
            guard isUpdatingOTA else {
                print("[MeshManager] OTA update aborted or encountered error")
                return
            }
            
            let remaining = data.count - offset
            let currentChunkSize = min(chunkSize, remaining)
            let chunkData = data.subdata(in: offset..<(offset + currentChunkSize))
            
            var chunkPayload = Data([0x02]) // Chunk prefix
            chunkPayload.append(chunkData)
            
            // Require ack for: first chunk (to ensure flash is ready), every 20th chunk (flow control), and the last chunk
            let isFirstChunk = (chunkIndex == 0)
            let isPeriodicAck = (chunkIndex > 0 && chunkIndex % 20 == 0)
            let isLastChunk = (offset + currentChunkSize >= data.count)
            let needsAck = isFirstChunk || isPeriodicAck || isLastChunk
            
            if needsAck {
                // Send with response for reliable delivery
                peripheral.writeValue(chunkPayload, for: otaChar, type: .withResponse)
                do {
                    try await withTimeout(seconds: 10) {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            self.otaWriteContinuation = continuation
                        }
                    }
                } catch {
                    print("[MeshManager] OTA write ack failed at chunk \(chunkIndex): \(error.localizedDescription)")
                    self.otaWriteContinuation = nil  // Clear stale continuation to prevent double-resume in didWriteValueFor
                    isUpdatingOTA = false
                    otaStatusMessage = "OTA Error: write failed at chunk \(chunkIndex) — \(error.localizedDescription)"
                    return
                }
            } else {
                // Send without response for speed between acks
                peripheral.writeValue(chunkPayload, for: otaChar, type: .withoutResponse)
                // Yield so the main actor can service other work while we stream chunks
                await Task.yield()
            }
            
            chunkIndex += 1
            offset += currentChunkSize
            
            // Update local progress estimation with ETA
            otaProgress = Float(offset) / Float(data.count)
            let uploadElapsed = CFAbsoluteTimeGetCurrent() - otaStartTime
            let uploadEta: String
            if uploadElapsed > 0.5, offset > 0 {
                let speed = Double(offset) / uploadElapsed
                let remaining = Double(data.count - offset)
                let etaSec = remaining / speed
                if etaSec >= 60 {
                    uploadEta = "\(Int(etaSec) / 60)m \(Int(etaSec) % 60)s"
                } else {
                    uploadEta = "\(Int(etaSec))s"
                }
            } else {
                uploadEta = "calculating..."
            }
            otaStatusMessage = "Uploading: \(offset) / \(data.count) bytes (\(Int(otaProgress * 100))%) \u{2014} ETA: \(uploadEta)"
            
            // Record speed data point periodically
            let speedNow = Date()
            let speedDelta = speedNow.timeIntervalSince(lastSpeedPointTime)
            if speedDelta >= 0.5 && offset > 0 {
                let bytesSinceLast = offset - lastSpeedPointBytes
                let instantSpeed = Double(bytesSinceLast) / speedDelta
                otaSpeedHistory.append(OTASpeedDataPoint(timestamp: speedNow, speedBytesPerSec: instantSpeed))
                lastSpeedPointBytes = offset
                lastSpeedPointTime = speedNow
            }
        }
        
        // 3. Send End command: [0x03] — await acknowledgement with timeout
        otaStatusMessage = "Flashed. Verifying firmware image..."
        var endPayload = Data([0x03])
        peripheral.writeValue(endPayload, for: otaChar, type: .withResponse)
        print("[MeshManager] Sent OTA end packet. Awaiting verification ACK...")
        do {
            try await withTimeout(seconds: 30) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.otaWriteContinuation = continuation
                }
            }
        } catch {
            print("[MeshManager] OTA End ACK failed: \(error.localizedDescription)")
            self.otaWriteContinuation = nil  // Clear stale continuation to prevent double-resume in didWriteValueFor
            isUpdatingOTA = false
            otaStatusMessage = "OTA Error: End command not acknowledged — \(error.localizedDescription)"
            return
        }
        print("[MeshManager] OTA End command acknowledged by firmware.")
        
        // Stay in isUpdatingOTA state so the firmware notification (0x02 success) can be picked up
        // by parseOTAData even after the End command write is acknowledged. The notification
        // will set the final status and schedule the cleanup task.
    }

    private func parseOTAData(_ data: Data) {
        guard data.count >= 5 else { return }
        let status = data[0]
        let value = data.readUInt32(at: 1)
        
        switch status {
        case 0x01: // Progress
            if otaImageSize > 0 {
                otaProgress = Float(value) / Float(otaImageSize)
                let writeElapsed = CFAbsoluteTimeGetCurrent() - otaStartTime
                let writeEta: String
                if writeElapsed > 0.5, value > 0 {
                    let speed = Double(value) / writeElapsed
                    let remaining = Double(otaImageSize - value)
                    let etaSec = remaining / speed
                    if etaSec >= 60 {
                        writeEta = "\(Int(etaSec) / 60)m \(Int(etaSec) % 60)s"
                    } else {
                        writeEta = "\(Int(etaSec))s"
                    }
                } else {
                    writeEta = "calculating..."
                }
                otaStatusMessage = "Writing: \(value) / \(otaImageSize) bytes (\(Int(otaProgress * 100))%) \u{2014} ETA: \(writeEta)"
            }
        case 0x02: // Success
            otaProgress = 1.0
            otaStatusMessage = "OTA Update Succeeded! Rebooting node..."
            // Send a local notification so the user knows even if they're on a different tab
            sendOTACompletionNotification()
            // Auto-cleanup after a success — only if still connected
            otaTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self = self, self.isConnected else { return }
                self.isUpdatingOTA = false
                self.otaTask = nil
            }
        case 0xFF: // Error
            let errString: String
            switch value {
            case 0x01: errString = "Failed to find update partition"
            case 0x02: errString = "Failed to initialize flash write"
            case 0x03: errString = "Flash write failed"
            case 0x04: errString = "Firmware image verification failed"
            case 0x05: errString = "Failed to update boot target"
            case 0x06: errString = "Incomplete upload — fewer bytes written than expected"
            default: errString = "Unknown error"
            }
            otaStatusMessage = "OTA Error: \(errString)"
            isUpdatingOTA = false
            // Send a local notification so the user knows even if they're on a different tab
            sendOTACompletionNotification()
            otaTask?.cancel()  // Cancel the running upload loop before dropping the reference
            otaTask = nil
        default:
            break
        }
    }
    
    // MARK: - AES-128-GCM Cryptography
    // Key MUST match AES_KEY in firmware/main/main.c ("MeshOSKey123!@#$")
    private let aesKey = SymmetricKey(data: Data([
        0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
        0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24
    ]))
    
    /// Decrypts an AES-GCM combined blob (nonce‖ciphertext‖tag) to a UTF-8 string.
    private func decryptBlob(_ combined: Data) -> String? {
        let keyToUse = sessionKey ?? aesKey
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plainData = try? AES.GCM.open(box, using: keyToUse) else {
            print("[MeshManager] AES-GCM decryption failed (wrong key or corrupt data)")
            return nil
        }
        return String(data: plainData, encoding: .utf8)
    }
    
    // MARK: - GATT Parsers
    private func parseStatusData(_ data: Data) {
        guard data.count >= 31 else { return }
        
        let nodeIdVal = data.readUInt32(at: 0)
        let uptimeVal = data.readUInt32(at: 4)
        let peerCountVal = data.readUInt16(at: 8)
        
        let epoch = data[10]
        let nickData = data.subdata(in: 11..<31)
        let nickname = String(bytes: nickData.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "Unknown"
        
        print("[MeshManager] Parsed Status: nodeId=\(nodeIdVal), uptime=\(uptimeVal), peers=\(peerCountVal), epoch=\(epoch), nick=\(nickname)")
        
        self.localNodeId = String(nodeIdVal)
        self.localNodeUptime = Int64(uptimeVal) * 1_000_000 // to microseconds
        self.localNodeNickname = nickname
        self.groupKeyEpoch = epoch
        
        updateMeshData()
    }
    
    private func parsePeersData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        let nodeCount = data.readUInt16(at: 0)
        var offset = 2
        var parsedNodes: [NodeEntry] = []
        
        for _ in 0..<nodeCount {
            guard offset + 26 <= data.count else { break }
            let nodeIdVal = data.readUInt32(at: offset)
            let isOnlineVal = data[offset + 4]
            let nickData = data.subdata(in: (offset + 5)..<(offset + 25))
            let nickname = String(bytes: nickData.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "Unknown"
            let neighborsCount = min(data[offset + 25], 32) // Cap to prevent excessive iteration from malformed payloads
            offset += 26
            
            var neighbors: [UInt32] = []
            for _ in 0..<neighborsCount {
                guard offset + 4 <= data.count else { break }
                let neighId = data.readUInt32(at: offset)
                neighbors.append(neighId)
                offset += 4
            }
            
            let newNode = NodeEntry(id: nodeIdVal, isOnline: isOnlineVal != 0, nickname: nickname, neighbors: neighbors)
            if !parsedNodes.contains(where: { $0.id == nodeIdVal }) {
                parsedNodes.append(newNode)
            }
        }
        
        print("[MeshManager] Parsed Peers: count=\(parsedNodes.count)")
        self.nodesList = parsedNodes
        
        updateMeshData()
    }
    
    private func parseChatNotification(_ data: Data) {
        // Wire format: [4 sender][4 dest][4 ts][1 flags][2 session_id][2 seq][1 channel_id][12 nonce][N ciphertext][16 tag]
        let headerLen = 18
        guard data.count >= headerLen else { return }
        
        let senderId = data.readUInt32(at: 0)
        let destId   = data.readUInt32(at: 4)
        let tsVal    = data.readUInt32(at: 8)
        let flagsVal = data[12]
        let sessId   = data.readUInt16(at: 13)
        let seqVal   = data.readUInt16(at: 15)
        let channelId = data[17]
        
        // Handle Telemetry (flags bit 6)
        if (flagsVal == 0x40) {
            let uptimeVal = data.readUInt32(at: 8)
            let battVal   = data.count > 18 ? data[18] : 0
            print("[MeshManager] Telemetry from \(senderId): uptime=\(uptimeVal), batt=\(battVal)%")
            
            if let idx = nodesList.firstIndex(where: { $0.id == senderId }) {
                nodesList[idx].uptime = Int64(uptimeVal)
                nodesList[idx].battery = Int(battVal)
                
                let point = TelemetryDataPoint(timestamp: Date(), nodeId: String(senderId), battery: Int(battVal), uptime: Int64(uptimeVal))
                telemetryHistory.append(point)
                if telemetryHistory.count > 100 {
                    telemetryHistory.removeFirst()
                }
                
                updateMeshData()
            }
            return
        }
        
        // Handle ACK notification (flags bit 7)
        if (flagsVal & 0x80) != 0 {
            print("[MeshManager] ACK received from \(senderId)")
            for i in (0..<messagesList.count).reversed() {
                // If we sent a DM to this sender recently, mark it delivered
                if messagesList[i].dest == String(senderId) && messagesList[i].me && !messagesList[i].delivered {
                    messagesList[i].delivered = true
                    break
                }
            }
            updateMeshData()
            return
        }

        let aesOverhead = 12 + 16 // nonce + tag
        guard data.count >= headerLen + aesOverhead + 1 else { return }
        
        // The encrypted blob starts at byte 18: nonce(12) + ciphertext + tag(16)
        let combined = data.subdata(in: headerLen..<data.count)
        guard let decryptedText = decryptBlob(combined), !decryptedText.isEmpty else {
            print("[MeshManager] Chat decrypt failed from sender \(senderId)")
            return
        }
        
        // Handle neighbor history request (flags = 0x10)
        if flagsVal == 0x10 {
            if decryptedText.hasPrefix("REQ_HIST:") {
                let parts = decryptedText.split(separator: ":")
                if parts.count == 2, let requesterIdVal = UInt32(parts[1], radix: 16) {
                    let requesterNodeId = String(requesterIdVal)
                    print("[MeshManager] Neighbor requested history. Target requester: \(requesterNodeId)")
                    
                    let msgs = self.messagesList
                    Task {
                        print("[MeshManager] Uploading \(msgs.count) historical messages to gateway for node \(requesterNodeId)...")
                        for msg in msgs {
                            if msg.channelId == 0 && msg.text.hasPrefix("REQ_HIST:") { continue }
                            await self.sendMessage(msg.text, to: requesterNodeId, channelId: msg.channelId)
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms throttle
                        }
                        print("[MeshManager] Historical messages upload complete.")
                    }
                }
            }
            return
        }
        
        // Handle reaction sync messages (__R: prefix) — don't add as chat message
        if decryptedText.hasPrefix("__R:") {
            // Never process our own reaction syncs — already applied locally
            if String(senderId) != self.localNodeId {
                applyReceivedReaction(decryptedText, from: senderId)
            }
            return
        }
        
        let isMe = String(senderId) == self.localNodeId
        let isDm = (flagsVal & 2) != 0
        
        let newMessage = MeshData.Message(
            sender: String(senderId),
            dest: String(destId),
            text: decryptedText,
            ts: Int64(tsVal),
            dm: isDm,
            me: isMe,
            sessionId: sessId,
            seq: seqVal,
            channelId: channelId
        )
        
        print("[MeshManager] Chat from \(senderId) → \(destId) ts=\(tsVal) me=\(isMe) sess=\(sessId) seq=\(seqVal) ch=\(channelId): \(decryptedText)")

        if isMe {
            // Match to optimistic insert: same text and ID starts with "opt-"
            if let idx = messagesList.firstIndex(where: { 
                $0.me && $0.text == decryptedText && $0.id.hasPrefix("opt-")
            }) {
                // Replace the optimistic one with the authoritative one
                messagesList[idx] = newMessage
                updateMeshData()
                return
            }
        }
        
        if !messagesList.contains(where: { $0.id == newMessage.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                messagesList.append(newMessage)
            }
            // Cap the in-memory list to 200 messages to prevent unbounded RAM growth
            if messagesList.count > 200 {
                messagesList.removeFirst(messagesList.count - 200)
            }
            updateMeshData()
            
            if !isMe {
                // Check message haptics setting before playing (default: true)
                if UserDefaults.standard.value(forKey: "messageHaptics") as? Bool ?? true {
                    Haptics.impact(.light)
                }
                showNotification(for: newMessage)
            }
        }
    }

    private func showNotification(for message: MeshData.Message) {
        let center = UNUserNotificationCenter.current()
        let senderNick = self.meshData?.nicknames.first(where: { $0.id == message.sender })?.nick ?? "Unknown"
        let title = message.dm ? "New DM from \(senderNick)" : "Mesh Broadcast"
        let body = message.text
        let msgId = message.id
        
        center.getNotificationSettings { [weak self] settings in
            guard let self = self, settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(identifier: msgId, content: content, trigger: nil)
            center.add(request)
        }
    }
    
    private func updateMeshData() {
        guard let localId = self.localNodeId else { return }
        
        // Nicknames
        var nicknames: [MeshData.Nickname] = []
        nicknames.append(MeshData.Nickname(id: localId, nick: self.localNodeNickname))
        
        for node in nodesList {
            let nodeIdStr = String(node.id)
            if !nicknames.contains(where: { $0.id == nodeIdStr }) {
                nicknames.append(MeshData.Nickname(id: nodeIdStr, nick: node.nickname))
            }
        }
        
        // Peers (Direct neighbors of self)
        var peers: [String] = []
        if let localUIntId = UInt32(localId),
           let selfEntry = nodesList.first(where: { $0.id == localUIntId }) {
            peers = selfEntry.neighbors.map { String($0) }.filter { $0 != localId }
        } else {
            peers = nodesList.filter { String($0.id) != localId && $0.isOnline }.map { String($0.id) }
        }
        
        // Topology
        let topologyNodes = buildTopologyTree(nodes: nodesList, rootId: UInt32(localId) ?? 0)
        let topology = MeshData.TopologyData(subs: topologyNodes)
        
        // Node Count
        let onlineCount = nodesList.filter { $0.isOnline }.count
        
        self.meshData = MeshData(
            nodeId: localId,
            nodeCount: max(1, onlineCount),
            meshTime: self.localNodeUptime,
            topology: topology,
            peers: peers,
            nicknames: nicknames,
            messages: self.messagesList
        )
        self.lastUpdate = Date()
        
        let lastSnap = networkHistory.last
        if lastSnap == nil || lastSnap!.activeNodeCount != onlineCount || lastSnap!.directPeerCount != peers.count || Date().timeIntervalSince(lastSnap!.timestamp) >= 5 {
            let snap = NetworkSnapshotPoint(timestamp: Date(), activeNodeCount: max(1, onlineCount), directPeerCount: peers.count)
            networkHistory.append(snap)
            if networkHistory.count > 100 {
                networkHistory.removeFirst()
            }
        }
        
        saveLocalData()
    }

    // MARK: - Persistence
    private var persistenceURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appPath = paths[0].appendingPathComponent("MeshOS")
        try? FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        return appPath.appendingPathComponent("mesh_data.json")
    }

    private var lastDiskSaveTime: Date = .distantPast

    private func saveLocalData() {
        // Throttle disk writes: at most once per 2 seconds
        guard Date().timeIntervalSince(lastDiskSaveTime) >= 2 else { return }
        lastDiskSaveTime = Date()
        
        guard let data = meshData else { return }
        let currentMessages = self.messagesList
        do {
            let dataToSave = MeshData(
                nodeId: data.nodeId,
                nodeCount: data.nodeCount,
                meshTime: data.meshTime,
                topology: data.topology,
                peers: data.peers,
                nicknames: data.nicknames,
                messages: currentMessages // Save all messages to disk!
            )
            let encoded = try JSONEncoder().encode(dataToSave)
            let fileURL = self.persistenceURL
            
            // Perform Disk I/O asynchronously on a background task to keep UI fluent
            Task.detached(priority: .background) {
                do {
                    try encoded.write(to: fileURL)
                } catch {
                    print("[MeshManager] Failed to write local data: \(error)")
                }
            }
        } catch {
            print("[MeshManager] Failed to encode local data: \(error)")
        }
    }

    private func loadLocalData() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode(MeshData.self, from: data)
            self.meshData = decoded
            self.messagesList = decoded.messages // Restore message history from disk!
            self.localNodeId = decoded.nodeId
            print("[MeshManager] Loaded local configuration and \(decoded.messages.count) messages.")
        } catch {
            print("[MeshManager] No local data found or corrupted.")
        }
    }
    
    func clearCache() {
        self.meshData = nil
        self.messagesList.removeAll()
        self.nodesList.removeAll()
        self.discoveredNodes.removeAll()
        self.localNodeId = nil
        self.localNodeNickname = "Unknown"
        self.lastConnectedPeripheralID = nil
        
        let fileURL = self.persistenceURL
        try? FileManager.default.removeItem(at: fileURL)
        print("[MeshManager] Cache cleared successfully.")
    }
    
    func cleanupOnClose() {
        // Disconnect BLE connection to trigger firmware re-advertising immediately
        disconnect(clearAutoReconnect: true)
        
        // Clear all memory lists
        self.meshData = nil
        self.messagesList.removeAll()
        self.nodesList.removeAll()
        self.discoveredNodes.removeAll()
        self.localNodeId = nil
        
        // Remove local storage file completely
        let fileURL = self.persistenceURL
        try? FileManager.default.removeItem(at: fileURL)
        
        print("[MeshManager] Cleaned up: disconnected, memory cleared, and local storage removed on close.")
    }
    
    func checkNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error = error {
                    print("[MeshManager] Notification authorization error: \(error.localizedDescription)")
                    self.errorMessage = "Notification Permission Error: \(error.localizedDescription)"
                } else {
                    print("[MeshManager] Notification authorization granted: \(granted)")
                    if granted {
                        self.notificationStatus = .authorized
                    } else {
                        self.notificationStatus = .denied
                        self.errorMessage = "Notifications are disabled. Please enable them in Settings."
                    }
                }
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func buildTopologyTree(nodes: [NodeEntry], rootId: UInt32) -> [MeshData.TopologyNode] {
        var visited = Set<UInt32>()
        visited.insert(rootId)
        
        func traverse(nodeId: UInt32) -> MeshData.TopologyNode {
            let nodeEntry = nodes.first(where: { $0.id == nodeId })
            let neighbors = nodeEntry?.neighbors ?? []
            
            var subs: [MeshData.TopologyNode] = []
            for neighId in neighbors {
                if !visited.contains(neighId) {
                    visited.insert(neighId)
                    subs.append(traverse(nodeId: neighId))
                }
            }
            return MeshData.TopologyNode(nodeId: nodeId, subs: subs.isEmpty ? nil : subs)
        }
        
        let rootNode = traverse(nodeId: rootId)
        return rootNode.subs ?? []
    }
}

// MARK: - CoreBluetooth Delegates
extension MeshManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                print("[MeshManager] Bluetooth Powered On")
                self.errorMessage = nil
                self.startScanning()
            default:
                print("[MeshManager] Bluetooth Unavailable: \(central.state.rawValue)")
                self.isConnected = false
                self.isScanning = false
                
                let stateString: String
                switch central.state {
                case .poweredOff:
                    stateString = "Bluetooth turned OFF"
                case .unauthorized:
                    stateString = "Bluetooth permission denied. Please authorize Bluetooth in System Settings."
                case .unsupported:
                    stateString = "Bluetooth is unsupported or restricted by App Sandbox."
                case .resetting:
                    stateString = "Bluetooth is resetting..."
                default:
                    stateString = "Bluetooth is unavailable (State \(central.state.rawValue))."
                }
                self.errorMessage = stateString
                if self.centralManager != nil {
                    self.centralManager.stopScan()
                }
                self.nodesList.removeAll()
                self.discoveredNodes.removeAll()
                self.localNodeId = nil
                self.localNodeNickname = "Unknown"
                self.meshData = nil
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
            let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            
            // Check if it is a MeshOS node (by name prefix or by service UUID)
            guard name.hasPrefix("MeshOS_") || uuids.contains(self.serviceUUID) else {
                return
            }
            
            // Cancel scan timeout since we found a node
            self.scanTimeoutTask?.cancel()
            self.scanTimeoutTask = nil
            self.scanDidTimeout = false
            
            let displayName = name.hasPrefix("MeshOS_") ? name : "Mesh Node (\(peripheral.identifier.uuidString.prefix(4)))"
            
            let node = DiscoveredNode(id: peripheral.identifier, peripheral: peripheral, name: displayName, rssi: RSSI.intValue)
            if let idx = self.discoveredNodes.firstIndex(where: { $0.id == node.id }) {
                // Keep the fully loaded name if we already resolved it, otherwise update
                let existingName = self.discoveredNodes[idx].name
                let finalName = existingName.hasPrefix("MeshOS_") ? existingName : displayName
                self.discoveredNodes[idx] = DiscoveredNode(id: node.id, peripheral: node.peripheral, name: finalName, rssi: node.rssi)
            } else {
                self.discoveredNodes.append(node)
            }
            
            // Attempt auto-reconnect to the last connected peripheral
            self.attemptAutoReconnect(for: peripheral)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            // Ignore connections for peripherals we didn't initiate
            if let target = self.targetPeripheral, target.identifier != peripheral.identifier {
                print("[MeshManager] Ignoring unexpected didConnect for \(peripheral.name ?? "Unknown")")
                central.cancelPeripheralConnection(peripheral)
                return
            }
            print("[MeshManager] Connected to \(peripheral.name ?? "Node"). Initiating service discovery...")
            // Stop any ongoing scanning/reconnect tasks now that we have a connection
            self.reconnectScanTask?.cancel()
            self.reconnectScanTask = nil
            self.scanTimeoutTask?.cancel()
            self.scanTimeoutTask = nil
            if self.centralManager.state == .poweredOn {
                self.centralManager.stopScan()
            }
            self.isScanning = false
            self.isAutoReconnecting = false
            self.isConnected = false
            self.isLoading = true
            self.targetPeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([self.serviceUUID])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[MeshManager] Connection failed: \(error?.localizedDescription ?? "unknown")")
            self.errorMessage = error?.localizedDescription ?? "Connection failed"
            self.isLoading = false
            self.isAutoReconnecting = false
            self.isConnected = false
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[MeshManager] Disconnected from node: \(error?.localizedDescription ?? "normal")")
            // Cancel any in-progress OTA update
            if self.isUpdatingOTA {
                self.otaTask?.cancel()
                self.otaTask = nil
                self.isUpdatingOTA = false
                self.otaStatusMessage = "OTA update cancelled — node disconnected"
                // Resume any pending OTA write continuation so the loop can exit cleanly
                if let continuation = self.otaWriteContinuation {
                    self.otaWriteContinuation = nil
                    continuation.resume(throwing: CancellationError())
                }
            }
            self.isConnected = false
            self.isLoading = false
            self.isSyncingMessages = false
            self.isAutoReconnecting = false
            self.targetPeripheral = nil
            self.statusCharacteristic = nil
            self.peersCharacteristic = nil
            self.chatCharacteristic = nil
            self.cmdCharacteristic = nil
            self.ecdhCharacteristic = nil
            self.otaCharacteristic = nil
            self.sessionKey = nil
            self.selectedBinURL = nil
            self.selectedBinData = nil
            self.nodesList.removeAll()
            // Keep discoveredNodes so the disconnected node remains visible for reconnection.
            // Restart scanning; the previously connected node should be re-discovered quickly
            // since the firmware starts re-advertising after disconnect.
            // Only restart scanning if we have a remembered peripheral to reconnect to
            if central.state == .poweredOn, self.lastConnectedPeripheralID != nil {
                self.isScanning = false
                self.centralManager.stopScan()
                self.reconnectScanTask?.cancel()
                self.reconnectScanTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000) // 500ms — firmware has 200ms re-advert delay
                        guard let self = self, !Task.isCancelled,
                              !self.isLoading, !self.isConnected,
                              self.centralManager.state == .poweredOn else { return }
                        self.centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                        self.isScanning = true
                        print("[MeshManager] Restarted scanning for reconnection...")
                    } catch {
                        // Cancelled, exit cleanly
                    }
                }
            }
            self.localNodeId = nil
            self.localNodeNickname = "Unknown"
            self.meshData = nil
        }
    }
}

extension MeshManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let err = error {
                print("[MeshManager] Service discovery error: \(err.localizedDescription)")
                return
            }
            guard let services = peripheral.services else { return }
            for service in services {
                if service.uuid == self.serviceUUID {
                    peripheral.discoverCharacteristics([self.statusUUID, self.peersUUID, self.chatUUID, self.cmdUUID, self.ecdhUUID, self.otaUUID], for: service)
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let err = error {
                print("[MeshManager] Characteristic discovery error: \(err.localizedDescription)")
                return
            }
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                switch characteristic.uuid {
                case self.statusUUID:
                    self.statusCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                case self.peersUUID:
                    self.peersCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                case self.chatUUID:
                    self.chatCharacteristic = characteristic
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                case self.cmdUUID:
                    self.cmdCharacteristic = characteristic
                case self.ecdhUUID:
                    self.ecdhCharacteristic = characteristic
                    self.performHandshake(peripheral: peripheral)
                case self.otaUUID:
                    self.otaCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    break
                }
            }
            
            // MTU exchange has completed by now — query the negotiated max write length
            let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
            self.maxWriteLength = mtu > 0 ? mtu : 512
            print("[MeshManager] Negotiated maxWriteLength: \(self.maxWriteLength) bytes")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let err = error {
                print("[MeshManager] Value update error on \(characteristic.uuid): \(err.localizedDescription)")
                return
            }
            guard let data = characteristic.value else { return }
            switch characteristic.uuid {
            case self.statusUUID:
                self.parseStatusData(data)
            case self.peersUUID:
                self.parsePeersData(data)
            case self.chatUUID:
                self.parseChatNotification(data)
            case self.ecdhUUID:
                self.parseECDHData(data)
            case self.otaUUID:
                self.parseOTAData(data)
            default:
                break
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let err = error {
                print("[MeshManager] Write error on \(characteristic.uuid): \(err.localizedDescription)")
                // Forward error to OTA continuation if waiting
                if characteristic.uuid == self.otaUUID, let continuation = self.otaWriteContinuation {
                    self.otaWriteContinuation = nil
                    continuation.resume(throwing: err)
                }
                return
            }
            if characteristic.uuid == self.ecdhUUID {
                print("[MeshManager] Client public key written successfully. Waiting for node to complete ECDH...")
                // Give the node 500ms to finish heavy ECC processing before we read back its key
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    peripheral.readValue(for: characteristic)
                }
            } else if characteristic.uuid == self.otaUUID {
                // Resume OTA flow control continuation
                if let continuation = self.otaWriteContinuation {
                    self.otaWriteContinuation = nil
                    continuation.resume()
                }
            }
        }
    }
}

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= self.count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= self.count else { return 0 }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }
}

extension MeshManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

