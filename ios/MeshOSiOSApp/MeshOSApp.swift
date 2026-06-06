import SwiftUI

@main
struct MeshOSApp: App {
    @StateObject private var meshManager = MeshManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshManager)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    meshManager.cleanupOnClose()
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MeshManager())
}
