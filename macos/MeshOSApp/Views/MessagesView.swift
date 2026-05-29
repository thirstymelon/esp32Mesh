//
//  MessagesView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var messageText = ""

    var messages: [MeshData.Message] {
        meshManager.meshData?.messages ?? []
    }

    var nodes: [NodeInfo] {
        guard let data = meshManager.meshData else { return [] }

        var result: [NodeInfo] = []
        let selfNick = data.nicknames.first(where: { $0.id == data.nodeId })?.nick ?? "This Mac"
        result.append(NodeInfo(id: data.nodeId, nickname: selfNick, isSelf: true, isOnline: true))

        for peerId in data.peers {
            let nick = data.nicknames.first(where: { $0.id == peerId })?.nick ?? String(peerId.prefix(6))
            result.append(NodeInfo(id: peerId, nickname: nick, isSelf: false, isOnline: true))
        }

        for nickname in data.nicknames where !result.contains(where: { $0.id == nickname.id }) {
            result.append(NodeInfo(id: nickname.id, nickname: nickname.nick, isSelf: false, isOnline: false))
        }

        return result.sorted {
            if $0.isSelf != $1.isSelf { return $0.isSelf && !$1.isSelf }
            if $0.isOnline != $1.isOnline { return $0.isOnline && !$1.isOnline }
            return $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ChatHeader(messagesCount: messages.count, nodesCount: nodes.count)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    if meshManager.isConnected {
                        ChatTranscript(messages: messages)
                    } else {
                        EmptyChatPanel()
                    }

                    MessageComposer(messageText: $messageText) {
                        sendMessage()
                    }
                    .disabled(!meshManager.isConnected)
                    .opacity(meshManager.isConnected ? 1 : 0.45)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                NodesRail(nodes: nodes)
                    .frame(minWidth: 270, idealWidth: 270, maxWidth: 270, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageText = ""
        Task {
            await meshManager.sendMessage(text)
        }
    }
}

struct ChatHeader: View {
    @EnvironmentObject var meshManager: MeshManager
    let messagesCount: Int
    let nodesCount: Int

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Mesh Chat")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.dimText)
            }

            Spacer()

            HStack(spacing: 10) {
                HeaderMetric(label: "Messages", value: "\(messagesCount)", tint: AppPalette.cyan)
                HeaderMetric(label: "Nodes", value: "\(nodesCount)", tint: AppPalette.violet)
            }
        }
    }

    private var statusText: String {
        guard let data = meshManager.meshData else { return "Connect to a node to join the mesh." }
        let nickname = meshManager.currentNodeNickname == "Unknown" ? String(data.nodeId.prefix(6)) : meshManager.currentNodeNickname
        return "Node \(nickname) · \(data.nodeCount) peers"
    }
}

struct HeaderMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(AppPalette.dimText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1) }
    }
}

struct ChatTranscript: View {
    let messages: [MeshData.Message]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.visible)
            .background(AppPalette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppPalette.cyan.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onAppear {
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct EmptyChatPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppPalette.dimText)
            Text("No mesh connection")
                .font(.system(size: 15, weight: .semibold))
            Text("Use the floating control bar to connect to a nearby node.")
                .font(.system(size: 13))
                .foregroundStyle(AppPalette.dimText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppPalette.border, lineWidth: 1)
        }
    }
}

struct MessageComposer: View {
    @Binding var messageText: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Type message...", text: $messageText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(.black.opacity(0.35), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .onSubmit(onSend)

            Button(action: onSend) {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(AppPalette.cyan.opacity(0.22), lineWidth: 1) }
        .shadow(color: AppPalette.cyan.opacity(0.14), radius: 14, y: 5)
    }
}

struct NodesRail: View {
    let nodes: [NodeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nodes")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(nodes.filter { $0.isOnline }.count)/\(nodes.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.dimText)
            }

            if nodes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppPalette.dimText)
                    Text("No nodes yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppPalette.dimText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(nodes) { node in
                            NodeRailRow(node: node)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppPalette.violet.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: AppPalette.violet.opacity(0.12), radius: 16, y: 6)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
    }
}

struct NodeRailRow: View {
    let node: NodeInfo

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(NodeColor.color(for: node.id))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(String(node.nickname.prefix(1)))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                    }

                Circle()
                    .fill(node.isOnline ? AppPalette.ok : AppPalette.error)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(node.nickname)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if node.isSelf {
                        Text("YOU")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                    }
                }

                Text(String(node.id.prefix(8)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppPalette.dimText)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NodeColor.color(for: node.id).opacity(0.45), lineWidth: 1)
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: MeshData.Message
    @EnvironmentObject var meshManager: MeshManager

    var senderNickname: String {
        meshManager.meshData?.nicknames.first(where: { $0.id == message.sender })?.nick ?? String(message.sender.prefix(6))
    }

    var body: some View {
        HStack {
            if message.me {
                Spacer(minLength: 48)
            }

            Text(displayText)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(message.me ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.me
                    ? AnyShapeStyle(AppPalette.sentBubble)
                    : AnyShapeStyle(nodeGradient),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(message.me ? Color.black.opacity(0.08) : nodeColor.opacity(0.84), lineWidth: message.me ? 1 : 1.5)
                }
                .shadow(color: message.me ? .black.opacity(0.18) : nodeColor.opacity(0.35), radius: 8, y: 3)
                .frame(maxWidth: 520, alignment: message.me ? .trailing : .leading)

            if !message.me {
                Spacer(minLength: 48)
            }
        }
    }

    private var displayText: String {
        let prefix = message.dm ? "DM " : ""
        if message.me {
            return prefix + message.text
        }
        return prefix + senderNickname + ": " + message.text
    }

    private var nodeColor: Color {
        NodeColor.color(for: message.sender)
    }

    private var nodeGradient: LinearGradient {
        LinearGradient(
            colors: [nodeColor.opacity(0.96), nodeColor.opacity(0.74)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AvatarView: View {
    let label: String
    var systemImage: String?
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Text(label)
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(.black)
        .frame(width: 34, height: 34)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .tracking(0.5)
                .foregroundStyle(AppPalette.dimText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppPalette.dimText)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.dimText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
