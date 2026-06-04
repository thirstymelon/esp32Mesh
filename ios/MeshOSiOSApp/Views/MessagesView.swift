import SwiftUI

enum FilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case broadcasts = "Broadcasts"
    case dms = "DMs"
    var id: Self { self }
}

struct MessagesView: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool
    
    @State private var selectedDestinationIds: Set<String> = [] // empty = Broadcast/All
    @State private var messageText = ""
    @State private var filterType: FilterType = .all
    
    var filteredMessages: [MeshData.Message] {
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
    
    var body: some View {
        ZStack {
            AppBackground()
            
            if meshManager.isConnected {
                VStack(spacing: 0) {
                    Picker("Filter", selection: $filterType) {
                        ForEach(FilterType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    if meshManager.isSyncingMessages {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Syncing history...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppPalette.dimText)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Main Chat Area (Unified transcript)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                if filteredMessages.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "message")
                                            .font(.title)
                                            .foregroundStyle(AppPalette.dimText)
                                        Text("No messages yet")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(AppPalette.dimText)
                                    }
                                    .padding(.top, 40)
                                } else {
                                    ForEach(filteredMessages) { msg in
                                        MessageBubble(message: msg)
                                            .environmentObject(meshManager)
                                            .id(msg.id)
                                    }
                                }
                            }
                            .padding()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                        )
                        .onChange(of: filteredMessages.count) { _, _ in
                            if let lastId = filteredMessages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            if let lastId = filteredMessages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    
                    // Horizontal scrollable nodes selection list
                    recipientRail
                    
                    // Composer
                    composerView
                }
            } else {
                EmptyChatPanel()
            }
        }
        .navigationTitle("MeshOS Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ConnectionBadgeButton(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
        }
    }
    
    private var recipientRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.08))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // "All" Broadcast Button
                    Button {
                        selectedDestinationIds = []
                        if filterType == .dms {
                            filterType = .all
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(
                                    selectedDestinationIds.isEmpty
                                    ? AppPalette.appleGreen
                                    : AppPalette.panel
                                )
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "megaphone.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedDestinationIds.isEmpty ? .black : .white)
                                }
                            
                            Text("All")
                                .font(.system(size: 11, weight: selectedDestinationIds.isEmpty ? .bold : .medium))
                                .foregroundStyle(selectedDestinationIds.isEmpty ? .white : AppPalette.dimText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            selectedDestinationIds.isEmpty
                            ? AppPalette.appleGreen.opacity(0.24)
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Active peers list
                    let activePeers = meshManager.activeNodes.filter { String($0.id) != meshManager.meshData?.nodeId }
                    ForEach(activePeers, id: \.id) { peer in
                        let peerIdStr = String(peer.id)
                        let isSelected = selectedDestinationIds.contains(peerIdStr)
                        Button {
                            if isSelected {
                                selectedDestinationIds.remove(peerIdStr)
                            } else {
                                selectedDestinationIds.insert(peerIdStr)
                            }
                            if filterType == .broadcasts {
                                filterType = .all
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(isSelected ? .black : NodeColor.color(for: peerIdStr))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Text(String(peer.nickname.prefix(1)))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(isSelected ? .white : .black)
                                    }
                                
                                Text(peer.nickname)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .black : AppPalette.dimText)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                isSelected
                                ? NodeColor.color(for: peerIdStr)
                                : AppPalette.panel,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .background(.black.opacity(0.12))
    }
    
    private var composerView: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.08))
            
            HStack(spacing: 12) {
                TextField(selectedDestinationIds.isEmpty ? "Broadcast to mesh..." : "Direct message...", text: $messageText)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .onChange(of: messageText) { _, newValue in
                        let maxLen = 171
                        if newValue.count > maxLen {
                            messageText = String(newValue.prefix(maxLen))
                        }
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(messageText.isEmpty ? .secondary : AppPalette.appleGreen)
                }
                .disabled(messageText.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(
            Color(red: 0.12, green: 0.13, blue: 0.16)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Haptics.impact(.medium)
        messageText = ""
        Task {
            if selectedDestinationIds.isEmpty {
                await meshManager.sendMessage(text, to: nil, channelId: 0)
            } else {
                for dest in selectedDestinationIds {
                    await meshManager.sendMessage(text, to: dest)
                }
            }
        }
    }
}

struct EmptyChatPanel: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppPalette.dimText)
            Text("No mesh connection")
                .font(.headline)
            Text("Use settings or connection bar to pair with a node.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.dimText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Spacer(minLength: 40)
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
                        if !message.me {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(nodeColor.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                
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
            .frame(maxWidth: 280, alignment: message.me ? .trailing : .leading)

            if !message.me {
                Spacer(minLength: 40)
            }
        }
    }

    private var nodeColor: Color {
        NodeColor.color(for: message.sender)
    }
}
