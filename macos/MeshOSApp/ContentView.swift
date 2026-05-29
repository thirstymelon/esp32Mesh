//
//  ContentView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var selectedTab: Tab = .messages
    @State private var showingConnectionSheet = false
    @Namespace private var navNamespace

    enum Tab: String, CaseIterable, Identifiable {
        case messages, network

        var id: Self { self }

        var title: String {
            switch self {
            case .messages: "Chat"
            case .network: "Network"
            }
        }

        var icon: String {
            switch self {
            case .messages: "message"
            case .network: "point.3.connected.trianglepath.dotted"
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
                showingConnectionSheet: $showingConnectionSheet,
                namespace: navNamespace
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.24), value: selectedTab)
        .frame(minWidth: 920, minHeight: 640)
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionSheet(isPresented: $showingConnectionSheet)
                .environmentObject(meshManager)
        }
    }

    @ViewBuilder
    private var currentView: some View {
        switch selectedTab {
        case .messages:
            MessagesView()
        case .network:
            NetworkView()
        }
    }
}

struct FloatingGlassNav: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var selectedTab: ContentView.Tab
    @Binding var showingConnectionSheet: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ContentView.Tab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.36)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .black.opacity(0.72) : .white.opacity(0.55))

                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundStyle(selectedTab == tab ? .black : .white.opacity(0.68))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(AppPalette.navSelection)
                                    .matchedGeometryEffect(id: "selectedNav", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }

            Divider()
                .frame(height: 24)
                .overlay(.white.opacity(0.16))

            ConnectionBadge()

            if meshManager.isConnected {
                CapsuleIconButton(systemImage: "arrow.clockwise", title: "Refresh") {
                    Task { await meshManager.fetchData() }
                }

                Button {
                    meshManager.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.error)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingConnectionSheet = true
                } label: {
                    Label("Connect", systemImage: "network")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(AppPalette.navSelection, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .liquidGlassCapsule()
        .shadow(color: AppPalette.cyan.opacity(0.18), radius: 28, y: 10)
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
    static let ok = Color(red: 0.25, green: 0.92, blue: 0.48)
    static let error = Color(red: 1.0, green: 0.22, blue: 0.28)
    static let cyan = Color(red: 0.25, green: 0.78, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.42, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.24)
    static let magenta = Color(red: 1.0, green: 0.34, blue: 0.66)
    static let sentBubble = Color.white
    static let receivedBubble = Color.black.opacity(0.74)
    static let border = Color.white.opacity(0.16)
    static let dimText = Color.white.opacity(0.62)
    static let panel = Color.white.opacity(0.065)
    static let navSelection = LinearGradient(
        colors: [Color.white, Color(red: 0.82, green: 0.94, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum NodeColor {
    static func color(for nodeId: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.31, green: 0.76, blue: 0.97),
            Color(red: 0.81, green: 0.58, blue: 0.85),
            Color(red: 1.00, green: 0.72, blue: 0.30),
            Color(red: 0.94, green: 0.60, blue: 0.60),
            Color(red: 0.50, green: 0.80, blue: 0.77),
            Color(red: 1.00, green: 0.95, blue: 0.46),
            Color(red: 0.96, green: 0.56, blue: 0.69),
            Color(red: 0.65, green: 0.84, blue: 0.65),
            Color(red: 1.00, green: 0.54, blue: 0.40),
            Color(red: 0.56, green: 0.79, blue: 0.98)
        ]
        let hash = nodeId.unicodeScalars.reduce(5381) { result, scalar in
            ((result << 5) &+ result) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.025, blue: 0.04),
                    Color(red: 0.02, green: 0.01, blue: 0.035),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppPalette.cyan.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )

            RadialGradient(
                colors: [AppPalette.violet.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 620
            )

            RadialGradient(
                colors: [AppPalette.amber.opacity(0.08), .clear],
                center: .center,
                startRadius: 120,
                endRadius: 700
            )
        }
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
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
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
