//
//  NetworkView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var meshManager: MeshManager

    var body: some View {
        VStack(spacing: 0) {
            Text("Network")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 14)

            if let data = meshManager.meshData {
                HStack {
                    HStack(spacing: 0) {
                        Text("Node: ")
                        Text(displayName(for: data.nodeId))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        Text("Peers: ")
                        Text("\(data.peers.count)")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                .font(.system(size: 12))
                .tracking(0.5)
                .foregroundStyle(AppPalette.dimText)
                .padding(.bottom, 12)
            } else {
                HStack {
                    HStack(spacing: 0) {
                        Text("Node: ")
                        Text("-")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        Text("Peers: ")
                        Text("0")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                .font(.system(size: 12))
                .tracking(0.5)
                .foregroundStyle(AppPalette.dimText)
                .padding(.bottom, 12)
            }

            if meshManager.isConnected, let data = meshManager.meshData {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            MetricCard(title: "Nodes", value: "\(data.nodeCount)", tint: AppPalette.cyan)
                            MetricCard(title: "Messages", value: "\(data.messages.count)", tint: AppPalette.violet)
                            MetricCard(title: "Peers", value: "\(data.peers.count)", tint: AppPalette.ok)
                        }

                        DetailPanel(data: data, nickname: meshManager.currentNodeNickname)

                        TopologyPanel(nodes: data.topology?.subs ?? [])
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
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Not Connected",
                    message: "Connect to a mesh node to inspect network topology."
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

    private func displayName(for nodeId: String) -> String {
        meshManager.meshData?.nicknames.first(where: { $0.id == nodeId })?.nick ?? String(nodeId.prefix(6))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11))
                .tracking(0.5)
                .foregroundStyle(AppPalette.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

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
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
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

struct TopologyPanel: View {
    let nodes: [MeshData.TopologyNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topology")
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
