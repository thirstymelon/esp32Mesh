import SwiftUI

@main
struct MeshOSApp: App {
    @StateObject private var meshManager = MeshManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshManager)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Disconnect") {
                    meshManager.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!meshManager.isConnected)
                
                Divider()
                
                Button("Refresh Data") {
                    Task {
                        await meshManager.fetchData()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!meshManager.isConnected)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(meshManager)
        }
    }
}
