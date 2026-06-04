//
//  NetworkView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct NodeLayoutInfo: Identifiable {
    let id: String
    let name: String
    let position: CGPoint // Normalized coordinate in range [-0.9, 0.9]
    let color: Color
    let isOnline: Bool
    let isSelf: Bool
}

struct NetworkView: View {
    @EnvironmentObject var meshManager: MeshManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Network Map")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Interactive live mesh topology and routing telemetry")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.dimText)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            if meshManager.isConnected, let data = meshManager.meshData {
                ScrollView {
                    VStack(spacing: 20) {
                        // Diagnostics Row (iOS Style)
                        HStack(spacing: 12) {
                            MiniMetricCard(title: "Active Nodes", value: "\(data.nodeCount)", icon: "cpu", tint: AppPalette.cyan)
                            MiniMetricCard(title: "Total Messages", value: "\(data.messages.count)", icon: "message.fill", tint: AppPalette.violet)
                            MiniMetricCard(title: "Direct Peers", value: "\(data.peers.count)", icon: "antenna.radiowaves.left.and.right", tint: AppPalette.ok)
                        }

                        // Metal Topology Map (macOS exclusive)
                        MetalTopologyMapPanel()
                            .frame(maxWidth: .infinity)

                        // Connected Nodes List (iOS style)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("CONNECTED NODES LIST")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppPalette.dimText)
                                    .tracking(1)
                                Spacer()
                            }
                            .padding(.horizontal, 4)

                            ForEach(meshManager.activeNodes, id: \.id) { node in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Node header
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(NodeColor.color(for: String(node.id)))
                                            .frame(width: 32, height: 32)
                                            .overlay {
                                                Text(String(node.nickname.prefix(1)))
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.black)
                                            }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(node.nickname)
                                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                
                                                if String(node.id) == data.nodeId {
                                                    Text("Local Gateway")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(AppPalette.cyan.opacity(0.15), in: Capsule())
                                                        .overlay {
                                                            Capsule()
                                                                .strokeBorder(AppPalette.cyan.opacity(0.3), lineWidth: 1)
                                                        }
                                                        .foregroundStyle(AppPalette.cyan)
                                                }
                                            }
                                            
                                            Text("ID: 0x\(String(format: "%08X", node.id))")
                                                  .font(.system(size: 10, design: .monospaced))
                                                  .foregroundStyle(AppPalette.dimText)
                                        }
                                        
                                        Spacer()
                                        
                                        Circle()
                                            .fill(node.isOnline ? AppPalette.ok : AppPalette.error)
                                            .frame(width: 8, height: 8)
                                    }
                                    
                                    Divider()
                                        .overlay(.white.opacity(0.08))
                                    
                                    // Node stats
                                    HStack(spacing: 20) {
                                        if let batt = node.battery {
                                            Label {
                                                Text("\(batt)%")
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            } icon: {
                                                Image(systemName: batteryIcon(for: batt))
                                            }
                                            .foregroundStyle(batt <= 20 ? AppPalette.error : AppPalette.ok)
                                        }
                                        
                                        if let uptime = node.uptime {
                                            Label {
                                                Text(formatUptime(uptime))
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            } icon: {
                                                Image(systemName: "clock")
                                            }
                                            .foregroundStyle(AppPalette.dimText)
                                        }
                                    }
                                    
                                    if !node.neighbors.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Direct Connections:")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(AppPalette.dimText)
                                            
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 6) {
                                                    ForEach(node.neighbors, id: \.self) { neighId in
                                                        let neighNick = data.nicknames.first(where: { $0.id == String(neighId) })?.nick ?? String(String(format: "%08X", neighId).prefix(6))
                                                        Text(neighNick)
                                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(.white.opacity(0.08), in: Capsule())
                                                            .overlay {
                                                                Capsule()
                                                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                                            }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding()
                                .meshGlass(cornerRadius: 16)
                            }
                        }

                        DetailPanel(data: data, nickname: meshManager.currentNodeNickname)

                        TopologyPanel(nodes: data.topology?.subs ?? [])
                    }
                    .padding(.bottom, 24)
                }
            } else {
                EmptyStateView(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Not Connected",
                    message: "Connect to a mesh node to inspect network topology."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...70: return "battery.50percent"
        case 71...95: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let secs = seconds > 1_000_000 ? seconds / 1_000_000 : seconds
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Metal Map Panel
struct MetalTopologyMapPanel: View {
    @EnvironmentObject var meshManager: MeshManager
    @StateObject private var simulation = PhysicsSimulation()
    private let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interactive Topology Map")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(AppPalette.dimText)

            let nodes = meshManager.activeNodes
            let layout = simulation.nodeLayouts

            if layout.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppPalette.dimText)
                    Text("Calculating topology layouts...")
                        .font(.system(size: 13))
                        .foregroundStyle(AppPalette.dimText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .meshGlass(cornerRadius: 16)
                .onAppear {
                    if let data = meshManager.meshData {
                        simulation.tick(nodes: meshManager.activeNodes, localIdStr: data.nodeId)
                    }
                }
                .onReceive(timer) { _ in
                    if let data = meshManager.meshData {
                        simulation.tick(nodes: meshManager.activeNodes, localIdStr: data.nodeId)
                    }
                }
            } else {
                GeometryReader { geo in
                    ZStack {
                        // Metal renderer view
                        MetalTopologyView(nodeLayouts: layout, activeNodes: nodes, messages: meshManager.meshData?.messages ?? [])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(16)

                        // SwiftUI overlays (node labels positioned based on Layout coordinates)
                        ForEach(layout) { item in
                            // Map coordinate space [-1, 1] to view size [0, width/height]
                            let x = (item.position.x + 1.0) / 2.0 * geo.size.width
                            let y = (1.0 - item.position.y) / 2.0 * geo.size.height

                            VStack(spacing: 3) {
                                Text(item.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(item.color.opacity(0.85), lineWidth: 1.5)
                                    )
                                
                                Text(String(item.id.prefix(6)))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            .position(x: x, y: y + 26) // offset label below dot
                        }
                    }
                }
                .frame(height: 380)
                .meshGlass(cornerRadius: 16)
                .onReceive(timer) { _ in
                    if let data = meshManager.meshData {
                        simulation.tick(nodes: meshManager.activeNodes, localIdStr: data.nodeId)
                    }
                }
            }
        }
    }
}

