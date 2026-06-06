//
//  ContentView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var selectedTab: Tab = .messages
    @Namespace private var navNamespace

    enum Tab: String, CaseIterable, Identifiable {
        case messages, network, settings

        var id: Self { self }

        var title: String {
            switch self {
            case .messages: "Chat"
            case .network: "Network"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .messages: "message"
            case .network: "point.3.connected.trianglepath.dotted"
            case .settings: "gearshape"
            }
        }
        
        var active_icon: String {
            switch self {
            case .messages: "message.fill"
            case .network: "point.3.filled.connected.trianglepath.dotted"
            case .settings: "gearshape.fill"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            currentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 92)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.42), value: selectedTab)

            FloatingGlassNav(
                selectedTab: $selectedTab,
                namespace: navNamespace
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.24), value: selectedTab)
        .frame(minWidth: 920, minHeight: 640)
        .onAppear {
            meshManager.checkNotificationPermission()
        }
    }

    @ViewBuilder
    private var currentView: some View {
        switch selectedTab {
        case .messages:
            MessagesView()
        case .network:
            NetworkView()
        case .settings:
            SettingsView()
        }
    }
}

struct FloatingGlassNav: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var selectedTab: ContentView.Tab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ContentView.Tab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedTab == tab ? tab.active_icon : tab.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(selectedTab == tab ? AppPalette.appleGreen : .white.opacity(0.55))

                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.55))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: tab, in: namespace, isSource: true)
                }
            }
            .background {
                // Sliding background capsule
                Capsule()
                    .fill(.white.opacity(0.08))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .matchedGeometryEffect(id: selectedTab, in: namespace, isSource: false)
            }
            .padding(4)
            .background(.white.opacity(0.06), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }

            Divider()
                .frame(height: 24)
                .overlay(.white.opacity(0.16))

            ConnectionBadge()

            if meshManager.isConnected {
                CapsuleIconButton(systemImage: "arrow.clockwise", title: "Refresh") {
                    Task { await meshManager.fetchData() }
                }
            }
        }
        .padding(8)
        .liquidGlassCapsule()
        .shadow(color: .black.opacity(0.42), radius: 26, y: 14)
    }
}

struct CapsuleIconButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct ConnectionBadge: View {
    @EnvironmentObject var meshManager: MeshManager

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(meshManager.isConnected ? AppPalette.ok : AppPalette.error)
                .frame(width: 8, height: 8)
                .shadow(color: meshManager.isConnected ? AppPalette.ok.opacity(0.65) : AppPalette.error.opacity(0.55), radius: 5)

            Text(meshManager.isConnected ? shortNodeName : "Offline")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.28), in: Capsule())
    }

    private var shortNodeName: String {
        guard let data = meshManager.meshData else { return "Online" }
        let nickname = meshManager.currentNodeNickname
        return nickname == "Unknown" ? String(data.nodeId.prefix(6)) : nickname
    }
}

// MARK: - Shared Styling
enum AppPalette {
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.35) // Apple Green
    static let error = Color(red: 1.00, green: 0.23, blue: 0.19) // Apple Red
    static let cyan = Color(red: 0.00, green: 0.48, blue: 1.00) // Apple Blue
    static let appleGreen = Color(red: 0.20, green: 0.78, blue: 0.35) // Apple Green
    static let violet = Color(red: 0.35, green: 0.34, blue: 0.84) // Apple Indigo/Violet
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.04) // Apple Orange
    static let magenta = Color(red: 0.86, green: 0.19, blue: 0.51) // Apple Pink
    static let sentBubble = Color(red: 0.00, green: 0.48, blue: 1.00)
    static let receivedBubble = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.12)
    static let dimText = Color.white.opacity(0.60)
    static let panel = Color.white.opacity(0.06)
    static let navSelection = LinearGradient(
        colors: [Color.white, Color(red: 0.88, green: 0.92, blue: 0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum NodeColor {
    static func color(for nodeId: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.00, green: 0.48, blue: 1.00), // Blue
            Color(red: 0.35, green: 0.34, blue: 0.84), // Indigo
            Color(red: 1.00, green: 0.62, blue: 0.04), // Orange
            Color(red: 1.00, green: 0.23, blue: 0.19), // Red
            Color(red: 0.20, green: 0.78, blue: 0.35), // Green
            Color(red: 0.00, green: 0.64, blue: 0.80), // Teal
            Color(red: 0.86, green: 0.19, blue: 0.51), // Pink
            Color(red: 0.57, green: 0.23, blue: 0.84), // Purple
            Color(red: 0.95, green: 0.45, blue: 0.20), // Coral
            Color(red: 0.10, green: 0.70, blue: 0.90)  // Sky
        ]
        let hash = nodeId.unicodeScalars.reduce(5381) { result, scalar in
            ((result << 5) &+ result) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}

enum NodeAvatar {
    static let symbols = [
        "tortoise.fill",
        "hare.fill",
        "bird.fill",
        "ant.fill",
        "ladybug.fill",
        "leaf.fill",
        "pawprint.fill",
        "flame.fill",
        "bolt.fill",
        "star.fill",
        "crown.fill",
        "shield.fill",
        "gamecontroller.fill",
        "sun.max.fill",
        "moon.stars.fill"
    ]
    
    static func symbol(for nodeId: String) -> String {
        let hash = nodeId.unicodeScalars.reduce(5381) { result, scalar in
            ((result << 5) &+ result) &+ Int(scalar.value)
        }
        return symbols[abs(hash) % symbols.count]
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.10),
                Color(red: 0.12, green: 0.13, blue: 0.16)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct MeshGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isInteractive ? 0.18 : 0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
    }
}

struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
    }
}

extension View {
    func meshGlass(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        modifier(MeshGlassModifier(cornerRadius: cornerRadius, isInteractive: interactive))
    }

    func liquidGlassCapsule() -> some View {
        modifier(LiquidGlassCapsuleModifier())
    }
}

#Preview {
    ContentView()
        .environmentObject(MeshManager())
        .frame(width: 920, height: 640)
        .preferredColorScheme(.dark)
}
