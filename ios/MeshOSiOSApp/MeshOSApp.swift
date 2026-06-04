import SwiftUI

@main
struct MeshOSApp: App {
    @StateObject private var meshManager = MeshManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshManager)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MeshManager())
}
