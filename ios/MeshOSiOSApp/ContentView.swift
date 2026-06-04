import SwiftUI

struct ContentView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var selectedTab: Tab = .messages
    @State private var showingConnectionSheet = false

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
            case .settings: "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MessagesView(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
            .tag(Tab.messages)
            .tabItem {
                Label(Tab.messages.title, systemImage: Tab.messages.icon)
            }

            NavigationStack {
                NetworkView(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
            .tag(Tab.network)
            .tabItem {
                Label(Tab.network.title, systemImage: Tab.network.icon)
            }

            NavigationStack {
                SettingsView(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
            .tag(Tab.settings)
            .tabItem {
                Label(Tab.settings.title, systemImage: Tab.settings.icon)
            }
        }
        .tint(AppPalette.cyan)
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionSheet(isPresented: $showingConnectionSheet)
                .environmentObject(meshManager)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithTransparentBackground()
            navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance = navBarAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance

            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithTransparentBackground()
            tabBarAppearance.backgroundColor = UIColor.clear
            tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            
            meshManager.checkNotificationPermission()
        }
    }

    private var shortNodeName: String {
        guard let data = meshManager.meshData else { return "Connected" }
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
            .background(Color(red: 0.14, green: 0.16, blue: 0.20), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isInteractive ? 0.08 : 0.05), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

extension View {
    func meshGlass(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        modifier(MeshGlassModifier(cornerRadius: cornerRadius, isInteractive: interactive))
    }
}

// MARK: - Haptic Feedback Helper
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        DispatchQueue.main.async {
            switch style {
            case .light:
                light.prepare()
                light.impactOccurred()
            case .medium:
                medium.prepare()
                medium.impactOccurred()
            default:
                let generator = UIImpactFeedbackGenerator(style: style)
                generator.prepare()
                generator.impactOccurred()
            }
        }
    }
    
    static func success() {
        DispatchQueue.main.async {
            notification.prepare()
            notification.notificationOccurred(.success)
        }
    }
    
    static func error() {
        DispatchQueue.main.async {
            notification.prepare()
            notification.notificationOccurred(.error)
        }
    }
    
    static func warning() {
        DispatchQueue.main.async {
            notification.prepare()
            notification.notificationOccurred(.warning)
        }
    }
    
    static func tap() {
        DispatchQueue.main.async {
            light.prepare()
            light.impactOccurred()
        }
    }
}

struct ConnectionBadgeButton: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool
    
    var body: some View {
        Button(action: { showingConnectionSheet = true }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(meshManager.isConnected ? AppPalette.ok : AppPalette.error)
                    .frame(width: 6, height: 6)
                
                Text(meshManager.isConnected ? shortNodeName : "Disconnected")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(meshManager.isConnected ? .white : AppPalette.dimText)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var shortNodeName: String {
        guard let data = meshManager.meshData else { return "Connected" }
        let nickname = meshManager.currentNodeNickname
        return nickname == "Unknown" ? String(data.nodeId.prefix(6)) : nickname
    }
}
