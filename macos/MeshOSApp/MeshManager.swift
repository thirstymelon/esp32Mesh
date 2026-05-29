//
//  MeshManager.swift
//  Mesh OS - macOS Client
//

import Foundation
import Combine

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
        var id: String { "\(sender)-\(text.hashValue)-\(ts)-\(me)-\(dm)" }

        let sender: String
        let text: String
        let ts: Int64
        let dm: Bool
        let me: Bool

        enum CodingKeys: String, CodingKey {
            case sender
            case text
            case ts
            case dm
            case me
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            sender = try container.decodeIfPresent(String.self, forKey: .sender) ?? "Unknown"
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            ts = Self.decodeTimestamp(from: container) ?? 0
            dm = try container.decodeIfPresent(Bool.self, forKey: .dm) ?? false
            me = try container.decodeIfPresent(Bool.self, forKey: .me) ?? false
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

// MARK: - Raw Response (for debugging)
struct RawMeshResponse {
    let data: Data
    let string: String
}

// MARK: - Mesh Manager
@MainActor
class MeshManager: ObservableObject {
    @Published var isConnected = false
    @Published var meshData: MeshData?
    @Published var nodeIP: String = ""
    @Published var errorMessage: String?
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    
    var currentNodeNickname: String {
        guard let data = meshData else { return "Not Connected" }
        return data.nicknames.first(where: { $0.id == data.nodeId })?.nick ?? "Unknown"
    }
    
    // MARK: - Connection
    func connect(to ip: String) async {
        nodeIP = ip.trimmingCharacters(in: .whitespaces)
        
        guard !nodeIP.isEmpty else {
            errorMessage = "Please enter a valid IP address"
            return
        }
        
        // Add http:// if not present
        if !nodeIP.hasPrefix("http://") && !nodeIP.hasPrefix("https://") {
            nodeIP = "http://" + nodeIP
        }
        
        isLoading = true
        print("[MeshManager] Attempting to connect to: \(nodeIP)")
        
        // Test connection
        await fetchData()
        
        isLoading = false
        
        if meshData != nil {
            isConnected = true
            startPolling()
            print("[MeshManager] Connected successfully")
        } else {
            print("[MeshManager] Connection failed: \(errorMessage ?? "unknown error")")
        }
    }
    
    func disconnect() {
        stopPolling()
        isConnected = false
        meshData = nil
        errorMessage = nil
        lastUpdate = nil
        print("[MeshManager] Disconnected")
    }
    
    // MARK: - Data Fetching
    func fetchData() async {
        guard !nodeIP.isEmpty else { return }
        
        var urlString = nodeIP
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "data"
        
        print("[MeshManager] Fetching from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL: \(urlString)"
            print("[MeshManager] Invalid URL")
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from server"
                return
            }
            
            print("[MeshManager] HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                errorMessage = "Server returned status \(httpResponse.statusCode)"
                return
            }
            
            // Log raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[MeshManager] Raw JSON response: \(jsonString.prefix(500))...")
            }
            
            let decoder = JSONDecoder()
            meshData = try decoder.decode(MeshData.self, from: data)
            errorMessage = nil
            lastUpdate = Date()
            
            print("[MeshManager] Successfully parsed data. Messages: \(meshData?.messages.count ?? 0), Nodes: \(meshData?.nodeCount ?? 0)")
            
        } catch let decodingError as DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                errorMessage = "Missing key '\(key.stringValue)' in response"
                print("[MeshManager] Decoding error - missing key: \(key.stringValue), context: \(context)")
            case .typeMismatch(let type, let context):
                errorMessage = "Type mismatch for \(type)"
                print("[MeshManager] Decoding error - type mismatch: \(type), context: \(context)")
            case .valueNotFound(let type, let context):
                errorMessage = "Value not found for \(type)"
                print("[MeshManager] Decoding error - value not found: \(type), context: \(context)")
            case .dataCorrupted(let context):
                errorMessage = "Data corrupted"
                print("[MeshManager] Decoding error - data corrupted: \(context)")
            @unknown default:
                errorMessage = "Decoding error: \(decodingError.localizedDescription)"
            }
            if isConnected {
                disconnect()
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
            print("[MeshManager] Network error: \(error)")
            if isConnected {
                disconnect()
            }
        }
    }
    
    // MARK: - Send Message
    func sendMessage(_ text: String) async {
        guard !nodeIP.isEmpty, !text.isEmpty else { return }
        
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        var urlString = nodeIP
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "send?msg=\(encoded)"
        
        print("[MeshManager] Sending message to: \(urlString)")
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[MeshManager] Message sent successfully")
                // Wait a bit then refresh
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await fetchData()
            }
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("[MeshManager] Send error: \(error)")
        }
    }
    
    // MARK: - Set Nickname
    func setNickname(_ nickname: String, for nodeId: String) async {
        guard !nodeIP.isEmpty, !nickname.isEmpty else { return }
        
        let encoded = nickname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nickname
        var urlString = nodeIP
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "setnick?id=\(nodeId)&nick=\(encoded)"
        
        print("[MeshManager] Setting nickname: \(urlString)")
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[MeshManager] Nickname set successfully")
                // Wait a bit then refresh
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchData()
            }
        } catch {
            errorMessage = "Failed to set nickname: \(error.localizedDescription)"
            print("[MeshManager] Nickname error: \(error)")
        }
    }
    
    // MARK: - Polling
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchData()
            }
        }
        print("[MeshManager] Polling started")
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