// MARK: - Mini Metric Card (Aligned with iOS)
struct MiniMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppPalette.dimText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppPalette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

// MARK: - Detail Panel
struct DetailPanel: View {
    let data: MeshData
    let nickname: String

    var body: some View {
        VStack(spacing: 9) {
            DetailRow(label: "Node ID", value: data.nodeId)
            DetailRow(label: "Nickname", value: nickname)
            DetailRow(label: "Mesh Time", value: formatMeshTime(data.meshTime))
            DetailRow(label: "Direct Peers", value: "\(data.peers.count)")
        }
        .padding(14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }

    private func formatMeshTime(_ microseconds: Int64?) -> String {
        guard let microseconds else { return "--:--:--" }

        let seconds = microseconds / 1_000_000
        if seconds > 1_000_000_000 {
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .none
            return formatter.string(from: date)
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let secs = seconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(AppPalette.dimText)

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Text Topology Panel
struct TopologyPanel: View {
    let nodes: [MeshData.TopologyNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topology Tree Explorer")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(AppPalette.dimText)

            if nodes.isEmpty {
                Text("No topology data reported by this node.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppPalette.dimText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(nodes, id: \.nodeId) { node in
                    TopologyNodeView(node: node)
                }
            }
        }
        .padding(14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

struct TopologyNodeView: View {
    let node: MeshData.TopologyNode
    @EnvironmentObject var meshManager: MeshManager
    @State private var isExpanded = true

    var nickname: String {
        let nodeIdString = String(node.nodeId)
        return meshManager.meshData?.nicknames.first(where: { $0.id == nodeIdString })?.nick ?? String(nodeIdString.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let subs = node.subs, !subs.isEmpty {
                    Button(isExpanded ? "-" : "+") {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.dimText)
                    .frame(width: 14)
                } else {
                    Circle()
                        .fill(AppPalette.dimText)
                        .frame(width: 5, height: 5)
                        .frame(width: 14)
                }

                Circle()
                    .fill(NodeColor.color(for: String(node.nodeId)))
                    .frame(width: 9, height: 9)

                Text(nickname)
                    .font(.system(size: 13, weight: .medium))

                Text(String(node.nodeId))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppPalette.dimText)
            }

            if isExpanded, let subs = node.subs, !subs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(subs, id: \.nodeId) { subNode in
                        TopologyNodeView(node: subNode)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }
}

// MARK: - Force-Directed Physics Simulation Engine
class PhysicsSimulation: ObservableObject {
    @Published var nodeLayouts: [NodeLayoutInfo] = []
    private var velocities: [String: CGPoint] = [:]
    
    func tick(nodes: [NodeEntry], localIdStr: String) {
        guard !nodes.isEmpty else { return }
        
        let kRepel: CGFloat = 0.003
        let kSpring: CGFloat = 0.08
        let restLength: CGFloat = 0.4
        let kGravity: CGFloat = 0.03
        let damping: CGFloat = 0.85
        let dt: CGFloat = 0.1
        
        var currentLayouts = nodeLayouts
        
        // Remove offline or missing nodes
        currentLayouts = currentLayouts.filter { layout in
            nodes.contains(where: { String($0.id) == layout.id }) || layout.id == localIdStr
        }
        
        // Add new nodes
        for node in nodes {
            let idStr = String(node.id)
            if !currentLayouts.contains(where: { $0.id == idStr }) {
                let isSelf = idStr == localIdStr
                let pos = isSelf ? CGPoint.zero : CGPoint(x: CGFloat.random(in: -0.2...0.2), y: CGFloat.random(in: -0.2...0.2))
                currentLayouts.append(NodeLayoutInfo(
                    id: idStr,
                    name: node.nickname,
                    position: pos,
                    color: isSelf ? AppPalette.cyan : NodeColor.color(for: idStr),
                    isOnline: node.isOnline,
                    isSelf: isSelf
                ))
                velocities[idStr] = CGPoint.zero
            } else {
                if let idx = currentLayouts.firstIndex(where: { $0.id == idStr }) {
                    let old = currentLayouts[idx]
                    currentLayouts[idx] = NodeLayoutInfo(
                        id: old.id,
                        name: node.nickname,
                        position: old.position,
                        color: old.color,
                        isOnline: node.isOnline,
                        isSelf: old.isSelf
                    )
                }
            }
        }
        
        // Ensure local node is added
        if !currentLayouts.contains(where: { $0.id == localIdStr }) {
            currentLayouts.append(NodeLayoutInfo(
                id: localIdStr,
                name: "Local Gateway",
                position: CGPoint.zero,
                color: AppPalette.cyan,
                isOnline: true,
                isSelf: true
            ))
            velocities[localIdStr] = CGPoint.zero
        }
        
        // Compute forces
        var forces: [String: CGPoint] = [:]
        for layout in currentLayouts {
            forces[layout.id] = CGPoint.zero
        }
        
        // Repulsion force
        for i in 0..<currentLayouts.count {
            let layoutA = currentLayouts[i]
            for j in 0..<currentLayouts.count {
                if i == j { continue }
                let layoutB = currentLayouts[j]
                
                let dx = layoutA.position.x - layoutB.position.x
                let dy = layoutA.position.y - layoutB.position.y
                let dist = sqrt(dx*dx + dy*dy)
                let safeDist = max(dist, 0.05)
                
                if safeDist < 0.9 {
                    let force = kRepel / (safeDist * safeDist)
                    forces[layoutA.id]?.x += (dx / safeDist) * force
                    forces[layoutA.id]?.y += (dy / safeDist) * force
                }
            }
        }
        
        // Spring attraction force
        for node in nodes {
            let idStr = String(node.id)
            guard let layoutA = currentLayouts.first(where: { $0.id == idStr }) else { continue }
            
            for neighborId in node.neighbors {
                let neighIdStr = String(neighborId)
                guard let layoutB = currentLayouts.first(where: { $0.id == neighIdStr }) else { continue }
                
                let dx = layoutB.position.x - layoutA.position.x
                let dy = layoutB.position.y - layoutA.position.y
                let dist = sqrt(dx*dx + dy*dy)
                let safeDist = max(dist, 0.05)
                
                let force = kSpring * (safeDist - restLength)
                forces[idStr]?.x += (dx / safeDist) * force
                forces[idStr]?.y += (dy / safeDist) * force
            }
        }
        
        // Gravity force (pull to center)
        for layout in currentLayouts {
            forces[layout.id]?.x -= layout.position.x * kGravity
            forces[layout.id]?.y -= layout.position.y * kGravity
        }
        
        // Update positions
        for idx in 0..<currentLayouts.count {
            let layout = currentLayouts[idx]
            let force = forces[layout.id] ?? CGPoint.zero
            var vel = velocities[layout.id] ?? CGPoint.zero
            
            if layout.isSelf {
                currentLayouts[idx] = NodeLayoutInfo(
                    id: layout.id,
                    name: layout.name,
                    position: CGPoint.zero,
                    color: layout.color,
                    isOnline: layout.isOnline,
                    isSelf: true
                )
                continue
            }
            
            vel.x = (vel.x + force.x) * damping
            vel.y = (vel.y + force.y) * damping
            velocities[layout.id] = vel
            
            var newX = layout.position.x + vel.x * dt
            var newY = layout.position.y + vel.y * dt
            
            newX = max(min(newX, 0.85), -0.85)
            newY = max(min(newY, 0.85), -0.85)
            
            currentLayouts[idx] = NodeLayoutInfo(
                id: layout.id,
                name: layout.name,
                position: CGPoint(x: newX, y: newY),
                color: layout.color,
                isOnline: layout.isOnline,
                isSelf: false
            )
        }
        
        self.nodeLayouts = currentLayouts
    }
}
