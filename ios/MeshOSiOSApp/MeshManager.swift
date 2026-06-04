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
        }

        init(sender: String, dest: String, text: String, ts: Int64, dm: Bool, me: Bool, sessionId: UInt16 = 0, seq: UInt16 = 0, delivered: Bool = true, channelId: UInt8 = 0, isMedia: Bool = false, mediaPath: String? = nil, mediaName: String? = nil) {
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
    @Published var discoveredNodes: [DiscoveredNode] = []
    @Published var meshData: MeshData?
    @Published var errorMessage: String?
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var isSyncingMessages = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    // CoreBluetooth properties
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    
    // GATT Characteristics
    private let serviceUUID = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000000")
    private let statusUUID  = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000001")
    private let peersUUID   = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000002")
    private let chatUUID    = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000003")
    private let cmdUUID     = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000004")
    private let ecdhUUID    = CBUUID(string: "DECAFBAD-CAFE-4BEE-B00B-000000000005")

    private var statusCharacteristic: CBCharacteristic?
    private var peersCharacteristic: CBCharacteristic?
    private var chatCharacteristic: CBCharacteristic?
    private var cmdCharacteristic: CBCharacteristic?
    private var ecdhCharacteristic: CBCharacteristic?

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
    
    @Published var telemetryHistory: [TelemetryDataPoint] = []
    @Published var networkHistory: [NetworkSnapshotPoint] = []

    // Security
    private var sessionKey: SymmetricKey?
    private var myPrivateKey = P256.KeyAgreement.PrivateKey()

    
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
        guard centralManager.state == .poweredOn else {
            let stateString: String
            switch centralManager.state {
            case .poweredOff:
                stateString = "Bluetooth is turned OFF. Please enable Bluetooth in System Settings."
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
            return
        }
        errorMessage = nil
        isScanning = true
        discoveredNodes.removeAll()
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        print("[MeshManager] Started scanning for MeshOS nodes...")
    }
    
    func stopScanning() {
        isScanning = false
        if centralManager != nil && centralManager.state == .poweredOn {
            centralManager.stopScan()
        }
        print("[MeshManager] Stopped scanning.")
    }
    
    // MARK: - Connection
    func connect(to node: DiscoveredNode) {
        stopScanning()
        isLoading = true
        errorMessage = nil
        targetPeripheral = node.peripheral
        targetPeripheral?.delegate = self
        centralManager.connect(node.peripheral, options: nil)
        print("[MeshManager] Connecting to \(node.name)...")
    }
    
    // compatibility function for original view logic if needed
    func connect(to ip: String) async {
        // Since we are no longer using IP, scan for matching nodes instead
        errorMessage = "BLE mode active. Please select a node from the list."
    }
    
    func disconnect() {
        if let p = targetPeripheral {
            centralManager.cancelPeripheralConnection(p)
        } else {
            isConnected = false
            meshData = nil
        }
        print("[MeshManager] Manually disconnected")
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
        guard data.count == 65 else { return }
        let peerPubData = data.dropFirst() // remove 0x04
        do {
            let peerPub = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPubData)
            let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPub)
            let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 16)
            self.sessionKey = derivedKey
            print("[MeshManager] ECDH Handshake successful. Session key derived.")
            
            // Trigger historical sync after secure link is up
            self.syncTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.syncMessages()
            }
        } catch {
            print("[MeshManager] ECDH Handshake failed: \(error.localizedDescription)")
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
            messagesList.append(newMessage)
            updateMeshData()
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
            let neighborsCount = data[offset + 25]
            offset += 26
            
            var neighbors: [UInt32] = []
            for _ in 0..<neighborsCount {
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
            let battVal   = data[12]
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
        
        let isMe = String(senderId) == self.localNodeId
        let isDm = (flagsVal & 2) != 0
        
        // File sharing removed
        
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
            messagesList.append(newMessage)
            // Cap the in-memory list to 200 messages to prevent unbounded RAM growth
            if messagesList.count > 200 {
                messagesList.removeFirst(messagesList.count - 200)
            }
            updateMeshData()
            
            if !isMe {
                Haptics.impact(.light)
                showNotification(for: newMessage)
            }
        }
    }

    private func showNotification(for message: MeshData.Message) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            let senderNick = self.meshData?.nicknames.first(where: { $0.id == message.sender })?.nick ?? "Unknown"
            content.title = message.dm ? "New DM from \(senderNick)" : "Mesh Broadcast"
            content.body = message.text
            content.sound = .default

            let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
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

    private func saveLocalData() {
        guard let data = meshData else { return }
        do {
            let dataToSave = MeshData(
                nodeId: data.nodeId,
                nodeCount: data.nodeCount,
                meshTime: data.meshTime,
                topology: data.topology,
                peers: data.peers,
                nicknames: data.nicknames,
                messages: [] // DO NOT SAVE MESSAGE HISTORY TO DISK
            )
            let encoded = try JSONEncoder().encode(dataToSave)
            try encoded.write(to: persistenceURL)
        } catch {
            print("[MeshManager] Failed to save local data: \(error)")
        }
    }

    private func loadLocalData() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode(MeshData.self, from: data)
            self.meshData = decoded
            self.messagesList = [] // Do not load message history from disk
            self.localNodeId = decoded.nodeId
            print("[MeshManager] Loaded local configuration.")
        } catch {
            print("[MeshManager] No local data found or corrupted.")
        }
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
                    stateString = "Bluetooth is turned OFF. Please enable Bluetooth in System Settings."
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
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown Node"
            
            // Since we scan with serviceUUID filter, any discovered node is our MeshOS node.
            // If the name is not yet loaded, show placeholder with truncated UUID.
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
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            print("[MeshManager] Connected to \(peripheral.name ?? "Node")")
            self.isConnected = true
            self.isLoading = false
            // Request a larger ATT MTU so the large peers/chat payloads fit in fewer round trips
            peripheral.maximumWriteValueLength(for: .withResponse)
            peripheral.discoverServices([self.serviceUUID])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[MeshManager] Connection failed: \(error?.localizedDescription ?? "unknown")")
            self.errorMessage = error?.localizedDescription ?? "Connection failed"
            self.isLoading = false
            self.isConnected = false
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            print("[MeshManager] Disconnected from node: \(error?.localizedDescription ?? "normal")")
            self.isConnected = false
            self.isLoading = false
            self.isSyncingMessages = false
            self.targetPeripheral = nil
            self.statusCharacteristic = nil
            self.peersCharacteristic = nil
            self.chatCharacteristic = nil
            self.cmdCharacteristic = nil
            self.messagesList.removeAll()
            self.updateMeshData()
            self.startScanning()
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
                    peripheral.discoverCharacteristics([self.statusUUID, self.peersUUID, self.chatUUID, self.cmdUUID, self.ecdhUUID], for: service)
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
                default:
                    break
                }
            }
            
            // Trigger time synchronization immediately
            self.syncTime()
            
            // Trigger message history sync 1 second after characteristics are ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.syncMessages()
            }
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
            default:
                break
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let err = error {
                print("[MeshManager] Write error on \(characteristic.uuid): \(err.localizedDescription)")
                return
            }
            if characteristic.uuid == self.ecdhUUID {
                print("[MeshManager] Client public key written successfully. Now reading server public key...")
                peripheral.readValue(for: characteristic)
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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

