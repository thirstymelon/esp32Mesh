//
//  MessagesView.swift
//  Mesh OS - macOS Client
//

import SwiftUI



struct MessagesView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var messageText = ""
    @State private var selectedNodeIds: Set<String> = [] // empty = Channel Mode
    @State private var selectedChannelId: UInt8 = 0
    @State private var filterType: FilterType = .all

    enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case broadcasts = "Broadcasts"
        case dms = "DMs"
        
        var id: String { self.rawValue }
    }

    var selectedTargetNickname: String {
        if !selectedNodeIds.isEmpty {
            let nicknames = selectedNodeIds.compactMap { targetId in
                meshManager.meshData?.nicknames.first(where: { $0.id == targetId })?.nick ?? String(targetId.prefix(6))
            }
            return nicknames.joined(separator: ", ")
        }
        return "Public Broadcast"
    }

    var messages: [MeshData.Message] {
        let allMsgs = meshManager.meshData?.messages ?? []
        let sorted = allMsgs.sorted(by: { $0.ts < $1.ts })
        switch filterType {
        case .all:
            return sorted
        case .broadcasts:
            return sorted.filter { !$0.dm }
        case .dms:
            return sorted.filter { $0.dm }
        }
    }

    var nodes: [NodeInfo] {
        guard let data = meshManager.meshData else { return [] }

        var result: [NodeInfo] = []
        let selfNick = data.nicknames.first(where: { $0.id == data.nodeId })?.nick ?? "This Mac"
        let selfEntry = meshManager.activeNodes.first(where: { String($0.id) == data.nodeId })
        result.append(NodeInfo(id: data.nodeId, nickname: selfNick, isSelf: true, isOnline: true, battery: selfEntry?.battery, uptime: selfEntry?.uptime))

        for peerId in data.peers {
            if peerId == data.nodeId { continue }
            let nick = data.nicknames.first(where: { $0.id == peerId })?.nick ?? String(peerId.prefix(6))
            let entry = meshManager.activeNodes.first(where: { String($0.id) == peerId })
            result.append(NodeInfo(id: peerId, nickname: nick, isSelf: false, isOnline: true, battery: entry?.battery, uptime: entry?.uptime))
        }

        for nickname in data.nicknames where !result.contains(where: { $0.id == nickname.id }) {
            let entry = meshManager.activeNodes.first(where: { String($0.id) == nickname.id })
            result.append(NodeInfo(id: nickname.id, nickname: nickname.nick, isSelf: false, isOnline: false, battery: entry?.battery, uptime: entry?.uptime))
        }

        return result.sorted {
            if $0.isSelf != $1.isSelf { return $0.isSelf && !$1.isSelf }
            if $0.isOnline != $1.isOnline { return $0.isOnline && !$1.isOnline }
            return $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ChatHeader(filterType: $filterType, selectedNodeIds: selectedNodeIds)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    if meshManager.isConnected {
                        ChatTranscript(messages: messages)
                    } else {
                        EmptyChatPanel()
                    }

                    MessageComposer(messageText: $messageText, targetName: selectedTargetNickname, onSend: {
                        sendMessage()
                    })
                    .disabled(!meshManager.isConnected)
                    .opacity(meshManager.isConnected ? 1 : 0.45)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                NodesRail(nodes: nodes, selectedNodeIds: $selectedNodeIds, selectedChannelId: $selectedChannelId)
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
            if !selectedNodeIds.isEmpty {
                for dest in selectedNodeIds {
                    await meshManager.sendMessage(text, to: dest)
                }
            } else {
                await meshManager.sendMessage(text, to: nil, channelId: selectedChannelId)
            }
        }
    }
}

