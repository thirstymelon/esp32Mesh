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
                    ZStack(alignment: .top) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 12) {
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
                                        let msgsWithDates = addDateSeparators(to: filteredMessages)
                                        ForEach(msgsWithDates, id: \.id) { item in
                                            if let dateStr = item.dateString {
                                                dateSeparator(dateStr)
                                            }
                                            MessageBubble(message: item.message)
                                                .environmentObject(meshManager)
                                                .id(item.message.id)
                                                .transition(.scale(scale: 0.85, anchor: item.message.me ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
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
                        
                        // Reaction notification banner
                        reactionBanner
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
        .navigationTitle("Chat")
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
                        filterType = .all
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
                                        Image(systemName: NodeAvatar.symbol(for: peerIdStr))
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(isSelected ? NodeColor.color(for: peerIdStr) : .black)
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
    
    @AppStorage("messageHaptics") private var messageHaptics = true
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if messageHaptics {
            Haptics.impact(.medium)
        }
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

// MARK: - Date Separator Helpers

private struct DateSeparatorItem: Identifiable {
    let id = UUID()
    let dateString: String?
    let message: MeshData.Message
}

private func addDateSeparators(to messages: [MeshData.Message]) -> [DateSeparatorItem] {
    var result: [DateSeparatorItem] = []
    var lastDate: Date?
    for msg in messages {
        let date = Date(timeIntervalSince1970: TimeInterval(msg.ts))
        if lastDate == nil || !Calendar.current.isDate(date, inSameDayAs: lastDate!) {
            let formatter = DateFormatter()
            if Calendar.current.isDateInToday(date) {
                result.append(DateSeparatorItem(dateString: "Today", message: msg))
            } else if Calendar.current.isDateInYesterday(date) {
                result.append(DateSeparatorItem(dateString: "Yesterday", message: msg))
            } else {
                formatter.dateFormat = "EEEE, MMMM d, yyyy"
                result.append(DateSeparatorItem(dateString: formatter.string(from: date), message: msg))
            }
            lastDate = date
        } else {
            result.append(DateSeparatorItem(dateString: nil, message: msg))
        }
    }
    return result
}

private func dateSeparator(_ text: String) -> some View {
    HStack(spacing: 8) {
        VStack { Divider().overlay(.white.opacity(0.1)) }
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(AppPalette.dimText.opacity(0.6))
            .padding(.horizontal, 8)
            .fixedSize()
        VStack { Divider().overlay(.white.opacity(0.1)) }
    }
    .padding(.vertical, 6)
}

// MARK: - Reaction Notification Banner

extension MessagesView {
    @ViewBuilder
    var reactionBanner: some View {
        if let notification = meshManager.currentReactionNotification {
            HStack(spacing: 10) {
                Text(notification.emoji)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reacted to \(notification.fromNickname)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(notification.messageText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 12)
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        meshManager.currentReactionNotification = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(6)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    meshManager.currentReactionNotification = nil
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
    
    private let reactionOptions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var senderNickname: String {
        meshManager.meshData?.nicknames.first(where: { $0.id == message.sender })?.nick ?? String(message.sender.prefix(6))
    }
    
    private var messageTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(message.ts))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.me {
                Circle()
                    .fill(nodeColor)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: NodeAvatar.symbol(for: message.sender))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                    }
            } else {
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
                
                // Timestamp and delivery status row
                HStack(spacing: 6) {
                    Text(messageTime)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppPalette.dimText.opacity(0.7))
                    
                    if message.me && message.dm {
                        Image(systemName: message.delivered ? "checkmark.circle.fill" : "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(message.delivered ? AppPalette.ok : AppPalette.dimText.opacity(0.7))
                    }
                }
                .padding(.horizontal, 4)
                
                // Reaction pills
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions) { reaction in
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    meshManager.toggleReaction(reaction.emoji, for: message.id)
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(reaction.emoji)
                                        .font(.system(size: 12))
                                    Text("\(reaction.count)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    reaction.reactedByMe
                                    ? nodeColor.opacity(0.25)
                                    : Color.white.opacity(0.08)
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            reaction.reactedByMe ? nodeColor.opacity(0.5) : .clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: 280, alignment: message.me ? .trailing : .leading)

            if message.me {
                Circle()
                    .fill(nodeColor)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: NodeAvatar.symbol(for: message.sender))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                    }
            } else {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 4)
        .contextMenu {
            ForEach(reactionOptions, id: \.self) { emoji in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        meshManager.toggleReaction(emoji, for: message.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(emoji)
                            .font(.system(size: 16))
                        Text(reactionLabel(for: emoji))
                            .font(.system(size: 13))
                    }
                }
            }
            
            if message.reactions.contains(where: { $0.reactedByMe }) {
                Divider()
                
                Button(role: .destructive) {
                    // Remove all my reactions
                    for reaction in message.reactions where reaction.reactedByMe {
                        meshManager.toggleReaction(reaction.emoji, for: message.id)
                    }
                } label: {
                    Label("Clear my reactions", systemImage: "xmark.circle")
                }
            }
        } preview: {
            VStack(alignment: .center, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .padding(8)
            }
            .frame(width: 160)
        }
    }
    
    private func reactionLabel(for emoji: String) -> String {
        switch emoji {
        case "👍": return "Like"
        case "❤️": return "Love"
        case "😂": return "Laugh"
        case "😮": return "Surprise"
        case "😢": return "Sad"
        case "🙏": return "Thanks"
        default: return "React"
        }
    }

    private var nodeColor: Color {
        NodeColor.color(for: message.sender)
    }
}

#Preview {
    NavigationStack {
        MessagesView(showingConnectionSheet: .constant(false))
            .environmentObject(MeshManager())
    }
    .preferredColorScheme(.dark)
}
