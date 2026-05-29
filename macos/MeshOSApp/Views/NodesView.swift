//
//  NodesView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct NodesView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var editingNodeId: String?
    @State private var editingNickname: String = ""

    var allNodes: [NodeInfo] {
        guard let data = meshManager.meshData else { return [] }

        var nodes: [NodeInfo] = []
        let selfNick = data.nicknames.first(where: { $0.id == data.nodeId })?.nick ?? "This Mac"
        nodes.append(NodeInfo(id: data.nodeId, nickname: selfNick, isSelf: true, isOnline: true))

        for peerId in data.peers {
            let nick = data.nicknames.first(where: { $0.id == peerId })?.nick ?? autoNickname(for: peerId)
            nodes.append(NodeInfo(id: peerId, nickname: nick, isSelf: false, isOnline: true))
        }

        for nickname in data.nicknames where !nodes.contains(where: { $0.id == nickname.id }) {
            nodes.append(NodeInfo(id: nickname.id, nickname: nickname.nick, isSelf: false, isOnline: false))
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
                            NodeRow(
                                node: node,
                                isEditing: editingNodeId == node.id,
                                editingNickname: $editingNickname,
                                onEdit: {
                                    editingNodeId = node.id
                                    editingNickname = node.nickname
                                },
                                onSave: { saveNickname(for: node) },
                                onCancel: { editingNodeId = nil }
                            )
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

    private func saveNickname(for node: NodeInfo) {
        let nickname = editingNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { return }

        Task {
            await meshManager.setNickname(nickname, for: node.id)
            editingNodeId = nil
        }
    }

    private func autoNickname(for nodeId: String) -> String {
        let adjectives = ["Swift", "Bold", "Bright", "Dark", "Fast", "Cool", "Sharp", "Wild", "Keen", "Calm"]
        let nouns = ["Fox", "Hawk", "Wolf", "Bear", "Lynx", "Kite", "Wren", "Crab", "Moth", "Ibis"]

        guard let id = UInt32(nodeId) else { return "Unknown" }
        return "\(adjectives[Int(id % 10)])\(nouns[Int((id >> 4) % 10)])"
    }
}

// MARK: - Node Info Model
struct NodeInfo: Identifiable {
    let id: String
    let nickname: String
    let isSelf: Bool
    let isOnline: Bool
}

struct NodeRow: View {
    let node: NodeInfo
    let isEditing: Bool
    @Binding var editingNickname: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(NodeColor.color(for: node.id))
                .frame(width: 10, height: 10)

            if isEditing {
                TextField("Nickname", text: $editingNickname)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
                    .overlay { Capsule().strokeBorder(AppPalette.border, lineWidth: 1) }
                    .onSubmit(onSave)

                Button("Save", action: onSave)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.dimText)
            } else {
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
                    }

                    Text(node.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppPalette.dimText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(node.isOnline ? "OK" : "ERR")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(node.isOnline ? AppPalette.ok : AppPalette.error)

                Button("Rename", action: onEdit)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.dimText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NodeColor.color(for: node.id).opacity(0.55), lineWidth: 1)
        }
    }
}