struct ChatHeader: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var filterType: MessagesView.FilterType
    let selectedNodeIds: Set<String>

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(titleText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.dimText)
            }

            Spacer()
            
            Picker("", selection: $filterType) {
                ForEach(MessagesView.FilterType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
        }
    }

    private var titleText: String {
        switch filterType {
        case .all:
            return "All Messages"
        case .broadcasts:
            return "Public Broadcasts"
        case .dms:
            return "Direct Messages"
        }
    }

    private var statusText: String {
        guard let data = meshManager.meshData else { return "Connect to a node to join the mesh." }
        if !selectedNodeIds.isEmpty {
            let names = selectedNodeIds.compactMap { targetId in
                data.nicknames.first(where: { $0.id == targetId })?.nick ?? String(targetId.prefix(6))
            }
            return "Composer Target: private chat with \(names.joined(separator: ", "))"
        } else {
            let nickname = meshManager.currentNodeNickname == "Unknown" ? String(data.nodeId.prefix(6)) : meshManager.currentNodeNickname
            return "Composer Target: Broadcasting to Public channel from \(nickname)"
        }
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
    @EnvironmentObject var meshManager: MeshManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if meshManager.isSyncingMessages {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing mesh history...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.cyan)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppPalette.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                if messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "message")
                            .font(.system(size: 24))
                            .foregroundStyle(AppPalette.dimText)
                        Text("No messages in this channel yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppPalette.dimText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
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
    let targetName: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {

            ZStack(alignment: .trailing) {
                TextField("Send to \(targetName)...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                    .padding(.trailing, 64)
                    .padding(.vertical, 13)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                    .onSubmit(onSend)
                    .onChange(of: messageText) { _, newValue in
                        let maxLen = 172
                        if newValue.count > maxLen {
                            messageText = String(newValue.prefix(maxLen))
                        }
                    }

                if !messageText.isEmpty {
                    Text("\(messageText.count)/172")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(messageText.count >= 160 ? AppPalette.error : AppPalette.dimText)
                        .padding(.trailing, 16)
                }
            }

            Button(action: onSend) {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.4) : .white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.12) : AppPalette.appleGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(AppPalette.cyan.opacity(0.22), lineWidth: 1) }
        .shadow(color: AppPalette.cyan.opacity(0.14), radius: 14, y: 5)
    }
}

struct NodesRail: View {
    let nodes: [NodeInfo]
    @Binding var selectedNodeIds: Set<String>
    @Binding var selectedChannelId: UInt8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mesh Network")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(nodes.filter { $0.isOnline }.count)/\(nodes.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.dimText)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedNodeIds.removeAll()
                    selectedChannelId = 0
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selectedNodeIds.isEmpty ? .black : AppPalette.cyan)
                        .frame(width: 26, height: 26)
                        .background(selectedNodeIds.isEmpty ? .white : .white.opacity(0.08), in: Circle())
                    
                    Text("Public Broadcast")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selectedNodeIds.isEmpty ? .white : .white.opacity(0.85))
                    
                    Spacer()
                }
                .padding(8)
                .background(selectedNodeIds.isEmpty ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selectedNodeIds.isEmpty ? AppPalette.cyan : .clear, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(.white.opacity(0.12))

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
                            if !node.isSelf {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedNodeIds.contains(node.id) {
                                            selectedNodeIds.remove(node.id)
                                        } else {
                                            selectedNodeIds.insert(node.id)
                                        }
                                    }
                                } label: {
                                    NodeRailRow(node: node, isSelected: selectedNodeIds.contains(node.id))
                                }
                                .buttonStyle(.plain)
                            } else {
                                NodeRailRow(node: node, isSelected: false)
                            }
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(isSelected ? .black : NodeColor.color(for: node.id))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(String(node.nickname.prefix(1)))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? NodeColor.color(for: node.id) : .black)
                    }

                Circle()
                    .fill(node.isOnline ? AppPalette.ok : AppPalette.error)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isSelected ? NodeColor.color(for: node.id) : .black, lineWidth: 1.5))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(node.nickname)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                    if node.isSelf {
                        Text("YOU")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isSelected ? .black.opacity(0.6) : AppPalette.dimText)
                    }
                }

                Text(String(node.id.prefix(8)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? .black.opacity(0.6) : AppPalette.dimText)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(isSelected ? NodeColor.color(for: node.id).opacity(0.7) : .black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? .black.opacity(0.2) : NodeColor.color(for: node.id).opacity(0.45), lineWidth: 1)
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

            VStack(alignment: message.me ? .trailing : .leading, spacing: 4) {
                // Sender Header with Symbols instead of text prefixes
                HStack(spacing: 4) {
                    if message.me {
                        Text("You")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                        Image(systemName: message.dm ? "envelope.fill" : "megaphone.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(AppPalette.dimText)
                    } else {
                        Image(systemName: message.dm ? "envelope.fill" : "megaphone.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(AppPalette.dimText)
                        Text(senderNickname)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                    }
                }
                .padding(.horizontal, 4)

                Text(message.text)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(message.me ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.me ? Color.white : AppPalette.receivedBubble,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(message.me ? .clear : nodeColor.opacity(0.8), lineWidth: message.me ? 0 : 1.5)
                    }
                    .shadow(color: message.me ? .clear : nodeColor.opacity(0.15), radius: 4, y: 2)
                
                if message.me && message.dm {
                    HStack(spacing: 4) {
                        Image(systemName: message.delivered ? "checkmark.circle.fill" : "circle")
                        Text(message.delivered ? "Delivered" : "Pending")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(message.delivered ? AppPalette.ok : AppPalette.dimText)
                    .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: 520, alignment: message.me ? .trailing : .leading)

            if !message.me {
                Spacer(minLength: 48)
            }
        }
    }
    private var nodeColor: Color {
        NodeColor.color(for: message.sender)
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
