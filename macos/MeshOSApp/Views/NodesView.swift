//
//  NodesView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct NodesView: View {
    @EnvironmentObject var meshManager: MeshManager

    var allNodes: [NodeInfo] {
        guard let data = meshManager.meshData else { return [] }

        var nodes: [NodeInfo] = []
        let selfNick = data.nicknames.first(where: { $0.id == data.nodeId })?.nick ?? "This Mac"
        
        let selfEntry = meshManager.activeNodes.first(where: { String($0.id) == data.nodeId })
        nodes.append(NodeInfo(id: data.nodeId, nickname: selfNick, isSelf: true, isOnline: true, battery: selfEntry?.battery, uptime: selfEntry?.uptime))

        for peerId in data.peers {
            let nick = data.nicknames.first(where: { $0.id == peerId })?.nick ?? "Node \(peerId.prefix(6))"
            let entry = meshManager.activeNodes.first(where: { String($0.id) == peerId })
            nodes.append(NodeInfo(id: peerId, nickname: nick, isSelf: false, isOnline: true, battery: entry?.battery, uptime: entry?.uptime))
        }

        for nickname in data.nicknames where !nodes.contains(where: { $0.id == nickname.id }) {
            let entry = meshManager.activeNodes.first(where: { String($0.id) == nickname.id })
            nodes.append(NodeInfo(id: nickname.id, nickname: nickname.nick, isSelf: false, isOnline: false, battery: entry?.battery, uptime: entry?.uptime))
        }

        return nodes.sorted {
            if $0.isOnline != $1.isOnline { return $0.isOnline && !$1.isOnline }
            if $0.isSelf != $1.isSelf { return $0.isSelf && !$1.isSelf }
            return $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Nodes")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 14)

            HStack {
                HStack(spacing: 0) {
                    Text("Online: ")
                    Text("\(allNodes.filter { $0.isOnline }.count)")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                Spacer()
                HStack(spacing: 0) {
                    Text("Total: ")
                    Text("\(allNodes.count)")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .font(.system(size: 12))
            .tracking(0.5)
            .foregroundStyle(AppPalette.dimText)
            .padding(.bottom, 12)

            if meshManager.isConnected {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(allNodes) { node in
                            NodeRow(node: node)
                        }
                    }
                    .padding(14)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppPalette.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                EmptyStateView(
                    icon: "person.2",
                    title: "Not Connected",
                    message: "Connect to a mesh node to view online and saved nodes."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppPalette.border, lineWidth: 1)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Node Info Model
struct NodeInfo: Identifiable {
    let id: String
    let nickname: String
    let isSelf: Bool
    let isOnline: Bool
    let battery: Int?
    let uptime: Int64?
}

struct NodeRow: View {
    let node: NodeInfo

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(NodeColor.color(for: node.id))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.nickname)
                        .font(.system(size: 14, weight: .semibold))
                    if node.isSelf {
                        Text("SELF")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.dimText)
                    }
                    
                    if let batt = node.battery {
                        HStack(spacing: 3) {
                            Image(systemName: batt > 20 ? "battery.75" : "battery.25")
                            Text("\(batt)%")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(batt > 20 ? .green : .red)
                    }
                }

                HStack(spacing: 8) {
                    Text(node.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppPalette.dimText)
                    
                    if let uptime = node.uptime {
                        Text("up: \(uptime)s")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.dimText)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer()

            Text(node.isOnline ? "OK" : "ERR")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(node.isOnline ? AppPalette.ok : AppPalette.error)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NodeColor.color(for: node.id).opacity(0.55), lineWidth: 1)
        }
    }
}
