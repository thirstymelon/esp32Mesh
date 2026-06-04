import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool

    var body: some View {
        ZStack {
            AppBackground()
            
            if meshManager.isConnected, let data = meshManager.meshData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section: Diagnostics
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SYSTEM DIAGNOSTICS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(1)
                                .padding(.horizontal, 4)
                            
                            HStack(spacing: 8) {
                                MiniMetricCard(title: "Active Nodes", value: "\(data.nodeCount)", icon: "cpu", tint: AppPalette.cyan)
                                MiniMetricCard(title: "Total Messages", value: "\(data.messages.count)", icon: "message.fill", tint: AppPalette.violet)
                                MiniMetricCard(title: "Direct Peers", value: "\(data.peers.count)", icon: "antenna.radiowaves.left.and.right", tint: AppPalette.ok)
                            }
                        }
                        
                        // Section: Connected Nodes List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONNECTED NODES LIST")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(1)
                                .padding(.horizontal, 4)
                            
                            ForEach(meshManager.activeNodes, id: \.id) { node in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Node info header
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
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            } icon: {
                                                Image(systemName: batteryIcon(for: batt))
                                            }
                                            .foregroundStyle(batt <= 20 ? AppPalette.error : AppPalette.ok)
                                        }
                                        
                                        if let uptime = node.uptime {
                                            Label {
                                                Text(formatUptime(uptime))
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                                                        let neighNick: String = data.nicknames.first(where: { $0.id == String(neighId) })?.nick ?? String(String(format: "%08X", neighId).prefix(6))
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
                                .padding(.all, 14)
                                .meshGlass(cornerRadius: 16)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .refreshable {
                    await meshManager.fetchData()
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 48))
                        .foregroundStyle(AppPalette.dimText)
                    Text("Offline")
                        .font(.headline)
                    Text("Connect to a BLE node to view the network layout.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.dimText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Network Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ConnectionBadgeButton(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
        }
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

    private func formatUptime(_ micros: Int64) -> String {
        let secs = micros / 1_000_000
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

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
